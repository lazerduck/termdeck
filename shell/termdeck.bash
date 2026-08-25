# Bash/Readline integration for termdeck.

if command -v termdeck >/dev/null 2>&1; then
  _TERMDECK_BIN=$(command -v termdeck)
elif [[ -x "$HOME/.local/bin/termdeck" ]]; then
  _TERMDECK_BIN=$HOME/.local/bin/termdeck
else
  _TERMDECK_BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/termdeck
fi

_termdeck_widget() {
  local result mode command original_line
  local -a lines

  original_line=$READLINE_LINE
  mapfile -t lines < <("$_TERMDECK_BIN" pick --emit)
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
  builtin eval -- "$command"
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

  printf '\n'
  IFS= read -r -p 'Friendly name: ' name
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

  printf '\n'
  IFS= read -r -p "Friendly name [$old_name]: " name
  name=${name:-$old_name}
  IFS= read -r -p "Command [$old_command]: " command
  command=${command:-$old_command}

  if [[ "$source" == 'Global command' ]]; then scope=--global; else scope=--local; fi
  "$_TERMDECK_BIN" add "$scope" --existing-name "$old_name" --name "$name" --command "$command"
}

# Kitty sends this otherwise-unused CSI-u sequence for Ctrl+Shift+P.
bind -x '"\e[112;5u":_termdeck_widget'

# Terminal-independent fallback. Remove this if you use Ctrl-G for Readline's
# default abort action.
bind -x '"\C-g":_termdeck_widget'
