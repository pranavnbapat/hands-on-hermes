#!/usr/bin/env bash
# Run the Hermes workshop in a Docker container so the agent can't see your
# laptop. Hermes, your API key and the lab live in a named volume and survive
# restarts until you "reset". The repo is mounted read-only and copied in.
#
# Usage: bash docker/workshop.sh <command> [options]
#
#   build [--installer-sha256 HASH] [--unpinned] [--refresh]
#                   build the image (runs the official Hermes installer inside).
#                   Pinned to the SHA-256 of .downloads/hermes-install.sh, the
#                   copy scripts/02-download-installer.sh fetches for review;
#                   without it the build stops. --unpinned skips the review and
#                   the pin; --refresh ignores the build cache
#   start [--web]   start or resume the container and open a shell in it
#                   (builds the image first if needed, with the same rules).
#                   --web also publishes Hermes' web dashboard on 127.0.0.1:9119
#                   (only on this machine); it takes effect when the container
#                   is created
#   shell           another shell in the running container
#   run CMD...      run one command inside, e.g. run hermes --version
#   sync            copy the repo in again after you edit it
#   status          image, container and volume state
#   stop            stop the container (keeps everything)
#   reset [--yes]   delete the container AND its volume (Hermes, key, sessions, lab)
#   install-demo [CMD...]
#                   throwaway container with the prerequisites but no Hermes,
#                   for the live install demo; gone when you exit
#
# HERMES_WS_IMAGE, HERMES_WS_CONTAINER and HERMES_WS_VOLUME override the names
# (the tests use them so they never touch your real container).
# HERMES_WS_WEB_PORT picks another port on this machine for --web (default 9119).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
IMAGE="${HERMES_WS_IMAGE:-hermes-workshop:latest}"
DEMO_IMAGE="${IMAGE%%:*}:prereqs"
CONTAINER="${HERMES_WS_CONTAINER:-hermes-workshop}"
VOLUME="${HERMES_WS_VOLUME:-hermes-workshop-home}"
WEB_PORT="${HERMES_WS_WEB_PORT:-9119}"
WEB=false
HOME_IN="/home/participant"
REPO_IN="$HOME_IN/hermes-workshop"
# Copies the read-only mount into the container, but only what the repository publishes:
# the files git tracks or .gitignore allows. Without git metadata (an unzipped archive)
# it copies everything. The lab is left alone.
# shellcheck disable=SC2016  # $HOME must expand inside the container, not here
SYNC_SCRIPT='mkdir -p "$HOME/hermes-workshop" &&
if git -c safe.directory=/workshop -C /workshop rev-parse --git-dir >/dev/null 2>&1; then
  git -c safe.directory=/workshop -C /workshop ls-files -z --cached --others --exclude-standard |
    tar -C /workshop --null --ignore-failed-read -T - -cf - | tar -C "$HOME/hermes-workshop" -xf -
else
  cp -R /workshop/. "$HOME/hermes-workshop/"
fi'

say()   { printf '==> %s\n' "$*"; }
die()   { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }
usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; }

interactive() { [ -t 0 ] && [ -t 1 ]; }

# Host user id for the image (root on the host maps to the default 1000).
host_uid() { local uid; uid="$(id -u)"; [ "$uid" -eq 0 ] && uid=1000; printf '%s' "$uid"; }

# Host time zone, so cron schedules such as "weekdays at 9am" mean your local time.
host_tz() {
  if [ -n "${TZ:-}" ]; then printf '%s' "$TZ"
  elif [ -r /etc/timezone ]; then head -n 1 /etc/timezone
  elif [ -L /etc/localtime ]; then readlink /etc/localtime | sed 's#.*/zoneinfo/##'
  fi
}

