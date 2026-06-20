#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
LIBEXEC_DIR="/usr/local/lib/devctl"
CONFIG_DIR="$HOME/.config/devctl"
CONFIG_FILE="$CONFIG_DIR/config.json"

SELECT_OPENCODE="off"
SELECT_CLAUDE="off"
SELECT_CODEX="off"

# PICK_* = tools the user chose to install (only ever set for tools that are
# not already on the system). SELECT_* = final config state (on if installed
# or picked).
PICK_OPENCODE="off"
PICK_CLAUDE="off"
PICK_CODEX="off"

# --debug shows the underlying command output instead of hiding it behind
# spinners. Everything is logged either way.
DEBUG=0
for _arg in "$@"; do
  [ "$_arg" = "--debug" ] && DEBUG=1
done

# Use a UTF-8 locale immediately so the installer UI renders correctly. Only
# switch to one that already exists (C.UTF-8 ships with glibc) to avoid
# setlocale warnings; a persistent locale is ensured later.
case "${LANG:-}" in
  *[Uu][Tt][Ff]*8*) ;;
  *)
    for _loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
      if locale -a 2>/dev/null | grep -qix "$_loc"; then export LANG="$_loc"; break; fi
    done
    unset _loc
    ;;
esac

LOG_DIR="$HOME/.config/devctl/logs"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
APT_Q="-qq"
[ "$DEBUG" = "1" ] && APT_Q=""
mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

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
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/.bun/bin:/usr/local/bin:$PATH"
}

has_command() {
  refresh_path
  command -v "$1" >/dev/null 2>&1
}

# Robustly detect whether a supported tool is already installed. Checks PATH
# and the common per-tool install locations, so detection does not depend on
# the current shell's PATH (or interactive-only aliases).
tool_present() {
  has_command "$1" && return 0
  local p
  for p in \
    "$HOME/.opencode/bin/$1" \
    "$HOME/.local/bin/$1" \
    "$HOME/.bun/bin/$1" \
    "/usr/local/bin/$1" \
    "/usr/bin/$1" \
    "/opt/$1/bin/$1"; do
    [ -x "$p" ] && return 0
  done
  return 1
}

is_root() { [ "$(id -u)" -eq 0 ]; }

run_root() {
  if is_root; then "$@"; else sudo "$@"; fi
}

SUDO=""
is_root || SUDO="sudo"

log() { printf '%s\n' "$*" >>"$LOG_FILE" 2>/dev/null || true; }

# Execute a shell command string. Output always goes to the log; it is shown
# on the terminal only in --debug mode.
run() {
  log "+ $1"
  if [ "$DEBUG" = "1" ]; then
    bash -c "$1" 2>&1 | tee -a "$LOG_FILE"
  else
    bash -c "$1" >>"$LOG_FILE" 2>&1
  fi
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
  run "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get update $APT_Q" || true
  APT_UPDATED=1
}

# Quiet, non-interactive package install — logged, hidden unless --debug.
apt_install_now() {
  require_apt "$@"
  prime_sudo
  apt_update_once
  run "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_Q $*" || true
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
  run "$SUDO mkdir -p /etc/apt/keyrings" || true
  run "curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg" || true
  run "echo 'deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *' | $SUDO tee /etc/apt/sources.list.d/charm.list" || true

  APT_UPDATED=""
  apt_install_now gum

  if ! has_command gum; then
    error "Failed to install gum (required for the installer UI)"
    exit 1
  fi
}

# A UTF-8 locale is required so tmux/opencode/claude render box-drawing
# glyphs instead of broken boxes. Generate en_US.UTF-8 and switch to it.
ensure_locale() {
  # Already on a UTF-8 locale (e.g. set by the top-level block)? Done.
  case "${LANG:-}" in
    *[Uu][Tt][Ff]*8*) return 0 ;;
  esac

  # Prefer an existing UTF-8 locale — C.UTF-8 ships with glibc and needs no
  # generation, which avoids "cannot change locale" warnings.
  local loc
  for loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if locale -a 2>/dev/null | grep -qix "$loc"; then
      export LANG="$loc"
      return 0
    fi
  done

  # Nothing available — generate en_US.UTF-8.
  prime_sudo
  spin "Configuring UTF-8 locale" \
    "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_Q locales; \
     [ -f /etc/locale.gen ] && $SUDO sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen; \
     $SUDO locale-gen en_US.UTF-8; \
     $SUDO update-locale LANG=en_US.UTF-8"

  export LANG=en_US.UTF-8
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
      "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get update $APT_Q && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_Q ${missing_packages[*]}"
    refresh_path
  fi

  # The config editor needs python3 + the curses stdlib module.
  if has_command python3 && ! python3 -c "import curses" >/dev/null 2>&1; then
    spin "Installing python3 (curses)" \
      "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_Q python3"
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

