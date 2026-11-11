#!/usr/bin/env bash
# Download the official Hermes installer so you can read it first. It never
# runs it: "docker/workshop.sh build" later installs Hermes inside the image
# from exactly this file, pinned to its SHA-256.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: bash scripts/02-download-installer.sh [--ref REF] [--expected-sha256 HASH]

Saves the installer to .downloads/hermes-install.sh and shows what to review.

  --ref REF               GitHub ref to compare the download with (default: main)
  --expected-sha256 HASH  fail unless the file has exactly this SHA-256
                          (same as setting HERMES_INSTALLER_SHA256)
EOF
}

INSTALLER_URL="${HERMES_INSTALLER_URL:-https://hermes-agent.nousresearch.com/install.sh}"
REF="main"
EXPECTED_SHA="${HERMES_INSTALLER_SHA256:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || die "--ref needs a value" 2; REF="$2"; shift 2 ;;
    --expected-sha256) [ $# -ge 2 ] || die "--expected-sha256 needs a value" 2; EXPECTED_SHA="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" 2 ;;
  esac
done
GITHUB_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/${REF}/scripts/install.sh"

have curl || die "curl is required (run scripts/01-check-prerequisites.sh)"
DOWNLOAD_DIR="$WORKSHOP_ROOT/.downloads"
TARGET="$DOWNLOAD_DIR/hermes-install.sh"
mkdir -p "$DOWNLOAD_DIR"
TMP="$(mktemp "$DOWNLOAD_DIR/.install.XXXXXX")"
TMP_GH="$(mktemp "$DOWNLOAD_DIR/.github.XXXXXX")"
trap 'rm -f "$TMP" "$TMP_GH"' EXIT

section "Download"
info "Source: $INSTALLER_URL"
curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 --max-time 120 \
  --output "$TMP" "$INSTALLER_URL" || die "download failed; check your network and try again"
[ -s "$TMP" ] || die "the downloaded file is empty"
ok "Downloaded $(wc -c < "$TMP" | tr -d ' ') bytes"

section "Basic checks"
first_line="$(head -n 1 "$TMP")"
case "$first_line" in
  "#!/usr/bin/env bash"|"#!/bin/bash") ok "Starts with a bash shebang: $first_line" ;;
  *) die "unexpected first line '$first_line' (an HTML error page or a captive portal?). Not saving it." ;;
esac
if bash -n "$TMP"; then ok "bash syntax check passed (bash -n parses without executing)"; else die "bash syntax check failed"; fi

SHA="$(sha256_of "$TMP")" || die "no SHA-256 tool found (sha256sum or shasum)"
ok "SHA-256: $SHA"
if [ -n "$EXPECTED_SHA" ]; then
  if [ "$SHA" = "$EXPECTED_SHA" ]; then
    ok "Matches the expected SHA-256 you supplied"
  else
    fail "Does NOT match the expected SHA-256 ($EXPECTED_SHA)"
    info "The installer changed since the facilitator rehearsed. Ask before running it."
    exit 1
  fi
else
  info "No expected hash supplied. Facilitators: publish this hash and pass it with --expected-sha256."
fi

# The website serves the same file as scripts/install.sh in the official repository.
if curl --fail --location --silent --show-error --proto '=https' --max-time 60 --output "$TMP_GH" "$GITHUB_URL" 2>/dev/null; then
  if cmp -s "$TMP" "$TMP_GH"; then
    ok "Identical to scripts/install.sh on GitHub at ref '$REF'"
  else
    warn "Differs from scripts/install.sh on GitHub at ref '$REF' (the branch may simply have moved on)."
    info "Compare them yourself: curl -fsSL $GITHUB_URL | diff - $TARGET"
  fi
else
  warn "Could not fetch $GITHUB_URL for comparison"
fi

if [ -f "$TARGET" ]; then
  if cmp -s "$TMP" "$TARGET"; then
    info "Unchanged since your previous download."
  else
    mv "$TARGET" "$TARGET.previous"
    info "Different from your previous download; the old copy is now $TARGET.previous"
  fi
fi
mv "$TMP" "$TARGET"
chmod 0644 "$TARGET"   # deliberately not executable: you run it explicitly with bash after reading it

section "What to look for while reviewing"
info "1. Options it accepts (from its --help text):"
grep -n 'echo "Usage:\|echo "  *\[--' "$TARGET" | sed 's/^/          /' | head -n 6 || true
info "2. Where it edits your shell start-up files (adds ~/.local/bin to PATH):"
# shellcheck disable=SC2016  # literal \$HOME is the text we search for
grep -n 'append_shell_path "\$HOME' "$TARGET" | sed 's/^/          /' || true
info "3. When it may use sudo (only to install the libatomic system library on Linux):"
grep -nE '^[^#]*sudo' "$TARGET" | head -n 5 | sed 's/^/          /' || true
info "4. Every host it downloads from:"
grep -oE 'https://[A-Za-z0-9.-]+\.[a-z]{2,}' "$TARGET" | sort -u | sed 's/^/          /'

section "Next steps"
if in_workshop_container; then
  cat <<EOF
  You are inside a throwaway workshop container, so running the installer here is fine.
  Read the installer (q quits):          less "$TARGET"
  Then run it with the workshop flags:   bash "$TARGET" --non-interactive --skip-browser --skip-computer-use

  --non-interactive     skip the setup wizard at the end; you configure a model later
  --skip-browser        do not download Chromium (not needed in this workshop)
  --skip-computer-use   do not download the computer-use driver (not needed either)

  Afterwards: source ~/.bashrc && bash scripts/03-verify-installation.sh
EOF
else
  cat <<EOF
  1. Read the installer (q quits):   less "$TARGET"
  2. Build the workshop image:       bash docker/workshop.sh build
     The build runs THIS file inside the image (as an unprivileged user, with
     --non-interactive --skip-browser --skip-computer-use) and refuses to use
     any installer whose SHA-256 differs from $SHA.
  3. Open the container:             bash docker/workshop.sh start

  Do not run the installer on this machine: in this workshop Hermes lives only
  in the container. It installs the latest stable release (the materials were
  tested with v$WORKSHOP_HERMES_VERSION).
EOF
fi
