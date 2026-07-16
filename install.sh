#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define target paths
TARGET_DIR="/usr/local/bin"
TARGET_NAME="androidmonitor"
SCRIPT_SOURCE="androidmonitor.sh"

# Ensure the script is run with sudo/root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this installer as root (e.g., sudo ./install.sh)"
  exit 1
fi

echo "Installing $TARGET_NAME to $TARGET_DIR..."

# install copies the file and sets ownership + permissions (755) in one go
install -Dm755 "$SCRIPT_SOURCE" "$TARGET_DIR/$TARGET_NAME"

echo "Installation complete! You can now run '$TARGET_NAME' from anywhere."
