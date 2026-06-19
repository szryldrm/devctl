# devctl

devctl is a small tmux-based development session manager.

It creates one tmux session per project folder and opens separate windows for:

- shell
- opencode
- claude
- codex

This is useful for remote development from a tablet or another SSH client. If the connection drops, the tmux session keeps running.

## Install

Run:

    git clone git@git.home.lan:sezeryildirim/devctl.git
    cd devctl
    ./install.sh

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

Example:

    dev kill dev-certificate-creation-app-a1b2c3d4

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

- bash
- tmux
- opencode
- claude
- codex

## Install location

The tool installs the dev command to:

    /usr/local/bin/dev
