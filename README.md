# devctl

devctl is a small tmux-based development session manager.

It creates one tmux session per project folder and opens configurable tmux windows for development tools like shell, opencode, claude, and codex.

This is useful for remote development from a tablet or another SSH client. If the connection drops, the tmux session keeps running.

## Install

One-line install (clones the repo and runs the installer):

    curl -fsSL https://raw.githubusercontent.com/szryldrm/devctl/main/bootstrap.sh | bash

With options (e.g. show command output):

    curl -fsSL https://raw.githubusercontent.com/szryldrm/devctl/main/bootstrap.sh | bash -s -- --debug

Or clone and run manually:

    git clone https://github.com/szryldrm/devctl.git
    cd devctl
    ./install.sh

The installer checks required dependencies and optionally installs supported tools if they are missing. It configures a UTF-8 locale (so tmux and the tools render correctly), installs everything quietly behind a loading bar, and writes a log to `~/.config/devctl/install-<timestamp>.log`. The log location is printed when the install finishes.

To see the underlying command output live instead of the loading bar:

    ./install.sh --debug

## Uninstall

Run:

    ./uninstall.sh

## Usage

Start or attach to the development session for the current folder:

    dev start

Same as dev start:

    dev

Stop the development session for the current folder:

    dev stop

Restart the development session for the current folder:

    dev restart

Show the current folder session status:

    dev status

List all development sessions:

    dev list

Kill a development session (full name or a fragment such as the hash):

    dev kill <session-name|fragment>

Freeze / thaw sessions to stop them eating CPU (and RAM, with swap):

    dev freeze              # freeze the current folder's session
    dev freeze <fragment>   # freeze a specific session
    dev freeze all          # freeze every session (skips the attached one)
    dev thaw <fragment|all> # resume

`freeze` sends SIGSTOP to every process in the session: it pauses exactly where
it was and uses no CPU; `thaw` (SIGCONT) resumes instantly, right where it left
off — nothing restarts. Physical RAM is reclaimed only if the host has swap or
zram (the kernel pages the stopped processes out under memory pressure); without
swap a frozen session keeps its RAM but burns no CPU. `dev list` marks frozen
sessions. You cannot freeze the session you are currently attached to — detach
first (Ctrl+B then D).

Open the interactive config editor:

    dev config

Editor keys:

    ↑ / ↓            select window
    k / j            reorder: move selected window up / down
    Space / Tab      toggle on/off
    Enter / e        edit name and command
    a                add window
    d                delete window
    q / Esc          exit

On exit, if you made changes, the editor shows a Save / Discard / Cancel
dialog. Use ←/→ and Enter (or the y / n / c shortcuts). Nothing is written
until you confirm.

## Config

Config file location (JSON):

    ~/.config/devctl/config.json

Only the tools you install/select are written to the config — there are no
"off" entries for tools you don't have. As you install more tools, they are
added. The installer migrates an older colon-format `config` file to JSON
automatically.

Example config:

    {
      "windows": [
        { "name": "shell",    "command": "shell",    "enabled": true },
        { "name": "opencode", "command": "opencode", "enabled": true }
      ]
    }

Each entry: `name` (window title), `command` (run on start; `shell` means a
plain shell), `enabled` (true/false). Window order is the array order. Add
another tool by appending an entry, e.g.:

    { "name": "lazygit", "command": "lazygit", "enabled": true }

Easiest is to edit it interactively with `dev config`. If a command does not
exist, devctl skips that window automatically.

## Logs

Install logs are written under:

    ~/.config/devctl/logs/

## Project-based sessions

devctl creates a different tmux session for each project directory.

Example:

    cd ~/projects/certificate-creation-app
    dev start

Then:

    cd ~/projects/another-project
    dev start

These two folders will have separate tmux sessions.

## Tmux shortcuts

Detach from tmux and keep the session running:

    CTRL + B, then D

Freeze the session and detach (pauses it; resumes automatically on reattach):

    CTRL + B, then CTRL + F

Normal detach (Ctrl+B D) and dropped connections keep the session running as
usual — only Ctrl+B Ctrl+F freezes it.

Switch windows:

    CTRL + B, then 1
    CTRL + B, then 2
    CTRL + B, then 3
    CTRL + B, then 4

## Requirements

Required:

- bash
- tmux
- realpath
- sha1sum
- curl
- python3 (config editor)
- locales / a UTF-8 locale (configured automatically by the installer)

Optional:

- opencode
- claude
- codex

## Install location

The installer places:

    /usr/local/bin/dev                  the command
    /usr/local/lib/devctl/dev-config    the config editor (used by "dev config")
