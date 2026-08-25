#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

HOME="$fixture" XDG_CONFIG_HOME="$fixture/.config" "$root/install.sh"
HOME="$fixture" XDG_CONFIG_HOME="$fixture/.config" "$fixture/.local/bin/termdeck" setup --yes
HOME="$fixture" XDG_CONFIG_HOME="$fixture/.config" "$fixture/.local/bin/termdeck" setup --yes

[[ -x "$fixture/.local/bin/termdeck" ]]
[[ -f "$fixture/.local/share/termdeck/termdeck.bash" ]]
[[ -f "$fixture/.config/termdeck/commands.yaml" ]]
[[ $(grep -Fxc "source '$fixture/.local/share/termdeck/termdeck.bash'" "$fixture/.bashrc") -eq 1 ]]
[[ $(grep -Fxc 'include termdeck.conf' "$fixture/.config/kitty/kitty.conf") -eq 1 ]]
grep -Fqx 'map ctrl+shift+p send_text all \x1b[112;5u' "$fixture/.config/kitty/termdeck.conf"

HOME="$fixture" bash --noprofile --norc -ic \
  "source '$fixture/.local/share/termdeck/termdeck.bash'; test \"\$_TERMDECK_BIN\" = '$fixture/.local/bin/termdeck'" \
  2>/dev/null

printf 'install test passed\n'
