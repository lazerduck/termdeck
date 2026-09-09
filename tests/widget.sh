#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/termdeck" <<'BASH'
#!/usr/bin/env bash
result_file=${3:?}
case ${TERMDECK_WIDGET_TEST_MODE:?} in
  insert) printf 'insert\necho inserted\n' > "$result_file" ;;
  execute) printf 'execute\nprintf executed > %q\n' "$TERMDECK_WIDGET_MARKER" > "$result_file" ;;
  terminal) printf 'execute\nstty -a > %q\n' "$TERMDECK_WIDGET_MARKER" > "$result_file" ;;
esac
BASH
chmod +x "$fixture/termdeck"

PATH="$fixture:$PATH"
source "$root/shell/termdeck.bash"

READLINE_LINE='before '
READLINE_POINT=${#READLINE_LINE}
TERMDECK_WIDGET_TEST_MODE=insert _termdeck_widget
[[ "$READLINE_LINE" == 'before echo inserted' ]]

marker=$fixture/executed
READLINE_LINE=
READLINE_POINT=0
TERMDECK_WIDGET_MARKER=$marker TERMDECK_WIDGET_TEST_MODE=execute _termdeck_widget
grep -Fqx executed "$marker"

# Exercise the actual Readline binding in a pseudo-terminal. Commands invoked
# by bind -x would otherwise inherit Readline's raw, no-echo terminal state.
cat > "$fixture/bashrc" <<'BASH'
source "$TERMDECK_WIDGET_ROOT/shell/termdeck.bash"
PS1='termdeck-test> '
BASH
terminal_state=$fixture/terminal-state
printf '\aexit\n' | env \
  PATH="$fixture:$PATH" \
  TERMDECK_WIDGET_ROOT="$root" \
  TERMDECK_WIDGET_TEST_MODE=terminal \
  TERMDECK_WIDGET_MARKER="$terminal_state" \
  script -qefc "bash --noprofile --rcfile '$fixture/bashrc' -i" /dev/null >/dev/null
grep -Eq '(^|[[:space:];])icanon([[:space:];]|$)' "$terminal_state"
grep -Eq '(^|[[:space:];])echo([[:space:];]|$)' "$terminal_state"

printf 'widget test passed\n'
