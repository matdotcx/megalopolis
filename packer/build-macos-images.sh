#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== macOS Image Builder with Packer ===${NC}"
echo "This script builds custom macOS images for Tart using Packer"
echo ""

# Check if packer is installed
if ! command -v packer &> /dev/null; then
    echo -e "${YELLOW}Packer not found. Installing via Homebrew...${NC}"
    brew install packer
fi

# Create packer directory structure
mkdir -p "${SCRIPT_DIR}/builds"
mkdir -p "${SCRIPT_DIR}/templates"

# Create base macOS Packer template
cat > "${SCRIPT_DIR}/templates/macos-dev.pkr.hcl" << 'EOF'
packer {
  required_plugins {
    tart = {
      version = ">= 1.0.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "macos_version" {
  type    = string
  default = "sequoia"
}

variable "vm_name" {
  type    = string
  default = "macos-dev-custom"
}

source "tart-cli" "macos-dev" {
  # Use the base image from Cirrus Labs
  from_base_image = "ghcr.io/cirruslabs/macos-sequoia-base:latest"
  vm_name         = var.vm_name
  cpu_count       = 4
  memory_gb       = 6
  disk_size_gb    = 60
  ssh_username    = "admin"
  ssh_password    = "admin"
  
  # Hardware acceleration
  enable_vnc      = true
  enable_hardware_acceleration = true
}

build {
  sources = ["source.tart-cli.macos-dev"]
  
  # Install development tools
  provisioner "shell" {
    inline = [
      "echo 'Setting up development environment...'",
      "# Wait for system to settle",
      "sleep 10",
      
      "# Install Xcode Command Line Tools",
      "touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress",
      "softwareupdate -i $(softwareupdate -l | grep -E 'Command Line Tools' | tail -1 | awk -F'*' '{print $2}' | sed 's/^ *//')",
      "rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress",
      
      "# Install Homebrew",
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" < /dev/null",
      
      "# Add Homebrew to PATH",
      "echo 'eval \"$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile",
      "eval \"$(/opt/homebrew/bin/brew shellenv)\"",
      
      "# Install common development tools",
      "/opt/homebrew/bin/brew install git node python3 wget jq",
      
      "# Create development directories",
      "mkdir -p ~/Developer ~/Projects",
      
      "echo 'Development environment setup complete!'"
    ]
    
    execute_command = "echo 'admin' | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
  }
  
  # Configure SSH for easier access
  provisioner "shell" {
    inline = [
      "# Enable SSH",
      "sudo systemsetup -setremotelogin on",
      
      "# Configure SSH to allow password authentication",
      "sudo sed -i '' 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "sudo sed -i '' 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      
      "# Restart SSH",
      "sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist",
      "sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist"
    ]
  }
}
EOF

# Create CI image template
cat > "${SCRIPT_DIR}/templates/macos-ci.pkr.hcl" << 'EOF'
packer {
  required_plugins {
    tart = {
      version = ">= 1.0.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

variable "vm_name" {
  type    = string
  default = "macos-ci-custom"
}

source "tart-cli" "macos-ci" {
  from_base_image = "ghcr.io/cirruslabs/macos-sequoia-base:latest"
  vm_name         = var.vm_name
  cpu_count       = 2
  memory_gb       = 4
  disk_size_gb    = 40
  ssh_username    = "admin"
  ssh_password    = "admin"
  
  # CI VMs are headless
  enable_vnc      = false
  enable_hardware_acceleration = true
}

build {
  sources = ["source.tart-cli.macos-ci"]
  
  provisioner "shell" {
    inline = [
      "echo 'Setting up CI environment...'",
      "sleep 10",
      
      "# Install Xcode Command Line Tools",
      "touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress",
      "softwareupdate -i $(softwareupdate -l | grep -E 'Command Line Tools' | tail -1 | awk -F'*' '{print $2}' | sed 's/^ *//')",
      "rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress",
      
      "# Install Homebrew",
      "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" < /dev/null",
      "eval \"$(/opt/homebrew/bin/brew shellenv)\"",
      
      "# Install CI tools",
      "/opt/homebrew/bin/brew install git fastlane xcbeautify",
      
      "# Configure auto-login for CI",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser admin",
      
      "echo 'CI environment setup complete!'"
    ]
    
    execute_command = "echo 'admin' | sudo -S bash -c '{{ .Vars }} {{ .Path }}'"
  }
}
EOF

# Function to build an image
build_image() {
    local template=$1
    local vm_name=$2
    
    echo -e "${GREEN}Building ${vm_name} from ${template}...${NC}"
    
    cd "${SCRIPT_DIR}"
    
    if packer build -var "vm_name=${vm_name}" "templates/${template}"; then
        echo -e "${GREEN}✅ Successfully built ${vm_name}${NC}"
        
        # List the new VM
        "${PROJECT_ROOT}/tart-binary" list | grep "${vm_name}" || true
    else
        echo -e "${RED}❌ Failed to build ${vm_name}${NC}"
        return 1
    fi
}

# Main menu
echo "What would you like to build?"
echo "1) macos-dev - Development environment"
echo "2) macos-ci - CI/build environment"
echo "3) Both images"
echo "4) Exit"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        build_image "macos-dev.pkr.hcl" "macos-dev"
        ;;
    2)
        build_image "macos-ci.pkr.hcl" "macos-ci"
        ;;
    3)
        build_image "macos-dev.pkr.hcl" "macos-dev"
        build_image "macos-ci.pkr.hcl" "macos-ci"
        ;;
    4)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}Build process complete!${NC}"
echo "Your custom images are now available in Tart."
echo "Run '${PROJECT_ROOT}/tart-binary list' to see all VMs."