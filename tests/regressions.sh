#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if (($# == 0)); then
  failed=0
  for scenario in lifecycle authorization alias agents docs; do
    if bash "$0" "$scenario"; then
      printf 'PASS: %s\n' "$scenario"
    else
      printf 'FAIL: %s\n' "$scenario" >&2
      failed=1
    fi
  done
  exit "$failed"
fi

scenario="$1"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
export CLAUDE_CODE_CONTAINER_SHELL_RC="$HOME/.zshrc"
unset CLAUDE_CODE_CONTAINER_HOME_VOLUME CLAUDE_CODE_CONTAINER_MOUNTS
unset CLAUDE_CODE_CONTAINER_EXTRA_HOME_DIRS CLAUDE_CODE_CONTAINER_AGENTS
mkdir -p "$HOME/.ssh" "$HOME/.agents"
# shellcheck disable=SC1091
source "$root/bin/claude-code-container" --instance 2

case "$scenario" in
  lifecycle)
    install_alias
    cp "$shell_rc" "$tmp/original-rc"
    docker() {
      case "$*" in
        "ps -aq --filter label=$container_label") printf 'current-instance\n' ;;
        'rm -f current-instance') printf 'removed current\n' >> "$tmp/operations" ;;
        *) printf 'unexpected shared-resource operation: %s\n' "$*" >&2; return 1 ;;
      esac
    }
    remove_runtime
    cmp "$shell_rc" "$tmp/original-rc"
    test "$(cat "$tmp/operations")" = 'removed current'
    docker() { return 1; }
    if (remove_runtime) >/dev/null 2>&1; then
      printf 'container inventory failure was ignored\n' >&2
      exit 1
    fi
    ;;
  authorization)
    legacy="claude-code-container:$home_volume"
    other='ssh-ed25519 OTHER claude-code-container:instance-1:claude-code-container-home'
    host_authorized_source() { printf '127.0.0.1/32\n'; }
    initialize_home() { printf 'ssh-ed25519 TEST %s\n' "$host_key_comment"; }
    for state in legacy both; do
      printf 'ssh-ed25519 TEST %s\n%s\n' "$legacy" "$other" > "$HOME/.ssh/authorized_keys"
      if [[ "$state" == both ]]; then
        printf 'from="127.0.0.1/32",no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc ssh-ed25519 TEST %s\n' \
          "$host_key_comment" >> "$HOME/.ssh/authorized_keys"
      fi
      install_host_authorization
      test "$(grep -c 'ssh-ed25519 TEST ' "$HOME/.ssh/authorized_keys")" -eq 1
      grep -Fqx "$other" "$HOME/.ssh/authorized_keys"
      remove_host_authorization
      test "$(cat "$HOME/.ssh/authorized_keys")" = "$other"
    done
    printf 'ssh-ed25519 TEST %s\n%s\n' "$legacy" "$other" > "$HOME/.ssh/authorized_keys"
    remove_host_authorization
    test "$(cat "$HOME/.ssh/authorized_keys")" = "$other"
    ;;
  alias)
    install_alias
    # shellcheck disable=SC2016
    reload='alias claude-container="old-launcher shell"; source "$1"; typeset -f claude-container >/dev/null'
    bash -O expand_aliases -c "$reload" bash "$shell_rc"
    if command -v zsh >/dev/null 2>&1; then
      zsh -f -c "$reload" zsh "$shell_rc"
    else
      printf 'SKIP: zsh alias reload (zsh unavailable)\n'
    fi
    ;;
  agents)
    custom_run_args=()
    mount_host_roots=()
    mount_container_roots=()
    append_custom_mount "$host_agents:$container_home/.agents"
    test "${#custom_run_args[@]}" -eq 0
    ln -s "$host_agents" "$HOME/agents-link"
    append_custom_mount "$HOME/agents-link:$container_home/.agents:rw"
    test "${#custom_run_args[@]}" -eq 0
    mkdir "$HOME/other-agents"
    if (append_custom_mount "$HOME/other-agents:$container_home/.agents") 2>/dev/null; then
      printf 'conflicting agents source was accepted\n' >&2
      exit 1
    fi
    if (append_custom_mount "$host_agents:$container_home/.agents:ro") 2>/dev/null; then
      printf 'read-only agents mount was silently upgraded to read-write\n' >&2
      exit 1
    fi
    mkdir -p "$host_work" "$host_downloads" "$host_documents" "$host_desktop" "$host_claude_projects" "$tmp/bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$tmp/bin/docker"
    chmod +x "$tmp/bin/docker"
    export PATH="$tmp/bin:$PATH"
    extra_home_dirs=.agents
    parse_mount_options
    (run_container true) > "$tmp/docker-args"
    test "$(grep -Fc -- "$host_agents:$container_home/.agents" "$tmp/docker-args")" -eq 1
    ;;
  docs)
    if grep -En '^[[:space:]]*claude-code-container[[:space:]]+(--instance|shell|run|install|reinstall|uninstall|clear|doctor|help)' \
      "$root/README.md" "$root/docs/herdr.md" "$root/SECURITY.md"; then
      printf 'docs require a launcher that is not on PATH\n' >&2
      exit 1
    fi
    help="$(usage)"
    for phrase in 'Host entry points:' 'First use (host):' 'Inside the container:' \
      'claude-container [N]' 'claude-herdr [N]' 'clear --yes' 'not added to PATH'; do
      grep -Fq -- "$phrase" <<< "$help"
    done
    test "$("$root/bin/claude-code-container" --help)" = "$help"
    # shellcheck disable=SC2016
    grep -Fq 'install -m 0755 ./bin/claude-herdr "$HOME/.local/bin/claude-herdr"' "$root/docs/herdr.md"
    if grep -Eq 'cat >.*claude-herdr' "$root/docs/herdr.md"; then
      printf 'Herdr docs duplicate the maintained wrapper\n' >&2
      exit 1
    fi
    grep -Fq 'http://host.docker.internal:7890' "$root/README.md"
    if grep -Eq '^export (HTTP|HTTPS)_PROXY=.*127\.0\.0\.1' "$root/README.md"; then
      printf 'docs use a loopback proxy without a build-network boundary\n' >&2
      exit 1
    fi
    mkdir "$tmp/examples"
    for doc in README.md docs/herdr.md SECURITY.md; do
      awk -v prefix="$tmp/examples/$(basename "$doc")" '
        /^```bash$/ { block++; file=prefix "-" block ".sh"; inside=1; next }
        /^```$/ { inside=0 }
        inside { print > file }
      ' "$root/$doc"
    done
    for example in "$tmp"/examples/*.sh; do bash -n "$example"; done
    ;;
  *) printf 'unknown scenario: %s\n' "$scenario" >&2; exit 1 ;;
esac
