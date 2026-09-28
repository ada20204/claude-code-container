#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-container-smoke.XXXXXX")"
token="$(date +%s)$$"
first="${token}1"
second="${token}2"
volumes=("claude-code-container-home-$first" "claude-code-container-home-$second")
export CLAUDE_CODE_CONTAINER_IMAGE="claude-code-container:smoke-$token"
export XDG_DATA_HOME="$tmp/data"
export CLAUDE_CODE_CONTAINER_SHELL_RC="$tmp/shellrc"
export CLAUDE_CODE_CONTAINER_LAUNCHER="$XDG_DATA_HOME/claude-code-container/claude-code-container"
export CLAUDE_CODE_CONTAINER_WORKSPACE="$tmp/work"
export CLAUDE_CODE_CONTAINER_DOWNLOADS="$tmp/Downloads"
export CLAUDE_CODE_CONTAINER_DOCUMENTS="$tmp/Documents"
export CLAUDE_CODE_CONTAINER_DESKTOP="$tmp/Desktop"
export CLAUDE_CODE_CONTAINER_CLAUDE_PROJECTS="$tmp/claude-projects"
export CLAUDE_CODE_CONTAINER_AGENTS="$tmp/agents"
export CLAUDE_CODE_CONTAINER_TIMEZONE=America/Chicago
unset CLAUDE_CODE_CONTAINER_HOME_VOLUME CLAUDE_CODE_CONTAINER_INSTANCE
unset CLAUDE_CODE_CONTAINER_MOUNTS CLAUDE_CODE_CONTAINER_EXTRA_HOME_DIRS
launcher="$CLAUDE_CODE_CONTAINER_LAUNCHER"
pids=()
peer_pid=
peer_id=

launch() {
  "$launcher" "$@" &
  local pid=$!
  pids+=("$pid")
  wait "$pid"
}

cleanup() {
  local status=$? instance pid backup volume
  trap - EXIT
  if [[ -x "$launcher" ]]; then
    for instance in "$first" "$second"; do
      launch --instance "$instance" clear --yes || status=1
    done
  fi
  if [[ -n "$peer_pid" ]]; then wait "$peer_pid" 2>/dev/null || true; fi
  if docker image inspect "$CLAUDE_CODE_CONTAINER_IMAGE" >/dev/null 2>&1; then
    docker image rm "$CLAUDE_CODE_CONTAINER_IMAGE" >/dev/null || status=1
  fi
  for pid in "${pids[@]}"; do
    for backup in "$HOME/.ssh"/authorized_keys.backup-before-claude-code-container-*-"$pid"; do
      [[ ! -f "$backup" ]] || rm "$backup"
    done
  done
  if [[ -n "${auth_before:-}" ]]; then
    [[ "$(shasum -a 256 "$HOME/.ssh/authorized_keys")" == "$auth_before" ]] || {
      printf 'Host authorized_keys changed unexpectedly; inspect before continuing.\n' >&2
      status=1
    }
  fi
  for volume in "${volumes[@]}"; do
    if docker volume inspect "$volume" >/dev/null 2>&1; then
      printf 'Test volume still exists: %s\n' "$volume" >&2
      status=1
    fi
  done
  rm -rf "$tmp"
  exit "$status"
}
docker info >/dev/null
for volume in "${volumes[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    printf 'Refusing to reuse existing volume: %s\n' "$volume" >&2
    rm -rf "$tmp"
    exit 1
  fi
done
if docker image inspect "$CLAUDE_CODE_CONTAINER_IMAGE" >/dev/null 2>&1; then
  printf 'Refusing to reuse existing test image\n' >&2
  rm -rf "$tmp"
  exit 1
fi
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ -f "$HOME/.ssh/authorized_keys" ]]; then
  auth_before="$(shasum -a 256 "$HOME/.ssh/authorized_keys")"
fi
mkdir -p "$tmp/work/project" "$tmp/Downloads" "$tmp/Documents" "$tmp/Desktop" "$tmp/claude-projects" "$tmp/agents"
"$root/install.sh"
printf 'Smoke instances: %s, %s\n' "$first" "$second"
launch --instance "$first" install
launch --instance "$second" install

