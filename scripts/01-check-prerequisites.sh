#!/usr/bin/env bash
# Is this machine ready for the workshop? Only looks, changes nothing.
# For anything missing it prints the commands to fix it, for you to run.
# On the host it checks Docker, disk space and network. Inside a workshop
# container (e.g. "docker/workshop.sh install-demo") it checks what the Hermes
# installer needs instead.
#
# Usage: bash scripts/01-check-prerequisites.sh [--offline]
#   --offline   skip the network checks
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

OFFLINE=false
for arg in "$@"; do
  case "$arg" in
    --offline) OFFLINE=true ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown option: $arg (try --help)" 2 ;;
  esac
done

OS="$(uname -s)"
ARCH="$(uname -m)"

# check_urls fail|warn URL...: any HTTP answer counts as reachable. "warn" is for
# sites only needed to build the image, when the image already exists.
check_urls() {
  local level="$1" url code; shift
  for url in "$@"; do
    code="$(curl -sS -o /dev/null --max-time 15 -w '%{http_code}' "$url" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "$code" != "000" ]; then
      ok "Reachable: $url (HTTP $code)"
    elif [ "$level" = warn ]; then
      warn "Cannot reach $url. Only needed to build the image, which is already built"
    else
      fail "Cannot reach $url"
      fix "run the check again (one-off timeouts happen); if it keeps failing, check Wi-Fi, VPN, proxy or firewall"
    fi
  done
}

# Minimums the host checks enforce (memory is a warning, disk a failure).
MIN_DOCKER_MEM_GB=4
MIN_DOCKER_DISK_GB=5

free_kb() { df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }

# "To fix" lines under a [FAIL] or [WARN]. They're printed, never run.
fix() {
  printf '       To fix: %s\n' "$1"; shift
  local line
  for line in "$@"; do printf '               %s\n' "$line"; done
}

# The install command for packages on this Linux distribution, if we know it.
pkg_install() {
  local ids=""
  # shellcheck source=/dev/null
  [ -r /etc/os-release ] && ids="$(. /etc/os-release && printf '%s %s' "${ID:-}" "${ID_LIKE:-}")"
  case " $ids " in
    *" debian "*|*" ubuntu "*) printf 'sudo apt-get install -y %s' "$*" ;;
    *" fedora "*|*" rhel "*|*" centos "*) printf 'sudo dnf install -y %s' "$*" ;;
    *) printf 'install %s with your package manager' "$*" ;;
  esac
}

