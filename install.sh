#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/devctl"
CONFIG_FILE="$CONFIG_DIR/config"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RED="\033[31m"
RESET="\033[0m"

print_header() {
  echo
  echo -e "${BLUE}${BOLD}╭──────────────────────────────╮${RESET}"
  echo -e "${BLUE}${BOLD}│        devctl installer       │${RESET}"
  echo -e "${BLUE}${BOLD}╰──────────────────────────────╯${RESET}"
  echo
}

info() {
  echo -e "${BLUE}●${RESET} $1"
}

success() {
  echo -e "${GREEN}✓${RESET} $1"
}

warn() {
  echo -e "${YELLOW}!${RESET} $1"
}

error() {
  echo -e "${RED}✗${RESET} $1"
}

ask_yes_no() {
  local question="$1"
  local answer

  read -r -p "$(echo -e "${YELLOW}?${RESET} $question [y/N]: ")" answer

  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

refresh_path() {
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
}

has_command() {
  refresh_path
  command -v "$1" >/dev/null 2>&1
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

apt_install() {
  if ! has_command apt; then
    error "apt not found. Please install required packages manually."
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
    success "Required dependencies are already installed"
    return 0
  fi

  info "Installing required dependencies: ${missing_packages[*]}"
  apt_install "${missing_packages[@]}"
  success "Required dependencies installed"
}

install_node_if_missing() {
  if has_command node && has_command npm; then
    success "Node.js/npm already installed"
    return 0
  fi

  if ask_yes_no "Node.js/npm is required for Claude Code. Install Node.js 22 now?"; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    refresh_path
    success "Node.js/npm installed"
    return 0
  fi

  warn "Skipping Node.js/npm installation"
  return 1
}

install_opencode_if_missing() {
  if has_command opencode; then
    success "opencode already installed"
    return 0
  fi

  if ask_yes_no "opencode is not installed. Install it now?"; then
    curl -fsSL https://opencode.ai/install | bash
    refresh_path

    if has_command opencode; then
      success "opencode installed"
      return 0
    fi

    warn "opencode installer finished, but opencode is not available in PATH yet"
  fi

  return 1
}

install_claude_if_missing() {
  if has_command claude; then
    success "Claude Code already installed"
    return 0
  fi

  if ! install_node_if_missing; then
    return 1
  fi

  if ask_yes_no "Claude Code is not installed. Install it now?"; then
    npm install -g @anthropic-ai/claude-code
    refresh_path

    if has_command claude; then
      success "Claude Code installed"
      return 0
    fi

    warn "Claude Code installer finished, but claude is not available in PATH yet"
  fi

  return 1
}

install_codex_if_missing() {
  if has_command codex; then
    success "Codex CLI already installed"
    return 0
  fi

  if ask_yes_no "Codex CLI is not installed. Install it now?"; then
    curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
    refresh_path

    if has_command codex; then
      success "Codex CLI installed"
      return 0
    fi

    warn "Codex installer finished, but codex is not available in PATH yet"
  fi

  return 1
}

write_config() {
  mkdir -p "$CONFIG_DIR"

  local opencode_status="off"
  local claude_status="off"
  local codex_status="off"

  has_command opencode && opencode_status="on"
  has_command claude && claude_status="on"
  has_command codex && codex_status="on"

  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<CONFIG_EOF
shell:shell:on
opencode:opencode:$opencode_status
claude:claude:$claude_status
codex:codex:$codex_status
CONFIG_EOF
    success "Created config: $CONFIG_FILE"
    return 0
  fi

  info "Config already exists: $CONFIG_FILE"

  ensure_config_line "opencode" "opencode" "$opencode_status"
  ensure_config_line "claude" "claude" "$claude_status"
  ensure_config_line "codex" "codex" "$codex_status"
}

ensure_config_line() {
  local window_name="$1"
  local window_command="$2"
  local status="$3"

  if grep -q "^$window_name:" "$CONFIG_FILE"; then
    if [ "$status" = "on" ]; then
      sed -i "s/^$window_name:$window_command:off$/$window_name:$window_command:on/" "$CONFIG_FILE"
    fi
    return 0
  fi

  echo "$window_name:$window_command:$status" >> "$CONFIG_FILE"
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
    success "Updated bash PATH config: $bashrc"
  else
    success "Bash PATH config already exists"
  fi
}

print_summary() {
  echo
  echo -e "${GREEN}${BOLD}Installation completed${RESET}"
  echo
  echo -e "${BOLD}Installed command:${RESET}"
  echo "  dev"
  echo
  echo -e "${BOLD}Config file:${RESET}"
  echo "  $CONFIG_FILE"
  echo
  echo -e "${BOLD}Current config:${RESET}"
  sed 's/^/  /' "$CONFIG_FILE"
  echo
  echo -e "${BOLD}Usage:${RESET}"
  echo "  dev start      Start or attach current project session"
  echo "  dev stop       Stop current project session"
  echo "  dev restart    Restart current project session"
  echo "  dev list       List all dev sessions"
  echo "  dev config     Show active config"
  echo
  echo -e "${DIM}Tip: open a new terminal or run: source ~/.bashrc${RESET}"
  echo
}

print_header

if [ ! -f "./bin/dev" ]; then
  error "bin/dev not found"
  exit 1
fi

refresh_path
ensure_required_dependencies

install_opencode_if_missing || true
install_claude_if_missing || true
install_codex_if_missing || true

install -m 755 ./bin/dev "$INSTALL_DIR/dev"
success "Installed dev command to $INSTALL_DIR/dev"

append_shell_path_if_needed
refresh_path
write_config
print_summary
