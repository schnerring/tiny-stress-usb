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
    -h                show help text
    -l <directory>    write log files to <directory> (default: $(pwd))
    -y                automatic \"yes\" to prompts
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
while getopts ':hl:y' option; do
  case "${option}" in
    h)  display_help
        exit
        ;;
    l)  LOG_DIR="${OPTARG}"
        ;;
    y)  readonly AUTO_CONFIRM_PROMPTS=true
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
grep
grub-install
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
if ! printf '%s' "${DEVICE}" | grep "/dev/\w*" > /dev/null 2>&1; then
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
  printf "%s\n" "[${now}] $1" | tee -a "${LOG_FILE}"
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
}

########################################
# Prompts for user confirmation.
# Globals:
#   AUTO_CONFIRM_PROMPTS
#   DEVICE
# Arguments:
#   None
########################################
confirmation_prompt() {
  if [ "${AUTO_CONFIRM_PROMPTS}" = true ]; then
    return
  fi

  printf 'ALL DATA ON %s WILL BE LOST!\n' "${DEVICE}"
  printf 'Really continue? (y/n) '
  read -r

  if ! printf '%s' "${REPLY}" | grep "^[Yy]$" > /dev/null 2>&1; then
    exit
  fi
}

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
  log_header "Deleting Temporary Directory"
  rm -rf "${TMP_DIR}"
  log_info "Done"
}

########################################
# Unmount all device partitions.
# The OS might auto-mount partitions in between steps which is why this function
# is called repeatedly throughout the script.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
unmount_partitions() {
  sleep 1
  umount --quiet "${DEVICE}"?*
  sleep 1
}

########################################
# Inform OS about device's partition table changes.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
read_partition_table() {
  unmount_partitions
  partprobe "${DEVICE}"
}

########################################
# Wipe all device partitions.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
wipe_partitions() {
  unmount_partitions
  log_header "Wiping Partitions"
  sgdisk --zap-all "${DEVICE}"
  log_info "Done"
  read_partition_table
}

########################################
# Create EFI and root partitions.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
create_partitions() {
  #unmount_partitions

  log_header "Creating EFI Partition (100 MiB)"
  sgdisk --new 1:0:+100M --typecode 1:ef00 "${DEVICE}"
  log_info "Done"

  log_header "Creating Root Partition (100%FREE)"
  sgdisk --new 2:0:0 "${DEVICE}"
  log_info "Done"

  read_partition_table
}

########################################
# Create file systems.
# Globals:
#   PART_EFI
#   PART_ROOT
# Arguments:
#   None
########################################
create_file_systems() {
  unmount_partitions

  log_header "Creating FAT32 File System On EFI Partition"
  mkfs.fat -F 32 "${PART_EFI}"
  log_info "Done"

  log_header "Creating ext2 File System On Root Partition"
  mkfs.ext2 -F "${PART_ROOT}"
  log_info "Done"
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
  unmount_partitions

  log_header "Mounting File Systems"

  mount "${PART_EFI}" "${MNT_EFI}"
  mount "${PART_ROOT}" "${MNT_ROOT}"

  log_info "Done"
}

########################################
# Download file.
# Arguments:
#   Download URL.
#   Destination file.
########################################
download_file() {
    wget \
      --quiet \
      --continue \
      --show-progress \
      --output-document="$2" \
      "$1"
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
    cd "$(dirname "$2")" || exit 2

    download_file "$1"         "$(basename "$2")"
    download_file "$1.md5.txt" "$(basename "$2").md5.txt"

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
########################################
download_tiny_core () {
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
# Install Tiny Core Linux on root partition.
# Globals:
#   DOWNLOAD_DIR
#   MNT_ROOT
########################################
install_tiny_core () {
  log_header "Installing Tiny Core Linux"
  cp --recursive "${DOWNLOAD_DIR}/boot" "${MNT_ROOT}"
  log_info "Done"
}

########################################
# Install GRUB 2 bootloader on EFI partition.
# Globals:
#   MNT_EFI
#   PART_ROOT
#   WORK_DIR
########################################
install_grub() {
  log_header "Installing GRUB 2"

  # TODO support legacy BIOS
  grub-install \
    --target=x86_64-efi \
    --boot-directory="${MNT_EFI}/EFI/BOOT" \
    --efi-directory="${MNT_EFI}" \
    --removable

  cp "${WORK_DIR}/grub.template.cfg" "${MNT_EFI}/EFI/BOOT/grub/grub.cfg"

  uuid="$(blkid --match-tag UUID --output value "${PART_ROOT}")"
  sed -i "s/<uuid>/${uuid}/g" "${MNT_EFI}/EFI/BOOT/grub/grub.cfg"

  log_info "Done"
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
  install_tiny_core
  install_grub
  #unmount_partitions
  #delete_temporary_directory
}

# entrypoint
main
