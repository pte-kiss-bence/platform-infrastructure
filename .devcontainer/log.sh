#!/usr/bin/env sh
# Shared colored logging for .devcontainer/*.sh scripts.
#
# POSIX sh (no bashisms) so it works on the host's /bin/sh (initializeCommand)
# and inside the container alike. Source it near the top of a script:
#
#     LOG_SCOPE=post-create  # short tag shown on every line
#     . "$(dirname "$0")/log.sh"
#     log_enable_error_trap   # red ✖ line on any failure under `set -e`
#
# Colors auto-disable when stdout is not a TTY or when NO_COLOR is set, so piped
# build logs stay clean while interactive rebuilds get color.

# Detect color support once. >&2 traffic (warn/error) follows stdout's decision
# to keep the stream consistent; that is the common, good-enough choice here.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _C_RESET='\033[0m'; _C_BOLD='\033[1m'; _C_DIM='\033[2m'
  _C_BLUE='\033[34m'; _C_GREEN='\033[32m'; _C_YELLOW='\033[33m'; _C_RED='\033[31m'
else
  _C_RESET=''; _C_BOLD=''; _C_DIM=''
  _C_BLUE=''; _C_GREEN=''; _C_YELLOW=''; _C_RED=''
fi

# Each line carries a scope tag so interleaved output from the three scripts is
# distinguishable. Default kept generic; callers set LOG_SCOPE before sourcing.
: "${LOG_SCOPE:=devcontainer}"

# log_step  — blue, a new phase is starting ("what it's doing now")
# log_info  — dim, a routine detail
# log_ok    — green, a step succeeded
# log_warn  — yellow, non-fatal, to stderr
# log_error — bold red, a failure, to stderr
log_step()  { printf '%b▶ [%s] %s%b\n' "$_C_BLUE$_C_BOLD" "$LOG_SCOPE" "$*" "$_C_RESET"; }
log_info()  { printf '%b· [%s] %s%b\n'  "$_C_DIM"          "$LOG_SCOPE" "$*" "$_C_RESET"; }
log_ok()    { printf '%b✓ [%s] %s%b\n'  "$_C_GREEN"        "$LOG_SCOPE" "$*" "$_C_RESET"; }
log_warn()  { printf '%b⚠ [%s] %s%b\n'  "$_C_YELLOW"       "$LOG_SCOPE" "$*" "$_C_RESET" >&2; }
log_error() { printf '%b✖ [%s] %s%b\n'  "$_C_RED$_C_BOLD"  "$LOG_SCOPE" "$*" "$_C_RESET" >&2; }

# Under `set -e` a failing command aborts the script silently. Trap EXIT and, if
# the exit code is non-zero, emit a red ✖ so the failure is impossible to miss.
# POSIX sh can't reliably report the failing line ($LINENO in traps is a bashism
# dash lacks), so we report the exit code — enough to spot which run died.
log_enable_error_trap() {
  trap '_log_ec=$?; [ "$_log_ec" -ne 0 ] && log_error "aborted (exit $_log_ec)"; exit $_log_ec' EXIT
}
