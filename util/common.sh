#!/bin/sh

# common directories
readonly SCRIPT_DIR="$(dirname -- "$0")"
readonly WORK_DIR="$(pwd)"
readonly TMP_DIR="/tmp"
readonly LOG_FILE="${WORK_DIR}/log.txt"

# include script and utilities directory in PATH
PATH="${SCRIPT_DIR}:${SCRIPT_DIR}/util:${PATH}"

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
  printf '%s\n' "[${now}] $1" | tee -a "${LOG_FILE}"

  log_status="$?"
  [ "${log_status}" = 0 ] && return 0

  exit 1
}

##################################################
# Log emphasized header message.
# Arguments:
#   Message to log.
##################################################
log_header()
{
  log_info "+-----------------------------------------------------------"
  log_info "+ $1"
  log_info "+-----------------------------------------------------------"
}

########################################
# Delete log file.
# Globals:
#   LOG_FILE
# Arguments:
#   None
########################################
delete_log() {
  log_info "Deleting Log ${LOG_FILE} ..."
  rm -- "${LOG_FILE}" || exit 1
}

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
    ! wget --quiet --spider "$1" && return 0
    cd "$(dirname -- "$2")" || exit 1
    wget \
      --quiet \
      --continue \
      --show-progress \
      --output-document="$2" \
      "$1" || return "$?"
    cd "${WORK_DIR}" || exit 1
}
