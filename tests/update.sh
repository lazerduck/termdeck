#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/installer.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/termdeck"
cat > "$HOME/.local/bin/termdeck" <<'BIN'
#!/usr/bin/env bash
[[ ${1:-} == version ]] && printf 'termdeck 9.9.9\n'
BIN
chmod +x "$HOME/.local/bin/termdeck"
printf 'TERMDECK_UPDATED_INTEGRATION=1\n' > "$HOME/.local/share/termdeck/termdeck.bash"
BASH

install_url=file://$fixture/installer.sh
output=$(HOME="$fixture" TERMDECK_VERSION=1.0.0 TERMDECK_INSTALL_URL="$install_url" "$root/bin/termdeck" update)
grep -F 'Termdeck version: 9.9.9 (updated from 1.0.0)' <<< "$output" >/dev/null

output=$(HOME="$fixture" TERMDECK_VERSION=9.9.9 TERMDECK_INSTALL_URL="$install_url" "$root/bin/termdeck" update)
grep -F 'Termdeck version: 9.9.9 (already current; no change)' <<< "$output" >/dev/null

printf 'update test passed\n'
