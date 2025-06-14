#!/bin/bash
set -euo pipefail

# Check Docker is running first
echo "Checking Docker..."
if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running."
    
    # Check if we're using Colima or Docker Desktop
    if command -v colima &> /dev/null; then
        echo "Starting Colima..."
        
        # Check if Colima is already running
        if colima status &>/dev/null; then
            echo "Colima is already running but Docker is not accessible."
            echo "Trying to restart Colima..."
            colima stop
            sleep 2
        fi
        
        # Start Colima with appropriate resources
        colima start --cpu 4 --memory 8 --disk 60
        
        # Wait for Docker to be ready (up to 60 seconds)
        echo "Waiting for Docker daemon to be ready..."
        for i in {1..60}; do
            if docker info >/dev/null 2>&1; then
                echo "Colima started successfully!"
                break
            fi
            # Show progress every 5 seconds
            if [ $((i % 5)) -eq 0 ]; then
                echo "Still waiting... ($i/60 seconds)"
            fi
            sleep 1
        done
        
        # Final check
        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: Docker daemon failed to start within 60 seconds."
            echo "Please check Colima status with: colima status"
            exit 1
        fi
        
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Fallback to Docker Desktop if Colima is not installed
        echo "Colima not found. Trying Docker Desktop..."
        
        if open -a Docker 2>/dev/null; then
            # Wait for Docker to start (up to 60 seconds)
            echo "Waiting for Docker Desktop to start..."
            for i in {1..60}; do
                if docker info >/dev/null 2>&1; then
                    echo "Docker Desktop started successfully!"
                    break
                fi
                # Show progress every 5 seconds
                if [ $((i % 5)) -eq 0 ]; then
                    echo "Still waiting... ($i/60 seconds)"
                fi
                sleep 1
            done
            
            # Final check
            if ! docker info >/dev/null 2>&1; then
                echo "ERROR: Docker Desktop failed to start within 60 seconds."
                exit 1
            fi
        else
            echo "ERROR: Neither Colima nor Docker Desktop found!"
            echo "Please run: ./scripts/setup-colima.sh"
            exit 1
        fi
    else
        echo "ERROR: Docker is not running!"
        echo "Please start Docker manually."
        exit 1
    fi
else
    echo "Docker is running."
fi
echo ""

# Tool versions
KUBECTL_VERSION="v1.33.1"
HELM_VERSION="v3.18.2"
KIND_VERSION="v0.23.0"
TART_VERSION="latest"
ORCHARD_VERSION="latest"

# Tool paths
KUBECTL_BIN="./kubectl"
HELM_BIN="./helm"
KIND_BIN="./kind-binary"
TART_BIN="./tart-binary"
ORCHARD_BIN="./orchard-binary"

# Architecture detection
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
fi

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

echo "Ensuring required tools are available..."
echo "Platform: $OS/$ARCH"

# Download kubectl if not present
if [ ! -f "$KUBECTL_BIN" ]; then
    echo "kubectl not found. Downloading version $KUBECTL_VERSION..."
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
    chmod +x kubectl
    echo "kubectl downloaded successfully."
else
    echo "kubectl already exists."
fi

# Download helm if not present
if [ ! -f "$HELM_BIN" ]; then
    echo "helm not found. Downloading version $HELM_VERSION..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    bash get_helm.sh --version ${HELM_VERSION} --no-sudo
    # Move helm to project directory
    if [ -f "/usr/local/bin/helm" ]; then
        mv /usr/local/bin/helm ./helm
    fi
    rm -f get_helm.sh
    echo "helm downloaded successfully."
else
    echo "helm already exists."
fi

# Download kind if not present
if [ ! -f "$KIND_BIN" ]; then
    echo "kind not found. Downloading version $KIND_VERSION..."
    curl -Lo ./kind-binary "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"
    chmod +x ./kind-binary
    echo "kind downloaded successfully."
else
    echo "kind already exists."
fi

