#!/bin/sh
# Install GRUB 2 to specified install directory.
#
# USAGE
#   ./install_grub.sh <directory>

. "$(dirname -- "$0")/util/common.sh"

if [ -z "$1" ]; then
  printf 'Missing option: install directory\n\n' >&2
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
