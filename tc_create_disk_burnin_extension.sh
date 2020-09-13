#!/bin/sh

. util/common.sh

readonly USAGE=\
"NAME
    $(basename -- "$0") -- create Tiny Core Linux disk burn-in extension

SYNOPSIS
    $(basename -- "$0") [-h] [-o <directory>]

DESCRIPTION
    Creates a Tiny Core Linux disk burn-in extension. It's just a wrapper for:

    https://github.com/Spearfoot/disk-burnin-and-testing

OPTIONS
    -h              Show help text
    -o <directory>  Output directory where packaged extension is put.
                    (default: $(pwd))

EXAMPLES
    $(basename -- "$0")

    $(basename -- "$0") -o .

    $(basename -- "$0") -o /tmp"

# parse options
while getopts ':ho:' option; do
  case "${option}" in
    h)  show_help
        exit 0
        ;;
    o)  readonly OUT_DIR="${OPTARG}"
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

ensure_dependencies.sh git mksquashfs || exit "$?"

# default output directory
[ -z "${OUT_DIR}" ] && readonly OUT_DIR="${WORK_DIR}"

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
