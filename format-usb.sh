#!/bin/sh

########################################
# Prompts for user confirmation.
# Globals:
#   AUTO_CONFIRM
#   DEVICE
# Arguments:
#   None
########################################
confirmation_prompt() {
  if [ "${AUTO_CONFIRM}" = true ]; then
    return
  fi

  printf 'ALL DATA ON %s WILL BE LOST!\n' "${DEVICE}"
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
#   DEVICE
# Arguments:
#   None
########################################
unmount_partitions() {
  log_info "Unmounting partitions"
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
  log_header "Wiping Partitions"
  read_partition_table
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
  log_header "Creating FAT32 File System On EFI Partition"
  mkfs.fat -F 32 "${PART_EFI}"
  log_info "Done"

  log_header "Creating ext2 File System On Root Partition"
  mkfs.ext2 -F "${PART_ROOT}"
  log_info "Done"

  unmount_partitions
}
