#!/bin/sh

. util/common.sh

readonly USAGE=\
"NAME
    $(basename -- "$0") -- format USB device for Tiny Core Linux

SYNOPSIS
    $(basename -- "$0") [-h] [-y] <device>

DESCRIPTION
    Format USB device, so Tiny Core Linux can be installed. Creates an EFI and
    root partition.

    ALL DATA ON <device> WILL BE LOST!

OPTIONS
    -h              Show help text
    -y              Automatic yes to prompts
    <device>        USB device to use (/dev/ may be omitted)

EXAMPLES
    $(basename -- "$0")

    $(basename -- "$0") sdc

    $(basename -- "$0") /dev/sdd"

########################################
# Display help text.
# Globals:
#   USAGE
# Arguments:
#   None
# Outputs:
#   Write help text to stdout.
########################################
show_help() {
  printf '%s\n' "${USAGE}"
}

# parse options
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

ensure_dependencies.sh \
  lsblk mkfs.fat mkfs.ext2 partprobe sgdisk umount || exit "$?"

ensure_root_privileges.sh || exit "$?"

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
  exit 1
fi

# Duration to wait before attempting to unmount the device.
# Slow systems might take longer.
readonly SLEEP_BEFORE_UNMOUNT=1

########################################
# Prompts for user confirmation.
# Globals:
#   AUTO_CONFIRM
#   DEVICE
########################################
confirmation_prompt() {
  if [ "${AUTO_CONFIRM}" = true ]; then
    return
  fi

  printf 'ALL DATA ON %s WILL BE LOST!\n' "${DEVICE}"
  printf 'Really continue? (y/n) '
  read -r

  if ! printf '%s' "${REPLY}" | grep -q "^[Yy]$"; then
    exit 0
  fi
}

########################################
# Unmount all device partitions.
# The OS might auto-mount partitions in between steps which is why this function
# is called repeatedly throughout the script.
# Globals:
#   DEVICE
#   SLEEP_BEFORE_UNMOUNT
########################################
unmount_partitions() {
  log_info "Unmounting partitions in ${SLEEP_BEFORE_UNMOUNT} seconds"
  sleep "${SLEEP_BEFORE_UNMOUNT}"
  umount --quiet "${DEVICE}"?* 2> /dev/null
  return 0
}

########################################
# Inform OS about device's partition table changes.
# Globals:
#   DEVICE
########################################
read_partition_table() {
  # TODO
  # Investigate reported errors about not being able to inform the kernel
  # because it seems to be working.
  partprobe "${DEVICE}" 2> /dev/null
  unmount_partitions
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
  if ! sgdisk --zap-all "${DEVICE}" 1> /dev/null; then
    log_info "Failed" >&2
    exit 1
  fi

  log_info "Done."
}

########################################
# Create EFI and root partitions.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
create_partitions() {
  read_partition_table

  log_header "Creating EFI Partition"
  if ! sgdisk --new 1:0:+100M --typecode 1:ef00 "${DEVICE}"; then
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done."

  log_header "Creating Root Partition"
  if ! sgdisk --new 2:0:0 "${DEVICE}"; then
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done."
}

########################################
# Create file systems.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
create_file_systems() {
  read_partition_table

  log_header "Creating FAT32 File System On EFI Partition"
  if ! mkfs.fat -F 32 "${DEVICE}1"; then # e.g. /dev/sdc1
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done."

  log_header "Creating ext2 File System On Root Partition"
  if ! mkfs.ext2 -F "${DEVICE}2"; then # e.g. /dev/sdc2
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done."

  unmount_partitions
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
