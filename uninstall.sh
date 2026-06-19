#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
LIBEXEC_DIR="/usr/local/lib/devctl"
CONFIG_DIR="$HOME/.config/devctl"

run_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

run_root rm -f "$INSTALL_DIR/dev"
# Remove the legacy on-PATH editor from older installs, if present.
run_root rm -f "$INSTALL_DIR/dev-config"
run_root rm -rf "$LIBEXEC_DIR"

echo "removed: $INSTALL_DIR/dev"
echo "removed: $LIBEXEC_DIR"

if [ -d "$CONFIG_DIR" ]; then
  read -r -p "Also remove config dir $CONFIG_DIR? [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES)
      rm -rf "$CONFIG_DIR"
      echo "removed: $CONFIG_DIR"
      ;;
    *)
      echo "kept: $CONFIG_DIR"
      ;;
  esac
fi
