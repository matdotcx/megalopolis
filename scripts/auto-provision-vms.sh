#!/bin/bash
set -eo pipefail

# Automated VM provisioning for high-resource systems (128GB RAM)
# This script intelligently provisions VMs based on available resources

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# VM Configuration mappings (name:config pairs)
VM_CONFIGS="
dev-primary:macos-dev-pro.yaml
dev-secondary:macos-dev-pro.yaml
ci-worker-1:macos-ci-farm.yaml
ci-worker-2:macos-ci-farm.yaml
ci-worker-3:macos-ci-farm.yaml
simulator-farm:macos-simulator-farm.yaml
"

# Resource limits for 128GB system
MAX_TOTAL_VM_MEMORY=100000  # 100GB max for VMs (leaving 28GB for host)
MAX_VMS=8                   # Maximum number of VMs
MIN_HOST_MEMORY=16000       # 16GB minimum for host

# Get current system memory usage
get_system_memory_usage() {
    # Get total system memory in GB
    local total_memory_bytes
    total_memory_bytes=$(sysctl -n hw.memsize)
    local total_memory_gb=$((total_memory_bytes / 1024 / 1024 / 1024))
    
    # Calculate used memory (simplified - would need more accurate calculation in production)
    local used_memory_gb
    used_memory_gb=$(vm_stat | awk '
        /Pages free/ {free = $3}
        /Pages active/ {active = $3} 
        /Pages inactive/ {inactive = $3}
        /Pages speculative/ {spec = $3}
        /Pages wired down/ {wired = $4}
        END {
            if (free && active && inactive && spec && wired) {
                used_pages = active + inactive + spec + wired
                used_gb = (used_pages * 4096) / (1024 * 1024 * 1024)
                print int(used_gb)
            } else {
                print 32  # fallback estimate
            }
        }'
    )
    
    echo "$total_memory_gb $used_memory_gb"
}

# Calculate VM memory usage
get_vm_memory_usage() {
    local total_vm_memory=0
    
    if command -v ./tart-binary >/dev/null 2>&1; then
        # This is a simplified calculation - in production you'd query actual VM memory usage
        local vm_count
        vm_count=$(./tart-binary list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        
        # Estimate based on our VM configurations (average 10GB per VM)
        total_vm_memory=$((vm_count * 10))
    fi
    
    echo "$total_vm_memory"
}

# Check if we can provision a new VM
can_provision_vm() {
    local vm_memory="$1"  # Memory required for new VM in GB
    
    read -r total_memory used_memory <<< "$(get_system_memory_usage)"
    local vm_memory_usage
    vm_memory_usage=$(get_vm_memory_usage)
    
    local available_memory=$((total_memory - used_memory - vm_memory_usage))
    local projected_usage=$((used_memory + vm_memory_usage + vm_memory))
    
    log_info "Memory analysis:"
    log_info "  Total system memory: ${total_memory}GB"
    log_info "  Currently used: ${used_memory}GB"
    log_info "  VM memory usage: ${vm_memory_usage}GB"
    log_info "  Available: ${available_memory}GB"
    log_info "  Required for new VM: ${vm_memory}GB"
    
    # Check if we have enough memory
    if [ "$available_memory" -ge "$((vm_memory + MIN_HOST_MEMORY))" ]; then
        return 0
    else
        log_warn "Insufficient memory for VM requiring ${vm_memory}GB"
        return 1
    fi
}

# Get VM memory requirement from config
get_vm_memory_requirement() {
    local config_file="$1"
    
    # Simple mapping based on known configs
    case "$config_file" in
        "macos-dev-pro.yaml") echo 16 ;;
        "macos-ci-farm.yaml") echo 8 ;;
        "macos-simulator-farm.yaml") echo 12 ;;
        *) echo 8 ;;  # Default fallback
    esac
}

# Provision a single VM
provision_vm() {
    local vm_name="$1"
    local config_file="$2"
    
    log_step "Provisioning $vm_name with $config_file"
    
    # Check if VM already exists
    if ./tart-binary list 2>/dev/null | grep -q "^$vm_name"; then
        log_warn "$vm_name already exists, skipping"
        return 0
    fi
    
    # Check resource availability
    local required_memory
    required_memory=$(get_vm_memory_requirement "$config_file")
    
    if ! can_provision_vm "$required_memory"; then
        log_error "Cannot provision $vm_name (requires ${required_memory}GB)"
        return 1
    fi
    
    # Create the VM
    if ./scripts/setup-vms.sh create "$vm_name" "$config_file"; then
        log_info "✅ $vm_name created successfully"
        
        # Wait for VM to initialize
        log_info "⏳ Waiting for $vm_name to initialize..."
        sleep 30
        
        # Start the VM
        if ./scripts/setup-vms.sh start "$vm_name"; then
            log_info "🟢 $vm_name is running"
            return 0
        else
            log_warn "VM created but failed to start"
            return 1
        fi
    else
        log_error "❌ Failed to create $vm_name"
        return 1
    fi
}

# Main provisioning logic
main() {
    log_info "🚀 Starting automated VM provisioning for high-resource system"
    log_info "System specs: 128GB RAM, multiple CPU cores"
    echo ""
    
    # Check prerequisites
    if ! command -v ./tart-binary >/dev/null 2>&1; then
        log_error "Tart binary not available. Please run 'make ensure-tools' first."
        exit 1
    fi
    
    # Get current VM count
    local current_vms
    current_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    log_info "Current VMs: $current_vms"
    
    if [ "$current_vms" -ge "$MAX_VMS" ]; then
        log_warn "Maximum VM limit reached ($MAX_VMS)"
        log_info "Use 'make scale-down' to remove idle VMs if needed"
        exit 0
    fi
    
    # Provision VMs in priority order
    local provisioned=0
    local failed=0
    
    echo "$VM_CONFIGS" | grep -v "^$" | while IFS=: read -r vm_name config_file; do
        
        echo ""
        log_step "Processing $vm_name..."
        
        if provision_vm "$vm_name" "$config_file"; then
            provisioned=$((provisioned + 1))
        else
            failed=$((failed + 1))
        fi
        
        # Check if we've hit limits
        current_vms=$((current_vms + 1))
        if [ "$current_vms" -ge "$MAX_VMS" ]; then
            log_warn "VM limit reached, stopping provisioning"
            break
        fi
        
        # Brief pause between provisions
        sleep 5
    done
    
    echo ""
    log_info "🎉 VM provisioning completed!"
    log_info "Provisioned: $provisioned VMs"
    if [ "$failed" -gt 0 ]; then
        log_warn "Failed: $failed VMs"
    fi
    
    echo ""
    log_step "Current VM status:"
    ./scripts/setup-vms.sh list || echo "No VMs found"
    
    echo ""
    log_info "Next steps:"
    log_info "  make status              - Check overall system status"
    log_info "  make vm-health           - Monitor VM health"
    log_info "  make comprehensive-status - Detailed dashboard"
}

# Handle command line arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be provisioned without doing it"
        echo ""
        echo "This script automatically provisions VMs based on available system resources."
        echo "Designed for high-resource systems (128GB+ RAM)."
        exit 0
        ;;
    "--dry-run")
        log_info "DRY RUN MODE - No VMs will be created"
        echo ""
        log_info "Would provision the following VMs:"
        echo "$VM_CONFIGS" | grep -v "^$" | while IFS=: read -r vm_name config_file; do
            required_memory=$(get_vm_memory_requirement "$config_file")
            echo "  - $vm_name (${required_memory}GB RAM) using $config_file"
        done
        exit 0
        ;;
    "")
        # Default action
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac