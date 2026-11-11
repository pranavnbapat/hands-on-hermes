#!/usr/bin/env bash
# Check that Hermes is installed and has a model configured. Run it inside the
# container; on the host it stops with exit 3. Never prints key values.
#
# Usage: bash scripts/03-verify-installation.sh [--live]
#   --live   also send one tiny prompt (a few tokens) and show the usage
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

LIVE=false
for arg in "$@"; do
  case "$arg" in
    --live) LIVE=true ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) die "unknown option: $arg (try --help)" 2 ;;
  esac
done
require_container

section "Hermes command"
if ! have hermes; then
  if [ -x "$HOME/.local/bin/hermes" ]; then
    fail "Hermes is installed at ~/.local/bin/hermes but that directory is not on PATH in this terminal."
    info "Open a new terminal, or run: source $(shell_rc_file)"
  else
    fail "The 'hermes' command was not found in this container."
    info "Workshop container: rebuild on your machine (bash docker/workshop.sh build --refresh), then reset and start."
    info "Install-demo container: run the installer first (bash scripts/02-download-installer.sh shows how)."
  fi
  summary || true
  exit 1
fi
ok "hermes: $(command -v hermes)"

version_output="$(hermes --version 2>&1 || true)"
version_line="$(printf '%s\n' "$version_output" | head -n 1)"
if grep -q 'Hermes Agent v' <<<"$version_line"; then
  ok "$version_line"
  case "$version_line" in
    *"v$WORKSHOP_HERMES_VERSION "*) info "Same release the workshop materials were tested with." ;;
    *) warn "The materials were tested with v$WORKSHOP_HERMES_VERSION. Newer releases usually work; if a command differs, check '<command> --help'." ;;
  esac
else
  fail "'hermes --version' did not report a version:"
  printf '%s\n' "$version_output" | head -n 5 | sed 's/^/         /'
  exit 1
fi

section "Configuration files"
config_file="$(hermes config path 2>/dev/null || printf '%s' "$HERMES_HOME_DIR/config.yaml")"
env_file="$(hermes config env-path 2>/dev/null || printf '%s' "$HERMES_HOME_DIR/.env")"
if [ -f "$config_file" ]; then ok "Settings: $config_file"; else warn "No settings file yet at $config_file (run: hermes setup)"; fi
if [ -f "$env_file" ]; then
  mode="$(file_mode "$env_file" || printf '?')"
  if [ "$mode" = "600" ]; then
    ok "Secrets file: $env_file (permissions 600: only you can read it)"
  else
    warn "Secrets file $env_file has permissions $mode; tighten them with: chmod 600 \"$env_file\""
  fi
  # Names of the keys only, never the values.
  set_keys="$(grep -oE '^(OPENROUTER|OPENAI|ANTHROPIC|NOUS|GOOGLE|GEMINI|DEEPSEEK|XAI|HF|OLLAMA)_[A-Z_]*(API_KEY|TOKEN)=.+' "$env_file" 2>/dev/null | cut -d= -f1 | sort -u | tr '\n' ' ' || true)"
  if [ -n "$set_keys" ]; then
    ok "Provider credentials present (values not shown): $set_keys"
  else
    info "No common provider API key found in .env. That is fine for OAuth logins (e.g. Nous Portal) or local models."
  fi
else
  warn "No secrets file at $env_file yet"
fi

section "Model selection"
provider="$(hermes config get model.provider 2>/dev/null | head -n 1 || true)"
model="$(hermes config get model.default 2>/dev/null | head -n 1 || true)"
base_url="$(hermes config get model.base_url 2>/dev/null | head -n 1 || true)"
info "model.provider = ${provider:-<unset>}"
info "model.default  = ${model:-<unset>}"
[ -n "$base_url" ] && info "model.base_url = $base_url"
if [ -z "$provider" ] || [ "$provider" = "auto" ]; then
  warn "No provider chosen yet. Set it with 'hermes config set model.provider openrouter' (or run 'hermes model' to use your own provider) before you start Hermes."
else
  ok "Provider '$provider' with model '${model:-<provider default>}'"
fi
# A fresh install pre-fills a premium model; it stays in use until someone changes it.
if [ -n "$model" ] && [ "$model" != "$WORKSHOP_DEFAULT_MODEL" ]; then
  if [ "$provider" = "openrouter" ]; then
    warn "The model is '$model', not the workshop's $WORKSHOP_DEFAULT_MODEL. Unless your facilitator chose it, it can cost far more per prompt."
    info "Fix: hermes config set model.default $WORKSHOP_DEFAULT_MODEL"
    info "then restart any Hermes session that is already running (/quit, then start it again)."
  else
    info "Your own provider ($provider): check that '$model' is a small, low-cost model. To change it, run: hermes model"
  fi
fi

section "hermes doctor"
doctor_log="$(mktemp)"
trap 'rm -f "$doctor_log"' EXIT
set +e
hermes doctor >"$doctor_log" 2>&1
doctor_status=$?
set -e
grep -E '✗|Found [0-9]+ issue' "$doctor_log" | head -n 15 | sed 's/^/         /' || true
if [ "$doctor_status" -eq 0 ]; then
  ok "hermes doctor reported no unresolved problems"
else
  warn "hermes doctor exited with status $doctor_status. Read its full report with: hermes doctor"
  info "It asks for API keys of optional tools (chat platforms, X search and the like), which the"
  info "workshop doesn't need. Configuration errors and a missing provider key do matter."
fi

if [ "$LIVE" = true ]; then
  section "Live model check (sends one short prompt)"
  usage_file="$(mktemp)"
  trap 'rm -f "$doctor_log" "$usage_file"' EXIT
  # -z skips approval prompts, so only the harmless 'todo' toolset is allowed here.
  set +e
  reply="$(hermes -z "Reply with exactly the text HERMES_OK and nothing else." -t todo --usage-file "$usage_file" 2>&1)"
  live_status=$?
  set -e
  printf '         model replied: %s\n' "$(printf '%s' "$reply" | head -n 3)"
  if [ "$live_status" -eq 0 ] && grep -q 'HERMES_OK' <<<"$reply"; then
    ok "The configured model answered"
  else
    fail "The live check failed (exit status $live_status). Run 'hermes doctor' for details."
  fi
  if [ -s "$usage_file" ] && have python3; then
    python3 - "$usage_file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
total = data.get("total_including_auxiliary") or {}
print("         provider={} model={} api_calls={}".format(data.get("provider"), data.get("model"), data.get("api_calls")))
print("         input_tokens={} output_tokens={} total_tokens={}".format(
    data.get("input_tokens"), data.get("output_tokens"), data.get("total_tokens")))
cost = total.get("estimated_cost_usd", data.get("estimated_cost_usd"))
print("         estimated cost (USD, incl. auxiliary calls): {}".format(cost if cost is not None else "not reported"))
PY
    info "Notice how many input tokens a one-word answer needs: the system prompt and tool"
    info "definitions travel with every request."
  fi
fi

if summary; then
  printf '\nNext: bash scripts/04-create-workspace.sh\n'
  exit 0
fi
exit 1
