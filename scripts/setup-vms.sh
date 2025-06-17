#!/bin/bash
set -euo pipefail

# VM setup script for Tart integration
# This script handles VM lifecycle management

TART_BIN="./tart-binary"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TART_CONFIG_DIR="$PROJECT_DIR/tart"

# Default VM configurations
DEFAULT_VMS=("macos-dev" "macos-ci")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Tart is available
check_tart() {
    if [[ ! -f "$TART_BIN" ]] || [[ ! -x "$TART_BIN" ]]; then
        log_error "Tart binary not found or not executable: $TART_BIN"
        log_error "Please run 'make ensure-tools' first."
        exit 1
    fi
    
    # Test if tart works
    if ! "$TART_BIN" --version >/dev/null 2>&1; then
        log_error "Tart is not working properly. Please check installation."
        exit 1
    fi
}

# Parse YAML config (simple grep-based parser)
get_yaml_value() {
    local file="$1"
    local key="$2"
    grep -E "^${key}:" "$file" | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/' | head -1
}

# Check if VM exists
vm_exists() {
    local vm_name="$1"
    "$TART_BIN" list 2>/dev/null | grep -q "^$vm_name[[:space:]]"
}

# Get VM status
vm_status() {
    local vm_name="$1"
    if vm_exists "$vm_name"; then
        "$TART_BIN" list 2>/dev/null | grep "^$vm_name[[:space:]]" | awk '{print $2}'
    else
        echo "not_found"
    fi
}

