#!/bin/sh

. "./logging.sh"

# Duration to wait before attempting to unmount the device.
# Slow systems might take longer.
readonly SLEEP_BEFORE_UNMOUNT=1

########################################
# Prompts for user confirmation.
# Arguments:
#   Auto-confirm.
#   Device.
########################################
confirmation_prompt() {
  if [ "$2" = true ]; then
    return
  fi

  printf 'ALL DATA ON %s WILL BE LOST!\n' "$1"
  printf 'Really continue? (y/n) '
  read -r

  if ! printf '%s' "${REPLY}" | grep -q "^[Yy]$"; then
    exit
  fi
}

########################################
# Unmount all device partitions.
# The OS might auto-mount partitions in between steps which is why this function
# is called repeatedly throughout the script.
# Globals:
#   SLEEP_DURATION_BEFORE_UNMOUNT
# Arguments:
#   Device.
########################################
unmount_partitions() {
  log_info "Unmounting partitions"
  sleep "${SLEEP_BEFORE_UNMOUNT}"
  umount --quiet "$1"?* 2> /dev/null
}

########################################
# Inform OS about device's partition table changes.
# Arguments:
#   Device.
########################################
read_partition_table() {
  # TODO
  # Investigate reported errors about not being able to inform the kernel
  # because it seems to be working.
  partprobe "$1" 2> /dev/null
  unmount_partitions "$1"
}

########################################
# Wipe all device partitions.
# Arguments:
#   Device
########################################
wipe_partitions() {
  read_partition_table "$1"
  log_header "Wiping Partitions"
  # surpress warnings about having to re-read the partition table
  if ! sgdisk --zap-all "$1" 1> /dev/null; then
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done"
}

########################################
# Create EFI and root partitions.
# Arguments:
#   Device.
########################################
create_partitions() {
  read_partition_table "$1"
  log_header "Creating EFI Partition (100 MiB)"
  if ! sgdisk --new 1:0:+100M --typecode 1:ef00 "$1"; then
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done"

  log_header "Creating Root Partition (100%FREE)"
  if ! sgdisk --new 2:0:0 "$1"; then
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done"
}

########################################
# Create file systems.
# Arguments:
#   Device.
########################################
create_file_systems() {
  read_partition_table "$1"
  log_header "Creating FAT32 File System On EFI Partition"
  if ! mkfs.fat -F 32 "${1}1"; then # e.g. /dev/sdc1
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done"

  log_header "Creating ext2 File System On Root Partition"
  if ! mkfs.ext2 -F "${1}2"; then # e.g. /dev/sdc2
    log_info "Failed" >&2
    exit 1
  fi
  log_info "Done"

  unmount_partitions "$1"
}

########################################
# Main function of script.
# Arguments:
#   Device to format.
#   Boolean whether to auto-confirm prompt:
#     - true to auto-confirm
#     - false otherwise
########################################
format_usb() {
  confirmation_prompt "$1" "$2"
  wipe_partitions "$1"
  create_partitions "$1"
  create_file_systems "$1"
}
