#!/bin/sh
readonly USAGE=\
"NAME
    $(basename "$0") -- create tiny, bootable stress test USB

SYNOPSIS
    $(basename "$0") [-h] [-l <directory>] <device>

DESCRIPTION
    Tool to create a bootable USB device, including a minimal Tiny Core Linux
    installation and various stress testing tools.

    ALL DATA ON <device> WILL BE LOST!

OPTIONS
    -h                Show help text
    -c                Clean up after the program succeeds. Delete temporary
                      directory and unmount the device.
    -l <directory>    Write log files to <directory> (default: $(pwd))
    -y                Automatic \"yes\" to prompts
    <device>          USB device to use (/dev/ may be omitted)

EXAMPLES
    $(basename "$0") sda

    $(basename "$0") -l . /dev/sdb

    $(basename "$0") -l ~/logs sdc"

########################################
# Display help text.
# Globals:
#   USAGE
# Arguments:
#   None
# Outputs:
#   Write help text to stdout.
########################################
display_help() {
  printf '%s\n' "${USAGE}"
}

# parse options
while getopts ':hcl:y' option; do
  case "${option}" in
    h)  display_help
        exit
        ;;
    c)  readonly CLEAN_UP=true
        ;;
    l)  LOG_DIR="${OPTARG}"
        ;;
    y)  readonly AUTO_CONFIRM=true
        ;;
    :)  printf 'Missing argument for: -%s\n\n' "${OPTARG}" >&2
        display_help >&2
        exit 2
        ;;
   \?)  printf 'Illegal option: -%s\n\n' "${OPTARG}" >&2
        display_help >&2
        exit 2
        ;;
  esac
done
shift $(( OPTIND - 1 ))

if [ -z "$1" ]; then
  printf 'Missing option: <device>\n\n' >&2
  display_help >&2
  exit 2
fi

# check required software packages
readonly DEPENDENCIES="
basename
blkid
cp
dirname
git
grep
grub-install
ln
lsblk
md5sum
mkdir
mkfs.fat
mkfs.ext2
mksquashfs
mount
partprobe
sed
tee
wget"
for dependency in ${DEPENDENCIES}; do
  if ! command -v "${dependency}" > /dev/null 2>&1; then
    printf 'Command not found: %s\n' "${dependency}" >&2
    exit 2
  fi
done

# check if running as root
if [ "$(id -u)" -ne 0 ]; then
  printf 'Must run as root\n' >&2
  exit 2
fi

################################################################################
# CONSTANTS
################################################################################

DEVICE="$1"
# prepend /dev/ if necessary
if ! printf '%s' "${DEVICE}" | grep -q "/dev/\w*"; then
  DEVICE="/dev/${DEVICE}"
fi
readonly DEVICE

# check if USB device
readonly BUS_CONNECTION="$(lsblk --nodeps --noheadings --output TRAN "${DEVICE}")"
if [ "${BUS_CONNECTION}" != "usb" ]; then
  printf 'Not a USB device: %s\n' "${DEVICE}" >&2
  exit 2
fi

# common directories
readonly WORK_DIR="$(pwd)"
readonly TMP_DIR="${WORK_DIR}/tmp"
readonly MNT_DIR="${TMP_DIR}/mnt"
readonly DOWNLOAD_DIR="${TMP_DIR}/downloads"

# partitions
readonly PART_EFI="${DEVICE}1" # e.g. /dev/sdc1
readonly PART_ROOT="${DEVICE}2" # e.g. /dev/sdc2

# mount points
readonly MNT_EFI="${MNT_DIR}${PART_EFI}" # e.g. ./tmp/mnt/dev/sdc1
readonly MNT_ROOT="${MNT_DIR}${PART_ROOT}" # e.g. ./tmp/mnt/dev/sdc2

# logging
[ -z "${LOG_DIR}" ] && LOG_DIR="${WORK_DIR}"
readonly LOG_FILE="${LOG_DIR}/log.txt"

# Tiny Core Linux
readonly TC_ARCH="x86_64"
readonly TC_VERSION="11"
readonly TC_SITE_URL="http://tinycorelinux.net/${TC_VERSION}.x/${TC_ARCH}"
readonly TC_EXTENSIONS="e2fsprogs kmaps screen smartmontools systester-cli"

################################################################################
# FUNCTIONS
################################################################################

##################################################
# Log informational message.
# Globals:
#   LOG_FILE
# Arguments:
#   Message to log.
# Outputs:
#   Write message to stdout and log file.
##################################################
log_info()
{
  now="$(date +"%F %T")"
  printf '%s\n' "[${now}] $1" | tee -a "${LOG_FILE}"
}

##################################################
# Log emphasized header message.
# Globals:
#   LOG_SEPARATOR
# Arguments:
#   Message to log.
##################################################
log_header()
{
  log_info "+-----------------------------------------------------------"
  log_info "+ $1"
  log_info "+-----------------------------------------------------------"
}

