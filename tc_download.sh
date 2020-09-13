#!/bin/sh

. util/common.sh

readonly USAGE=\
"NAME
    $(basename -- "$0") -- download Tiny Core Linux

SYNOPSIS
    $(basename -- "$0") [-h] [-a <architecture>] [-v <version>] [-o <directory>]

DESCRIPTION
    Download Tiny Core Linux with extensions required for stress testing:

      * e2fsprogs:      badblocks
      * kmaps:          additional keyboard layouts
      * screen:         session management
      * smartmontools:  SMART disk tooling
      * systester-cli:  CPU stress testing

OPTIONS
    -h              Show help text
    -a              Architecture: x86 or x86_64 (default: x86_64)
    -v              Tiny Core Linux version (default: 11)
    -o <directory>  Output directory (default: $(pwd))

EXAMPLES
    $(basename -- "$0")

    $(basename -- "$0") -o .

    $(basename -- "$0") -o /tmp"

# parse options
while getopts ':ha:v:o:' option; do
  case "${option}" in
    h)  show_help
        exit 0
        ;;
    a)  readonly ARCH="${OPTARG}"
        ;;
    v)  readonly VERSION="${OPTARG}"
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

ensure_dependencies.sh md5sum wget || exit "$?"

################################################################################
# CONSTANTS
################################################################################

[ -z "${ARCH}" ]    && readonly ARCH="x86_64"
[ -z "${VERSION}" ] && readonly VERSION="11"
[ -z "${OUT_DIR}" ] && readonly OUT_DIR="${WORK_DIR}"

readonly SITE_URL="http://tinycorelinux.net/${VERSION}.x/${ARCH}"
readonly EXTENSIONS="e2fsprogs kmaps screen smartmontools systester-cli"

################################################################################
# FUNCTIONS
################################################################################

########################################
# Download file.
# If URL doesn't exist, skip.
# If output file exists, skip or continue getting partially-downloaded file.
# Globals:
#   WORK_DIR
# Arguments:
#   Download URL.
#   Output file.
# Outputs:
#   Writes progress to stdout.
########################################
download_file() {
    wget --quiet --spider "$1" || return 0
    cd "$(dirname -- "$2")" || exit 1
    wget \
      --quiet \
      --continue \
      --show-progress \
      --output-document="$(basename "$2")" \
      "$1" || return "$?"
    cd "${WORK_DIR}" || exit 1
}

########################################
# Download Tiny Core Linux component and validate its MD5 checksum.
# Exit on checksum error.
# Globals:
#   WORK_DIR
# Arguments:
#   Download URL.
#   Destination file.
########################################
download_and_validate_component() {
    download_file "$1"         "$2"
    download_file "$1.md5.txt" "$2.md5.txt"

    cd "$(dirname -- "$2")" || exit 1
    md5sum --check "$(basename -- "$2").md5.txt"
    validation_status="$?"
    cd "${WORK_DIR}" || exit 1

    if [ "${validation_status}" -ne 0 ]; then
      log_info "Checksum error" >&2
      exit 1
    fi
}

########################################
# Download Tiny Core Linux core components.
# Globals:
#   OUT_DIR
#   SITE_URL
# Arguments:
#   None
########################################
download_base() {
    mkdir -p -- "${OUT_DIR}/boot"

    log_header "Downloading corepure64"
    download_and_validate_component \
      "${SITE_URL}/release/distribution_files/corepure64.gz" \
      "${OUT_DIR}/boot/corepure64.gz"
    log_info "Done."

    log_header "Downloading vmlinuz64"
    download_and_validate_component \
      "${SITE_URL}/release/distribution_files/vmlinuz64" \
      "${OUT_DIR}/boot/vmlinuz64"
    log_info "Done."
}

########################################
# Download Tiny Core Linux extension.
# Globals:
#   OUT_DIR
#   SITE_URL
# Arguments:
#   Name of the extension, including the .tcz extension.
########################################
already_downloaded=""
download_extension() {
  [ -z "$1" ] && return 1

  mkdir -p -- "${OUT_DIR}/tce/optional"

  log_info "Downloading: $1"

  if printf '%s' "${already_downloaded}" | grep -q "$1"; then
    log_info "Already downloaded: $1. Skipping."
    return
  fi

  download_and_validate_component \
    "${SITE_URL}/tcz/$1" \
    "${OUT_DIR}/tce/optional/$1"

  download_file \
    "${SITE_URL}/tcz/$1.dep" \
    "${OUT_DIR}/tce/optional/$1.dep"

  already_downloaded="${already_downloaded} $1"

  if [ -f "${OUT_DIR}/tce/optional/$1.dep" ]; then
    # download dependencies recursively
    while read -r dependency; do
      download_extension "${dependency}"
    done < "${OUT_DIR}/tce/optional/$1.dep"
  fi

  printf '%s\n' "$1" >> "${OUT_DIR}/tce/onboot.lst"
}

########################################
# Download Tiny Core Linux extensions.
# Globals:
#   OUT_DIR
#   EXTENSIONS
# Arguments:
#   None
########################################
download_extensions() {
  rm -f -- "${OUT_DIR}/tce/onboot.lst"
  for extension in ${EXTENSIONS}; do
    log_header "Downloading: ${extension}"
    download_extension "${extension}.tcz"
    log_info "Done."
  done
}

########################################
# Main function of script.
# Globals:
#   ARCH
#   VERSION
#   SITE_URL
#   EXTENSIONS
# Arguments:
#   None
########################################
main() {
  log_header "Downloading Tiny Core Linux"
  log_info "Architecture: ${ARCH}"
  log_info "Version:      ${VERSION}"
  log_info "Site URL:     ${SITE_URL}"
  log_info "Extensions:   ${EXTENSIONS}"

  download_base
  download_extensions
}

main "$@"
