#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
LIBEXEC_DIR="/usr/local/lib/devctl"
CONFIG_DIR="$HOME/.config/devctl"
CONFIG_FILE="$CONFIG_DIR/config"

SELECT_OPENCODE="off"
SELECT_CLAUDE="off"
SELECT_CODEX="off"

# Commands devctl needs at runtime, mapped to apt packages in apt_pkg_for().
# gum is handled separately because it may need the charm apt repo.
REQUIRED_COMMANDS="tmux git curl ssh python3 realpath sha1sum"

STEP_TOTAL=5
STEP_NO=0

# --- palette (256-color) -----------------------------------------------------
ACCENT=141
SKY=117
GREEN=114
AMBER=215
DANGER=203
MUTED=244
BORDER=240
TEXT=252

C_ACCENT="\033[38;5;${ACCENT}m"
C_SKY="\033[38;5;${SKY}m"
C_GREEN="\033[38;5;${GREEN}m"
C_AMBER="\033[38;5;${AMBER}m"
C_DANGER="\033[38;5;${DANGER}m"
C_MUTED="\033[38;5;${MUTED}m"
C_TEXT="\033[38;5;${TEXT}m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

# --- plain helpers (work before gum is installed) ----------------------------
info()    { echo -e "  ${C_SKY}•${RESET} $1"; }
success() { echo -e "  ${C_GREEN}✓${RESET} $1"; }
warn()    { echo -e "  ${C_AMBER}!${RESET} $1"; }
error()   { echo -e "  ${C_DANGER}✗${RESET} $1"; }

rule() {
  local width="${1:-60}"
  printf "  ${C_MUTED}"
  printf '─%.0s' $(seq 1 "$width")
  printf "${RESET}\n"
}

step() {
  STEP_NO=$((STEP_NO + 1))
  echo
  echo -e "  ${C_ACCENT}${BOLD}STEP ${STEP_NO}/${STEP_TOTAL}${RESET}  ${C_TEXT}${BOLD}$1${RESET}"
  rule 56
}

refresh_path() {
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
}

has_command() {
  refresh_path
  command -v "$1" >/dev/null 2>&1
}

is_root() { [ "$(id -u)" -eq 0 ]; }

run_root() {
  if is_root; then "$@"; else sudo "$@"; fi
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
    error "Install these packages manually, then re-run: $*"
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

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------

banner() {
  clear 2>/dev/null || true
  echo

  gum style \
    --foreground "$ACCENT" \
    --border double \
    --border-foreground "$ACCENT" \
    --align center \
    --width 60 \
    --padding "1 4" \
    --bold \
    "◆  D E V C T L  ◆" \
    "" \
    "Remote Development Session Manager"

  echo
  gum style --align center --width 64 --foreground "$MUTED" \
    "tmux  ·  opencode  ·  claude  ·  codex"
  echo
}

# -----------------------------------------------------------------------------
# Dependencies
# -----------------------------------------------------------------------------

ensure_required_dependencies() {
  echo
  echo -e "  ${C_ACCENT}${BOLD}BOOTSTRAP${RESET}  ${C_TEXT}${BOLD}Required dependencies${RESET}"
  rule 56

  local missing_packages=()
  local seen=""
  local cmd pkg

  for cmd in $REQUIRED_COMMANDS; do
    if has_command "$cmd"; then
      success "$cmd"
      continue
    fi

    warn "$cmd ${C_MUTED}(will install)${RESET}"
    pkg="$(apt_pkg_for "$cmd")"
    case " $seen " in
      *" $pkg "*) ;;
      *) missing_packages+=("$pkg"); seen="$seen $pkg" ;;
    esac
  done

  if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    success "ca-certificates"
  else
    warn "ca-certificates ${C_MUTED}(will install)${RESET}"
    missing_packages+=("ca-certificates")
  fi

  if [ "${#missing_packages[@]}" -gt 0 ]; then
    echo
    info "Installing: ${C_TEXT}${missing_packages[*]}${RESET}"
    apt_install "${missing_packages[@]}"
  fi

  # The config editor needs python3 + the curses stdlib module.
  if has_command python3 && ! python3 -c "import curses" >/dev/null 2>&1; then
    warn "python3 is missing the curses module (needed by 'dev config')"
    apt_install python3 || true
  fi

  local still_missing=()
  for cmd in $REQUIRED_COMMANDS; do
    has_command "$cmd" || still_missing+=("$cmd")
  done

  if [ "${#still_missing[@]}" -gt 0 ]; then
    echo
    error "Could not install: ${still_missing[*]}"
    error "Install them manually and re-run ./install.sh"
    exit 1
  fi

  echo
  success "All required dependencies are present"
}