image_exists()     { docker image inspect "$1" >/dev/null 2>&1; }
container_exists() { docker container inspect "$CONTAINER" >/dev/null 2>&1; }
volume_exists()    { docker volume inspect "$VOLUME" >/dev/null 2>&1; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" = "true" ]; }

# Every container we start gets these: no Linux capabilities, no privilege
# escalation, and a tiny init so it shuts down cleanly.
SECURITY_FLAGS=(--init --cap-drop ALL --security-opt no-new-privileges)

exec_in() {
  if interactive; then
    docker exec -it -e TERM -e COLORTERM -w "$REPO_IN" "$CONTAINER" "$@"
  else
    docker exec -w "$REPO_IN" "$CONTAINER" "$@"
  fi
}

build_image() {   # build_image TAG INSTALL_HERMES [extra docker build args...]
  local tag="$1" install="$2"; shift 2
  docker build -f "$HERE/Dockerfile" \
    --build-arg USER_UID="$(host_uid)" \
    --build-arg INSTALL_HERMES="$install" \
    "$@" -t "$tag" "$HERE"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}

cmd_build() {
  local extra=() sha="" unpinned=false reviewed="$ROOT/.downloads/hermes-install.sh"
  while [ $# -gt 0 ]; do
    case "$1" in
      --installer-sha256) [ $# -ge 2 ] || die "--installer-sha256 needs a value" 2; sha="$2"; shift 2 ;;
      --unpinned) unpinned=true; shift ;;
      --refresh) extra+=(--build-arg "HERMES_REFRESH=$(date +%s)"); shift ;;
      *) die "unknown build option: $1" 2 ;;
    esac
  done
  if [ -z "$sha" ] && [ "$unpinned" != true ]; then
    if [ -f "$reviewed" ]; then
      sha="$(sha256_file "$reviewed")"
      say "Pinning the installer you reviewed: $sha (.downloads/hermes-install.sh)"
    else
      say "No reviewed installer in .downloads/, so there is nothing to pin the build to. First:"
      say "  bash scripts/02-download-installer.sh"
      say "  less .downloads/hermes-install.sh"
      say "  bash docker/workshop.sh build"
      die "stopped before running an installer nobody has read (to skip the review on purpose: build --unpinned)" 2
    fi
  fi
  [ -n "$sha" ] && extra+=(--build-arg "INSTALLER_SHA256=$sha")
  say "Building $IMAGE (the official Hermes installer runs inside the build; about 2 minutes)"
  if ! build_image "$IMAGE" true ${extra[@]+"${extra[@]}"}; then
    if [ -n "$sha" ]; then
      say "If the log above shows 'checksum did NOT match', the installer changed since you reviewed it:"
      say "run bash scripts/02-download-installer.sh again, review it, then rebuild."
    fi
    die "image build failed"
  fi
  if volume_exists; then
    say "Note: volume $VOLUME still holds the previously installed Hermes."
    say "To use the new image: 'bash docker/workshop.sh reset', or update in place: 'bash docker/workshop.sh run hermes update'"
  fi
}

# Does the image or container carry the workshop marker? Stale builds don't.
has_marker() {   # has_marker image|container NAME
  local envs
  envs="$(docker "$1" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$2" 2>/dev/null || true)"
  grep -qx 'HERMES_WORKSHOP_CONTAINER=1' <<<"$envs"
}

ensure_running() {
  if ! image_exists "$IMAGE"; then
    say "The image $IMAGE isn't built yet."
    cmd_build
  fi
  has_marker image "$IMAGE" || die "image $IMAGE is from an older version of this workshop; rebuild it: bash docker/workshop.sh build"
  if container_exists && ! has_marker container "$CONTAINER"; then
    die "container $CONTAINER was created from an older image; recreate it: bash docker/workshop.sh reset, then start"
  fi
  if ! container_exists; then
    local tz tz_flags=() port_flags=()
    tz="$(host_tz || true)"
    [ -n "$tz" ] && tz_flags=(-e "TZ=$tz")
    # Published on 127.0.0.1 only: reachable from this machine, not from the network.
    if [ "$WEB" = true ]; then
      # Something already answers there (often another project's container): stop before
      # Docker leaves a half-created container behind.
      if (exec 3<>"/dev/tcp/127.0.0.1/$WEB_PORT") 2>/dev/null; then
        die "port $WEB_PORT is already in use on this machine; choose another, e.g.: HERMES_WS_WEB_PORT=9120 bash docker/workshop.sh start --web" 2
      fi
      port_flags=(-p "127.0.0.1:$WEB_PORT:9119")
    fi
    say "Creating container $CONTAINER (volume $VOLUME, repository mounted read-only at /workshop)"
    docker run -d --name "$CONTAINER" --hostname hermes-lab \
      "${SECURITY_FLAGS[@]}" \
      -v "$VOLUME:$HOME_IN" \
      -v "$ROOT:/workshop:ro" \
      --add-host=host.docker.internal:host-gateway \
      ${tz_flags[@]+"${tz_flags[@]}"} \
      ${port_flags[@]+"${port_flags[@]}"} \
      "$IMAGE" sleep infinity >/dev/null
  elif ! running; then
    say "Resuming container $CONTAINER"
    docker start "$CONTAINER" >/dev/null
  fi
  if ! docker exec "$CONTAINER" test -d "$REPO_IN"; then
    docker exec "$CONTAINER" bash -c "$SYNC_SCRIPT"
    say "Copied the workshop repository to $REPO_IN"
  fi
}

