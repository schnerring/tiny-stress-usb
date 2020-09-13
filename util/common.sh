#!/bin/sh
# Commonly shared constants and functions.
# WARNING: only source, don't execute!

# common directories
readonly SCRIPT_DIR="$(dirname -- "$0")"; export SCRIPT_DIR
readonly WORK_DIR="$(pwd)";               export WORK_DIR
readonly TMP_DIR="/tmp/tiny_stress_usb";  export TMP_DIR
readonly LOG_FILE="${WORK_DIR}/log.txt";  export LOG_FILE

# file system labels
# 16 chars max length
readonly FS_LABEL_ROOT=tiny_stress_root;  export FS_LABEL_ROOT
readonly FS_LABEL_HOME=tiny_stress_home;  export FS_LABEL_HOME

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
# Log error message and exit with code 1.
# Arguments:
#   Message to log.
# Outputs:
#   Redirect log_info output to stderr.
##################################################
log_error()
{
  log_info "$1" >&2
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
# Show help text.
# Globals:
#   USAGE
# Arguments:
#   None
# Outputs:
#   Write help text to stdout.
########################################
show_help() {
  printf '%s\n' "${USAGE}"
}
