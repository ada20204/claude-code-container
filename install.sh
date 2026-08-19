#!/usr/bin/env bash
set -euo pipefail

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
data_dir="$data_home/claude-code-container"
launcher="$data_dir/claude-code-container"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -d "$data_dir"
install -m 0755 "$source_dir/bin/claude-code-container" "$launcher"
install -m 0644 "$source_dir/Dockerfile" "$data_dir/Dockerfile"

printf 'Installed internal launcher: %s\n' "$launcher"
printf 'Initialize with: %s install\n' "$launcher"
