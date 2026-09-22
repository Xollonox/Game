#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Godot Engine Installer ===${NC}"
echo "This script downloads and installs the latest Godot Engine 4.x"
echo ""

# Detect OS and architecture
OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Linux)
    if [ "$ARCH" = "x86_64" ]; then
      PLATFORM="linux.x86_64"
    elif [ "$ARCH" = "aarch64" ]; then
      PLATFORM="linux.arm64"
    else
      echo -e "${RED}Unsupported architecture: $ARCH${NC}"
      exit 1
    fi
    ;;
  Darwin)
    if [ "$ARCH" = "arm64" ]; then
      PLATFORM="macos.arm64"
    else
      PLATFORM="macos.x86_64"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    PLATFORM="win64"
    ;;
  *)
    echo -e "${RED}Unsupported OS: $OS${NC}"
    exit 1
    ;;
esac

echo -e "${BLUE}Detected: $OS ($ARCH) -> $PLATFORM${NC}"
echo ""

# Get latest stable version
echo -e "${BLUE}Fetching latest Godot release...${NC}"
LATEST_VERSION=$(curl -s https://api.github.com/repos/godotengine/godot-releases/releases/latest | grep '"tag_name"' | head -1 | cut -d'"' -f4 | sed 's/-stable//')

if [ -z "$LATEST_VERSION" ]; then
  echo -e "${RED}Failed to fetch latest version. Trying Godot 4.2.2...${NC}"
  LATEST_VERSION="4.2.2"
fi

echo -e "${GREEN}Latest version: $LATEST_VERSION${NC}"
echo ""

# Build download URL
DOWNLOAD_URL="https://github.com/godotengine/godot-releases/releases/download/${LATEST_VERSION}-stable/Godot_v${LATEST_VERSION}-stable_${PLATFORM}.zip"
FILENAME="godot-${LATEST_VERSION}.zip"
INSTALL_DIR="${HOME}/.godot"

echo -e "${BLUE}Download URL:${NC} $DOWNLOAD_URL"
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"

# Download
echo -e "${BLUE}Downloading Godot ${LATEST_VERSION}...${NC}"
if ! curl -L -o "$FILENAME" "$DOWNLOAD_URL"; then
  echo -e "${RED}Download failed!${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Downloaded!${NC}"
echo ""

# Extract
echo -e "${BLUE}Extracting...${NC}"
unzip -q "$FILENAME" -d "$INSTALL_DIR"
rm "$FILENAME"

# Find the binary
GODOT_BIN=$(find "$INSTALL_DIR" -name "Godot_v*" -type f | head -1)

if [ ! -f "$GODOT_BIN" ]; then
  echo -e "${RED}Failed to extract Godot binary!${NC}"
  exit 1
fi

chmod +x "$GODOT_BIN"
echo -e "${GREEN}✓ Extracted!${NC}"
echo ""

# Create symlink
BIN_DIR="${HOME}/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$GODOT_BIN" "$BIN_DIR/godot"

echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo -e "${BLUE}Godot binary location:${NC} $GODOT_BIN"
echo -e "${BLUE}Symlink created at:${NC} $BIN_DIR/godot"
echo ""

# Check if .local/bin is in PATH
if [[ ":$PATH:" == *":${BIN_DIR}:"* ]]; then
  echo -e "${GREEN}✓ $BIN_DIR is in your PATH${NC}"
  echo "You can now run: ${GREEN}godot${NC}"
else
  echo -e "${RED}! $BIN_DIR is not in your PATH${NC}"
  echo "Add this line to your shell profile (~/.bashrc, ~/.zshrc, etc):"
  echo -e "  ${BLUE}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
  echo ""
  echo "Or run Godot directly with:"
  echo -e "  ${BLUE}$GODOT_BIN${NC}"
fi

echo ""
echo -e "${BLUE}To open this project in Godot:${NC}"
echo -e "  ${GREEN}godot${NC} (then select File > Open Project)"
echo "  or"
echo -e "  ${GREEN}godot project.godot${NC}"
