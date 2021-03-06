#!/bin/sh

. "$(dirname -- "$0")/util/common.sh"

readonly USAGE=\
"NAME
    $(basename -- "$0") -- format USB device for Tiny Core Linux

SYNOPSIS
    $(basename -- "$0") [-h] [-y] <device>

DESCRIPTION
    Format USB device, so Tiny Core Linux can be installed.

    ALL DATA ON <device> WILL BE LOST!

    Partitioning layout:

      * EFI Partition   FAT32 100M
      * Root Partition  ext2   40M
      * Home Partition  ext2  100M

OPTIONS
    -h              Show help text
    -y              Automatic yes to prompts
    <device>        USB device to use (/dev/ may be omitted)

EXAMPLES
    $(basename -- "$0")

    $(basename -- "$0") sdc

    $(basename -- "$0") /dev/sdd"

while getopts ':hy' option; do
  case "${option}" in
    h)  show_help
        exit 0
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

ensure_dependencies.sh lsblk mkfs.fat mkfs.ext2 partprobe sgdisk umount || exit "$?"
ensure_root_privileges.sh || exit "$?"

readonly DEVICE="$1"

# check if USB device
readonly BUS_CONNECTION="$(lsblk --nodeps --noheadings --output TRAN "${DEVICE}")"
if [ "${BUS_CONNECTION}" != "usb" ]; then
  printf 'Not a USB device: %s\n' "${DEVICE}" >&2
  exit 1
fi

# TODO check minimum size 256 MiB

# Duration to wait before attempting to unmount the device.
# Slow systems might take longer.
readonly SLEEP_BEFORE_UNMOUNT=1 # TODO make configurable via option

########################################
# Prompts for user confirmation.
# Globals:
#   AUTO_CONFIRM
#   DEVICE
########################################
confirmation_prompt() {
  [ "${AUTO_CONFIRM}" = true ] && return 0

  printf 'ALL DATA ON %s WILL BE LOST!\n' "${DEVICE}"
  printf 'Really continue? (y/n) '
  read -r

  printf '%s' "${REPLY}" | grep -q "^[Yy]$" || log_error "Format aborted."
}

########################################
# Inform OS about device's partition table changes.
# Globals:
#   DEVICE
#   SLEEP_BEFORE_UNMOUNT
########################################
read_partition_table() {
  # TODO
  # Investigate reported errors about not being able to inform the kernel
  # because it seems to be working.
  partprobe "${DEVICE}" 2> /dev/null
  unmount_partitions "${DEVICE}" "${SLEEP_BEFORE_UNMOUNT}"
}

########################################
# Wipe all device partitions.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
wipe_partitions() {
  read_partition_table
  log_header "Wiping Partitions"
  # surpress warnings about having to re-read the partition table
  sgdisk --zap-all "${DEVICE}" 1> /dev/null || log_error "Failed."
  log_info "Done."
}

########################################
# Create EFI, root and home partitions.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
create_partitions() {
  read_partition_table

  log_header "Creating EFI Partition"
  sgdisk --new 1:0:+100M --typecode 1:ef00 "${DEVICE}" || log_error "Failed."
  log_info "Done."

  log_header "Creating Root Partition"
  sgdisk --new 2:0:+40M "${DEVICE}" || log_error "Failed."
  log_info "Done."

  log_header "Creating Home Partition"
  sgdisk --new 3:0:+100M "${DEVICE}" || log_error "Failed."
  log_info "Done."
}

########################################
# Create file systems.
# Globals:
#   DEVICE
#   SLEEP_BEFORE_UNMOUNT
# Arguments:
#   None
########################################
create_file_systems() {
  read_partition_table

  log_header "Creating FAT32 File System On EFI Partition"
  mkfs.fat -F 32 "${DEVICE}1" || log_error "Failed."
  log_info "Done."

  log_header "Creating ext2 File System On Root Partition"
  mkfs.ext2 -F "${DEVICE}2" -L "${FS_LABEL_ROOT}" || log_error "Failed."
  log_info "Done."

  log_header "Creating ext2 File System On Home Partition"
  mkfs.ext2 -F "${DEVICE}3" -L "${FS_LABEL_HOME}" || log_error "Failed."
  log_info "Done."

  unmount_partitions "${DEVICE}" "${SLEEP_BEFORE_UNMOUNT}"
}

########################################
# Main function of script.
# Arguments:
#   None
########################################
main() {
  log_header "Format USB device"
  log_info "Device:         ${DEVICE}"
  log_info "Bus Connection: ${BUS_CONNECTION}"

  confirmation_prompt
  wipe_partitions
  create_partitions
  create_file_systems
}

main "$@"
