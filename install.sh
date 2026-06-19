#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/devctl"
CONFIG_FILE="$CONFIG_DIR/config"

SELECT_OPENCODE="off"
SELECT_CLAUDE="off"
SELECT_CODEX="off"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RED="\033[31m"
RESET="\033[0m"

print_header() {
  clear 2>/dev/null || true

  gum style \
    --foreground 212 \
    --border-foreground 57 \
    --border double \
    --align center \
    --width 64 \
    --margin "1 0" \
    --padding "1 3" \
    "devctl" \
    "Remote Development Session Manager" \
    "tmux + opencode + claude + codex"
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

select_tools() {
  SELECT_OPENCODE="off"
  SELECT_CLAUDE="off"
  SELECT_CODEX="off"

  gum style \
    --foreground 212 \
    --border-foreground 57 \
    --border double \
    --align center \
    --width 56 \
    --margin "1 0" \
    --padding "1 3" \
    "devctl setup" "Select tools to install and enable"

  local selected

  selected="$(gum choose --no-limit \
    --cursor "› " \
    --selected "● " \
    --unselected-prefix "○ " \
    --height 8 \
    --header "Use Space to select, Enter to continue" \
    "opencode" \
    "claude" \
    "codex")"

  if echo "$selected" | grep -qx "opencode"; then
    SELECT_OPENCODE="on"
  fi

  if echo "$selected" | grep -qx "claude"; then
    SELECT_CLAUDE="on"
  fi

  if echo "$selected" | grep -qx "codex"; then
    SELECT_CODEX="on"
  fi

  echo
  gum style \
    --foreground 46 \
    --border-foreground 46 \
    --border rounded \
    --padding "1 2" \
    "Selected tools" \
    "opencode: $SELECT_OPENCODE" \
    "claude:   $SELECT_CLAUDE" \
    "codex:    $SELECT_CODEX"
  echo
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
  has_command gum || missing_packages+=("gum")
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

  local opencode_status="$SELECT_OPENCODE"
  local claude_status="$SELECT_CLAUDE"
  local codex_status="$SELECT_CODEX"

  if [ "$SELECT_OPENCODE" = "on" ] && ! has_command opencode; then
    opencode_status="off"
  fi

  if [ "$SELECT_CLAUDE" = "on" ] && ! has_command claude; then
    claude_status="off"
  fi

  if [ "$SELECT_CODEX" = "on" ] && ! has_command codex; then
    codex_status="off"
  fi

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

  set_config_line "opencode" "opencode" "$opencode_status"
  set_config_line "claude" "claude" "$claude_status"
  set_config_line "codex" "codex" "$codex_status"
}

set_config_line() {
  local window_name="$1"
  local window_command="$2"
  local status="$3"

  if grep -q "^$window_name:" "$CONFIG_FILE"; then
    sed -i "s/^$window_name:$window_command:.*$/$window_name:$window_command:$status/" "$CONFIG_FILE"
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

  gum style \
    --foreground 46 \
    --border-foreground 46 \
    --border double \
    --align center \
    --width 64 \
    --padding "1 3" \
    "Installation completed" \
    "devctl is ready to use"

  echo
  gum style --foreground 212 --bold "COMMAND"
  gum style --foreground 46 "  dev"

  echo
  gum style --foreground 212 --bold "CONFIG"
  gum style --foreground 39 "  $CONFIG_FILE"

  echo
  gum style --foreground 212 --bold "WINDOWS"

  printf "  %-4s %-14s %-18s %-8s\n" "#" "name" "command" "status"
  echo "  ────────────────────────────────────────────"

  local index=1

  while IFS=":" read -r window_name window_command enabled; do
    if [ -z "$window_name" ] || [ -z "$window_command" ] || [ -z "$enabled" ]; then
      continue
    fi

    if [ "$enabled" = "on" ]; then
      printf "  \033[32m%-4s\033[0m %-14s %-18s \033[32m%s\033[0m\n" "$index" "$window_name" "$window_command" "on"
    else
      printf "  \033[33m%-4s\033[0m %-14s %-18s \033[33m%s\033[0m\n" "$index" "$window_name" "$window_command" "off"
    fi

    index=$((index + 1))
  done < "$CONFIG_FILE"

  echo
  gum style --foreground 212 --bold "COMMANDS"
  echo "  dev start             Start or attach current project"
  echo "  dev stop              Stop current project session"
  echo "  dev restart           Restart current project session"
  echo "  dev status            Show current project session"
  echo "  dev list              List all dev sessions"
  echo "  dev kill <session>    Kill a specific session"
  echo "  dev config            Show config"

  echo
  gum style --foreground 212 --bold "NEXT"
  gum style \
    --foreground 250 \
    --border rounded \
    --border-foreground 240 \
    --padding "1 2" \
    "cd ~/projects/my-project" \
    "dev start"

  echo
  gum style --foreground 244 "Open a new terminal or run: source ~/.bashrc"
  echo
}

print_header

if [ ! -f "./bin/dev" ]; then
  error "bin/dev not found"
  exit 1
fi

refresh_path
ensure_required_dependencies

select_tools

if [ "$SELECT_OPENCODE" = "on" ]; then
  install_opencode_if_missing || true
fi

if [ "$SELECT_CLAUDE" = "on" ]; then
  install_claude_if_missing || true
fi

if [ "$SELECT_CODEX" = "on" ]; then
  install_codex_if_missing || true
fi

install -m 755 ./bin/dev "$INSTALL_DIR/dev"
install -m 755 ./bin/dev-config "$INSTALL_DIR/dev-config"
success "Installed dev command to $INSTALL_DIR/dev"
success "Installed dev-config command to $INSTALL_DIR/dev-config"

append_shell_path_if_needed
refresh_path
write_config
print_summary
