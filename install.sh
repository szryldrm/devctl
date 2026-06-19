#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/devctl"
CONFIG_FILE="$CONFIG_DIR/config"

SELECT_OPENCODE="off"
SELECT_CLAUDE="off"
SELECT_CODEX="off"

# Commands devctl needs to run, mapped to their apt packages below.
# gum is handled separately because it may need the charm apt repo.
REQUIRED_COMMANDS="tmux git curl ssh python3 realpath sha1sum"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RED="\033[31m"
RESET="\033[0m"

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

step() {
  echo
  echo -e "${BOLD}${BLUE}==>${RESET} ${BOLD}$1${RESET}"
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

run_root() {
  if is_root; then
    "$@"
  else
    sudo "$@"
  fi
}

ask_yes_no() {
  local question="$1"
  local answer

  read -r -p "$(echo -e "${YELLOW}?${RESET} $question [y/N]: ")" answer

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

apt_pkg_for() {
  case "$1" in
    ssh) echo "openssh-client" ;;
    realpath|sha1sum) echo "coreutils" ;;
    *) echo "$1" ;;
  esac
}

require_apt() {
  if ! has_command apt-get; then
    error "apt-get not found. This installer targets Debian/Ubuntu."
    error "Please install the missing packages manually: $*"
    exit 1
  fi
}

apt_update_once() {
  if [ "${APT_UPDATED:-}" != "1" ]; then
    run_root apt-get update
    APT_UPDATED=1
  fi
}

apt_install() {
  require_apt "$@"
  apt_update_once
  run_root apt-get install -y "$@"
}

# ---------------------------------------------------------------------------
# Dependency resolution
# ---------------------------------------------------------------------------

ensure_required_dependencies() {
  step "Checking required dependencies"

  local missing_commands=()
  local missing_packages=()
  local seen_packages=""
  local cmd
  local pkg

  for cmd in $REQUIRED_COMMANDS; do
    if has_command "$cmd"; then
      success "$cmd"
      continue
    fi

    warn "$cmd missing"
    missing_commands+=("$cmd")

    pkg="$(apt_pkg_for "$cmd")"

    case " $seen_packages " in
      *" $pkg "*) ;;
      *)
        missing_packages+=("$pkg")
        seen_packages="$seen_packages $pkg"
        ;;
    esac
  done

  if [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
    warn "ca-certificates missing"
    missing_packages+=("ca-certificates")
  else
    success "ca-certificates"
  fi

  if [ "${#missing_packages[@]}" -gt 0 ]; then
    info "Installing: ${missing_packages[*]}"
    apt_install "${missing_packages[@]}"
  fi

  # Verify the config editor can actually run (python3 + curses stdlib).
  if has_command python3 && ! python3 -c "import curses" >/dev/null 2>&1; then
    warn "python3 is missing the curses module (needed by 'dev config')"
    apt_install python3 || true
  fi

  # Re-verify everything is now present.
  local still_missing=()

  for cmd in $REQUIRED_COMMANDS; do
    has_command "$cmd" || still_missing+=("$cmd")
  done

  if [ "${#still_missing[@]}" -gt 0 ]; then
    error "Could not install: ${still_missing[*]}"
    error "Please install them manually and re-run ./install.sh"
    exit 1
  fi

  success "All required dependencies are present"
}

# gum powers the nice UI for the rest of the installer. On Debian/Ubuntu it
# usually requires the charm apt repository, so install it on its own.
ensure_gum() {
  step "Setting up gum (installer UI)"

  if has_command gum; then
    success "gum already installed"
    return 0
  fi

  if apt_install gum >/dev/null 2>&1 && has_command gum; then
    success "gum installed"
    return 0
  fi

  info "Adding charm apt repository for gum"

  run_root mkdir -p /etc/apt/keyrings
  curl -fsSL https://repo.charm.sh/apt/gpg.key |
    run_root gpg --dearmor -o /etc/apt/keyrings/charm.gpg
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" |
    run_root tee /etc/apt/sources.list.d/charm.list >/dev/null

  APT_UPDATED=""
  apt_install gum

  if has_command gum; then
    success "gum installed"
    return 0
  fi

  error "Failed to install gum"
  exit 1
}

# ---------------------------------------------------------------------------
# Optional AI tools
# ---------------------------------------------------------------------------

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
    --selected-prefix "● " \
    --unselected-prefix "○ " \
    --height 8 \
    --header "Use Space to select, Enter to continue" \
    "opencode" \
    "claude" \
    "codex")"

  echo "$selected" | grep -qx "opencode" && SELECT_OPENCODE="on"
  echo "$selected" | grep -qx "claude" && SELECT_CLAUDE="on"
  echo "$selected" | grep -qx "codex" && SELECT_CODEX="on"

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

