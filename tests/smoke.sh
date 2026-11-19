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

# delete: global and local CLI remove the named entry and report it,
# preserving unrelated entries, order and the document version.
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --global --name 'To delete' --command 'echo bye'
output=$(XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --global --name 'To delete')
[[ $output == "removed 'To delete' in $fixture/config/termdeck/commands.yaml" ]]
if grep -q 'To delete' "$fixture/config/termdeck/commands.yaml"; then
  printf 'global delete did not remove the entry\n' >&2; exit 1
fi

(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --local --name 'To remove' --command 'echo rm')
output=$(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --local --name 'To remove')
[[ $output == "removed 'To remove' in $fixture/project/.termdeck.yaml" ]]
if grep -q 'To remove' "$fixture/project/.termdeck.yaml"; then
  printf 'local delete did not remove the entry\n' >&2; exit 1
fi

# delete: unknown name fails and leaves the file unchanged
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --global --name 'Absolutely missing' 2>"$fixture/delete-err"; then
  printf 'delete of unknown name should fail\n' >&2; exit 1
fi
grep -F "termdeck: command not found: Absolutely missing" "$fixture/delete-err" >/dev/null
if ! grep -q 'Saved status' "$fixture/config/termdeck/commands.yaml"; then
  printf 'unknown-name delete changed the file\n' >&2; exit 1
fi

# delete: missing scope and missing name are rejected
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete >/dev/null 2>&1; then
  printf 'delete with no args should fail\n' >&2; exit 1
fi
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --global >/dev/null 2>&1; then
  printf 'delete with missing name should fail\n' >&2; exit 1
fi

# delete: unknown option is rejected
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --global --name 'X' --bogus 2>"$fixture/delete-err"; then
  printf 'delete should reject unknown option\n' >&2; exit 1
fi
grep -F "unknown delete option: --bogus" "$fixture/delete-err" >/dev/null

# delete: conflicting --global and --local are rejected before any file changes.
# The same name exists in both scopes; both files must stay byte-for-byte unchanged.
XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --global --name 'Same name' --command 'echo global'
(cd "$fixture/project" && XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" add --local --name 'Same name' --command 'echo local')
cp "$fixture/config/termdeck/commands.yaml" "$fixture/global-before.yaml"
cp "$fixture/project/.termdeck.yaml" "$fixture/local-before.yaml"
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --global --local --name 'Same name' 2>"$fixture/delete-err"; then
  printf 'conflicting scopes should be rejected\n' >&2; exit 1
fi
grep -F "delete requires exactly one of --global or --local" "$fixture/delete-err" >/dev/null
if XDG_CONFIG_HOME="$fixture/config" "$root/bin/termdeck" delete --local --global --name 'Same name' 2>"$fixture/delete-err"; then
  printf 'conflicting scopes (reversed) should be rejected\n' >&2; exit 1
fi
grep -F "delete requires exactly one of --global or --local" "$fixture/delete-err" >/dev/null
if ! cmp -s "$fixture/config/termdeck/commands.yaml" "$fixture/global-before.yaml"; then
  printf 'global file changed by a rejected delete\n' >&2; exit 1
fi
if ! cmp -s "$fixture/project/.termdeck.yaml" "$fixture/local-before.yaml"; then
  printf 'local file changed by a rejected delete\n' >&2; exit 1
fi

# delete: picker ctrl-d default cancellation leaves bytes unchanged and creates
# no execute/insert result
key_used=$fixture/delete-cancel-key-used
cancel_result=$fixture/delete-cancel-result
: > "$cancel_result"
if ! (cd "$fixture/project" && \
  TERMDECK_TEST_PATTERN=$'Global command\x1fSaved status\x1f' \
  TERMDECK_TEST_KEY=ctrl-d \
  TERMDECK_TEST_KEY_USED="$key_used" \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick --emit-to "$cancel_result"); then
  printf 'cancelled picker delete should not fail\n' >&2; exit 1
fi
[[ -e "$key_used" ]]
if [[ -s "$cancel_result" ]]; then
  printf 'cancelled delete produced an execute/insert result\n' >&2; exit 1
fi
if ! grep -q 'Saved status' "$fixture/config/termdeck/commands.yaml"; then
  printf 'cancelled delete changed the file\n' >&2; exit 1
fi

# delete: picker ctrl-d with confirmation removes the entry and re-displays the catalog
key_used=$fixture/delete-key-used
(cd "$fixture/project" && \
  TERMDECK_TEST_PATTERN=$'Global command\x1fSaved status\x1f' \
  TERMDECK_TEST_KEY=ctrl-d \
  TERMDECK_TEST_CONFIRM=Delete \
  TERMDECK_TEST_KEY_USED="$key_used" \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick --emit-to "$result_file") || true
[[ -e "$key_used" ]]
if grep -q 'Saved status' "$fixture/config/termdeck/commands.yaml"; then
  printf 'confirmed picker delete did not remove the entry\n' >&2; exit 1
fi

# delete: picker ctrl-d with a failed confirmation (Escape) leaves bytes unchanged
key_used=$fixture/delete-escape-key-used
(cd "$fixture/project" && \
  TERMDECK_TEST_PATTERN=$'Global command\x1fDocker: list all containers\x1f' \
  TERMDECK_TEST_KEY=ctrl-d \
  TERMDECK_TEST_FAIL_CONFIRM=1 \
  TERMDECK_TEST_KEY_USED="$key_used" \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick) || true
[[ -e "$key_used" ]]
if ! grep -q 'Docker: list all containers' "$fixture/config/termdeck/commands.yaml"; then
  printf 'failed confirmation delete changed the file\n' >&2; exit 1
fi

# delete: picker ctrl-d on a Taskfile task is read-only and removes nothing
key_used=$fixture/delete-task-key-used
(cd "$fixture/project" && \
  TERMDECK_TEST_PATTERN=$'Local task\x1ftest\x1f' \
  TERMDECK_TEST_KEY=ctrl-d \
  TERMDECK_TEST_KEY_USED="$key_used" \
  PATH="$fixture/bin:$PATH" \
  XDG_CONFIG_HOME="$fixture/config" \
  "$root/bin/termdeck" pick 2>"$fixture/delete-task-err") || true
[[ -e "$key_used" ]]
grep -F 'termdeck: Taskfile tasks are read-only' "$fixture/delete-task-err" >/dev/null

printf 'smoke test passed\n'
