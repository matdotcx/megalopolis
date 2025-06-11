#!/bin/bash
set -euo pipefail

echo "Setting up Colima with MacPorts..."

# Check if MacPorts is available
if ! command -v port &> /dev/null; then
    echo "ERROR: MacPorts is not installed or not in PATH"
    echo "Please install MacPorts from https://www.macports.org/"
    exit 1
fi

# Check if Colima is installed
if ! command -v colima &> /dev/null; then
    echo "Colima not found. Installing via MacPorts..."
    # Note: Colima might not be in MacPorts, so we'll use the binary release
    
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        ARCH="x86_64"
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        ARCH="aarch64"
    fi
    
    COLIMA_VERSION="v0.6.8"
    echo "Downloading Colima ${COLIMA_VERSION} for ${ARCH}..."
    
    curl -LO "https://github.com/abiosoft/colima/releases/download/${COLIMA_VERSION}/colima-Darwin-${ARCH}"
    chmod +x "colima-Darwin-${ARCH}"
    
    # Move to /opt/local/bin (MacPorts bin directory)
    echo "Installing Colima to /opt/local/bin/..."
    sudo mv "colima-Darwin-${ARCH}" /opt/local/bin/colima
    
    echo "Colima installed successfully."
else
    echo "Colima is already installed."
fi

# Check if docker CLI is installed via MacPorts
if ! command -v docker &> /dev/null; then
    echo "Docker CLI not found. Installing via MacPorts..."
    sudo port install docker
else
    echo "Docker CLI is already installed."
fi

# Check Colima version
echo ""
echo "Installed versions:"
colima version
docker version --format 'Docker Client {{.Client.Version}}' 2>/dev/null || echo "Docker client version check failed"

echo ""
echo "Colima setup complete!"
echo "You can start Colima with: colima start"