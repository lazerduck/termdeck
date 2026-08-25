#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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

grep -F $'Global task\tdocker:list-all\tDocker: list all containers' <<< "$output" >/dev/null
grep -F $'Local task\ttest\tRun the tests' <<< "$output" >/dev/null
grep -F $'Global command\tSaved status\t\tgit status' <<< "$output" >/dev/null
grep -F $'Local command\tFriendly greeting\t\techo hi' <<< "$output" >/dev/null
! grep -F $'Local command\tProject greeting\t' <<< "$output" >/dev/null
[[ $(grep -Fc $'Global command\tSaved status\t' <<< "$output") -eq 1 ]]

cat > "$fixture/bin/fzf" <<'BASH'
#!/usr/bin/env bash
selection=$(grep $'^Local task\ttest\t' | head -1)
printf 'enter\n%s\n' "$selection"
BASH
chmod +x "$fixture/bin/fzf"

output=$(cd "$fixture/project" && PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick)
grep -F 'tested' <<< "$output" >/dev/null

output=$(cd "$fixture/project" && PATH="$fixture/bin:$PATH" XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" pick --emit)
grep -F 'execute' <<< "$output" >/dev/null
grep -F 'task --dir' <<< "$output" >/dev/null
printf 'smoke test passed\n'
