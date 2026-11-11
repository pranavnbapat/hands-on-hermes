#!/usr/bin/env bash
# Show the four files every Hermes session starts from (inside the container):
# SOUL.md, the lab's AGENTS.md, MEMORY.md and USER.md, and how much of each a new
# session loads, measured offline with 'hermes prompt-size'. Read-only.
#
# Usage: bash scripts/04.1-show-context-files.sh
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

for arg in "$@"; do
  case "$arg" in
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown option: $arg (try --help)" 2 ;;
  esac
done
require_container
have hermes || die "The 'hermes' command was not found. Check the install: bash scripts/03-verify-installation.sh"

bytes_of() { with_commas "$(wc -c <"$1" | tr -d ' ')"; }

# preview MAX_LINES < text: wrapped, indented, at most MAX_LINES lines.
preview() {
  local text total
  text="$(fold -s -w 88)"
  total="$(printf '%s\n' "$text" | wc -l | tr -d ' ')"
  printf '%s\n' "$text" | sed -n "1,${1}p" | sed 's/^/       | /'
  if [ "$total" -gt "$1" ]; then info "  ... $((total - $1)) more line(s)"; fi
}

section "1. SOUL.md: who the agent is (every session, wherever it starts)"
soul="$HERMES_HOME_DIR/SOUL.md"
if [ -s "$soul" ]; then
  ok "$soul ($(bytes_of "$soul") bytes). Hermes created it on first run; you may edit it."
  preview 6 <"$soul"
else
  info "$soul is missing or empty, so Hermes uses its built-in default identity."
fi

section "2. AGENTS.md: rules for one folder (every session started there reads them)"
agents="$LAB_DIR/AGENTS.md"
if [ -s "$agents" ]; then
  ok "$agents ($(bytes_of "$agents") bytes). You write it; script 04 copied the workshop's version."
  if grep -q '^## Rules' "$agents"; then
    sed -n '/^## Rules/,$p' "$agents" | preview 16
  else
    preview 16 <"$agents"
  fi
else
  warn "No AGENTS.md at $agents yet. Create the lab first: bash scripts/04-create-workspace.sh"
fi

section "3. MEMORY.md and USER.md: what the agent saved (every session, wherever it starts)"
for entry in "MEMORY.md|the agent's notes about the setup and what it learned" \
             "USER.md|what the agent knows about you"; do
  name="${entry%%|*}"; what="${entry#*|}"
  file="$HERMES_HOME_DIR/memories/$name"
  if [ -s "$file" ]; then
    count=$(( $(grep -c '^§$' "$file" || true) + 1 ))
    ok "$file: $count entr$([ "$count" -eq 1 ] && echo y || echo ies), $(bytes_of "$file") bytes ($what)"
    preview 10 <"$file"
  else
    info "$name: not created yet ($what)."
  fi
done
info "The agent creates these with its memory tool the first time it saves something."

section "4. What a new session would load (hermes prompt-size, offline)"
empty_dir="$(mktemp -d)"
trap 'rm -rf "$empty_dir"' EXIT
if [ ! -d "$LAB_DIR" ]; then
  warn "No lab at $LAB_DIR yet, so there is nothing to compare. Run: bash scripts/04-create-workspace.sh"
elif lab="$(prompt_bytes_in "$LAB_DIR")" && empty="$(prompt_bytes_in "$empty_dir")"; then
  read -r lab_ctx lab_mem lab_user lab_total <<<"$lab"
  read -r e_ctx e_mem e_user e_total <<<"$empty"
  row() { printf '       %-28s %14s %20s\n' "$1" "$2" "$3"; }
  row "" "in the lab" "in an empty folder"
  row "Folder rules (AGENTS.md)" "$(with_commas "$lab_ctx") B" "$(with_commas "$e_ctx") B"
  row "MEMORY.md" "$(with_commas "$lab_mem") B" "$(with_commas "$e_mem") B"
  row "USER.md" "$(with_commas "$lab_user") B" "$(with_commas "$e_user") B"
  row "Whole system prompt" "$(with_commas "$lab_total") B" "$(with_commas "$e_total") B"
  echo
  if [ "$lab_ctx" -gt 0 ] && [ "$e_ctx" -eq 0 ]; then
    ok "AGENTS.md is loaded only when Hermes starts in the lab (the bytes include Hermes' own heading)."
    extra=$(( lab_total - e_total - lab_ctx - (lab_mem - e_mem) - (lab_user - e_user) ))
    if [ "$extra" -gt 500 ]; then
      info "Most of the other $(with_commas "$extra") B: an AGENTS.md also marks the folder as a code project,"
      info "so Hermes adds its built-in coding guidance (setting agent.coding_context, default auto)."
    fi
  else
    warn "Unexpected: folder rules are $lab_ctx bytes in the lab and $e_ctx bytes in an empty folder."
  fi
  if [ "$lab_mem" -gt 0 ] || [ "$lab_user" -gt 0 ]; then
    ok "Saved memory is loaded in every new session, wherever it starts (same in both columns)."
  else
    info "Nothing saved in memory yet, hence 0 B. Run this again after the agent has saved a memory."
  fi
  info "SOUL.md is in every prompt too, inside Hermes' fixed identity and guidance block."
else
  warn "Could not read the output of 'hermes prompt-size --json'. Try 'cd $LAB_DIR && hermes prompt-size'."
fi
info "A running session keeps the prompt it started with: edits count from the next session (/new)."
