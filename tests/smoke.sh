#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$(go env GOPATH 2>/dev/null)/bin:$PATH"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/project" "$fixture/config/termdeck" "$fixture/bin"

cp "$root/examples/global.Taskfile.yml" "$fixture/config/termdeck/Taskfile.yml"
cp "$root/examples/commands.yaml" "$fixture/config/termdeck/commands.yaml"
cat > "$fixture/project/Taskfile.yml" <<'YAML'
version: '3'
tasks:
  test:
    desc: Run the tests
    cmds:
      - echo tested
YAML

(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --local --name 'Project greeting' --command 'echo hello')
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --global --name 'Saved status' --command 'git status --short'
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --global --name 'Saved status' --command 'git status'
(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --local --existing-name 'Project greeting' --name 'Friendly greeting' --command 'echo hi')

XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" reorder --global --name 'Saved status' --first
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" reorder --global --name 'Saved status' --down
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" reorder --global --name 'Saved status' --last
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" reorder --global --name 'Saved status' --up

mapfile -t global_names < <(python3 - "$fixture/config/termdeck/commands.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    print("\n".join(entry["name"] for entry in yaml.safe_load(handle)["commands"]))
PY
)
[[ ${global_names[0]} == 'Docker: list all containers' ]]
[[ ${global_names[1]} == 'Saved status' ]]
[[ ${global_names[2]} == 'Git: recently updated branches' ]]

output=$(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list)

grep -F $'Termdeck\x1fUpdate\x1fInstall the latest release\x1ftermdeck update' <<< "$output" >/dev/null
grep -F $'Global task\x1fdocker:list-all\x1fDocker: list all containers' <<< "$output" >/dev/null
grep -F $'Local task\x1ftest\x1fRun the tests' <<< "$output" >/dev/null
grep -F $'Global command\x1fSaved status\x1f\x1fgit status' <<< "$output" >/dev/null
grep -F $'Local command\x1fFriendly greeting\x1f\x1fecho hi' <<< "$output" >/dev/null
! grep -F $'Local command\x1fProject greeting\x1f' <<< "$output" >/dev/null
[[ $(grep -Fc $'Global command\x1fSaved status\x1f' <<< "$output") -eq 1 ]]

cat > "$fixture/bin/fzf" <<'BASH'
#!/usr/bin/env bash
pattern=${TERMDECK_TEST_PATTERN:-$'Local task\x1ftest\x1f'}
input=$(cat)
grep -F $'Local task: test — Run the tests\x1fLocal task\x1ftest\x1f' <<< "$input" >/dev/null
selection=$(grep -F "$pattern" <<< "$input" | head -1)
key=enter
if [[ -n ${TERMDECK_TEST_KEY:-} && ! -e ${TERMDECK_TEST_KEY_USED:?} ]]; then
  key=$TERMDECK_TEST_KEY
  touch "$TERMDECK_TEST_KEY_USED"
fi
printf '%s\n%s\n' "$key" "$selection"
BASH
chmod +x "$fixture/bin/fzf"

output=$(cd "$fixture/project" && PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick)
grep -F 'tested' <<< "$output" >/dev/null

output=$(cd "$fixture/project" && PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick --emit)
grep -F 'execute' <<< "$output" >/dev/null
grep -F 'task --dir' <<< "$output" >/dev/null

result_file=$fixture/result
(cd "$fixture/project" && PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick --emit-to "$result_file")
grep -F 'execute' "$result_file" >/dev/null
grep -F 'task --dir' "$result_file" >/dev/null

saved_pattern=$'Local command\x1fFriendly greeting\x1f'
output=$(cd "$fixture/project" && TERMDECK_TEST_PATTERN="$saved_pattern" PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick)
grep -F 'hi' <<< "$output" >/dev/null

(cd "$fixture/project" && TERMDECK_TEST_PATTERN="$saved_pattern" PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick --emit-to "$result_file")
grep -Fqx 'execute' "$result_file"
grep -Fqx 'echo hi' "$result_file"

(cd "$fixture/project" && \
  TERMDECK_TEST_PATTERN=$'Termdeck\x1fUpdate\x1f' \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick --emit-to "$result_file")
grep -Fqx 'update' "$result_file"

key_used=$fixture/reorder-key-used
(cd "$fixture/project" && \
  TERMDECK_TEST_PATTERN=$'Global command\x1fSaved status\x1f' \
  TERMDECK_TEST_KEY=alt-down \
  TERMDECK_TEST_KEY_USED="$key_used" \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick --emit-to "$result_file")
[[ -e "$key_used" ]]
[[ $(python3 - "$fixture/config/termdeck/commands.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    print(yaml.safe_load(handle)["commands"][-1]["name"])
PY
) == 'Saved status' ]]
printf 'smoke test passed\n'
