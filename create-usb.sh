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
readonly DEPENDENCIES="grep grub-install lsblk md5sum mkdir mkfs.fat mkfs.ext2 mksquashfs mount partprobe tee wget"
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
readonly DL_DIR="${TMP_DIR}/downloads"

# partitions
readonly PART_1="${DEVICE}1" # e.g. /dev/sdc1
readonly PART_2="${DEVICE}2" # e.g. /dev/sdc2

# mount points
readonly MNT_1="${MNT_DIR}${PART_1}" # e.g. ./tmp/mnt/dev/sdc1
readonly MNT_2="${MNT_DIR}${PART_2}" # e.g. ./tmp/mnt/dev/sdc2

# logging
[ -z "${LOG_DIR}" ] && LOG_DIR="${WORK_DIR}"
readonly LOG_FILE="${LOG_DIR}/log.txt"

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
#   DL_DIR
#   PART_1
#   PART_2
#   MNT_1
#   MNT_2
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
  log_info "Downloads:      ${DL_DIR}"

  log_header "EFI Partition"
  log_info "Partition:      ${PART_1}"
  log_info "Mount Point:    ${MNT_1}"

  log_header "Target Partition"
  log_info "Partition:      ${PART_2}"
  log_info "Mount Point:    ${MNT_2}"
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
#   DL_DIR
# Arguments:
#   None
########################################
ensure_directories() {
  log_header "Creating directories"

  mkdir -p -- "${TMP_DIR}"
  mkdir -p -- "${MNT_DIR}"
  mkdir -p -- "${DL_DIR}"
  mkdir -p -- "${MNT_1}"
  mkdir -p -- "${MNT_2}"

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
  log_header "Deleting temporary directory"
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
  log_header "Wiping partitions"
  sgdisk --zap-all "${DEVICE}"
  log_info "Done"
  read_partition_table
}

########################################
# Create EFI and target partitions.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
create_partitions() {
  #unmount_partitions

  log_header "Creating EFI partition (100 MiB)"
  sgdisk --new 1:0:+100M --typecode 1:ef00 "${DEVICE}"
  log_info "Done"

  log_header "Creating target partition (100%FREE)"
  sgdisk --new 2:0:0 "${DEVICE}"
  log_info "Done"

  read_partition_table
}

########################################
# Create file systems.
# Globals:
#   PART_1
#   PART_2
# Arguments:
#   None
########################################
create_file_systems() {
  unmount_partitions

  log_header "Creating FAT32 file system on EFI partition"
  mkfs.fat -F 32 "${PART_1}"
  log_info "Done"

  log_header "Creating ext2 file system on target partition"
  mkfs.ext2 -F "${PART_2}"
  log_info "Done"
}

########################################
# Mount file systems.
# Globals:
#   PART_1
#   PART_2
#   MNT_1
#   MNT_2
# Arguments:
#   None
########################################
mount_file_systems() {
  unmount_partitions

  log_header "Mounting file systems"

  mount "${PART_1}" "${MNT_1}"
  mount "${PART_2}" "${MNT_2}"

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
  #unmount_partitions
  #delete_temporary_directory
}

# entrypoint
main