# gum drives the rest of the UI. On Debian/Ubuntu it usually needs the
# charm apt repository, so install it on its own before anything pretty.
ensure_gum() {
  echo
  echo -e "  ${C_ACCENT}${BOLD}BOOTSTRAP${RESET}  ${C_TEXT}${BOLD}Installer UI (gum)${RESET}"
  rule 56

  if has_command gum; then
    success "gum already installed"
    return 0
  fi

  if apt_install gum >/dev/null 2>&1 && has_command gum; then
    success "gum installed"
    return 0
  fi

  info "Adding charm apt repository"
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

# -----------------------------------------------------------------------------
# Optional AI tools
# -----------------------------------------------------------------------------

select_tools() {
  step "Select tools"

  echo
  local selected
  selected="$(gum choose --no-limit \
    --cursor "❯ " \
    --cursor-prefix "○ " \
    --selected-prefix "● " \
    --unselected-prefix "○ " \
    --cursor.foreground "$ACCENT" \
    --selected.foreground "$GREEN" \
    --height 8 \
    --header "  Space to select · Enter to confirm" \
    "opencode" \
    "claude" \
    "codex")"

  echo "$selected" | grep -qx "opencode" && SELECT_OPENCODE="on"
  echo "$selected" | grep -qx "claude" && SELECT_CLAUDE="on"
  echo "$selected" | grep -qx "codex" && SELECT_CODEX="on"

  echo
  tool_badge "opencode" "$SELECT_OPENCODE"
  tool_badge "claude" "$SELECT_CLAUDE"
  tool_badge "codex" "$SELECT_CODEX"
}

tool_badge() {
  local name="$1" state="$2"
  if [ "$state" = "on" ]; then
    printf "  ${C_GREEN}●${RESET} %-10s ${C_GREEN}selected${RESET}\n" "$name"
  else
    printf "  ${C_MUTED}○ %-10s skipped${RESET}\n" "$name"
  fi
}

install_node_if_missing() {
  if has_command node && has_command npm; then
    success "Node.js/npm already installed"
    return 0
  fi

  info "Installing Node.js 22 (required for Claude Code)"
  curl -fsSL https://deb.nodesource.com/setup_22.x | run_root bash -
  apt_install nodejs
  refresh_path

  has_command node && { success "Node.js/npm installed"; return 0; }
  warn "Node.js install finished, but it is not on PATH yet"
  return 1
}

install_opencode_if_missing() {
  if has_command opencode; then
    success "opencode already installed"
    return 0
  fi

  info "Installing opencode"
  curl -fsSL https://opencode.ai/install | bash
  refresh_path

  has_command opencode && { success "opencode installed"; return 0; }
  warn "opencode installer finished, but it is not on PATH yet"
  return 1
}

install_claude_if_missing() {
  if has_command claude; then
    success "Claude Code already installed"
    return 0
  fi

  install_node_if_missing || return 1

  info "Installing Claude Code"
  npm install -g @anthropic-ai/claude-code
  refresh_path

  has_command claude && { success "Claude Code installed"; return 0; }
  warn "Claude Code installer finished, but it is not on PATH yet"
  return 1
}

install_codex_if_missing() {
  if has_command codex; then
    success "Codex CLI already installed"
    return 0
  fi

  info "Installing Codex CLI"
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
  refresh_path

  has_command codex && { success "Codex CLI installed"; return 0; }
  warn "Codex installer finished, but it is not on PATH yet"
  return 1
}

install_selected_tools() {
  step "Install tools"

  if [ "$SELECT_OPENCODE$SELECT_CLAUDE$SELECT_CODEX" = "offoffoff" ]; then
    echo
    info "No tools selected — skipping"
    return 0
  fi

  echo
  [ "$SELECT_OPENCODE" = "on" ] && { install_opencode_if_missing || true; }
  [ "$SELECT_CLAUDE" = "on" ] && { install_claude_if_missing || true; }
  [ "$SELECT_CODEX" = "on" ] && { install_codex_if_missing || true; }
}

# -----------------------------------------------------------------------------
# Install + config
# -----------------------------------------------------------------------------

install_binaries() {
  step "Install devctl"
  echo
  run_root install -m 755 ./bin/dev "$INSTALL_DIR/dev"
  run_root install -d "$LIBEXEC_DIR"
  run_root install -m 755 ./bin/dev-config "$LIBEXEC_DIR/dev-config"
  success "command        → $INSTALL_DIR/dev"
  success "config editor  → $LIBEXEC_DIR/dev-config"

  append_shell_path_if_needed
  refresh_path
}

append_shell_path_if_needed() {
  local bashrc="$HOME/.bashrc"
  touch "$bashrc"

  if grep -q 'devctl path config' "$bashrc"; then
    success "bash PATH already configured"
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
  success "updated bash PATH ($bashrc)"
}

set_config_line() {
  local window_name="$1" window_command="$2" status="$3"

  if grep -q "^$window_name:" "$CONFIG_FILE"; then
    sed -i "s/^$window_name:$window_command:.*$/$window_name:$window_command:$status/" "$CONFIG_FILE"
    return 0
  fi
  echo "$window_name:$window_command:$status" >> "$CONFIG_FILE"
}

write_config() {
  step "Write config"
  echo

  mkdir -p "$CONFIG_DIR"

  # The selection is the user's intent — keep it on even if the tool is not
  # on PATH in this exact shell yet. dev skips missing commands at runtime.
  local oc="$SELECT_OPENCODE" cl="$SELECT_CLAUDE" cx="$SELECT_CODEX"

  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<CONFIG_EOF
shell:shell:on
opencode:opencode:$oc
claude:claude:$cl
codex:codex:$cx
CONFIG_EOF
    success "created $CONFIG_FILE"
    return 0
  fi

  info "updating existing $CONFIG_FILE"
  set_config_line "opencode" "opencode" "$oc"
  set_config_line "claude" "claude" "$cl"
  set_config_line "codex" "codex" "$cx"
}

# -----------------------------------------------------------------------------
# Verify + summary
# -----------------------------------------------------------------------------

check_row() {
  local label="$1" cmd="$2"
  if has_command "$cmd"; then
    printf "  ${C_GREEN}✓${RESET} %-16s ${C_MUTED}%s${RESET}\n" "$label" "$(command -v "$cmd")"
  else
    printf "  ${C_DANGER}✗${RESET} %-16s ${C_DANGER}missing${RESET}\n" "$label"
    VERIFY_OK=0
  fi
}

verify_install() {
  step "Verify"
  echo

  VERIFY_OK=1

  check_row "dev" "dev"
  check_row "tmux" "tmux"
  check_row "python3" "python3"
  check_row "gum" "gum"

  if [ -f "$LIBEXEC_DIR/dev-config" ] && python3 -c "import curses" >/dev/null 2>&1; then
    printf "  ${C_GREEN}✓${RESET} %-16s ${C_MUTED}%s${RESET}\n" "config editor" "$LIBEXEC_DIR/dev-config"
  else
    printf "  ${C_DANGER}✗${RESET} %-16s ${C_DANGER}missing (file or python3 curses)${RESET}\n" "config editor"
    VERIFY_OK=0
  fi

  echo
  printf "  ${C_MUTED}${BOLD}%-2s  %-14s %-14s %s${RESET}\n" "#" "WINDOW" "COMMAND" "STATUS"
  rule 48

  local i=1
  while IFS=":" read -r window_name window_command enabled; do
    [ -z "$window_name" ] && continue
    if [ "$enabled" = "on" ]; then
      printf "  ${C_MUTED}%-2s${RESET}  ${C_TEXT}%-14s${RESET} ${C_SKY}%-14s${RESET} ${C_GREEN}● ON${RESET}\n" \
        "$i" "$window_name" "$window_command"
    else
      printf "  ${C_MUTED}%-2s  %-14s %-14s ○ OFF${RESET}\n" \
        "$i" "$window_name" "$window_command"
    fi
    i=$((i + 1))
  done < "$CONFIG_FILE"

  echo
  if [ "$VERIFY_OK" -ne 1 ]; then
    error "Finished with missing components (see above)"
    return 1
  fi
  success "Everything checks out"
}

print_summary() {
  echo

  gum style \
    --foreground "$GREEN" \
    --border double \
    --border-foreground "$GREEN" \
    --align center \
    --width 60 \
    --padding "1 3" \
    --bold \
    "✓  INSTALLED" \
    "devctl is ready to use"

  echo
  echo -e "  ${C_ACCENT}${BOLD}COMMANDS${RESET}"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev start"        "start or attach the current project"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev stop"         "stop the current project session"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev restart"      "restart the current project session"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev status"       "show the current project session"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev list"         "list all dev sessions"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev kill <name>"  "kill a specific session"
  printf "  ${C_SKY}%-22s${RESET}${C_MUTED}%s${RESET}\n" "dev config"       "open the interactive config editor"

  echo
  echo -e "  ${C_ACCENT}${BOLD}GET STARTED${RESET}"
  gum style \
    --foreground "$TEXT" \
    --border rounded \
    --border-foreground "$BORDER" \
    --padding "1 2" \
    "cd ~/projects/my-project" \
    "dev start"

  echo
  echo -e "  ${C_MUTED}Open a new terminal or run: ${C_TEXT}source ~/.bashrc${RESET}"
  echo
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

if [ ! -f "./bin/dev" ] || [ ! -f "./bin/dev-config" ]; then
  error "Run this from the devctl repository root (bin/dev not found)"
  exit 1
fi

refresh_path
ensure_required_dependencies
ensure_gum
banner

select_tools
install_selected_tools
install_binaries
write_config
verify_install || true
print_summary