host_checks() {
  printf '%sHermes workshop: checking this machine%s (Hermes itself runs only in the workshop container)\n' \
    "$C_BOLD" "$C_RESET"
  cat <<EOF

Minimum requirements:
  System    Linux, macOS, or Windows with WSL 2; x86_64 or arm64
  Commands  bash, curl, sha256sum or shasum (git is optional)
  Docker    Docker Engine, Docker Desktop or Colima, running and usable by you
  Memory    ${MIN_DOCKER_MEM_GB} GB available to Docker
  Disk      ${MIN_DOCKER_DISK_GB} GB free where Docker stores images
  Network   HTTPS to the Hermes installer, GitHub, Docker Hub, the Ubuntu
            mirror and OpenRouter
EOF

  # linux, wsl2, wsl1, macos or other: decides which fix commands to show.
  local platform=other
  case "$OS" in
    Linux)
      platform=linux
      if grep -qi microsoft /proc/version 2>/dev/null; then
        if grep -qi 'wsl2' /proc/version 2>/dev/null || [ -n "${WSL_INTEROP:-}" ]; then platform=wsl2; else platform=wsl1; fi
      fi
      ;;
    Darwin) platform=macos ;;
  esac

  section "Operating system and architecture"
  info "Detected: $OS $ARCH"
  case "$platform" in
    linux) ok "Linux" ;;
    wsl2) ok "Windows Subsystem for Linux 2 (use Docker Desktop's WSL integration or Docker Engine inside WSL)" ;;
    wsl1)
      fail "This is WSL 1; Docker needs WSL 2"
      fix "in Windows PowerShell: wsl --set-version <distribution> 2" "(wsl -l -v lists your distributions and their versions)"
      ;;
    macos) ok "macOS $(sw_vers -productVersion 2>/dev/null || true) ($ARCH). The container runs Linux, so Intel and Apple Silicon both work" ;;
    *)
      case "$OS" in
        MINGW*|MSYS*|CYGWIN*)
          fail "Git Bash, MSYS and Cygwin are not supported"
          fix "run the workshop in a WSL 2 terminal instead. To install WSL 2, in PowerShell as administrator:" \
              "  wsl --install" \
              "https://learn.microsoft.com/windows/wsl/install"
          ;;
        *) fail "Unsupported operating system: $OS (use Linux, macOS, or Windows with WSL 2)" ;;
      esac
      ;;
  esac
  case "$ARCH" in
    x86_64|amd64|arm64|aarch64) ok "CPU architecture $ARCH (the container image is built natively for it)" ;;
    *) fail "CPU architecture $ARCH is not supported (x86_64 and arm64 only)" ;;
  esac

  section "Required commands"
  local program
  for program in bash curl; do
    if have "$program"; then
      ok "$program: $(command -v "$program")"
    else
      fail "$program is missing"
      if [ "$platform" = macos ]; then fix "brew install $program   (Homebrew: https://brew.sh)"; else fix "$(pkg_install "$program")"; fi
    fi
  done
  if have git; then
    ok "git: $(command -v git)"
  else
    warn "git is missing: fine if you downloaded the workshop as a ZIP file"
    if [ "$platform" = macos ]; then fix "xcode-select --install"; else fix "$(pkg_install git)"; fi
  fi
  if have sha256sum || have shasum; then
    ok "SHA-256 tool: $(command -v sha256sum || command -v shasum) (to fingerprint the installer you review)"
  else
    fail "Neither sha256sum nor shasum is available"
    if [ "$platform" = macos ]; then fix "brew install coreutils   (Homebrew: https://brew.sh)"; else fix "$(pkg_install coreutils)"; fi
  fi

  section "Docker"
  local docker_err=""
  if ! have docker; then
    fail "Docker is not installed, and this workshop requires it"
    case "$platform" in
      macos) fix "install Docker Desktop: https://docs.docker.com/desktop/setup/install/mac-install/" \
                 "or Colima, which is free (needs Homebrew, https://brew.sh):" \
                 "  brew install colima docker" \
                 "  colima start --memory $MIN_DOCKER_MEM_GB" ;;
      wsl2)  fix "install Docker Desktop on Windows and turn on its WSL integration for this distribution:" \
                 "https://docs.docker.com/desktop/features/wsl/" \
                 "(or install Docker Engine inside WSL: https://docs.docker.com/engine/install/)" ;;
      *)     fix "install Docker Engine for your distribution: https://docs.docker.com/engine/install/" \
                 "then let your user run it, and log out and in again:" \
                 "  sudo usermod -aG docker \"\$USER\"" ;;
    esac
  elif ! docker_err="$(docker info 2>&1 >/dev/null)"; then
    if grep -qi 'permission denied' <<<"$docker_err"; then
      fail "Docker is installed, but your user isn't allowed to use it"
      fix "sudo usermod -aG docker \"\$USER\"   then log out and in again (or run: newgrp docker)" \
          "https://docs.docker.com/engine/install/linux-postinstall/"
    else
      fail "Docker is installed but not running"
      case "$platform" in
        macos) fix "open Docker Desktop, or with Colima: colima start --memory $MIN_DOCKER_MEM_GB" ;;
        wsl2)  fix "start Docker Desktop on Windows, and check that Settings > Resources > WSL integration" \
                   "is on for this distribution (Docker Engine inside WSL instead: sudo service docker start)" ;;
        *)     fix "sudo systemctl start docker   (start it at every boot: sudo systemctl enable docker)" ;;
      esac
    fi
  else
    ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || printf '?') is running ($(docker info --format '{{.OSType}}/{{.Architecture}}' 2>/dev/null || true))"
    local mem_bytes mem_gb
    mem_bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null || printf 0)"
    mem_gb=$((mem_bytes / 1024 / 1024 / 1024))
    if [ "$mem_gb" -ge "$MIN_DOCKER_MEM_GB" ]; then
      ok "Memory available to Docker: ${mem_gb} GB (minimum ${MIN_DOCKER_MEM_GB} GB)"
    else
      warn "Docker has only ${mem_gb} GB of memory; give it at least ${MIN_DOCKER_MEM_GB} GB"
      case "$platform" in
        macos) fix "Docker Desktop: Settings > Resources > Memory" \
                   "Colima: colima stop, then colima start --memory $MIN_DOCKER_MEM_GB" ;;
        wsl2)  fix "Docker Desktop on WSL 2 gets WSL's memory. In Windows, add to %UserProfile%\\.wslconfig:" \
                   "  [wsl2]" \
                   "  memory=${MIN_DOCKER_MEM_GB}GB" \
                   "then run wsl --shutdown in PowerShell and start Docker Desktop again" ;;
        *)     fix "Docker uses this machine's memory directly: close other programs, or use a machine with more RAM" ;;
      esac
    fi
    if docker image inspect hermes-workshop:latest >/dev/null 2>&1; then
      ok "Workshop image already built (hermes-workshop:latest)"
    else
      info "Workshop image not built yet (next steps below)."
    fi
  fi

  section "Disk space"
  local where avail_kb
  where="$HOME"
  if [ "$OS" = "Linux" ] && have docker && docker info >/dev/null 2>&1; then
    where="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || printf '%s' "$HOME")"
  fi
  avail_kb="$(free_kb "$where")"
  if [ -n "$avail_kb" ]; then
    # The image ends up around 2.7 GB but the build needs more while it runs.
    if [ "$avail_kb" -lt $((MIN_DOCKER_DISK_GB * 1024 * 1024)) ]; then
      fail "Only $((avail_kb / 1024 / 1024)) GB free for Docker ($where); the workshop image needs about ${MIN_DOCKER_DISK_GB} GB while building"
      fix "free up space on that disk. 'docker system df' shows how much Docker itself uses;" \
          "remove only images and volumes you recognise"
    else
      ok "$((avail_kb / 1024 / 1024)) GB free for Docker ($where; minimum ${MIN_DOCKER_DISK_GB} GB)"
    fi
    if [ "$OS" = "Darwin" ]; then
      info "Docker Desktop and Colima keep images in a virtual disk with its own size limit (Docker Desktop: Settings > Resources; Colima: 100 GB by default)."
    fi
  else
    warn "Could not determine free disk space"
  fi

  section "Network"
  if [ "$OFFLINE" = true ]; then
    info "Skipped (--offline)"
  else
    if [ -n "${HTTPS_PROXY:-}${https_proxy:-}" ]; then
      info "An HTTPS proxy is configured (value not shown). Docker may need its own proxy settings."
    fi
    local apt_mirror=http://archive.ubuntu.com
    case "$ARCH" in arm64|aarch64) apt_mirror=http://ports.ubuntu.com ;; esac
    check_urls fail https://hermes-agent.nousresearch.com/install.sh https://github.com https://openrouter.ai
    # Docker Hub and the Ubuntu mirror are only used while building the image.
    local build_level=fail
    if have docker && docker image inspect hermes-workshop:latest >/dev/null 2>&1; then build_level=warn; fi
    check_urls "$build_level" https://registry-1.docker.io/v2/ "$apt_mirror"
  fi

  section "Hermes on this machine"
  if have hermes; then
    warn "Hermes is installed directly on this machine ($(command -v hermes)). The workshop does not use it; everything runs in the container."
    fix "nothing needed for the workshop. To remove it: hermes uninstall"
  else
    ok "Hermes is not installed on this machine (as intended)"
  fi
}

