#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$(go env GOPATH 2>/dev/null)/bin:$PATH"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/home" "$fixture/project" "$fixture/config/termdeck"
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config"
export TERMDECK_GLOBAL_COMMANDS="$fixture/config/termdeck/commands.yaml"
export TERMDECK_LOCAL_COMMANDS="$fixture/project/.termdeck.yaml"
cd "$fixture/project"

fail() { printf 'run test: %s\n' "$*" >&2; exit 1; }
assert_same() { cmp -s "$1" "$2" || fail "unexpected change: $1"; }

reset_files() {
  cat > "$TERMDECK_GLOBAL_COMMANDS" <<'YAML'
version: 1
metadata:
  keep: [one, two]
commands:
  - name: Before
    command: echo before
    description: Keep me
  - name: Target
    command: echo ran-target
  - name: Survivor
    command: echo surviving
YAML
  cat > "$TERMDECK_LOCAL_COMMANDS" <<'YAML'
version: 2
commands:
  - name: Local Target
    command: echo ran-local
  - name: Local Survivor
    command: echo local-survivor
YAML
  cp "$TERMDECK_GLOBAL_COMMANDS" "$fixture/global-before"
  cp "$TERMDECK_LOCAL_COMMANDS" "$fixture/local-before"
}

assert_unchanged() {
  assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/global-before"
  assert_same "$TERMDECK_LOCAL_COMMANDS" "$fixture/local-before"
}

# --global executes the saved command; output passes through, exit 0
reset_files
output=$("$root/bin/termdeck" run --global --name Target)
[[ "$output" == ran-target ]] || fail "global run did not execute: $output"

# --local executes the saved command
reset_files
output=$("$root/bin/termdeck" run --local --name "Local Target")
[[ "$output" == ran-local ]] || fail "local run did not execute: $output"

# output capture: output=$(termdeck run ...)
reset_files
output=$("$root/bin/termdeck" run --global --name 'Before')
[[ "$output" == before ]] || fail "output capture failed: $output"

# exit status propagation: a failing command makes run exit with that status
reset_files
cat > "$TERMDECK_GLOBAL_COMMANDS" <<'YAML'
version: 1
commands:
  - name: Fails
    command: exit 3
YAML
"$root/bin/termdeck" run --global --name Fails >"$fixture/stdout" 2>"$fixture/stderr" && fail "failing command should make run exit non-zero"
status=$?
[[ $status == 3 ]] || fail "exit status not propagated: $status"

# unknown name -> command not found, exit 1, file unchanged
reset_files
"$root/bin/termdeck" run --global --name Absent >"$fixture/stdout" 2>"$fixture/stderr" && fail "unknown name should fail"
[[ $? == 1 ]] || fail "unexpected error status"
grep -Fq "command not found: Absent" "$fixture/stderr" || fail "missing not-found diagnostic"
[[ ! -s "$fixture/stdout" ]] || fail "error printed success output"
assert_unchanged

# missing commands file -> command not found, exit 1, no file created
reset_files
rm -f "$TERMDECK_GLOBAL_COMMANDS"
"$root/bin/termdeck" run --global --name Anything >"$fixture/stdout" 2>"$fixture/stderr" && fail "missing file should fail"
[[ $? == 1 ]] || fail "unexpected error status for missing file"
grep -Fq "command not found: Anything" "$fixture/stderr" || fail "missing not-found diagnostic for missing file"
[[ ! -e "$TERMDECK_GLOBAL_COMMANDS" ]] || fail "run created a missing commands file"

# no scope -> non-zero, files unchanged
reset_files
"$root/bin/termdeck" run --name Target >"$fixture/stdout" 2>"$fixture/stderr" && fail "no scope should fail"
[[ $? != 0 ]] || fail "no scope should be non-zero"
assert_unchanged

# no name -> non-zero, files unchanged
reset_files
"$root/bin/termdeck" run --global >"$fixture/stdout" 2>"$fixture/stderr" && fail "no name should fail"
[[ $? != 0 ]] || fail "no name should be non-zero"
assert_unchanged

# both scopes -> non-zero before reading any file, either order, files unchanged
reset_files
"$root/bin/termdeck" run --global --local --name Target >"$fixture/stdout" 2>"$fixture/stderr" && fail "both scopes should fail"
[[ $? != 0 ]] || fail "both scopes should be non-zero"
assert_unchanged
reset_files
"$root/bin/termdeck" run --local --global --name Target >"$fixture/stdout" 2>"$fixture/stderr" && fail "both scopes (reverse) should fail"
[[ $? != 0 ]] || fail "both scopes (reverse) should be non-zero"
assert_unchanged

# unknown option -> non-zero, files unchanged
reset_files
"$root/bin/termdeck" run --global --name Target --bogus >"$fixture/stdout" 2>"$fixture/stderr" && fail "unknown option should fail"
[[ $? != 0 ]] || fail "unknown option should be non-zero"
assert_unchanged

# entry with no command -> error, exit 1, file unchanged by run
reset_files
cat > "$TERMDECK_GLOBAL_COMMANDS" <<'YAML'
version: 1
commands:
  - name: Empty
YAML
cp "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-empty"
"$root/bin/termdeck" run --global --name Empty >"$fixture/stdout" 2>"$fixture/stderr" && fail "no command should fail"
[[ $? == 1 ]] || fail "unexpected error status for no command"
grep -Fq "has no command" "$fixture/stderr" || fail "missing no-command diagnostic"
assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-empty"

# malformed YAML -> error, exit 1, file unchanged by run
reset_files
printf 'not: [valid: yaml\n' > "$TERMDECK_GLOBAL_COMMANDS"
cp "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-malformed"
"$root/bin/termdeck" run --global --name Target >"$fixture/stdout" 2>"$fixture/stderr" && fail "malformed YAML should fail"
[[ $? == 1 ]] || fail "unexpected error status for malformed YAML"
assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-malformed"

# top-level not a mapping -> error, exit 1, file unchanged by run
reset_files
printf -- '- just a list\n' > "$TERMDECK_GLOBAL_COMMANDS"
cp "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-nonmap"
"$root/bin/termdeck" run --global --name Target >"$fixture/stdout" 2>"$fixture/stderr" && fail "non-mapping top-level should fail"
[[ $? == 1 ]] || fail "unexpected error status for non-mapping"
assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-nonmap"

# commands not a list -> error, exit 1, file unchanged by run
reset_files
printf 'version: 1\ncommands: not-a-list\n' > "$TERMDECK_GLOBAL_COMMANDS"
cp "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-nonlist"
"$root/bin/termdeck" run --global --name Target >"$fixture/stdout" 2>"$fixture/stderr" && fail "non-list commands should fail"
[[ $? == 1 ]] || fail "unexpected error status for non-list commands"
assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/before-nonlist"

# successful run is read-only: surviving entries, version, ordering unchanged
reset_files
"$root/bin/termdeck" run --global --name Target >"$fixture/stdout" 2>&1
assert_same "$TERMDECK_GLOBAL_COMMANDS" "$fixture/global-before"
assert_same "$TERMDECK_LOCAL_COMMANDS" "$fixture/local-before"

printf 'run tests passed\n'
