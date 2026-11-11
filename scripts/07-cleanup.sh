#!/usr/bin/env bash
# Tidy up after the workshop: remove the demo cron job and move the
# csv-reporting skill to ~/.hermes/workshop-backups/. The lab, reports,
# memories and Hermes itself are yours to delete; it only prints how.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/07-cleanup.sh [--yes]
Without --yes it only shows what it would do.

To remove everything (container, Hermes, API key, lab), run this on your
machine instead: bash docker/workshop.sh reset
EOF
}

APPLY=false
for arg in "$@"; do
  case "$arg" in
    --yes) APPLY=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $arg (try --help)" 2 ;;
  esac
done
require_container
[ "$APPLY" = true ] || printf '%sDry run.%s Nothing will change. Re-run with --yes to apply.\n' "$C_BOLD" "$C_RESET"

CRON_JOB="workshop-sales-report"
SKILL_DIR="$HERMES_HOME_DIR/skills/workshop/csv-reporting"

section "Scheduled jobs"
if have hermes; then
  # Capture first (pipefail + grep -q don't mix).
  jobs_listing="$(hermes cron list --all 2>&1 || true)"
  if grep -q "Name: *$CRON_JOB\$" <<<"$jobs_listing"; then
    if [ "$APPLY" = true ]; then
      if hermes cron remove "$CRON_JOB"; then ok "Removed cron job $CRON_JOB"; else fail "Could not remove $CRON_JOB"; fi
    else
      info "Would run: hermes cron remove $CRON_JOB"
    fi
  else
    ok "No '$CRON_JOB' cron job found"
  fi
  info "Review any other jobs yourself: hermes cron list --all"
  info "If you started a gateway for the demo, stop it: Ctrl+C in its terminal, or 'hermes gateway stop' for a service."
else
  info "hermes not on PATH; skipping cron checks"
fi

section "Workshop skill"
if [ -d "$SKILL_DIR" ]; then
  if [ "$APPLY" = true ]; then
    backup="$HERMES_HOME_DIR/workshop-backups/csv-reporting-$(timestamp)"
    mkdir -p "$(dirname "$backup")"
    mv "$SKILL_DIR" "$backup"
    rmdir "$HERMES_HOME_DIR/skills/workshop" 2>/dev/null || true
    ok "Moved the skill to $backup"
  else
    info "Would move $SKILL_DIR to $HERMES_HOME_DIR/workshop-backups/"
  fi
else
  ok "Skill not installed"
fi

section "Left for you to decide"
info "Lab directory (your reports live here):  rm -r \"$LAB_DIR\""
info "Memories you added during the workshop: delete those entries from $HERMES_HOME_DIR/memories/USER.md"
info "  or MEMORY.md (bash scripts/04.1-show-context-files.sh shows both)."
info "  ('hermes memory reset' erases BOTH files completely, not only the workshop entries.)"
info "Provider keys: revoke workshop-only keys in your provider's dashboard."
info "Remove everything (container, Hermes, API key, lab): on your machine, bash docker/workshop.sh reset"
info "Then free the disk space: docker rmi hermes-workshop:latest hermes-workshop:prereqs"

summary || exit 1
