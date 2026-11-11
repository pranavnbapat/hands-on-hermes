#!/usr/bin/env bash
# Install the csv-reporting skill to ~/.hermes/skills/workshop/csv-reporting/.
#
# Hermes picks up any skill folder under ~/.hermes/skills/, so a plain copy is
# enough. `hermes skills install` is for registry/URL sources and runs a
# security scan first; copying skips that scan, so read SKILL.md before you
# install a skill this way.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/06-install-skill.sh [--force]
Run inside the workshop container.

  --force   replace a different copy that is already installed
            (the old one is moved to ~/.hermes/workshop-backups/)
EOF
}

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $arg (try --help)" 2 ;;
  esac
done
require_container

SKILL_NAME="csv-reporting"
SOURCE_DIR="$WORKSHOP_ROOT/skills/$SKILL_NAME"
SKILLS_ROOT="$HERMES_HOME_DIR/skills"
TARGET="$SKILLS_ROOT/workshop/$SKILL_NAME"

section "Check the skill before installing"
[ -f "$SOURCE_DIR/SKILL.md" ] || die "missing $SOURCE_DIR/SKILL.md"
have python3 || die "python3 is required for the frontmatter check"
python3 - "$SOURCE_DIR/SKILL.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
if not match:
    sys.exit("SKILL.md must start with a '---' YAML frontmatter block")
front, body = match.groups()
fields = dict(re.findall(r"^([A-Za-z_]+):\s*(.*)$", front, re.M))
name = fields.get("name", "").strip().strip("\"'")
description = fields.get("description", "").strip().strip("\"'")
problems = []
if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", name) or len(name) > 64:
    problems.append(f"invalid name {name!r} (lowercase letters, digits, . _ -; at most 64 chars)")
if not description:
    problems.append("description is missing")
elif len(description) > 60:
    problems.append(f"description is {len(description)} chars; Hermes shows only 60 in its skills index")
if not body.strip():
    problems.append("the instructions body is empty")
if problems:
    sys.exit("SKILL.md problems: " + "; ".join(problems))
print(f"[ OK ] frontmatter: name={name!r}, description={len(description)} chars")
PY
ok "Source: $SOURCE_DIR ($(find "$SOURCE_DIR" -type f | wc -l | tr -d ' ') file(s))"

# A second skill with the same name would clash with this one.
others="$(find "$SKILLS_ROOT" -name SKILL.md -path "*/$SKILL_NAME/SKILL.md" 2>/dev/null | grep -v "^$TARGET/SKILL.md$" || true)"
if [ -n "$others" ]; then
  warn "Another '$SKILL_NAME' skill is already installed; remove it to avoid confusion:"
  printf '%s\n' "$others" | sed 's/^/         /'
fi

section "Install"
if [ -d "$TARGET" ]; then
  if diff -rq "$SOURCE_DIR" "$TARGET" >/dev/null 2>&1; then
    ok "Already installed and identical: $TARGET"
  elif [ "$FORCE" = true ]; then
    backup="$HERMES_HOME_DIR/workshop-backups/$SKILL_NAME-$(timestamp)"
    mkdir -p "$(dirname "$backup")"
    mv "$TARGET" "$backup"
    cp -R "$SOURCE_DIR" "$TARGET"
    ok "Replaced the installed copy (previous version saved to $backup)"
  else
    fail "A different copy is installed at $TARGET. Not overwriting it."
    info "See what differs: diff -ru \"$TARGET\" \"$SOURCE_DIR\""
    info "Replace it (the old copy is backed up): bash scripts/06-install-skill.sh --force"
    exit 1
  fi
else
  mkdir -p "$(dirname "$TARGET")"
  cp -R "$SOURCE_DIR" "$TARGET"
  ok "Installed to $TARGET"
fi

section "Confirm Hermes can see it"
if have hermes; then
  # Not "cmd | grep -q": under pipefail that fails when grep exits early.
  listing="$(hermes skills list --source local 2>&1 || true)"
  if grep -q "$SKILL_NAME" <<<"$listing"; then
    ok "'hermes skills list --source local' lists $SKILL_NAME"
  else
    warn "Hermes does not list $SKILL_NAME yet. Run 'hermes skills list --source local' and check for errors."
  fi
else
  warn "hermes is not on PATH, so the listing could not be checked"
fi

summary || exit 1
cat <<EOF

Next: in Hermes, start a new session with /new (or type /reload-skills), then:
  /csv-reporting Analyse data/sales-sample-2.csv and save the report to reports/sales-sample-2-report.md
EOF
