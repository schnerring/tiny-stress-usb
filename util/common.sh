#!/bin/sh

readonly SCRIPT_DIR="$(dirname -- "$0")"
readonly WORK_DIR="$(pwd)"
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
  if [ "${log_status}" = 0 ]; then
    return 0
  else
    exit 1
  fi
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
