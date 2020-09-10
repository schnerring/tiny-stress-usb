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
readonly DEPENDENCIES="grep grub-install lsblk md5sum mksquashfs partprobe tee wget"
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
readonly WORKING_DIR="$(pwd)"
readonly TEMP_DIR="${WORKING_DIR}/temp"
readonly DOWNLOAD_DIR="${TEMP_DIR}/downloads"

# logging
readonly LOG_SEPARATOR="--------------------------------------------------------------------------------"
[ -z "${LOG_DIR}" ] && LOG_DIR="${WORKING_DIR}"
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
  log_info "${LOG_SEPARATOR}"
  log_info "  $1"
  log_info "${LOG_SEPARATOR}"
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
# Unmount all device partitions.
# The OS might auto-mount partitions in between steps which is why this function
# is called repeatedly throughout the script.
# Globals:
#   DEVICE
# Arguments:
#   None
########################################
unmount_partitions() {
  umount --quiet "${DEVICE}"?*
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
  log_header "Wiping partitions ..."
  sgdisk --zap-all "${DEVICE}"
  partprobe "${DEVICE}" # re-read partition table
}

##################################################
# Main function of script.
# Arguments:
#   None
##################################################
main() {
  confirmation_prompt
  wipe_partitions
}

# entrypoint
main
