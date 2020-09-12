#!/bin/sh

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
# Arguments:
#   Device.
########################################
unmount_partitions() {
  log_info "Unmounting partitions"
  sleep 1
  umount --quiet "$1"?*
  sleep 1
}

########################################
# Inform OS about device's partition table changes.
# Arguments:
#   Device.
########################################
read_partition_table() {
  unmount_partitions "$1"
  partprobe "$1"
}

########################################
# Wipe all device partitions.
# Arguments:
#   Device
########################################
wipe_partitions() {
  log_header "Wiping Partitions"
  sgdisk --zap-all "$1"
  log_info "Done"
  read_partition_table "$1"
}

########################################
# Create EFI and root partitions.
# Arguments:
#   Device.
########################################
create_partitions() {
  log_header "Creating EFI Partition (100 MiB)"
  sgdisk --new 1:0:+100M --typecode 1:ef00 "$1"
  log_info "Done"

  log_header "Creating Root Partition (100%FREE)"
  sgdisk --new 2:0:0 "$1"
  log_info "Done"

  read_partition_table "$1"
}

########################################
# Create file systems.
# Arguments:
#   Device.
########################################
create_file_systems() {
  log_header "Creating FAT32 File System On EFI Partition"
  mkfs.fat -F 32 "${1}1" # e.g. /dev/sdc1
  log_info "Done"

  log_header "Creating ext2 File System On Root Partition"
  mkfs.ext2 -F "${1}2" # e.g. /dev/sdc2
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
  read_partition_table "$1"
  confirmation_prompt "$1" "$2"
  wipe_partitions "$1"
  create_partitions "$1"
  create_file_systems "$1"
}