# The dashboard listens on 9119 inside; the port on this machine may differ (HERMES_WS_WEB_PORT).
web_published() { docker port "$CONTAINER" 9119/tcp >/dev/null 2>&1; }
web_url() { printf 'http://%s' "$(docker port "$CONTAINER" 9119/tcp 2>/dev/null | head -n 1)"; }
DASHBOARD_CMD="cd ~/hermes-workshop-lab && hermes dashboard --host 0.0.0.0 --skip-build --no-open"

banner() {
  cat <<EOF
You are inside the workshop container ($CONTAINER). Your laptop's files are not visible here.
  Repository copy:  $REPO_IN     (refresh from your laptop: bash docker/workshop.sh sync)
  First time:       bash scripts/03-verify-installation.sh && bash scripts/04-create-workspace.sh
  Start Hermes:     cd ~/hermes-workshop-lab && hermes --checkpoints
  Second terminal:  on your laptop, bash docker/workshop.sh shell
  Leave:            exit (the container keeps running)
EOF
  if web_published; then
    cat <<EOF
  Web dashboard:    $DASHBOARD_CMD
                    then open $(web_url) (it asks you to set a login the first time)
EOF
  fi
}

cmd_start() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --web) WEB=true ;;
      *) die "unknown option for start: $1 (expected --web)" 2 ;;
    esac
    shift
  done
  ensure_running
  if [ "$WEB" = true ] && ! web_published; then
    local port_env=""
    if [ "$WEB_PORT" != 9119 ]; then port_env="HERMES_WS_WEB_PORT=$WEB_PORT "; fi
    say "This container was created without the web port, and Docker can't add one later."
    say "To recreate it and keep the volume (Hermes, API key, sessions, lab), type exit, then on this machine:"
    say "  docker rm -f $CONTAINER && ${port_env}bash docker/workshop.sh start --web"
  fi
  if interactive; then
    banner
    exec_in bash -l
  else
    say "Container $CONTAINER is running. Open a shell with: bash docker/workshop.sh shell"
  fi
}

cmd_shell() {
  running || die "container $CONTAINER is not running; use: bash docker/workshop.sh start"
  interactive || die "'shell' needs a terminal; use 'run CMD...' for scripts" 2
  exec_in bash -l
}

