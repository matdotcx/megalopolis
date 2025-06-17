#!/bin/bash
set -euo pipefail

# VM readiness monitoring script
# Enhanced monitoring with boot progress indicators

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TART_BIN="${PROJECT_ROOT}/tart-binary"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Cross-platform timeout function 
portable_timeout() {
    local seconds=$1
    shift
    
    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$seconds" "$@"
    else
        # macOS fallback using background process + kill
        "$@" &
        local pid=$!
        (
            sleep "$seconds"
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
                sleep 1
                kill -9 "$pid" 2>/dev/null || true
            fi
        ) &
        local killer_pid=$!
        wait "$pid" 2>/dev/null
        local exit_code=$?
        kill "$killer_pid" 2>/dev/null || true
        return $exit_code
    fi
}

# Enhanced VM readiness check with detailed progress
wait_for_vm_ready() {
    local vm_name="$1"
    local max_wait="${2:-300}"  # 5 minutes default
    local start_time=$(date +%s)
    
    log_info "Waiting for VM $vm_name to be ready (max wait: ${max_wait}s)..."
    
    # Helper function to check timeout
    check_timeout() {
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [ $elapsed -ge $max_wait ]; then
            log_error "Timeout waiting for VM $vm_name (${elapsed}s elapsed)"
            return 1
        fi
        
        # Show progress indicator
        local progress=$((elapsed * 100 / max_wait))
        local bar_length=20
        local filled_length=$((progress * bar_length / 100))
        local bar=""
        
        for i in $(seq 1 $filled_length); do bar+="█"; done
        for i in $(seq $((filled_length + 1)) $bar_length); do bar+="░"; done
        
        printf "\r  Progress: [%s] %d%% (%ds/%ds)" "$bar" "$progress" "$elapsed" "$max_wait"
        return 0
    }
    
    # Phase 1: Wait for VM to show as running
    log_info "Phase 1: Waiting for VM to start..."
    while true; do
        check_timeout || return 1
        
        local vm_status
        vm_status=$("$TART_BIN" list 2>/dev/null | awk -v vm="$vm_name" '$2 == vm {print $NF}' || echo "not_found")
        
        case "$vm_status" in
            "running")
                echo ""  # New line after progress bar
                log_info "✅ VM is running"
                break
                ;;
            "stopped"|"not_found")
                sleep 5
                ;;
            *)
                sleep 5
                ;;
        esac
    done
    
    # Phase 2: Wait for IP assignment
    log_info "Phase 2: Waiting for IP assignment..."
    local vm_ip=""
    while [ -z "$vm_ip" ]; do
        check_timeout || return 1
        
        vm_ip=$("$TART_BIN" ip "$vm_name" 2>/dev/null || echo "")
        if [ -z "$vm_ip" ]; then
            sleep 5
        else
            echo ""  # New line after progress bar
            log_info "✅ VM has IP: $vm_ip"
        fi
    done
    
    # Phase 3: Wait for SSH port to be open
    log_info "Phase 3: Waiting for SSH service..."
    while true; do
        check_timeout || return 1
        
        if nc -z "$vm_ip" 22 2>/dev/null; then
            echo ""  # New line after progress bar
            log_info "✅ SSH port is open"
            break
        else
            sleep 10
        fi
    done
    
    # Phase 4: Wait for SSH authentication to work
    log_info "Phase 4: Waiting for SSH authentication..."
    while true; do
        check_timeout || return 1
        
        if portable_timeout 5 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "admin@$vm_ip" "echo ready" >/dev/null 2>&1; then
            echo ""  # New line after progress bar
            log_info "✅ SSH authentication successful"
            break
        else
            sleep 15
        fi
    done
    
    # Phase 5: Test system readiness
    log_info "Phase 5: Testing system readiness..."
    check_timeout || return 1
    
    if portable_timeout 10 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "admin@$vm_ip" "uname -a && sw_vers && echo 'System ready'" >/dev/null 2>&1; then
        log_info "✅ VM $vm_name is fully ready!"
        
        # Final boot time report
        local total_time=$(date +%s)
        local boot_time=$((total_time - start_time))
        log_info "Total boot time: ${boot_time} seconds"
        
        return 0
    else
        log_error "System readiness check failed"
        return 1
    fi
}

