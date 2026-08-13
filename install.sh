#!/usr/bin/env bash
set -euo pipefail

prefix="${PREFIX:-$HOME/.local}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
bin_dir="$prefix/bin"
data_dir="$data_home/claude-code-container"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d "$bin_dir" "$data_dir"
install -m 0755 "$source_dir/bin/claude-code-container" "$bin_dir/claude-code-container"
install -m 0644 "$source_dir/Dockerfile" "$data_dir/Dockerfile"

printf 'Installed %s\n' "$bin_dir/claude-code-container"
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) printf 'Add %s to PATH, then run: claude-code-container install\n' "$bin_dir" ;;
esac
