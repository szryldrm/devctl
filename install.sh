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

SUDO=""
is_root || SUDO="sudo"

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

# Cache sudo credentials up front so the silent installs below never block on
# a hidden password prompt. Prompted at most once, and only when needed.
prime_sudo() {
  is_root && return 0
  [ "${SUDO_PRIMED:-}" = "1" ] && return 0
  has_command sudo || return 0
  warn "sudo access is required to install packages"
  sudo -v 2>/dev/null || true
  SUDO_PRIMED=1
}

apt_update_once() {
  [ "${APT_UPDATED:-}" = "1" ] && return 0
  require_apt
  prime_sudo
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
  APT_UPDATED=1
}

# Quiet, non-interactive package install — produces no terminal output.
apt_install_now() {
  require_apt "$@"
  prime_sudo
  apt_update_once
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" >/dev/null 2>&1 || true
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

# gum drives the whole UI, so install it first and silently (there is no gum
# yet to draw a spinner with). On Debian/Ubuntu it usually needs the charm
# apt repository.
ensure_gum() {
  has_command gum && return 0

  echo -e "  ${C_MUTED}Preparing installer…${RESET}"

  apt_install_now gum
  has_command gum && return 0

  # charm apt repository fallback
  apt_install_now curl ca-certificates gnupg
  $SUDO mkdir -p /etc/apt/keyrings >/dev/null 2>&1 || true
  curl -fsSL https://repo.charm.sh/apt/gpg.key 2>/dev/null |
    $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg >/dev/null 2>&1 || true
  echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" |
    $SUDO tee /etc/apt/sources.list.d/charm.list >/dev/null 2>&1 || true

  APT_UPDATED=""
  apt_install_now gum

  if ! has_command gum; then
    error "Failed to install gum (required for the installer UI)"
    exit 1
  fi
}

ensure_required_dependencies() {
  echo
  echo -e "  ${C_ACCENT}${BOLD}DEPENDENCIES${RESET}"
  rule 56
  echo

  local missing_packages=()
  local seen=""
  local cmd pkg

  for cmd in $REQUIRED_COMMANDS; do
    has_command "$cmd" && continue
    pkg="$(apt_pkg_for "$cmd")"
    case " $seen " in
      *" $pkg "*) ;;
      *) missing_packages+=("$pkg"); seen="$seen $pkg" ;;
    esac
  done

  [ -f /etc/ssl/certs/ca-certificates.crt ] || missing_packages+=("ca-certificates")

  if [ "${#missing_packages[@]}" -eq 0 ]; then
    success "all required dependencies already present"
  else
    info "These packages will be installed:"
    for pkg in "${missing_packages[@]}"; do
      echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}${pkg}${RESET}"
    done
    echo
    prime_sudo
    spin "Installing dependencies" \
      "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ${missing_packages[*]}"
    refresh_path
  fi

  # The config editor needs python3 + the curses stdlib module.
  if has_command python3 && ! python3 -c "import curses" >/dev/null 2>&1; then
    spin "Installing python3 (curses)" \
      "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3"
  fi

  local still_missing=()
  for cmd in $REQUIRED_COMMANDS; do
    has_command "$cmd" || still_missing+=("$cmd")
  done

  if [ "${#still_missing[@]}" -gt 0 ]; then
    error "Could not install: ${still_missing[*]}"
    error "Install them manually and re-run ./install.sh"
    exit 1
  fi

  success "dependencies ready"
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

# Run a command behind a spinner. gum hides the command's own output and shows
# only the loading bar with our title — so we must NOT redirect gum's output.
spin() {
  local title="$1" cmd="$2"

  if has_command gum; then
    gum spin --spinner dot \
      --spinner.foreground "$ACCENT" \
      --title.foreground "$TEXT" \
      --title "$title" \
      -- bash -c "$cmd" || true
  else
    info "$title"
    bash -c "$cmd" >/dev/null 2>&1 || true
  fi
}

install_node_if_missing() {
  if has_command node && has_command npm; then
    return 0
  fi

  prime_sudo
  spin "Installing Node.js 22" \
    "curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash - && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs"
  refresh_path
}

install_opencode_if_missing() {
  if has_command opencode; then
    success "opencode already installed"
    return 0
  fi

  spin "Installing opencode" "curl -fsSL https://opencode.ai/install | bash"
  refresh_path

  has_command opencode && success "opencode installed" || warn "opencode is not on PATH yet"
}

install_claude_if_missing() {
  if has_command claude; then
    success "Claude Code already installed"
    return 0
  fi

  install_node_if_missing

  if ! has_command npm; then
    warn "npm unavailable — skipping Claude Code"
    return 0
  fi

  spin "Installing Claude Code" "npm install -g @anthropic-ai/claude-code"
  refresh_path

  has_command claude && success "Claude Code installed" || warn "claude is not on PATH yet"
}

install_codex_if_missing() {
  if has_command codex; then
    success "Codex CLI already installed"
    return 0
  fi

  spin "Installing Codex CLI" "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh"
  refresh_path

  has_command codex && success "Codex CLI installed" || warn "codex is not on PATH yet"
}

install_selected_tools() {
  step "Install tools"

  if [ "$SELECT_OPENCODE$SELECT_CLAUDE$SELECT_CODEX" = "offoffoff" ]; then
    echo
    info "No tools selected — skipping"
    return 0
  fi

  echo
  info "These tools will be installed:"
  [ "$SELECT_OPENCODE" = "on" ] && echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}opencode${RESET}"
  [ "$SELECT_CLAUDE" = "on" ] && echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}claude  ${C_MUTED}(+ Node.js)${RESET}"
  [ "$SELECT_CODEX" = "on" ] && echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}codex${RESET}"
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
ensure_gum
banner
ensure_required_dependencies

select_tools
install_selected_tools
install_binaries
write_config
verify_install || true
print_summary