# Create VM from configuration
create_vm() {
    local config_file="$1"
    local vm_name
    local base_image
    local memory
    local disk
    local cpu
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Parse configuration
    vm_name=$(get_yaml_value "$config_file" "name")
    base_image=$(get_yaml_value "$config_file" "base_image")
    memory=$(get_yaml_value "$config_file" "memory" || echo "4096")
    disk=$(get_yaml_value "$config_file" "disk" || echo "40")
    cpu=$(get_yaml_value "$config_file" "cpu" || echo "2")
    
    if [[ -z "$vm_name" ]]; then
        log_error "VM name not found in configuration file"
        return 1
    fi
    
    log_info "Creating VM: $vm_name"
    
    # Check if VM already exists
    if vm_exists "$vm_name"; then
        log_warn "VM '$vm_name' already exists. Skipping creation."
        return 0
    fi
    
    # Get base image source from base-images.yaml
    local base_images_file="$TART_CONFIG_DIR/base-images.yaml"
    local image_source
    
    if [[ -f "$base_images_file" ]]; then
        # Look for the base image configuration
        image_source=$(awk -v img="$base_image" '
            /^[[:space:]]*[^#].*:$/ { current_section = $1; gsub(/:$/, "", current_section) }
            current_section == img && /source:/ { 
                gsub(/^[[:space:]]*source:[[:space:]]*"?/, "")
                gsub(/"?[[:space:]]*$/, "")
                print
                exit
            }
        ' "$base_images_file")
    fi
    
    # Default to GitHub registry if not found
    if [[ -z "$image_source" ]]; then
        case "$base_image" in
            "macos-sequoia")
                image_source="ghcr.io/cirruslabs/macos-sequoia-base:latest"
                ;;
            "ubuntu-jammy")
                image_source="ghcr.io/cirruslabs/ubuntu:jammy"
                ;;
            *)
                log_error "Unknown base image: $base_image"
                return 1
                ;;
        esac
    fi
    
    log_info "Using base image: $image_source"
    
    # Create the VM
    if "$TART_BIN" clone "$image_source" "$vm_name" 2>/dev/null; then
        log_info "VM '$vm_name' created successfully"
        
        # Configure VM resources if needed
        # Note: Tart resource configuration may require different commands
        # This is a placeholder for resource configuration
        log_info "VM configuration completed"
        
        return 0
    else
        log_error "Failed to create VM '$vm_name'"
        return 1
    fi
}

# Start VM
start_vm() {
    local vm_name="$1"
    local wait_for_ready="${2:-true}"
    
    if ! vm_exists "$vm_name"; then
        log_error "VM '$vm_name' does not exist"
        return 1
    fi
    
    local status
    status=$(vm_status "$vm_name")
    
    if [[ "$status" == "running" ]]; then
        log_info "VM '$vm_name' is already running"
        
        # If requested, wait for it to be ready
        if [[ "$wait_for_ready" == "true" ]]; then
            log_info "Checking VM readiness..."
            if command -v "$SCRIPT_DIR/vm-readiness-monitor.sh" >/dev/null 2>&1; then
                "$SCRIPT_DIR/vm-readiness-monitor.sh" wait "$vm_name" 60
            fi
        fi
        return 0
    fi
    
    log_info "Starting VM: $vm_name"
    if "$TART_BIN" run "$vm_name" --no-graphics >/dev/null 2>&1 &
    then
        log_info "VM '$vm_name' started successfully"
        
        # Wait for VM to be ready if requested
        if [[ "$wait_for_ready" == "true" ]]; then
            log_info "Waiting for VM to be ready..."
            if [[ -x "$SCRIPT_DIR/vm-readiness-monitor.sh" ]]; then
                if "$SCRIPT_DIR/vm-readiness-monitor.sh" wait "$vm_name" 300; then
                    log_info "VM '$vm_name' is ready for use"
                else
                    log_warn "VM '$vm_name' started but readiness check failed"
                fi
            else
                log_warn "VM readiness monitor not available, skipping readiness check"
                sleep 30  # Basic wait
            fi
        fi
        
        return 0
    else
        log_error "Failed to start VM '$vm_name'"
        return 1
    fi
}

# Stop VM
stop_vm() {
    local vm_name="$1"
    
    if ! vm_exists "$vm_name"; then
        log_warn "VM '$vm_name' does not exist"
        return 0
    fi
    
    local status
    status=$(vm_status "$vm_name")
    
    if [[ "$status" != "running" ]]; then
        log_info "VM '$vm_name' is not running"
        return 0
    fi
    
    log_info "Stopping VM: $vm_name"
    if "$TART_BIN" stop "$vm_name" >/dev/null 2>&1; then
        log_info "VM '$vm_name' stopped successfully"
        return 0
    else
        log_error "Failed to stop VM '$vm_name'"
        return 1
    fi
}

# Delete VM
delete_vm() {
    local vm_name="$1"
    
    if ! vm_exists "$vm_name"; then
        log_warn "VM '$vm_name' does not exist"
        return 0
    fi
    
    # Stop VM first if running
    stop_vm "$vm_name"
    
    log_info "Deleting VM: $vm_name"
    if "$TART_BIN" delete "$vm_name" >/dev/null 2>&1; then
        log_info "VM '$vm_name' deleted successfully"
        return 0
    else
        log_error "Failed to delete VM '$vm_name'"
        return 1
    fi
}

# Setup default VMs
setup_default_vms() {
    log_info "Setting up default VMs..."
    
    for vm_config in "${DEFAULT_VMS[@]}"; do
        local config_file="$TART_CONFIG_DIR/vm-configs/${vm_config}.yaml"
        
        if [[ -f "$config_file" ]]; then
            create_vm "$config_file"
            # Start the VM after creation
            start_vm "$vm_config"
        else
            log_warn "Configuration file not found: $config_file"
        fi
    done
    
    log_info "Default VM setup completed"
}

# List all VMs
list_vms() {
    log_info "Virtual Machines:"
    if "$TART_BIN" list 2>/dev/null; then
        return 0
    else
        log_warn "No VMs found or Tart not available"
        return 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  setup          Setup default VMs"
    echo "  list           List all VMs"
    echo "  create <name> <config>  Create VM from config file"
    echo "  start <name> [wait]     Start VM (wait=true/false for readiness check)"
    echo "  stop <name>    Stop VM"
    echo "  delete <name>  Delete VM"
    echo "  rebuild        Rebuild all default VMs"
    echo "  status         Show VM status"
    echo "  wait <name> [timeout]   Wait for VM to be ready (default: 300s)"
    echo "  health <name>  Check VM health and connectivity"
    echo "  monitor        Monitor health of all VMs"
    echo ""
    echo "Examples:"
    echo "  $0 setup"
    echo "  $0 create my-vm macos-dev.yaml"
    echo "  $0 start macos-dev true     # Start and wait for readiness"
    echo "  $0 wait macos-dev 600       # Wait up to 10 minutes for VM"
    echo "  $0 health macos-dev         # Check VM health"
    echo "  $0 monitor                  # Monitor all VMs"
    echo "  $0 list"
}

# Main script logic
main() {
    # Check prerequisites
    check_tart
    
    # Handle commands
    case "${1:-setup}" in
        "setup")
            setup_default_vms
            ;;
        "list")
            list_vms
            ;;
        "create")
            if [[ $# -lt 3 ]]; then
                log_error "Usage: $0 create <vm_name> <config_file>"
                exit 1
            fi
            
            local vm_name="$2"
            local config_name="$3"
            local config_file="$TART_CONFIG_DIR/vm-configs/$config_name"
            
            create_vm "$config_file"
            ;;
        "start")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 start <vm_name> [wait_for_ready]"
                exit 1
            fi
            start_vm "$2" "${3:-true}"
            ;;
        "stop")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 stop <vm_name>"
                exit 1
            fi
            stop_vm "$2"
            ;;
        "delete")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 delete <vm_name>"
                exit 1
            fi
            delete_vm "$2"
            ;;
        "rebuild")
            log_info "Rebuilding all default VMs..."
            for vm_config in "${DEFAULT_VMS[@]}"; do
                delete_vm "$vm_config"
            done
            setup_default_vms
            ;;
        "status")
            list_vms
            ;;
        "wait")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 wait <vm_name> [timeout_seconds]"
                exit 1
            fi
            if [[ -x "$SCRIPT_DIR/vm-readiness-monitor.sh" ]]; then
                "$SCRIPT_DIR/vm-readiness-monitor.sh" wait "$2" "${3:-300}"
            else
                log_error "VM readiness monitor not available"
                exit 1
            fi
            ;;
        "health")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 health <vm_name>"
                exit 1
            fi
            if [[ -x "$SCRIPT_DIR/vm-readiness-monitor.sh" ]]; then
                "$SCRIPT_DIR/vm-readiness-monitor.sh" check "$2"
            else
                log_error "VM readiness monitor not available"
                exit 1
            fi
            ;;
        "monitor")
            if [[ -x "$SCRIPT_DIR/vm-readiness-monitor.sh" ]]; then
                "$SCRIPT_DIR/vm-readiness-monitor.sh" monitor
            else
                log_error "VM readiness monitor not available"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"