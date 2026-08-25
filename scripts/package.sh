#!/usr/bin/env bash

set -euo pipefail

version=${1:?Usage: scripts/package.sh VERSION [OUTPUT_DIRECTORY]}
output=${2:-dist}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

rm -rf "$output/termdeck"
mkdir -p "$output/termdeck/bin" "$output/termdeck/shell" "$output/termdeck/examples"
cp "$root/bin/termdeck" "$output/termdeck/bin/"
sed -i "s/@VERSION@/$version/" "$output/termdeck/bin/termdeck"
cp "$root/shell/termdeck.bash" "$output/termdeck/shell/"
cp "$root/examples/commands.yaml" "$output/termdeck/examples/"
cp "$root/install.sh" "$root/README.md" "$root/LICENSE" "$output/termdeck/"
tar -C "$output" -czf "$output/termdeck.tar.gz" termdeck
(cd "$output" && sha256sum termdeck.tar.gz > termdeck.tar.gz.sha256)
