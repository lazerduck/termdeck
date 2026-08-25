#!/usr/bin/env bash

set -euo pipefail

repository=${TERMDECK_REPOSITORY:-lazerduck/termdeck}
bin_dir=${TERMDECK_BIN_DIR:-$HOME/.local/bin}
share_dir=${TERMDECK_SHARE_DIR:-$HOME/.local/share/termdeck}
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/termdeck
temporary=

cleanup() {
  [[ -z "$temporary" ]] || rm -rf "$temporary"
}
trap cleanup EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
if [[ -f "$script_dir/bin/termdeck" && -f "$script_dir/shell/termdeck.bash" ]]; then
  source_dir=$script_dir
else
  command -v curl >/dev/null 2>&1 || { printf 'termdeck installer: curl is required\n' >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { printf 'termdeck installer: tar is required\n' >&2; exit 1; }
  temporary=$(mktemp -d)
  archive=$temporary/termdeck.tar.gz
  checksum=$temporary/termdeck.tar.gz.sha256
  base_url="https://github.com/$repository/releases/latest/download"
  printf 'Downloading Termdeck from %s...\n' "$repository"
  curl -fL "$base_url/termdeck.tar.gz" -o "$archive"
  curl -fL "$base_url/termdeck.tar.gz.sha256" -o "$checksum"
  (cd "$temporary" && sha256sum --check termdeck.tar.gz.sha256)
  tar -xzf "$archive" -C "$temporary"
  source_dir=$temporary/termdeck
fi

mkdir -p "$bin_dir" "$share_dir" "$config_dir"
install -m 0755 "$source_dir/bin/termdeck" "$bin_dir/termdeck"
install -m 0644 "$source_dir/shell/termdeck.bash" "$share_dir/termdeck.bash"

if [[ ! -e "$config_dir/commands.yaml" ]]; then
  install -m 0644 "$source_dir/examples/commands.yaml" "$config_dir/commands.yaml"
  printf 'created   %s\n' "$config_dir/commands.yaml"
else
  printf 'preserved %s\n' "$config_dir/commands.yaml"
fi

printf 'installed %s\n' "$bin_dir/termdeck"
printf 'installed %s\n' "$share_dir/termdeck.bash"
printf '\nNext, run:\n  %q setup\n' "$bin_dir/termdeck"
