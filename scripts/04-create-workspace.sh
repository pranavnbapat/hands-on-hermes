#!/usr/bin/env bash
# Set up the lab folder the agent works in (inside the container):
# ~/hermes-workshop-lab with AGENTS.md, data/, reports/ and work/.
# Set HERMES_LAB_DIR to use a different folder.
#
# Re-running is fine. Files that were changed are left alone unless you pass
# --restore, which moves them to .backup/ and puts the originals back.
#
# Usage: bash scripts/04-create-workspace.sh [--restore]
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

RESTORE=false
for arg in "$@"; do
  case "$arg" in
    --restore) RESTORE=true ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option: $arg (try --help)" 2 ;;
  esac
done
require_container
assert_safe_lab_dir

section "Workspace: $LAB_DIR"
mkdir -p "$LAB_DIR/data" "$LAB_DIR/reports" "$LAB_DIR/work"
ok "Directories data/, reports/ and work/ exist"

BACKUP_DIR="$LAB_DIR/.backup/$(timestamp)"
DIFFERENT=0

# Copy a file into the lab, but don't clobber local changes.
place() {
  local source_file="$1" dest="$2" label="$3"
  if [ ! -e "$dest" ]; then
    cp "$source_file" "$dest"
    ok "Created $label"
  elif cmp -s "$source_file" "$dest"; then
    ok "$label is up to date"
  elif [ "$RESTORE" = true ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dest" "$BACKUP_DIR/"
    cp "$source_file" "$dest"
    warn "$label had been changed; restored the original (changed copy saved in ${BACKUP_DIR#"$LAB_DIR"/}/)"
  else
    warn "$label differs from the workshop original. It was left untouched."
    DIFFERENT=$((DIFFERENT + 1))
  fi
}

place "$WORKSHOP_ROOT/lab-template/AGENTS.md" "$LAB_DIR/AGENTS.md" "AGENTS.md"
for csv in "$WORKSHOP_ROOT"/data/*.csv; do
  place "$csv" "$LAB_DIR/data/$(basename "$csv")" "data/$(basename "$csv")"
done

section "Contents"
(cd "$LAB_DIR" && find . -path ./.backup -prune -o -type f -print | sort | sed 's/^/       /')

if [ "$DIFFERENT" -gt 0 ]; then
  printf '\n%d file(s) differ from the originals. If the agent modified them, run:\n' "$DIFFERENT"
  printf '  bash scripts/04-create-workspace.sh --restore\n'
  exit 1
fi

cat <<EOF

Workspace ready. Start Hermes from inside it so AGENTS.md is loaded:
  cd "$LAB_DIR" && hermes --checkpoints

Check the reference figures at any time in a second terminal (on your machine run
"bash docker/workshop.sh shell"; it opens in ~/hermes-workshop):
  python3 scripts/05-verify-results.py --dataset "$LAB_DIR/data/sales-sample.csv"
EOF
