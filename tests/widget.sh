#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/termdeck" <<'BASH'
#!/usr/bin/env bash
result_file=${3:?}
if [[ ${TERMDECK_WIDGET_TEST_MODE:?} == insert ]]; then
  printf 'insert\necho inserted\n' > "$result_file"
else
  printf 'execute\nprintf executed > %q\n' "$TERMDECK_WIDGET_MARKER" > "$result_file"
fi
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

printf 'widget test passed\n'