# Optional: compressed RAM swap so the kernel can page out idle sessions
# (opencode/claude/codex) under memory pressure, reclaiming RAM without
# touching the processes. The cleanest way to run many sessions at once.
ensure_zram() {
  echo
  echo -e "  ${C_ACCENT}${BOLD}MEMORY${RESET}"
  rule 56
  echo

  if grep -q zram /proc/swaps 2>/dev/null; then
    success "zram swap already active"
    return 0
  fi

  if ! gum confirm "Enable zram (compressed RAM swap) to fit more sessions in RAM?"; then
    info "skipped zram"
    return 0
  fi

  prime_sudo
  spin "Enabling zram swap" \
    "$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_Q zram-tools && \
     printf 'ALGO=zstd\nPERCENT=50\n' | $SUDO tee /etc/default/zramswap >/dev/null && \
     { $SUDO systemctl restart zramswap || $SUDO systemctl enable --now zramswap; } && \
     { $SUDO service zramswap restart 2>/dev/null || true; }"

  if grep -q zram /proc/swaps 2>/dev/null; then
    success "zram swap enabled (zstd, 50% of RAM)"
  else
    warn "zram-tools installed, but no zram device is active yet"
    warn "(some VMs/containers lack the zram kernel module) — see the log"
  fi
}

# -----------------------------------------------------------------------------
# Optional AI tools
# -----------------------------------------------------------------------------

tool_badge() {
  local name="$1" state="$2"
  if [ "$state" = "on" ]; then
    printf "  ${C_GREEN}●${RESET} %-10s ${C_GREEN}will install${RESET}\n" "$name"
  else
    printf "  ${C_MUTED}○ %-10s skipped${RESET}\n" "$name"
  fi
}

select_tools() {
  step "Select tools"
  echo

  # Split into already-installed (kept, never prompted/installed) vs available.
  local installed=() available=() t
  for t in opencode claude codex; do
    if tool_present "$t"; then installed+=("$t"); else available+=("$t"); fi
  done

  if [ "${#installed[@]}" -gt 0 ]; then
    for t in "${installed[@]}"; do
      printf "  ${C_GREEN}✓${RESET} %-10s ${C_MUTED}already installed${RESET}\n" "$t"
    done
    echo
  fi

  if [ "${#available[@]}" -eq 0 ]; then
    info "All supported tools are already installed — nothing to choose"
  else
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
      "${available[@]}")"

    echo "$selected" | grep -qx "opencode" && PICK_OPENCODE="on"
    echo "$selected" | grep -qx "claude" && PICK_CLAUDE="on"
    echo "$selected" | grep -qx "codex" && PICK_CODEX="on"

    echo
    for t in "${available[@]}"; do
      case "$t" in
        opencode) tool_badge opencode "$PICK_OPENCODE" ;;
        claude)   tool_badge claude "$PICK_CLAUDE" ;;
        codex)    tool_badge codex "$PICK_CODEX" ;;
      esac
    done
  fi

  # Final config state: enabled if already installed OR picked to install.
  tool_present opencode && SELECT_OPENCODE="on"; [ "$PICK_OPENCODE" = "on" ] && SELECT_OPENCODE="on"
  tool_present claude && SELECT_CLAUDE="on"; [ "$PICK_CLAUDE" = "on" ] && SELECT_CLAUDE="on"
  tool_present codex && SELECT_CODEX="on"; [ "$PICK_CODEX" = "on" ] && SELECT_CODEX="on"

  return 0
}

# Run a command behind a spinner. In --debug the output is shown (and logged)
# instead of a spinner. Otherwise gum shows only the loading bar and the
# command's output is appended to the log file.
spin() {
  local title="$1" cmd="$2"
  log "=== $title ==="

  if [ "$DEBUG" = "1" ]; then
    info "$title"
    run "$cmd" || true
    return 0
  fi

  if has_command gum; then
    gum spin --spinner dot \
      --spinner.foreground "$ACCENT" \
      --title.foreground "$TEXT" \
      --title "$title" \
      -- bash -c "{ $cmd ; } >> '$LOG_FILE' 2>&1" || true
  else
    info "$title"
    bash -c "{ $cmd ; } >> '$LOG_FILE' 2>&1" || true
  fi
}

install_node_if_missing() {
  if has_command node && has_command npm; then
    return 0
  fi

  prime_sudo
  spin "Installing Node.js 22" \
    "curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO bash - && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_Q nodejs"
  refresh_path
}

install_opencode_if_missing() {
  if tool_present opencode; then
    success "opencode already installed"
    return 0
  fi

  spin "Installing opencode" "curl -fsSL https://opencode.ai/install | bash"
  refresh_path

  has_command opencode && success "opencode installed" || warn "opencode is not on PATH yet"
}

install_claude_if_missing() {
  if tool_present claude; then
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
  if tool_present codex; then
    success "Codex CLI already installed"
    return 0
  fi

  spin "Installing Codex CLI" "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh"
  refresh_path

  has_command codex && success "Codex CLI installed" || warn "codex is not on PATH yet"
}

