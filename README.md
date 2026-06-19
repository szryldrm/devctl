# devctl

devctl is a small tmux-based development session manager.

It creates one tmux session per project folder and opens configurable tmux windows for development tools like shell, opencode, claude, and codex.

This is useful for remote development from a tablet or another SSH client. If the connection drops, the tmux session keeps running.

## Install

Run:

    git clone git@git.home.lan:sezeryildirim/devctl.git
    cd devctl
    ./install.sh

The installer checks required dependencies and optionally installs supported tools if they are missing.

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

Kill a specific development session:

    dev kill <session-name>

Open the interactive config editor:

    dev config

Editor keys:

    ↑/↓ or k/j       select window
    Space / Tab      toggle on/off
    Enter / e        edit name and command
    a                add window
    d                delete window
    K / Shift+↑      move selected window up
    J / Shift+↓      move selected window down
    q / Esc          exit

Changes are saved automatically.

## Config

Config file location:

    ~/.config/devctl/config

Default config:

    shell:shell:on
    opencode:opencode:on
    claude:claude:on
    codex:codex:on

Format:

    window_name:command:on/off

Examples:

Disable codex:

    codex:codex:off

Change window order by changing line order:

    shell:shell:on
    claude:claude:on
    opencode:opencode:on
    codex:codex:on

Add another tool:

    lazygit:lazygit:on

If a command does not exist, devctl skips that window automatically.

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

Optional:

- opencode
- claude
- codex

## Install location

The tool installs the dev command to:

    /usr/local/bin/dev