########################################
# Show runtime information.
# Globals:
#   DEVICE
#   BUS_CONNECTION
#   WORK_DIR
#   TMP_DIR
#   MNT_DIR
#   DOWNLOAD_DIR
#   PART_EFI
#   PART_ROOT
#   MNT_EFI
#   MNT_ROOT
#   TC_ARCH
#   TC_VERSION
#   TC_SITE_URL
#   TC_EXTENSIONS
#   AUTO_CONFIRM
#   CLEAN_UP
# Arguments:
#   None
########################################
show_runtime_info() {
  log_header "Device Information"
  log_info "Device:         ${DEVICE}"
  log_info "Bus Connection: ${BUS_CONNECTION}"

  log_header "Common Directories"
  log_info "Working:        ${WORK_DIR}"
  log_info "Temporary:      ${TMP_DIR}"
  log_info "Mount Points:   ${MNT_DIR}"
  log_info "Downloads:      ${DOWNLOAD_DIR}"

  log_header "EFI Partition"
  log_info "Partition:      ${PART_EFI}"
  log_info "Mount Point:    ${MNT_EFI}"

  log_header "Root Partition"
  log_info "Partition:      ${PART_ROOT}"
  log_info "Mount Point:    ${MNT_ROOT}"

  log_header "Tiny Core Linux"
  log_info "Architecture:   ${TC_ARCH}"
  log_info "Version:        ${TC_VERSION}"
  log_info "Site URL:       ${TC_SITE_URL}"
  log_info "Extensions:     ${TC_EXTENSIONS}"

  log_header "Other"
  log_info "Auto Confirm:   ${AUTO_CONFIRM}"
  log_info "Clean Up:       ${CLEAN_UP}"

}

. "./format-usb.sh"

########################################
# Ensures directories exist.
# Globals:
#   TMP_DIR
#   MNT_DIR
#   DOWNLOAD_DIR
# Arguments:
#   None
########################################
ensure_directories() {
  log_header "Creating Directories"

  mkdir -p -- "${TMP_DIR}"
  mkdir -p -- "${MNT_DIR}"
  mkdir -p -- "${DOWNLOAD_DIR}"
  mkdir -p -- "${MNT_EFI}"
  mkdir -p -- "${MNT_ROOT}"

  log_info "Done"
}

########################################
# Delete temporary directory.
# Globals:
#   TMP_DIR
# Arguments:
#   None
########################################
delete_temporary_directory() {
  log_info "Deleting Temporary Directory"
  rm -rf "${TMP_DIR}"
}

########################################
# Mount file systems.
# Globals:
#   PART_EFI
#   PART_ROOT
#   MNT_EFI
#   MNT_ROOT
# Arguments:
#   None
########################################
mount_file_systems() {
  log_header "Mounting File Systems"
  mount "${PART_EFI}" "${MNT_EFI}"
  mount "${PART_ROOT}" "${MNT_ROOT}"
  log_info "Done"
}

########################################
# Download file.
# Globals:
#   WORK_DIR
# Arguments:
#   Download URL.
#   Destination file.
########################################
download_file() {
    cd "$(dirname "$2")" || exit 2
    wget \
      --quiet \
      --continue \
      --show-progress \
      --output-document="$(basename "$2")" \
      "$1"
    cd "${WORK_DIR}" || exit 2
}

########################################
# Download Tiny Core Linux component and validate its MD5 checksum.
# Exit on checksum error.
# Globals:
#   WORK_DIR
# Arguments:
#   Download URL.
#   Destination file.
########################################
download_and_validate_tiny_core_component() {
    download_file "$1"         "$2"
    download_file "$1.md5.txt" "$2.md5.txt"

    cd "$(dirname "$2")" || exit 2
    md5sum --check "$(basename "$2").md5.txt"
    validation_status="$?"
    cd "${WORK_DIR}" || exit 2

    if [ "${validation_status}" -ne 0 ]; then
      log_info "Checksum error" 2>&1
      exit 2
    fi
}

########################################
# Download Tiny Core Linux core components.
# Globals:
#   DOWNLOAD_DIR
#   TC_SITE_URL
# Arguments:
#   None
########################################
download_tiny_core() {
    mkdir -p -- "${DOWNLOAD_DIR}/boot"

    log_header "Downloading Tiny Core Linux"

    download_and_validate_tiny_core_component \
      "${TC_SITE_URL}/release/distribution_files/corepure64.gz" \
      "${DOWNLOAD_DIR}/boot/corepure64.gz"

    download_and_validate_tiny_core_component \
      "${TC_SITE_URL}/release/distribution_files/vmlinuz64" \
      "${DOWNLOAD_DIR}/boot/vmlinuz64"

    log_info "Done"
}

