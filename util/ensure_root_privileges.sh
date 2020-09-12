#!/bin/sh

########################################
# Exit with code 0 if running as root, code 1 otherwise.
# Arguments:
#   None
########################################
main() {
  [ "$(id -u)" -eq 0 ] && exit 0
  printf 'Must run as root\n' >&2
  exit 1
}

main "$@"
