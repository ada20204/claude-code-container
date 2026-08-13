#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$root/bin/claude-code-container" "$root/install.sh"

if grep -RInE --exclude-dir=.git \
  '(/Users/|10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|sk-[A-Za-z0-9]+|BEGIN OPENSSH PRIVATE KEY)' \
  "$root/bin" "$root/Dockerfile" "$root/install.sh" \
  "$root/README.md" "$root/SECURITY.md" "$root/.github"; then
  printf 'private host data or credentials found\n' >&2
  exit 1
fi

help="$("$root/bin/claude-code-container" help)"
for command in install reinstall uninstall clear shell run doctor; do
  grep -q "  $command" <<<"$help"
done

grep -Fq 'ARG BASE_IMAGE=' "$root/Dockerfile"
grep -Fq 'RUN ln -s /usr/sbin/ifconfig /usr/local/bin/ifconfig' "$root/Dockerfile"
grep -Fq 'CLAUDE_CODE_CONTAINER_BASE_IMAGE' "$root/bin/claude-code-container"
grep -Fq 'CLAUDE_CODE_CONTAINER_BASE_IMAGE' "$root/README.md"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
HOME="$tmp/home" PREFIX="$tmp/prefix" XDG_DATA_HOME="$tmp/data" "$root/install.sh" >/dev/null
test -x "$tmp/prefix/bin/claude-code-container"
test -f "$tmp/data/claude-code-container/Dockerfile"

mkdir -p "$tmp/function-home"
printf 'export USER_SETTING=keep\n' > "$tmp/function-home/.bashrc"
(
  export HOME="$tmp/function-home"
  export CLAUDE_CODE_CONTAINER_SHELL_RC="$HOME/.bashrc"
  # shellcheck disable=SC1091
  source "$root/bin/claude-code-container"
  install_alias
  install_alias
  test "$(grep -c '^# claude-code-container: shell alias begin$' "$HOME/.bashrc")" -eq 1
  remove_alias
  grep -q '^export USER_SETTING=keep$' "$HOME/.bashrc"
  ! grep -q 'claude-code-container: shell alias' "$HOME/.bashrc"
)

mkdir -p "$tmp/conflict-home"
printf "alias claude-container='user-command'\n" > "$tmp/conflict-home/.bashrc"
if (
  export HOME="$tmp/conflict-home"
  export CLAUDE_CODE_CONTAINER_SHELL_RC="$HOME/.bashrc"
  # shellcheck disable=SC1091
  source "$root/bin/claude-code-container"
  install_alias
) 2>/dev/null; then
  printf 'conflicting alias was not rejected\n' >&2
  exit 1
fi
grep -q "alias claude-container='user-command'" "$tmp/conflict-home/.bashrc"

printf 'Static and installer tests passed.\n'