########################################
# Download Tiny Core Linux extension.
# Globals:
#   DOWNLOAD_DIR
#   TC_SITE_URL
# Arguments:
#   Name of the extension, including the .tcz extension.
########################################
already_downloaded=""
download_tiny_core_extension() {
  [ -z "$1" ] && return 1

  mkdir -p -- "${DOWNLOAD_DIR}/tce/optional"

  log_info "Downloading: $1"

  if printf '%s' "${already_downloaded}" | grep -q "$1"; then
    log_info "Already downloaded: $1. Skipping."
    return
  fi

  download_and_validate_tiny_core_component \
    "${TC_SITE_URL}/tcz/$1" \
    "${DOWNLOAD_DIR}/tce/optional/$1"

  download_file \
    "${TC_SITE_URL}/tcz/$1.dep" \
    "${DOWNLOAD_DIR}/tce/optional/$1.dep"

  already_downloaded="${already_downloaded} $1"

  if [ -f "${DOWNLOAD_DIR}/tce/optional/$1.dep" ]; then
    # download dependencies recursively
    while read -r dependency; do
      download_tiny_core_extension "${dependency}"
    done < "${DOWNLOAD_DIR}/tce/optional/$1.dep"
  fi

  printf '%s\n' "$1" >> "${DOWNLOAD_DIR}/tce/onboot.lst"
}

########################################
# Download Tiny Core Linux extensions.
# Globals:
#   DOWNLOAD_DIR
#   TC_EXTENSIONS
# Arguments:
#   None
########################################
download_tiny_core_extensions() {
  rm -f -- "${DOWNLOAD_DIR}/tce/onboot.lst"
  for extension in ${TC_EXTENSIONS}; do
    log_header "Downloading: ${extension}"
    download_tiny_core_extension "${extension}.tcz"
  done
}

########################################
# Create custom disk-burnin extension.
# Globals:
#   DOWNLOAD_DIR
# Arguments:
#   None
########################################
create_custom_disk_burnin_extension() {
  log_header "Creating Disk Burn-In Extension"

  log_info "Downloading script"

  mkdir -p "${DOWNLOAD_DIR}/disk-burnin-and-testing/usr/local/bin"
  cd "${DOWNLOAD_DIR}/disk-burnin-and-testing/usr/local/bin" || exit 2
  git clone \
    --depth=1 \
    --branch=master \
    "https://github.com/Spearfoot/disk-burnin-and-testing.git"
  rm -rf "disk-burnin-and-testing/.git"
  ln -s "disk-burnin-and-testing/disk-burnin.sh" "disk-burnin"
  cd "${WORK_DIR}" || exit 2

  log_info "Packaging extension"

  mksquashfs \
    "${DOWNLOAD_DIR}/disk-burnin-and-testing" \
    "${DOWNLOAD_DIR}/tce/optional/disk-burnin.tcz" \
    -b 4k \
    -no-xattrs \
    -noappend \
    -quiet

  printf 'disk-burnin.tcz\n' >> "${DOWNLOAD_DIR}/tce/onboot.lst"

  log_info "Done"
}

########################################
# Install downloaded Tiny Core Linux on root partition.
# Globals:
#   DOWNLOAD_DIR
#   MNT_ROOT
# Arguments:
#   None
########################################
install_tiny_core() {
  log_header "Installing Tiny Core Linux"
  cp --recursive -- "${DOWNLOAD_DIR}/boot" "${MNT_ROOT}"
  cp --recursive -- "${DOWNLOAD_DIR}/tce" "${MNT_ROOT}"
  log_info "Done"
}

########################################
# Install GRUB 2 bootloader on EFI partition.
# Globals:
#   MNT_EFI
#   PART_ROOT
#   WORK_DIR
# Arguments:
#   None
########################################
install_grub() {
  log_header "Installing GRUB 2"

  # TODO support legacy BIOS
  grub-install \
    --target=x86_64-efi \
    --boot-directory="${MNT_EFI}/EFI/BOOT" \
    --efi-directory="${MNT_EFI}" \
    --removable

  cp -- "${WORK_DIR}/grub.template.cfg" "${MNT_EFI}/EFI/BOOT/grub/grub.cfg"

  uuid="$(blkid --match-tag UUID --output value "${PART_ROOT}")"
  sed -i "s/<uuid>/${uuid}/g" "${MNT_EFI}/EFI/BOOT/grub/grub.cfg"

  log_info "Done"
}

########################################
# Unmount the device and delete temporary directory.
# Globals:
#   CLEAN_UP
# Arguments:
#   None
########################################
teardown() {
  [ "${CLEAN_UP}" != true ] && exit
  log_header "Cleaning Up"
  unmount_partitions
  delete_temporary_directory
}

########################################
# Main function of script.
# Arguments:
#   None
########################################
main() {
  show_runtime_info
  confirmation_prompt
  ensure_directories
  wipe_partitions
  create_partitions
  create_file_systems
  mount_file_systems
  download_tiny_core
  download_tiny_core_extensions
  create_custom_disk_burnin_extension
  install_tiny_core
  install_grub
  teardown
}

# entrypoint
main
