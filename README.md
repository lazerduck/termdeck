# Termdeck

Termdeck is a searchable command palette for the terminal. It combines commands
you save globally, commands saved for the current project, and tasks from a
Taskfile in the current directory.

Press a shortcut, type a few characters, and run or insert the selected command.

## Install

On Linux with Bash and Kitty:

```bash
curl -fsSL https://raw.githubusercontent.com/lazerduck/termdeck/main/install.sh | bash
~/.local/bin/termdeck setup
```

`termdeck setup` shows the files it will change and asks before modifying them.
It creates backups, can be run repeatedly, and supports a preview:

```bash
termdeck setup --dry-run
```

Open a new Kitty tab after setup. Press Ctrl+Shift+P to open Termdeck. Ctrl-G is
also available as a terminal-independent Bash shortcut.

### Requirements

- Bash 4 or newer
- [Task](https://taskfile.dev/)
- `fzf`
- `jq`
- Python 3 with PyYAML

Run `termdeck doctor` to check the dependencies and discovered configuration.

## Use

Inside the palette:

| Key | Action |
| --- | --- |
| Enter | Execute the selected command or task |
| Alt-Enter | Insert it at the current prompt without executing |
| Ctrl-N | Save the current prompt, a history entry, or another command |
| Ctrl-E | Edit the selected Termdeck-owned command |
| Alt-Up / Alt-Down | Move a saved command up or down |

The built-in `Termdeck: Update` entry installs the latest release, reloads the
Bash integration, and reports whether the installed version changed.

Termdeck stores its own commands in:

```text
Global: ~/.config/termdeck/commands.yaml
Local:  ./.termdeck.yaml
```

It also reads tasks from these files without modifying them:

```text
Global: ~/.config/termdeck/Taskfile.yml
Local:  ./Taskfile.yml (including Task's supported filename variants)
```

Termdeck looks only in the exact current directory for local configuration; it
does not walk up through parent directories.

## CLI

```text
termdeck                   Open the palette
termdeck add               Add a saved command using flags
termdeck reorder           Move a saved command within its global or local list
termdeck update            Install the latest release and report its version
termdeck list              Print the merged catalog
termdeck setup             Configure Bash and Kitty
termdeck setup --dry-run   Preview setup changes
termdeck doctor            Check dependencies and configuration
termdeck version           Print the version
```

For example:

```bash
termdeck add --global --name 'Docker: list all' --command 'docker ps -a'
termdeck add --local --name 'Start development' --command 'npm run dev'
termdeck reorder --global --name 'Docker: list all' --first
termdeck reorder --local --name 'Start development' --down
termdeck update
```

## Install from a checkout

```bash
git clone https://github.com/lazerduck/termdeck.git
cd termdeck
./install.sh
~/.local/bin/termdeck setup
```

The installer preserves an existing global command file.

## Development

```bash
./tests/smoke.sh
./tests/widget.sh
./tests/install.sh
./tests/update.sh
```

The current prototype targets Bash and Kitty. Zsh, Fish, and additional terminal
integrations can be added independently of the command catalog.

## License

MIT
