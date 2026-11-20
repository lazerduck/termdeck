#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$(go env GOPATH 2>/dev/null)/bin:$PATH"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/home" "$fixture/project" "$fixture/config/termdeck" "$fixture/bin"
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config"
export TERMDECK_GLOBAL_COMMANDS="$fixture/config/termdeck/commands.yaml"
export TERMDECK_LOCAL_COMMANDS="$fixture/project/.termdeck.yaml"
export TERMDECK_GLOBAL_TASKFILE="$fixture/config/termdeck/Taskfile.yml"
cd "$fixture/project"
cat > Taskfile.yml <<'YAML'
version: '3'
tasks:
  test:
    desc: Fixture task
    cmds:
      - echo task-ran
YAML
cp Taskfile.yml "$fixture/task-before"

fail() { printf 'deletion test: %s\n' "$*" >&2; exit 1; }
assert_same() { cmp -s "$1" "$2" || fail "unexpected change: $1"; }
reset_files() {
  python3 - "$TERMDECK_GLOBAL_COMMANDS" "$TERMDECK_LOCAL_COMMANDS" <<'PY'
import sys
import yaml
for scope, path in zip(('global', 'local'), sys.argv[1:]):
    document = {'version': 17, 'metadata': {'keep': ['one', 'two']}, 'commands': [
        {'name': 'Before', 'command': 'echo before', 'extra': {'keep': True}},
        {'name': "Remove '$(touch SHOULD_NOT_EXIST)'", 'command': 'touch "$HOME/executed"'},
        {'name': 'Survivor', 'command': 'echo surviving-' + scope, 'description': 'Keep me'},
    ]}
    with open(path, 'w') as handle:
        yaml.safe_dump(document, handle, sort_keys=False)
PY
  cp "$TERMDECK_GLOBAL_COMMANDS" "$fixture/global-before"
  cp "$TERMDECK_LOCAL_COMMANDS" "$fixture/local-before"
}
assert_unchanged() {
  assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/global-before"
  assert_same "$TERMDECK_LOCAL_COMMANDS" "$fixture/local-before"
  assert_same Taskfile.yml "$fixture/task-before"
  [[ ! -e "$HOME/executed" && ! -e SHOULD_NOT_EXIST ]] || fail 'a command was executed'
}
assert_removed() {
  python3 - "$1" "$2" <<'PY'
import sys
import yaml
with open(sys.argv[1]) as handle:
    actual = yaml.safe_load(handle)
with open(sys.argv[2]) as handle:
    expected = yaml.safe_load(handle)
assert len(expected['commands']) == 3
del expected['commands'][1]
assert actual == expected, 'deletion must remove only the target and preserve order and metadata'
PY
}
expect_error() {
  local expected=$1 status
  shift
  if "$root/bin/termdeck" delete "$@" >"$fixture/stdout" 2>"$fixture/stderr"; then
    fail "invalid deletion succeeded: $*"
  else
    status=$?
  fi
  [[ $status == 1 ]] || fail "unexpected error status: $status"
  grep -Fq -- "$expected" "$fixture/stderr" || fail 'missing error diagnostic'
  [[ ! -s "$fixture/stdout" ]] || fail 'error printed success output'
  assert_unchanged
}

# A strict scripted fzf checks the actual interaction arguments and call order.
# After confirmation it selects a different surviving entry, so a broken
# refresh cannot be mistaken for normal cancellation.
cat > "$fixture/bin/fzf" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
input=$(cat)
count=0
[[ ! -f "$TD_COUNT" ]] || read -r count < "$TD_COUNT"
count=$((count + 1))
printf '%s\n' "$count" > "$TD_COUNT"
case $count in
  1)
    selection=$(printf '%s\n' "$input" | grep -F -- "$TD_PATTERN")
    [[ -n "$selection" && "$selection" != *$'\n'* ]]
    printf 'ctrl-d\n%s\n' "$selection"
    ;;
  2)
    [[ "$input" == $'Cancel\nDelete' ]] || exit 90
    header=false
    for arg in "$@"; do
      [[ "$arg" != "--header=Delete $TD_NAME ($TD_SCOPE command)?" ]] || header=true
    done
    $header || exit 91
    touch "$TD_COUNT.confirmed"
    case "$TD_CONFIRM" in
      cancel) printf 'enter\nCancel\n' ;;
      delete) printf 'enter\nDelete\n' ;;
      escape) exit 130 ;;
      error) exit 2 ;;
      eof) exit 0 ;;
      *) exit 92 ;;
    esac
    ;;
  3)
    [[ "$TD_CONFIRM" == delete ]] || exit 93
    # The deleted entry must be absent from the refreshed catalog.
    if grep -Fq -- "$TD_PATTERN" <<< "$input"; then exit 94; fi
    selection=$(printf '%s\n' "$input" | grep -F -- "$TD_SURVIVOR")
    [[ -n "$selection" && "$selection" != *$'\n'* ]]
    printf 'alt-enter\n%s\n' "$selection"
    ;;
  *) exit 95 ;;