install_selected_tools() {
  step "Install tools"

  if [ "$PICK_OPENCODE$PICK_CLAUDE$PICK_CODEX" = "offoffoff" ]; then
    echo
    info "Nothing new to install"
    return 0
  fi

  echo
  info "These tools will be installed:"
  [ "$PICK_OPENCODE" = "on" ] && echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}opencode${RESET}"
  [ "$PICK_CLAUDE" = "on" ] && echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}claude  ${C_MUTED}(+ Node.js)${RESET}"
  [ "$PICK_CODEX" = "on" ] && echo -e "    ${C_ACCENT}•${RESET} ${C_TEXT}codex${RESET}"
  echo

  [ "$PICK_OPENCODE" = "on" ] && { install_opencode_if_missing || true; }
  [ "$PICK_CLAUDE" = "on" ] && { install_claude_if_missing || true; }
  [ "$PICK_CODEX" = "on" ] && { install_codex_if_missing || true; }

  return 0
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

  # Migrate: older installs hardcoded a locale that may not exist on the
  # system, which caused "cannot change locale" warnings. Drop that line.
  sed -i '/^[[:space:]]*\*) export LANG=en_US\.UTF-8 ;;[[:space:]]*$/d' "$bashrc" 2>/dev/null || true

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

# devctl: ensure a UTF-8 locale for correct glyph rendering
case "${LANG:-}" in
  *[Uu][Tt][Ff]*8*) ;;
  *)
    for _loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
      if locale -a 2>/dev/null | grep -qix "$_loc"; then export LANG="$_loc"; break; fi
    done
    unset _loc
    ;;
esac
BASHRC_EOF
  success "updated bash PATH ($bashrc)"
}

write_config() {
  step "Write config"
  echo

  mkdir -p "$CONFIG_DIR"

  # Only the tools that are installed/selected go into the config. Existing
  # entries are preserved; newly selected tools are added (enabled). Nothing
  # is written as "off".
  local tools=()
  [ "$SELECT_OPENCODE" = "on" ] && tools+=("opencode")
  [ "$SELECT_CLAUDE" = "on" ] && tools+=("claude")
  [ "$SELECT_CODEX" = "on" ] && tools+=("codex")

  python3 - "$CONFIG_FILE" "${tools[@]}" <<'PY'
import json, os, sys

path = sys.argv[1]
tools = sys.argv[2:]
legacy = os.path.join(os.path.dirname(path), "config")

data = {"windows": []}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = {"windows": []}
elif os.path.exists(legacy):
    wins = []
    for line in open(legacy):
        parts = line.strip().split(":", 2)
        if len(parts) == 3:
            wins.append({"name": parts[0], "command": parts[1], "enabled": parts[2] == "on"})
    data = {"windows": wins}

wins = data.setdefault("windows", [])
names = {w.get("name") for w in wins}

if "shell" not in names:
    wins.insert(0, {"name": "shell", "command": "shell", "enabled": True})

for t in tools:
    found = next((w for w in wins if w.get("name") == t), None)
    if found:
        found["enabled"] = True
    else:
        wins.append({"name": t, "command": t, "enabled": True})

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

  success "wrote $CONFIG_FILE"
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
  while IFS=$'\t' read -r window_name window_command enabled; do
    [ -z "$window_name" ] && continue
    if [ "$enabled" = "on" ]; then
      printf "  ${C_MUTED}%-2s${RESET}  ${C_TEXT}%-14s${RESET} ${C_SKY}%-14s${RESET} ${C_GREEN}● ON${RESET}\n" \
        "$i" "$window_name" "$window_command"
    else
      printf "  ${C_MUTED}%-2s  %-14s %-14s ○ OFF${RESET}\n" \
        "$i" "$window_name" "$window_command"
    fi
    i=$((i + 1))
  done < <(python3 - "$CONFIG_FILE" <<'PY'
import json, sys
try:
    wins = json.load(open(sys.argv[1])).get("windows", [])
except Exception:
    wins = []
for w in wins:
    print(f"{w.get('name','')}\t{w.get('command','')}\t{'on' if w.get('enabled') else 'off'}")
PY
)

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
  echo -e "  ${C_ACCENT}${BOLD}LOG${RESET}"
  echo -e "  ${C_MUTED}Install log:${RESET} ${C_TEXT}${LOG_FILE}${RESET}"
  echo -e "  ${C_MUTED}Re-run with ${C_TEXT}./install.sh --debug${C_MUTED} to see command output live${RESET}"

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

log "devctl install started $(date)"
log "debug=$DEBUG"

refresh_path
ensure_gum
ensure_locale
banner
ensure_required_dependencies
ensure_zram

select_tools
install_selected_tools
install_binaries
write_config
verify_install || true
print_summary
