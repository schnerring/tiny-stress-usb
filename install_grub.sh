#!/bin/sh

. util/common.sh

readonly USAGE=\
"NAME
    $(basename -- "$0") -- install GRUB 2 bootloader

SYNOPSIS
    $(basename -- "$0") [-h] <directory>

DESCRIPTION
    Install GRUB 2 bootloader in specified directory.

OPTIONS
    -h            Show help text
    <directory>   Installation directory.

EXAMPLES
    $(basename -- "$0") /tmp/tiny_core/boot

    $(basename -- "$0") ./tc/boot"

# parse options
while getopts ':h' option; do
  case "${option}" in
    h)  show_help
        exit 0
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
  printf 'Missing option: <directory>\n\n' >&2
  show_help >&2
  exit 1
fi

ensure_dependencies.sh grub-install || exit "$?"
ensure_root_privileges.sh           || exit "$?"

INSTALL_DIR="$1"

readonly GRUB_CFG=\
"loadfont unicode
insmod all_video
set gfxterm_font=unicode
terminal_output gfxterm

search --no-floppy --label --set=root ${FS_LABEL_ROOT}

menuentry \"Tiny Stress USB\" {
    linux /boot/vmlinuz64 quiet text waitusb=5 tce=LABEL=${FS_LABEL_ROOT}/tce home=LABEL=${FS_LABEL_HOME}
    initrd /boot/corepure64.gz
}"

log_header "Installing GRUB 2"

# TODO support legacy BIOS
grub-install \
  --target=x86_64-efi \
  --boot-directory="${INSTALL_DIR}/EFI/BOOT" \
  --efi-directory="${INSTALL_DIR}" \
  --removable || exit 1

printf '%s' "${GRUB_CFG}" > "${INSTALL_DIR}/EFI/BOOT/grub/grub.cfg"

log_info "Done."