esac
BASH
chmod +x "$fixture/bin/fzf"
export PATH="$fixture/bin:$PATH"
export TD_NAME='Remove '\''$(touch SHOULD_NOT_EXIST)'\'''
export TD_COUNT="$fixture/fzf-count"

for scope in global local; do
  reset_files
  if [[ "$scope" == global ]]; then
    target=$TERMDECK_GLOBAL_COMMANDS
    other=$TERMDECK_LOCAL_COMMANDS
    other_scope=local
  else
    target=$TERMDECK_LOCAL_COMMANDS
    other=$TERMDECK_GLOBAL_COMMANDS
    other_scope=global
  fi
  output=$("$root/bin/termdeck" delete "--$scope" --name "$TD_NAME")
  [[ "$output" == removed*" in $target" ]] || fail 'missing CLI success message'
  assert_removed "$target" "$fixture/$scope-before"
  assert_same "$other" "$fixture/$other_scope-before"

  # Cover cancellation and successful deletion for direct pick and both shell
  # output protocols, in both command scopes.
  export TD_SCOPE=$scope
  label=${scope^}
  export TD_PATTERN="${label} command"$'\x1f'"$TD_NAME"$'\x1f'
  export TD_SURVIVOR="${label} command"$'\x1fSurvivor\x1f'
  for mode in direct emit file; do
    for confirmation in cancel escape error eof delete; do
      reset_files
      : > "$fixture/result"
      printf '0\n' > "$TD_COUNT"
      rm -f "$TD_COUNT.confirmed"
      export TD_CONFIRM=$confirmation
      args=(pick)
      case $mode in
        emit) args+=(--emit) ;;
        file) args+=(--emit-to "$fixture/result") ;;
      esac
      "$root/bin/termdeck" "${args[@]}" > "$fixture/output"
      [[ -f "$TD_COUNT.confirmed" ]] || fail 'confirmation choices or header were incorrect'
      if [[ "$confirmation" == delete ]]; then
        [[ $(cat "$TD_COUNT") == 3 ]] || fail 'picker did not refresh after deletion'
        assert_removed "$target" "$fixture/$scope-before"
        assert_same "$other" "$fixture/$other_scope-before"
        case $mode in
          direct) printf 'echo surviving-%s\n' "$scope" > "$fixture/expected" ;;
          *) printf 'insert\necho surviving-%s\n' "$scope" > "$fixture/expected" ;;
        esac
        if [[ "$mode" == file ]]; then
          assert_same "$fixture/result" "$fixture/expected"
          [[ ! -s "$fixture/output" ]] || fail 'file protocol leaked output'
        else
          assert_same "$fixture/output" "$fixture/expected"
          [[ ! -s "$fixture/result" ]] || fail 'unexpected result file'
        fi
      else
        [[ $(cat "$TD_COUNT") == 2 ]] || fail 'confirmation was not requested'
        assert_unchanged
        [[ ! -s "$fixture/output" && ! -s "$fixture/result" ]] || fail 'cancelled deletion emitted a command'
      fi
      [[ ! -e "$HOME/executed" && ! -e SHOULD_NOT_EXIST ]] || fail 'a command was executed'
    done
  done
done

reset_files
expect_error 'command not found:' --global --name Absent
expect_error 'delete requires --global or --local'
expect_error 'delete requires --name' --global
expect_error '--name needs a value' --global --name
expect_error 'unknown delete option:' --global --name "$TD_NAME" --bogus
expect_error 'delete requires exactly one' --global --local --name "$TD_NAME"
expect_error 'delete requires exactly one' --local --global --name "$TD_NAME"

# Taskfile entries must never reach the confirmation dialog or emit a command.
export TD_PATTERN=$'Local task\x1ftest\x1f'
printf '0\n' > "$TD_COUNT"
: > "$fixture/result"
"$root/bin/termdeck" pick --emit-to "$fixture/result" > "$fixture/output" 2> "$fixture/stderr"
[[ $(cat "$TD_COUNT") == 1 ]] || fail 'Taskfile deletion asked for confirmation'
grep -Fq 'Taskfile tasks are read-only' "$fixture/stderr"
[[ ! -s "$fixture/output" && ! -s "$fixture/result" ]] || fail 'Taskfile deletion emitted a command'
assert_unchanged

printf 'deletion tests passed\n'
