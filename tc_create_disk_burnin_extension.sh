#!/bin/sh
# Create Tiny Core disk burn-in extension and output to specified directory.
#
# Wraps https://github.com/Spearfoot/disk-burnin-and-testing
#
# USAGE
#   ./tc_create_disk_burnin_extension.sh <directory>

. util/common.sh

ensure_dependencies.sh git mksquashfs || exit "$?"

if [ -z "$1" ]; then
  # default output directory
  readonly OUT_DIR="${WORK_DIR}"
else
  readonly OUT_DIR="$1"
fi

# base directory of extension
readonly EXT_DIR="${TMP_DIR}/disk-burnin"

# mirror resulting file system tree in Tiny Core Linux
readonly BIN_DIR="${EXT_DIR}/usr/local/bin"

# Git repository
readonly GIT_REPO_NAME="disk-burnin-and-testing"
readonly GIT_REPO_URL="https://github.com/Spearfoot/${GIT_REPO_NAME}.git"

log_header "Creating Disk Burn-In Extension"

rm -rf -- "${EXT_DIR}" || exit 1
mkdir -p -- "${BIN_DIR}" || exit 1

log_info "Downloading: ${GIT_REPO_URL} ..."

cd -- "${BIN_DIR}" || exit 1

git clone \
  --depth=1 \
  --branch=master \
  "${GIT_REPO_URL}" \
  "${GIT_REPO_NAME}" || exit 1

rm -rf -- "${GIT_REPO_NAME}/.git" || exit 1
ln -s "${GIT_REPO_NAME}/disk-burnin.sh" "disk-burnin"

cd -- "${WORK_DIR}" || exit 1

log_info "Packaging: ${OUT_DIR}/disk-burnin.tcz ..."

mksquashfs \
  "${EXT_DIR}" \
  "${OUT_DIR}/disk-burnin.tcz" \
  -b 4k \
  -no-xattrs \
  -noappend \
  -quiet || exit 1

log_info "Done."