cmd_run() {
  [ $# -gt 0 ] || die "run needs a command, e.g.: run hermes --version" 2
  ensure_running
  exec_in "$@"
}

cmd_sync() {
  running || die "container $CONTAINER is not running; use: bash docker/workshop.sh start"
  docker exec "$CONTAINER" bash -c "$SYNC_SCRIPT"
  say "Repository copied to $REPO_IN (files deleted from the repository are not deleted inside)"
}

cmd_status() {
  if image_exists "$IMAGE"; then
    say "Image:     $IMAGE (built $(docker image inspect -f '{{.Created}}' "$IMAGE" | cut -c1-19))"
  else
    say "Image:     $IMAGE not built (bash docker/workshop.sh build)"
  fi
  if container_exists; then
    say "Container: $CONTAINER, $(docker container inspect -f '{{.State.Status}}' "$CONTAINER")"
  else
    say "Container: $CONTAINER does not exist"
  fi
  if volume_exists; then say "Volume:    $VOLUME exists"; else say "Volume:    $VOLUME does not exist"; fi
  if running; then
    say "Hermes:    $(docker exec "$CONTAINER" hermes --version 2>/dev/null | head -n 1)"
    if web_published; then
      say "Web port:  $(web_url) (inside, start it with: $DASHBOARD_CMD)"
    fi
    if docker exec "$CONTAINER" test -d "$HOME_IN/hermes-workshop-lab"; then
      say "Lab:       ~/hermes-workshop-lab exists"
    else
      say "Lab:       not created yet (bash scripts/04-create-workspace.sh inside)"
    fi
  fi
}

cmd_stop() {
  if running; then docker stop -t 5 "$CONTAINER" >/dev/null; say "Stopped $CONTAINER (nothing deleted)"; else say "$CONTAINER is not running"; fi
}

cmd_reset() {
  local yes=false
  [ "${1:-}" = "--yes" ] && yes=true
  if [ "$yes" != true ]; then
    interactive || die "reset deletes data; re-run with --yes to confirm" 2
    printf 'Delete container %s and volume %s (Hermes install, API key, sessions, lab)? [y/N] ' "$CONTAINER" "$VOLUME"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) say "Cancelled"; return 0 ;; esac
  fi
  if container_exists; then docker rm -f "$CONTAINER" >/dev/null; say "Removed container $CONTAINER"; fi
  if volume_exists; then docker volume rm "$VOLUME" >/dev/null; say "Removed volume $VOLUME"; fi
  say "Images are kept; remove them with: docker rmi $IMAGE $DEMO_IMAGE"
}

cmd_install_demo() {
  if ! image_exists "$DEMO_IMAGE" || ! has_marker image "$DEMO_IMAGE"; then
    say "Building $DEMO_IMAGE (prerequisites only, no Hermes)"
    build_image "$DEMO_IMAGE" false
  fi
  local tty_flags=() inner
  interactive && tty_flags=(-it -e TERM -e COLORTERM)
  if [ $# -gt 0 ]; then
    inner="$SYNC_SCRIPT && cd \"\$HOME/hermes-workshop\" && $*"
  else
    cat <<'EOF'
Fresh "laptop" with no Hermes. Everything here is deleted when you exit. Demo:
  bash scripts/01-check-prerequisites.sh
  bash scripts/02-download-installer.sh && less .downloads/hermes-install.sh
  bash .downloads/hermes-install.sh --non-interactive --skip-browser --skip-computer-use
  source ~/.bashrc && bash scripts/03-verify-installation.sh
EOF
    inner="$SYNC_SCRIPT && cd \"\$HOME/hermes-workshop\" && exec bash -l"
  fi
  docker run --rm ${tty_flags[@]+"${tty_flags[@]}"} --hostname fresh-laptop \
    "${SECURITY_FLAGS[@]}" -v "$ROOT:/workshop:ro" "$DEMO_IMAGE" bash -lc "$inner"
}

[ $# -gt 0 ] || { usage; exit 2; }
case "$1" in -h|--help|help) usage; exit 0 ;; esac
if [ "${HERMES_WORKSHOP_CONTAINER:-}" = 1 ]; then
  die "you are inside the workshop container; workshop.sh runs on your laptop. Type exit, then run it there." 3
fi
command -v docker >/dev/null 2>&1 || die "Docker is not installed or not on PATH"
docker info >/dev/null 2>&1 || die "cannot reach the Docker daemon (is Docker running, and may your user use it?)"

command_name="$1"; shift
case "$command_name" in
  build)        cmd_build "$@" ;;
  start)        cmd_start "$@" ;;
  shell)        cmd_shell ;;
  run)          cmd_run "$@" ;;
  sync)         cmd_sync ;;
  status)       cmd_status ;;
  stop)         cmd_stop ;;
  reset)        cmd_reset "$@" ;;
  install-demo) cmd_install_demo "$@" ;;
  *) usage; die "unknown command: $command_name" 2 ;;
esac
