#!/bin/sh

########################################
# Exit with code 0 if dependencies are met, code 1 otherwise.
# Arguments:
#   Dependencies to check.
# Outputs:
#   Write name of first command not found to stderr.
########################################
main() {
  for dependency in "$@"; do
    if ! command -v "${dependency}" > /dev/null 2>&1; then
      printf 'Command not found: %s\n' "${dependency}" >&2
      exit 1
    fi
  done
}

main "$@"