# Install/Update Tart using MacPorts (macOS only)
if [[ "$OS" == "darwin" ]]; then
    if [ ! -f "$TART_BIN" ]; then
        echo "tart not found. Checking for existing installation..."
        
        # Check if tart is available in PATH first
        if command -v tart &> /dev/null; then
            echo "Found existing tart installation, creating symlink..."
            ln -sf "$(which tart)" "$TART_BIN"
            echo "tart linked successfully."
        elif command -v port &> /dev/null; then
            echo "MacPorts found. Attempting to install tart..."
            echo "Note: This requires sudo privileges. If you don't have sudo access,"
            echo "you can install tart manually and rerun this script."
            
            # Try to install tart via MacPorts
            if sudo -n port install tart 2>/dev/null; then
                echo "tart installed via MacPorts successfully."
                if command -v tart &> /dev/null; then
                    ln -sf "$(which tart)" "$TART_BIN"
                    echo "tart linked successfully."
                fi
            else
                echo "WARNING: Could not install tart via MacPorts (sudo required)."
                echo "Please install tart manually:"
                echo "  sudo port install tart"
                echo "Or install from GitHub: https://github.com/cirruslabs/tart"
                
                # Create a helpful wrapper script
                cat > "$TART_BIN" << 'EOF'
#!/bin/bash
echo "ERROR: Tart is not installed."
echo "Please install tart via MacPorts:"
echo "  sudo port install tart"
echo "Or from GitHub: https://github.com/cirruslabs/tart"
echo "Then run 'make ensure-tools' again."
exit 1
EOF
                chmod +x "$TART_BIN"
            fi
        else
            echo "WARNING: Neither tart nor MacPorts found."
            echo "Please install tart manually:"
            echo "  - Via MacPorts: sudo port install tart"
            echo "  - Via GitHub: https://github.com/cirruslabs/tart"
            
            # Create a helpful wrapper script
            cat > "$TART_BIN" << 'EOF'
#!/bin/bash
echo "ERROR: Tart is not installed."
echo "Please install tart via MacPorts:"
echo "  sudo port install tart"
echo "Or from GitHub: https://github.com/cirruslabs/tart"
echo "Then run 'make ensure-tools' again."
exit 1
EOF
            chmod +x "$TART_BIN"
        fi
    else
        echo "tart already exists."
    fi
    
    # Install/Update Orchard CLI
    if [ ! -f "$ORCHARD_BIN" ]; then
        echo "orchard not found. Downloading latest version..."
        
        # Download Orchard CLI from GitHub releases
        ORCHARD_DOWNLOAD_URL="https://github.com/cirruslabs/orchard/releases/latest/download/orchard-${OS}-${ARCH}"
        
        if curl -fsSL "$ORCHARD_DOWNLOAD_URL" -o "$ORCHARD_BIN"; then
            chmod +x "$ORCHARD_BIN"
            echo "orchard downloaded successfully."
        else
            echo "WARNING: Failed to download orchard CLI. VM management features may be limited."
            # Create a dummy script that shows a helpful error
            cat > "$ORCHARD_BIN" << 'EOF'
#!/bin/bash
echo "ERROR: Orchard CLI not available."
echo "VM management requires Orchard to be installed."
echo "Please install manually from: https://github.com/cirruslabs/orchard"
exit 1
EOF
            chmod +x "$ORCHARD_BIN"
        fi
    else
        echo "orchard already exists."
    fi
else
    echo "Tart/Orchard installation skipped (macOS only features)."
    # Create dummy binaries for non-macOS systems
    for tool in "$TART_BIN" "$ORCHARD_BIN"; do
        if [ ! -f "$tool" ]; then
            cat > "$tool" << 'EOF'
#!/bin/bash
echo "ERROR: This tool is only available on macOS."
exit 1
EOF
            chmod +x "$tool"
        fi
    done
fi

# Verify tool versions
echo ""
echo "Tool versions:"
echo -n "kubectl: "
$KUBECTL_BIN version --client 2>/dev/null | grep "Client Version" | awk '{print $3}' || echo "Error checking version"
echo -n "helm: "
$HELM_BIN version --short 2>/dev/null || echo "Error checking version"
echo -n "kind: "
$KIND_BIN version 2>/dev/null || echo "Error checking version"

if [[ "$OS" == "darwin" ]]; then
    echo -n "tart: "
    $TART_BIN --version 2>/dev/null || echo "Not available"
    echo -n "orchard: "
    $ORCHARD_BIN --version 2>/dev/null || echo "Not available"
fi

echo ""
echo "All tools are ready."