# Check VM health and connectivity
check_vm_health() {
    local vm_name="$1"
    
    log_info "🔍 Checking health of $vm_name..."
    
    # Check if VM is running
    local status
    status=$("$TART_BIN" list 2>/dev/null | awk -v vm="$vm_name" '$2 == vm {print $NF}' || echo "not_found")
    
    case "$status" in
        "running")
            log_info "✅ $vm_name is running"
            
            # Check SSH connectivity
            local vm_ip
            vm_ip=$("$TART_BIN" ip "$vm_name" 2>/dev/null || echo "")
            
            if [ -n "$vm_ip" ]; then
                if portable_timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
                    "admin@$vm_ip" "echo 'SSH OK'" >/dev/null 2>&1; then
                    log_info "✅ $vm_name SSH connectivity OK"
                    return 0
                else
                    log_warn "⚠️  $vm_name SSH connectivity failed"
                    return 1
                fi
            else
                log_warn "⚠️  $vm_name IP not available"
                return 1
            fi
            ;;
        "stopped")
            log_warn "🟡 $vm_name is stopped"
            return 2
            ;;
        "not_found")
            log_error "❌ $vm_name not found"
            return 3
            ;;
        *)
            log_warn "❓ $vm_name status unknown: $status"
            return 4
            ;;
    esac
}

# Get VM boot status with detailed information
get_vm_status() {
    local vm_name="$1"
    
    # Basic VM status
    local vm_status
    vm_status=$("$TART_BIN" list 2>/dev/null | awk -v vm="$vm_name" '$2 == vm {print $NF}' || echo "not_found")
    
    case "$vm_status" in
        "running")
            local vm_ip
            vm_ip=$("$TART_BIN" ip "$vm_name" 2>/dev/null || echo "")
            
            if [ -n "$vm_ip" ]; then
                # Check SSH availability
                if portable_timeout 3 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
                    "admin@$vm_ip" "echo ready" >/dev/null 2>&1; then
                    echo "ready"
                else
                    echo "ssh-pending"
                fi
            else
                echo "booting"
            fi
            ;;
        "stopped")
            echo "stopped"
            ;;
        "not_found")
            echo "not_found"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Main function
main() {
    case "${1:-help}" in
        "wait")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 wait <vm_name> [timeout_seconds]"
                exit 1
            fi
            wait_for_vm_ready "$2" "${3:-300}"
            ;;
        "check")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 check <vm_name>"
                exit 1
            fi
            check_vm_health "$2"
            ;;
        "status")
            if [[ $# -lt 2 ]]; then
                log_error "Usage: $0 status <vm_name>"
                exit 1
            fi
            status=$(get_vm_status "$2")
            echo "$status"
            ;;
        "monitor")
            # Monitor all VMs
            log_info "🏥 Starting VM health monitoring..."
            
            while IFS= read -r vm_name; do
                [ -z "$vm_name" ] && continue
                # Skip header line
                [[ "$vm_name" =~ ^NAME ]] && continue
                
                vm_name=$(echo "$vm_name" | awk '{print $1}')
                check_vm_health "$vm_name" || log_warn "⚠️  Health check failed for $vm_name"
            done < <("$TART_BIN" list 2>/dev/null)
            
            log_info "✅ Health monitoring completed"
            ;;
        "help"|"-h"|"--help")
            echo "VM Readiness Monitor"
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  wait <vm_name> [timeout]   Wait for VM to be fully ready"
            echo "  check <vm_name>            Check VM health and connectivity"
            echo "  status <vm_name>           Get detailed VM status"
            echo "  monitor                    Monitor all VMs"
            echo ""
            echo "Examples:"
            echo "  $0 wait macos-dev 300     # Wait up to 5 minutes for VM to be ready"
            echo "  $0 check macos-dev        # Check if VM is healthy"
            echo "  $0 status macos-dev       # Get VM status (ready|booting|ssh-pending|stopped|not_found)"
            echo "  $0 monitor                # Check health of all VMs"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Check if Tart is available
if [[ ! -f "$TART_BIN" ]] || [[ ! -x "$TART_BIN" ]]; then
    log_error "Tart binary not found or not executable: $TART_BIN"
    exit 1
fi

main "$@"