install_node_if_missing() {
  if has_command node && has_command npm; then
    success "Node.js/npm already installed"
    return 0
  fi

  if ask_yes_no "Node.js/npm is required for Claude Code. Install Node.js 22 now?"; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | run_root bash -
    apt_install nodejs
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

    warn "opencode installer finished, but opencode is not on PATH yet"
  fi

  return 1
}

install_claude_if_missing() {
  if has_command claude; then
    success "Claude Code already installed"
    return 0
  fi

  install_node_if_missing || return 1

  if ask_yes_no "Claude Code is not installed. Install it now?"; then
    npm install -g @anthropic-ai/claude-code
    refresh_path

    if has_command claude; then
      success "Claude Code installed"
      return 0
    fi

    warn "Claude Code installer finished, but claude is not on PATH yet"
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

    warn "Codex installer finished, but codex is not on PATH yet"
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Config + PATH
# ---------------------------------------------------------------------------

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

write_config() {
  step "Writing config"

  mkdir -p "$CONFIG_DIR"

  local opencode_status="$SELECT_OPENCODE"
  local claude_status="$SELECT_CLAUDE"
  local codex_status="$SELECT_CODEX"

  [ "$SELECT_OPENCODE" = "on" ] && ! has_command opencode && opencode_status="off"
  [ "$SELECT_CLAUDE" = "on" ] && ! has_command claude && claude_status="off"
  [ "$SELECT_CODEX" = "on" ] && ! has_command codex && codex_status="off"

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

append_shell_path_if_needed() {
  local bashrc="$HOME/.bashrc"

  touch "$bashrc"

  if grep -q 'devctl path config' "$bashrc"; then
    success "Bash PATH config already exists"
    return 0
  fi

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
}

# ---------------------------------------------------------------------------
# Verification + summary
# ---------------------------------------------------------------------------

verify_install() {
  step "Verifying installation"

  local ok=1

  check_command() {
    local label="$1"
    local cmd="$2"

    if has_command "$cmd"; then
      printf "  ${GREEN}✓${RESET} %-20s %s\n" "$label" "$(command -v "$cmd")"
    else
      printf "  ${RED}✗${RESET} %-20s %s\n" "$label" "missing"
      ok=0
    fi
  }

  check_command "dev"        "dev"
  check_command "dev-config" "dev-config"
  check_command "tmux"       "tmux"
  check_command "python3"    "python3"
  check_command "gum"        "gum"

  if python3 -c "import curses" >/dev/null 2>&1; then
    printf "  ${GREEN}✓${RESET} %-20s %s\n" "python3 curses" "available"
  else
    printf "  ${RED}✗${RESET} %-20s %s\n" "python3 curses" "missing"
    ok=0
  fi

  echo
  printf "  ${BOLD}%-16s %-12s %s${RESET}\n" "window" "command" "status"
  printf "  %s\n" "────────────────────────────────────────"

  while IFS=":" read -r window_name window_command enabled; do
    [ -z "$window_name" ] && continue

    if [ "$enabled" = "on" ]; then
      printf "  %-16s %-12s ${GREEN}%s${RESET}\n" "$window_name" "$window_command" "on"
    else
      printf "  %-16s %-12s ${DIM}%s${RESET}\n" "$window_name" "$window_command" "off"
    fi
  done < "$CONFIG_FILE"

  echo

  if [ "$ok" -ne 1 ]; then
    error "Installation finished with missing components (see above)"
    return 1
  fi

  success "Everything checks out"
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
  gum style --foreground 212 --bold "COMMANDS"
  echo "  dev start             Start or attach current project"
  echo "  dev stop              Stop current project session"
  echo "  dev restart           Restart current project session"
  echo "  dev status            Show current project session"
  echo "  dev list              List all dev sessions"
  echo "  dev kill <session>    Kill a specific session"
  echo "  dev config            Open the interactive config editor"

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

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if [ ! -f "./bin/dev" ] || [ ! -f "./bin/dev-config" ]; then
  error "Run this script from the devctl repository root (bin/dev not found)"
  exit 1
fi

refresh_path
ensure_required_dependencies
ensure_gum
print_header

select_tools

[ "$SELECT_OPENCODE" = "on" ] && { install_opencode_if_missing || true; }
[ "$SELECT_CLAUDE" = "on" ] && { install_claude_if_missing || true; }
[ "$SELECT_CODEX" = "on" ] && { install_codex_if_missing || true; }

step "Installing devctl"
run_root install -m 755 ./bin/dev "$INSTALL_DIR/dev"
run_root install -m 755 ./bin/dev-config "$INSTALL_DIR/dev-config"
success "Installed dev to $INSTALL_DIR/dev"
success "Installed dev-config to $INSTALL_DIR/dev-config"

append_shell_path_if_needed
refresh_path
write_config
verify_install || true
print_summary
