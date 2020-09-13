#!/bin/sh

. util/common.sh

readonly USAGE=\
"NAME
    $(basename -- "$0") -- create tiny, bootable stress test USB

SYNOPSIS
    $(basename -- "$0") [-h] [-c] [-y] <device>

DESCRIPTION
    Tool to create a bootable USB device, including a minimal Tiny Core Linux
    installation and various stress testing tools.

    ALL DATA ON <device> WILL BE LOST!

OPTIONS
    -h                Show help text
    -c                Clean up after the program succeeds. Delete temporary
                      directory and unmount the device.
    -y                Automatic yes to prompts
    <device>          USB device to use (/dev/ may be omitted)

EXAMPLES
    $(basename -- "$0") sda

    $(basename -- "$0") -y /dev/sdb

    $(basename -- "$0") -cy sdc"

while getopts ':hcy' option; do
  case "${option}" in
    h)  show_help
        exit 0
        ;;
    c)  readonly CLEAN_UP=true
        ;;
    y)  readonly AUTO_CONFIRM=true
        ;;
    :)  printf 'Missing argument for: -%s\n\n' "${OPTARG}" >&2
        show_help >&2
        exit 1
        ;;
   \?)  printf 'Illegal option: -%s\n\n' "${OPTARG}" >&2
        show_help >&2
        exit 1
        ;;
  esac
done
shift $(( OPTIND - 1 ))

if [ -z "$1" ]; then
  printf 'Missing option: <device>\n\n' >&2
  show_help >&2
  exit 1
fi

ensure_dependencies.sh mount  || exit "$?"
ensure_root_privileges.sh     || exit "$?"

DEVICE="$1"

# TODO duplicate
# prepend /dev/ if necessary
if ! printf '%s' "${DEVICE}" | grep -q "/dev/\w*"; then
  DEVICE="/dev/${DEVICE}"
fi
readonly DEVICE

# common directories
readonly MNT_DIR="${TMP_DIR}/mnt"
readonly DOWNLOAD_DIR="${TMP_DIR}/downloads"

# partitions
readonly PART_EFI="${DEVICE}1" # e.g. /dev/sdc1
readonly PART_ROOT="${DEVICE}2" # e.g. /dev/sdc2

# mount points
readonly MNT_EFI="${MNT_DIR}${PART_EFI}" # e.g. ./tmp/mnt/dev/sdc1
readonly MNT_ROOT="${MNT_DIR}${PART_ROOT}" # e.g. ./tmp/mnt/dev/sdc2

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
#   AUTO_CONFIRM
#   CLEAN_UP
# Arguments:
#   None
########################################
show_runtime_info() {
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

  log_header "Other"
  log_info "Auto-Confirm:   ${AUTO_CONFIRM}"
  log_info "Clean Up:       ${CLEAN_UP}"
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

  mkdir -p -- "${MNT_DIR}"
  mkdir -p -- "${DOWNLOAD_DIR}"
  mkdir -p -- "${MNT_EFI}"
  mkdir -p -- "${MNT_ROOT}"

  log_info "Done."
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
  log_info "Done."
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
  log_info "Done."
}

########################################
# Unmount the device and delete temporary directory.
# Globals:
#   CLEAN_UP
# Arguments:
#   None
########################################
teardown() {
  [ "${CLEAN_UP}" != true ] && exit 0
  log_header "Cleaning Up"
  unmount_partitions # TODO unknown
}

########################################
# Main function of script.
# Arguments:
#   None
########################################
main() {
  show_runtime_info
  ensure_directories
  if [ "${AUTO_CONFIRM}" = true ]; then
    format_usb.sh -y "${DEVICE}" || exit 1
  else
    format_usb.sh "${DEVICE}" || exit 1
  fi
  mount_file_systems
  tc_download.sh "${DOWNLOAD_DIR}" || exit 1
  tc_create_disk_burnin_extension.sh "${DOWNLOAD_DIR}/tce/optional" || exit 1
  printf 'disk-burnin.tcz\n' >> "${DOWNLOAD_DIR}/tce/onboot.lst"
  install_tiny_core
  install_grub.sh "${MNT_EFI}" || exit 1
  #teardown # TODO
}

main "$@"
