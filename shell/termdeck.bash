# Bash/Readline integration for termdeck.

if command -v termdeck >/dev/null 2>&1; then
  _TERMDECK_BIN=$(command -v termdeck)
elif [[ -x "$HOME/.local/bin/termdeck" ]]; then
  _TERMDECK_BIN=$HOME/.local/bin/termdeck
else
  _TERMDECK_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/termdeck
fi

_termdeck_widget() {
  local result_file mode command original_line terminal_state= command_status
  local -a lines

  original_line=$READLINE_LINE
  result_file=$(mktemp "${TMPDIR:-/tmp}/termdeck-result.XXXXXX") || return 1
  "$_TERMDECK_BIN" pick --emit-to "$result_file"
  mapfile -t lines < "$result_file"
  rm -f "$result_file"
  ((${#lines[@]} >= 1)) || return 0

  mode=${lines[0]}
  if [[ "$mode" == add ]]; then
    _termdeck_add_command "$original_line"
    return 0
  fi

  if [[ "$mode" == edit ]]; then
    ((${#lines[@]} >= 4)) || return 0
    _termdeck_edit_command "${lines[1]}" "${lines[2]}" "${lines[3]}"
    return 0
  fi

  ((${#lines[@]} >= 2)) || return 0
  command=${lines[1]}

  if [[ "$mode" == insert ]]; then
    READLINE_LINE=${READLINE_LINE:0:READLINE_POINT}${command}${READLINE_LINE:READLINE_POINT}
    READLINE_POINT=$((READLINE_POINT + ${#command}))
    return 0
  fi

  READLINE_LINE=
  READLINE_POINT=0
  printf '\n'
  history -s "$command"

  # bind -x callbacks run while Readline has the terminal in raw, no-echo
  # mode. Interactive programs such as ssh must start from the normal shell
  # state, then Readline's state must be restored when they return.
  if [[ -t 0 ]]; then
    terminal_state=$(stty -g 2>/dev/null) || terminal_state=
    [[ -z "$terminal_state" ]] || stty sane
  fi
  if builtin eval -- "$command"; then
    command_status=0
  else
    command_status=$?
  fi
  [[ -z "$terminal_state" ]] || stty "$terminal_state"
  return "$command_status"
}

_termdeck_add_command() {
  local current_line=$1 command name scope

  command=$(
    {
      [[ -n "$current_line" ]] && printf '%s\n' "$current_line"
      builtin fc -lnr -100 2>/dev/null | sed 's/^[[:space:]]*//'
    } | awk 'NF && !seen[$0]++' | fzf \
      --height=70% --layout=reverse --border=rounded \
      --prompt='command> ' \
      --header='Select current prompt/history command'
  ) || return 0

  name=$(_termdeck_text_prompt 'friendly name> ' '') || return 0
  [[ -n "$name" ]] || return 0

  scope=$(printf 'Global\nLocal\n' | fzf \
    --height=20% --layout=reverse --border=rounded \
    --prompt='save to> ' --header='Global or current project') || return 0

  if [[ "$scope" == Global ]]; then
    "$_TERMDECK_BIN" add --global --name "$name" --command "$command"
  else
    "$_TERMDECK_BIN" add --local --name "$name" --command "$command"
  fi
}

_termdeck_edit_command() {
  local source=$1 old_name=$2 old_command=$3 name command scope

  name=$(_termdeck_text_prompt 'friendly name> ' "$old_name") || return 0
  [[ -n "$name" ]] || return 0
  command=$(_termdeck_text_prompt 'command> ' "$old_command") || return 0
  [[ -n "$command" ]] || return 0

  if [[ "$source" == 'Global command' ]]; then scope=--global; else scope=--local; fi
  "$_TERMDECK_BIN" add "$scope" --existing-name "$old_name" --name "$name" --command "$command"
}

_termdeck_text_prompt() {
  local prompt=$1 initial=$2 output
  output=$(printf 'Press Enter to accept\n' | fzf \
    --height=20% --layout=reverse --border=rounded \
    --disabled --print-query --query="$initial" --prompt="$prompt" \
    --header='Type a value and press Enter') || return 1
  printf '%s\n' "${output%%$'\n'*}"
}

if [[ $- == *i* ]]; then
  # Kitty sends this otherwise-unused CSI-u sequence for Ctrl+Shift+P.
  bind -x '"\e[112;5u":_termdeck_widget'

  # Terminal-independent fallback. Remove this if you use Ctrl-G for
  # Readline's default abort action.
  bind -x '"\C-g":_termdeck_widget'
fi
