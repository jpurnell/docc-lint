#!/bin/bash

# docc-lint installation script
# Installs the docc-lint tool to /usr/local/custom/bin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/custom/bin}"

echo "Building docc-lint..."
cd "$PROJECT_DIR"

# Build in release mode
swift build -c release

# Find the built binary
BINARY_PATH="$(swift build -c release --show-bin-path)/docc-lint"

if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Build failed - binary not found at $BINARY_PATH"
    exit 1
fi

# Create install directory if needed
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating install directory: $INSTALL_DIR"
    sudo mkdir -p "$INSTALL_DIR"
fi

# Install the binary
echo "Installing to $INSTALL_DIR/docc-lint..."
sudo cp "$BINARY_PATH" "$INSTALL_DIR/docc-lint"
sudo chmod +x "$INSTALL_DIR/docc-lint"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "⚠️  $INSTALL_DIR is not in your PATH."
    echo ""
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo ""
    echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    echo ""
fi

echo ""
echo "✅ docc-lint installed successfully!"
echo ""
echo "Usage:"
echo "  docc-lint /path/to/project          # Syntax-only validation (fast)"
echo "  docc-lint /path/to/project --full   # Full validation with symbol graphs"
echo "  docc-lint --help                    # Show all options"
echo ""
