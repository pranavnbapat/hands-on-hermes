# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this file
# Helpers shared by the workshop scripts (sourced, not run).
# Sticks to bash 3.2 features because that's what macOS ships.

# Hermes release these materials were tested with.
WORKSHOP_HERMES_VERSION="0.23.1"
# The model every participant should use. Fresh installs pre-fill a premium one.
WORKSHOP_DEFAULT_MODEL="anthropic/claude-haiku-5.5"

WORKSHOP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

LAB_DIR="${HERMES_LAB_DIR:-$HOME/hermes-workshop-lab}"
HERMES_HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

ok()      { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
warn()    { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
fail()    { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info()    { printf '       %s\n' "$*"; }
section() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET"; }
die()     { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; exit "${2:-1}"; }
have()    { command -v "$1" >/dev/null 2>&1; }

sha256_of() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else return 1
  fi
}

# Octal permission bits of a file (GNU stat on Linux, BSD stat on macOS).
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

timestamp() { date +%Y%m%d-%H%M%S; }

# The shell start-up file the Hermes installer edits for this user's login shell.
shell_rc_file() {
  case "$(basename "${SHELL:-}")" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) printf '%s\n' "$HOME/.bashrc" ;;
    *)    printf '%s\n' "$HOME/.profile" ;;
  esac
}

# Hermes only ever runs inside the workshop container; docker/Dockerfile sets
# HERMES_WORKSHOP_CONTAINER=1 there.
in_workshop_container() { [ "${HERMES_WORKSHOP_CONTAINER:-}" = "1" ]; }

# Host guard: any step that installs, configures or runs Hermes calls this
# first and exits 3 on the host.
require_container() {
  in_workshop_container && return 0
  {
    printf '%sThis step runs inside the workshop container, not on this machine.%s\n' "$C_RED" "$C_RESET"
    printf 'In this workshop Hermes is never installed or run on the host. On the host, run:\n'
    printf '  bash docker/workshop.sh start      (or "shell" for a second terminal)\n'
    printf 'then run the same command inside the container, from ~/hermes-workshop.\n'
  } >&2
  exit 3
}

# Bytes a new session started in DIR would load, from 'hermes prompt-size --json'
# (offline): folder rules, MEMORY.md, USER.md, whole system prompt.
prompt_bytes_in() {
  (cd "$1" && hermes prompt-size --json 2>/dev/null) | python3 -c '
import json, sys
d = json.load(sys.stdin)
context = next(s[2] for s in d["sections"] if s[0].startswith("context"))
print(context, d["memory"]["bytes"], d["user_profile"]["bytes"], d["system_prompt"]["bytes"])
' 2>/dev/null
}

# 12345 -> 12,345
with_commas() { awk -v n="$1" 'BEGIN { s = ""; while (length(n) > 3) { s = "," substr(n, length(n) - 2) s; n = substr(n, 1, length(n) - 3) } print n s }'; }

# Don't let HERMES_LAB_DIR point at / or $HOME.
assert_safe_lab_dir() {
  case "$LAB_DIR" in
    ""|"/"|"$HOME"|"$HOME/") die "Refusing to use '$LAB_DIR' as the workshop directory. Set HERMES_LAB_DIR to a dedicated folder." 2 ;;
  esac
}

# Returns 1 if anything failed.
summary() {
  printf '\n%sSummary:%s %d ok, %d warning(s), %d failure(s)\n' "$C_BOLD" "$C_RESET" \
    "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  [ "$FAIL_COUNT" -eq 0 ]
}
