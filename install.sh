#!/usr/bin/env bash

set -e

INSTALL_DIR="/usr/local/bin"

if [ ! -f "./bin/dev" ]; then
  echo "bin/dev not found"
  exit 1
fi

install -m 755 ./bin/dev "$INSTALL_DIR/dev"

echo "dev installed to $INSTALL_DIR/dev"
echo "Run: dev start"