container_checks() {
  printf '%sInside a workshop container: checking the Hermes installer prerequisites%s\n' "$C_BOLD" "$C_RESET"

  section "Operating system and architecture"
  info "Detected: $OS $ARCH"
  if [ "$OS" = "Linux" ]; then ok "Linux container"; else fail "Expected a Linux container, got $OS"; fi
  case "$ARCH" in
    x86_64|amd64|arm64|aarch64) ok "CPU architecture $ARCH is supported by Hermes" ;;
    *) fail "CPU architecture $ARCH is not supported by Hermes" ;;
  esac

  section "Installer prerequisites"
  local program
  for program in bash git curl tar; do
    if have "$program"; then ok "$program: $(command -v "$program")"; else fail "$program is missing"; fi
  done
  if have sha256sum || have shasum; then ok "SHA-256 tool present"; else fail "No SHA-256 tool"; fi
  if have python3; then ok "python3 (used by the workshop verifier)"; else fail "python3 is missing"; fi
  local ldconfig_bin libs
  ldconfig_bin="$(command -v ldconfig || true)"
  if [ -z "$ldconfig_bin" ] && [ -x /sbin/ldconfig ]; then ldconfig_bin=/sbin/ldconfig; fi
  if [ -n "$ldconfig_bin" ]; then
    libs="$("$ldconfig_bin" -p 2>/dev/null || true)"   # capture: "cmd | grep -q" breaks under pipefail
    if grep -q 'libatomic.so.1' <<<"$libs"; then ok "libatomic.so.1 present"; else warn "libatomic.so.1 missing (the installer needs it)"; fi
  fi

  section "Disk space"
  local avail_kb
  avail_kb="$(free_kb "$HOME")"
  if [ -n "$avail_kb" ] && [ "$avail_kb" -lt $((3 * 1024 * 1024)) ]; then
    fail "Only $((avail_kb / 1024 / 1024)) GB free; Hermes needs about 2.5 GB"
  elif [ -n "$avail_kb" ]; then
    ok "$((avail_kb / 1024 / 1024)) GB free in $HOME"
  fi

  section "Network"
  if [ "$OFFLINE" = true ]; then
    info "Skipped (--offline)"
  else
    check_urls fail https://hermes-agent.nousresearch.com/install.sh https://github.com https://openrouter.ai
  fi

  section "Hermes in this container"
  if have hermes; then
    ok "hermes found: $(hermes --version 2>/dev/null | head -n 1 || true)"
  else
    info "Hermes is not installed in this container yet."
  fi
}

if in_workshop_container; then container_checks; else host_checks; fi

if summary; then
  if in_workshop_container; then
    printf '\nReady. Next: bash scripts/02-download-installer.sh\n'
  else
    cat <<'EOF'

This machine is ready. Next:
  bash scripts/02-download-installer.sh    # download and review the official installer
  bash docker/workshop.sh build            # install Hermes inside the image, pinned to what you reviewed
  bash docker/workshop.sh start            # open a shell inside the container
EOF
  fi
  exit 0
fi
printf '\nFix the [FAIL] items above ("To fix" shows how), then run this script again.\n'
printf 'This script installed and changed nothing; the commands are for you to run.\n'
exit 1
