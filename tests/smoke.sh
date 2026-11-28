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

grep -F $'Global task\x1fdocker:list-all\x1fDocker: list all containers' <<< "$output" >/dev/null
grep -F $'Local task\x1ftest\x1fRun the tests' <<< "$output" >/dev/null
grep -F $'Global command\x1fSaved status\x1f\x1fgit status' <<< "$output" >/dev/null
grep -F $'Local command\x1fFriendly greeting\x1f\x1fecho hi' <<< "$output" >/dev/null
! grep -F $'Local command\x1fProject greeting\x1f' <<< "$output" >/dev/null
[[ $(grep -Fc $'Global command\x1fSaved status\x1f' <<< "$output") -eq 1 ]]

# list --global: global sources only, no local lines
output=$(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list --global)
grep -F $'Global command\x1fSaved status\x1f\x1fgit status' <<< "$output" >/dev/null
grep -F $'Global task\x1fdocker:list-all\x1fDocker: list all containers' <<< "$output" >/dev/null
if grep -Fq $'Local command\x1f' <<< "$output" || grep -Fq $'Local task\x1f' <<< "$output"; then
  echo "list --global must not emit Local command or Local task entries" >&2
  exit 1
fi

# list --local: local sources only, no global lines
output=$(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list --local)
grep -F $'Local command\x1fFriendly greeting\x1f\x1fecho hi' <<< "$output" >/dev/null
grep -F $'Local task\x1ftest\x1fRun the tests' <<< "$output" >/dev/null
if grep -Fq $'Global command\x1f' <<< "$output" || grep -Fq $'Global task\x1f' <<< "$output"; then
  echo "list --local must not emit Global command or Global task entries" >&2
  exit 1
fi

# list --global --local: all sources, same as no flags
output=$(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list --global --local)
grep -F $'Global command\x1fSaved status\x1f' <<< "$output" >/dev/null
grep -F $'Local task\x1ftest\x1fRun the tests' <<< "$output" >/dev/null

# unknown list option: exit 1, diagnostic on stderr, no stdout
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list --bogus >"$fixture/list-out" 2>"$fixture/list-err"; then
  echo "list --bogus should fail" >&2
  exit 1
fi
[[ ! -s "$fixture/list-out" ]] || { echo "list --bogus printed stdout" >&2; exit 1; }
grep -F 'unknown list option: --bogus' "$fixture/list-err" >/dev/null || { echo "missing unknown list option diagnostic" >&2; exit 1; }

# list --local with no local command file and no local Taskfile: no output, exit 0
mkdir -p "$fixture/empty"
output=$(cd "$fixture/empty" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" list --local)
[[ -z "$output" ]] || { echo "list --local without local files should print nothing: $output" >&2; exit 1; }

# list --global with no global files: no output, exit 0
mkdir -p "$fixture/nowhere"
output=$(cd "$fixture/nowhere" && HOME="$fixture/nowhere" XDG_CONFIG_HOME="$fixture/nowhere" "$root/bin/termdeck" list --global 2>"$fixture/list-err2")
[[ -z "$output" ]] || { echo "list --global without global files should print nothing: $output" >&2; exit 1; }

cat > "$fixture/bin/fzf" <<'BASH'
#!/usr/bin/env bash
input=$(cat)

# A confirmation dialog presents exactly two lines: Cancel then Delete.
if [[ "$input" == $'Cancel\nDelete'* ]]; then
  if [[ -n ${TERMDECK_TEST_FAIL_CONFIRM:-} ]]; then
    # Simulate Escape / a failed confirmation interaction.
    exit 1
  fi
  selection=${TERMDECK_TEST_CONFIRM:-Cancel}
else
  pattern=${TERMDECK_TEST_PATTERN:-$'Local task\x1ftest\x1f'}
  selection=$(grep -F "$pattern" <<< "$input" | head -1)
fi

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

update_key_used=$fixture/update-key-used
(cd "$fixture/project" && \
  TERMDECK_TEST_KEY=ctrl-u \
  TERMDECK_TEST_KEY_USED="$update_key_used" \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick --emit-to "$result_file")
[[ -e "$update_key_used" ]]
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

# Deletion has its own fixtures and strict picker/confirmation assertions.
"$root/tests/deletion.sh"
"$root/tests/run.sh"

printf 'smoke test passed\n'