# shellcheck disable=SC2016
launch --instance "$first" run -- bash -c '
  test "$PWD" = "$HOME"
  test "$(readlink "$HOME/work")" = /workspace
  test "$TZ" = America/Chicago
  test "$LANG" = en_US.UTF-8
  test -f "$HOME/.claude/CLAUDE.md"
  test ! -f "$HOME/.claude/.credentials.json"
  for tool in node python3 git curl ssh zsh tmux; do command -v "$tool"; done
  claude --version
  printf first > "$HOME/instance-marker"
  printf shared > "$HOME/.claude/projects/smoke-marker"
  printf shared > "$HOME/.agents/smoke-marker"
  ssh -o BatchMode=yes -o ConnectTimeout=8 host true
'
# shellcheck disable=SC2016
launch --instance "$second" run -- bash -c '
  test ! -e "$HOME/instance-marker"
  test "$(cat "$HOME/.claude/projects/smoke-marker")" = shared
  test "$(cat "$HOME/.agents/smoke-marker")" = shared
  printf second > "$HOME/instance-marker"
'
printf 'PASS: Home isolation, shared paths, environment, and host SSH\n'

if [[ "$(uname -s)" == Darwin ]]; then container_home="/Users/$(id -un)"; else container_home="/home/$(id -un)"; fi
export CLAUDE_CODE_CONTAINER_MOUNTS="$tmp/agents:$container_home/.agents"
launch --instance "$first" run -- true
unset CLAUDE_CODE_CONTAINER_MOUNTS
launch --instance "$first" run --cwd "$tmp/work/project" -- pwd > "$tmp/container-cwd"
test "$(cat "$tmp/container-cwd")" = /workspace/project
(cd "$tmp/work/project" && "$root/bin/claude-herdr" "$first" --version)
# shellcheck disable=SC2016
zsh -f -c 'alias claude-container="obsolete shell"; source "$1"; claude-container "$2" </dev/null' \
  zsh "$CLAUDE_CODE_CONTAINER_SHELL_RC" "$first"
printf 'PASS: legacy mount, Herdr wrapper, and alias reload\n'

"$launcher" --instance "$second" run -- sleep 600 &
peer_pid=$!
pids+=("$peer_pid")
for ((attempt=0; attempt<60; attempt++)); do
  peer_id="$(docker ps -q --filter "label=io.github.claude-code-container.home-volume=${volumes[1]}")"
  [[ -z "$peer_id" ]] || break
  kill -0 "$peer_pid"
  sleep 1
done
[[ -n "$peer_id" ]]
launch --instance "$first" uninstall
test "$(docker inspect --format '{{.State.Running}}' "$peer_id")" = true
docker image inspect "$CLAUDE_CODE_CONTAINER_IMAGE" >/dev/null
grep -Fq 'claude-container() {' "$CLAUDE_CODE_CONTAINER_SHELL_RC"
if docker run --rm --add-host host.docker.internal:host-gateway \
  --volume "${volumes[0]}:$container_home" "$CLAUDE_CODE_CONTAINER_IMAGE" \
  ssh -o BatchMode=yes -o ConnectTimeout=8 host true 2> "$tmp/ssh-denied"; then
  printf 'Uninstall failed to revoke host SSH access\n' >&2
  exit 1
fi
grep -Fq 'Permission denied' "$tmp/ssh-denied"
printf 'PASS: instance uninstall preserves peer and revokes its own SSH key\n'

launch --instance "$first" reinstall
test "$(docker inspect --format '{{.State.Running}}' "$peer_id")" = true
# shellcheck disable=SC2016
launch --instance "$first" run -- bash -c 'test "$(cat "$HOME/instance-marker")" = first'
launch --instance "$first" clear --yes
if docker volume inspect "${volumes[0]}" >/dev/null 2>&1; then
  printf 'Clear did not remove the selected Home volume\n' >&2
  exit 1
fi
# shellcheck disable=SC2016
launch --instance "$second" run -- bash -c 'test "$(cat "$HOME/instance-marker")" = second'
printf 'PASS: reinstall and clear preserve the other running instance\n'
printf 'Docker smoke tests passed; removing only smoke resources.\n'
