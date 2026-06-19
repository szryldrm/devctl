#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/devctl"
CONFIG_FILE="$CONFIG_DIR/config"

ask_yes_no() {
  local question="$1"
  local answer

  read -r -p "$question [y/N]: " answer

  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

apt_install() {
  if ! has_command apt; then
    echo "apt not found. Please install required packages manually."
    exit 1
  fi

  if is_root; then
    apt update
    apt install -y "$@"
  else
    sudo apt update
    sudo apt install -y "$@"
  fi
}

ensure_required_dependencies() {
  local missing_packages=()

  has_command bash || missing_packages+=("bash")
  has_command tmux || missing_packages+=("tmux")
  has_command realpath || missing_packages+=("coreutils")
  has_command sha1sum || missing_packages+=("coreutils")
  has_command curl || missing_packages+=("curl")
  has_command git || missing_packages+=("git")
  has_command ssh || missing_packages+=("openssh-client")
  [ -f /etc/ssl/certs/ca-certificates.crt ] || missing_packages+=("ca-certificates")

  if [ "${#missing_packages[@]}" -eq 0 ]; then
    return 0
  fi

  echo "Installing required dependencies: ${missing_packages[*]}"
  apt_install "${missing_packages[@]}"
}

install_node_if_missing() {
  if has_command node && has_command npm; then
    return 0
  fi

  if ask_yes_no "Node.js/npm is required for Claude Code. Install Node.js 22 now?"; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
  else
    echo "Skipping Node.js/npm installation"
    return 1
  fi
}

install_opencode_if_missing() {
  if has_command opencode; then
    return 0
  fi

  if ask_yes_no "opencode is not installed. Install it now?"; then
    curl -fsSL https://opencode.ai/install | bash
    return 0
  fi

  return 1
}

install_claude_if_missing() {
  if has_command claude; then
    return 0
  fi

  if ! install_node_if_missing; then
    return 1
  fi

  if ask_yes_no "Claude Code is not installed. Install it now?"; then
    npm install -g @anthropic-ai/claude-code
    return 0
  fi

  return 1
}

install_codex_if_missing() {
  if has_command codex; then
    return 0
  fi

  if ask_yes_no "Codex CLI is not installed. Install it now?"; then
    curl -fsSL https://chatgpt.com/codex/install.sh | sh
    return 0
  fi

  return 1
}

write_config() {
  mkdir -p "$CONFIG_DIR"

  local opencode_status="off"
  local claude_status="off"
  local codex_status="off"

  if has_command opencode; then
    opencode_status="on"
  fi

  if has_command claude; then
    claude_status="on"
  fi

  if has_command codex; then
    codex_status="on"
  fi

  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<CONFIG_EOF
shell:shell:on
opencode:opencode:$opencode_status
claude:claude:$claude_status
codex:codex:$codex_status
CONFIG_EOF
    echo "created config: $CONFIG_FILE"
    return 0
  fi

  echo "config already exists: $CONFIG_FILE"
}

append_shell_path_if_needed() {
  local bashrc="$HOME/.bashrc"

  touch "$bashrc"

  if ! grep -q 'devctl path config' "$bashrc"; then
    cat >> "$bashrc" <<'BASHRC_EOF'

# devctl path config
path_add() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}

path_add "$HOME/.opencode/bin"
path_add "$HOME/.local/bin"
path_add "/usr/local/bin"
export PATH

unset -f path_add
BASHRC_EOF
    echo "updated bash PATH config: $bashrc"
  fi
}

if [ ! -f "./bin/dev" ]; then
  echo "bin/dev not found"
  exit 1
fi

ensure_required_dependencies

install_opencode_if_missing || true
install_claude_if_missing || true
install_codex_if_missing || true

install -m 755 ./bin/dev "$INSTALL_DIR/dev"

write_config
append_shell_path_if_needed

echo "dev installed to $INSTALL_DIR/dev"
echo "config file: $CONFIG_FILE"
echo "Run: dev start"
