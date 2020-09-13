#!/bin/sh

. "$(dirname -- "$0")/util/common.sh"

readonly USAGE=\
"NAME
    $(basename -- "$0") -- create tiny, bootable stress test USB

SYNOPSIS
    $(basename -- "$0") [-h] [-c] [-u] [-y] <device>

DESCRIPTION
    Tool to create a bootable USB device, including a minimal Tiny Core Linux
    installation and various stress testing tools.

    ALL DATA ON <device> WILL BE LOST!

OPTIONS
    -h                Show help text
    -c                Clean up after program succeeds. Unmount device and delete
                      temporary directory.
    -u                Unmount device after program succeeds
    -y                Automatic yes to prompts
    <device>          USB device to use (/dev/ may be omitted)

EXAMPLES
    $(basename -- "$0") sda

    $(basename -- "$0") -y /dev/sdb

    $(basename -- "$0") -cy sdc"

while getopts ':hcuy' option; do
  case "${option}" in
    h)  show_help
        exit 0
        ;;
    c)  readonly CLEAN_UP=true
        ;;
    u)  readonly UNMOUNT=true
        ;;
    y)  readonly AUTO_CONFIRM="-y"
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

ensure_root_privileges.sh     || exit "$?"

readonly DEVICE="$1"

format_usb.sh ${AUTO_CONFIRM} "${DEVICE}" \
  || log_error "Format failed: ${DEVICE}"

mkdir -p -- "${TMP_DIR}/mnt/efi" \
  || log_error "Creating directory failed: ${TMP_DIR}/mnt/efi"

mount -- "${DEVICE}1" "${TMP_DIR}/mnt/efi" \
  || log_error "Mount failed: ${DEVICE}1 on ${TMP_DIR}/mnt/efi"

install_grub.sh "${TMP_DIR}/mnt/efi" \
  || log_error "Installing GRUB failed"

tc_download.sh "${TMP_DIR}/downloads" \
  || log_error "Downloading Tiny Core Linux failed"

tc_create_disk_burnin_extension.sh "${TMP_DIR}/downloads/tce/optional" \
  || log_error "Creating Tiny Core extension failed: disk-burnin"
printf 'disk-burnin.tcz\n' >> "${TMP_DIR}/downloads/tce/onboot.lst"

mkdir -p -- "${TMP_DIR}/mnt/root" \
  || log_error "Creating directory failed: ${TMP_DIR}/mnt/root"

mount -- "${DEVICE}2" "${TMP_DIR}/mnt/root" \
  || log_error "Mount failed: ${DEVICE}2 on ${TMP_DIR}/mnt/root"

cp -r -- "${TMP_DIR}/downloads/boot" "${TMP_DIR}/mnt/root" \
  || log_error "Copy failed: ${TMP_DIR}/downloads/boot to ${TMP_DIR}/mnt/root"

cp -r -- "${TMP_DIR}/downloads/tce" "${TMP_DIR}/mnt/root" \
  || log_error "Copy failed: ${TMP_DIR}/downloads/tce to ${TMP_DIR}/mnt/root"

if [ "${CLEAN_UP}" = true ]; then
  unmount_partitions "${DEVICE}"
  rm -rf -- "${TMP_DIR}"
elif [ "${UNMOUNT}" = true ]; then
  unmount_partitions "${DEVICE}"
fi

log_header "Completed."
