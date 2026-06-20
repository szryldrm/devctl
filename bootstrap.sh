#!/usr/bin/env bash
#
# One-line installer for devctl. Clones the repository to a temporary
# directory and runs ./install.sh from there.
#
#   curl -fsSL https://raw.githubusercontent.com/szryldrm/devctl/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/szryldrm/devctl/main/bootstrap.sh | bash -s -- --debug
#
# Override the source with env vars:
#   DEVCTL_REPO=https://github.com/szryldrm/devctl.git
#   DEVCTL_BRANCH=main

set -e

REPO="${DEVCTL_REPO:-https://github.com/szryldrm/devctl.git}"
BRANCH="${DEVCTL_BRANCH:-main}"

RED="\033[31m"; GREEN="\033[32m"; BLUE="\033[34m"; RESET="\033[0m"
info()  { echo -e "${BLUE}●${RESET} $1"; }
ok()    { echo -e "${GREEN}✓${RESET} $1"; }
die()   { echo -e "${RED}✗${RESET} $1"; exit 1; }

run_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

# git is needed to clone the repo.
if ! command -v git >/dev/null 2>&1; then
  info "Installing git"
  if command -v apt-get >/dev/null 2>&1; then
    run_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
  else
    die "git is required but not installed (and apt-get was not found)"
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "Cloning $REPO ($BRANCH)"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$TMP/devctl" >/dev/null 2>&1 \
  || die "Failed to clone $REPO"
ok "Cloned"

cd "$TMP/devctl"

# Re-attach the terminal so the installer's interactive prompts work even when
# this script was fed to bash over a pipe (curl ... | bash).
if [ -e /dev/tty ]; then
  exec bash ./install.sh "$@" < /dev/tty
else
  exec bash ./install.sh "$@"
fi
