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

output=$(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list)

grep -F $'Global task\x1fdocker:list-all\x1fDocker: list all containers' <<< "$output" >/dev/null
grep -F $'Local task\x1ftest\x1fRun the tests' <<< "$output" >/dev/null
grep -F $'Global command\x1fSaved status\x1f\x1fgit status' <<< "$output" >/dev/null
grep -F $'Local command\x1fFriendly greeting\x1f\x1fecho hi' <<< "$output" >/dev/null
! grep -F $'Local command\x1fProject greeting\x1f' <<< "$output" >/dev/null
[[ $(grep -Fc $'Global command\x1fSaved status\x1f' <<< "$output") -eq 1 ]]

cat > "$fixture/bin/fzf" <<'BASH'
#!/usr/bin/env bash
pattern=${TERMDECK_TEST_PATTERN:-$'Local task\x1ftest\x1f'}
selection=$(grep -F "$pattern" | head -1)
printf 'enter\n%s\n' "$selection"
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
printf 'smoke test passed\n'
