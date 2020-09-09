#!/bin/sh
readonly USAGE=\
"NAME
    $(basename "$0") -- create tiny, bootable stress test USB

SYNOPSIS
    $(basename "$0") [-h] [-l <directory>] <drive>

DESCRIPTION
    Tool to create a bootable USB device, including a minimal Tiny Core Linux
    installation and various stress testing tools.

    ALL DATA ON <drive> WILL BE LOST!

OPTIONS
    -h                show help text
    -l <directory>    write log files to <directory> (default: $(pwd))
    <drive>           USB drive to use (/dev/ may be omitted)

EXAMPLES
    $(basename "$0") sda

    $(basename "$0") -l . /dev/sdb

    $(basename "$0") -l ~/logs sdc"

# parse options
while getopts ':hl:' option; do
  case "${option}" in
    h)  echo "${USAGE}"
        exit
        ;;
    l)  LOG_DIR="${OPTARG}"
        ;;
    :)  printf 'Missing argument for -%s\n\n' "${OPTARG}" >&2
        printf '%s\n' "${USAGE}" >&2
        exit 2
        ;;
   \?)  printf 'Illegal option: -%s\n\n' "${OPTARG}" >&2
        printf '%s\n' "${USAGE}\n" >&2
        exit 2
        ;;
  esac
done
shift $(( OPTIND - 1 ))

if [ -z "$1" ]; then
  printf 'Missing option: <drive>\n\n' >&2
  printf '%s\n' "${USAGE}" >&2
  exit 2
fi

################################################################################
# CONSTANTS
################################################################################

DRIVE="$1"
# prepend /dev/ if necessary
if ! printf '%s' "${DRIVE}" | grep "/dev/\w*" > /dev/null 2>&1; then
  DRIVE="/dev/${DRIVE}"
fi
readonly DRIVE

[ -z "${LOG_DIR}" ] && LOG_DIR="$(pwd)"
