#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/devctl"

rm -f "$INSTALL_DIR/dev"
rm -f "$INSTALL_DIR/dev-config"

echo "removed: $INSTALL_DIR/dev"
echo "removed: $INSTALL_DIR/dev-config"

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
