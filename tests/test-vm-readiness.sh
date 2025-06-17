#!/bin/bash

set -euo pipefail

# Enhanced VM readiness testing
# Tests VM boot sequence and SSH availability with proper timeouts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TART="${PROJECT_ROOT}/tart-binary"
FAILED_TESTS=0
PASSED_TESTS=0

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
    else
        # macOS fallback using background process + kill
        "$@" &
        local pid=$!
        (sleep "$seconds" && kill "$pid" 2>/dev/null) &
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
        log_debug "Elapsed time: ${elapsed}s / ${max_wait}s"
        return 0
    }
    
    # Phase 1: Wait for VM to show as running
    log_info "Phase 1: Waiting for VM to start..."
    while true; do
        check_timeout || return 1
        
        local vm_status
        vm_status=$(${TART} list 2>/dev/null | grep "^$vm_name" | awk '{print $2}' || echo "not_found")
        
        case "$vm_status" in
            "running")
                log_info "✅ VM is running"
                break
                ;;
            "stopped"|"not_found")
                log_warn "VM is $vm_status, waiting..."
                sleep 5
                ;;
            *)
                log_debug "VM status: $vm_status, waiting..."
                sleep 5
                ;;
        esac
    done
    
    # Phase 2: Wait for IP assignment
    log_info "Phase 2: Waiting for IP assignment..."
    local vm_ip=""
    while [ -z "$vm_ip" ]; do
        check_timeout || return 1
        
        vm_ip=$(${TART} ip "$vm_name" 2>/dev/null || echo "")
        if [ -z "$vm_ip" ]; then
            log_debug "IP not yet assigned, waiting..."
            sleep 5
        else
            log_info "✅ VM has IP: $vm_ip"
        fi
    done
    
    # Phase 3: Wait for SSH port to be open
    log_info "Phase 3: Waiting for SSH service..."
    while true; do
        check_timeout || return 1
        
        if nc -z "$vm_ip" 22 2>/dev/null; then
            log_info "✅ SSH port is open"
            break
        else
            log_debug "SSH port not yet open, waiting..."
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
            log_info "✅ SSH authentication successful"
            break
        else
            log_debug "SSH authentication not ready, waiting..."
            sleep 15
        fi
    done
    
    # Phase 5: Test system readiness
    log_info "Phase 5: Testing system readiness..."
    if portable_timeout 10 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "admin@$vm_ip" "uname -a && sw_vers && echo 'System ready'" >/dev/null 2>&1; then
        log_info "✅ VM $vm_name is fully ready!"
        return 0
    else
        log_error "System readiness check failed"
        return 1
    fi
}

# Test VM boot sequence
test_vm_boot_sequence() {
    local vm_name="$1"
    
    log_info "=== Testing VM Boot Sequence: $vm_name ==="
    
    # Check if VM exists
    if ! ${TART} list 2>/dev/null | grep -q "^$vm_name"; then
        log_warn "VM $vm_name does not exist, skipping boot test"
        return 0
    fi
    
    # Get current status
    local current_status
    current_status=$(${TART} list 2>/dev/null | grep "^$vm_name" | awk '{print $2}' || echo "unknown")
    
    log_info "Current VM status: $current_status"
    
    case "$current_status" in
        "running")
            log_info "VM already running, testing readiness..."
            if wait_for_vm_ready "$vm_name" 60; then
                ((PASSED_TESTS++))
                return 0
            else
                ((FAILED_TESTS++))
                return 1
            fi
            ;;
        "stopped")
            log_info "Starting VM for boot test..."
            ${TART} run "$vm_name" --no-graphics >/dev/null 2>&1 &
            
            if wait_for_vm_ready "$vm_name" 300; then
                ((PASSED_TESTS++))
                log_info "Boot sequence test passed for $vm_name"
                return 0
            else
                ((FAILED_TESTS++))
                log_error "Boot sequence test failed for $vm_name"
                return 1
            fi
            ;;
        *)
            log_error "VM in unexpected state: $current_status"
            ((FAILED_TESTS++))
            return 1
            ;;
    esac
}

# Test SSH resilience (multiple connection attempts)
test_ssh_resilience() {
    local vm_name="$1"
    local attempts="${2:-5}"
    
    log_info "=== Testing SSH Resilience: $vm_name ==="
    
    # Get VM IP
    local vm_ip
    vm_ip=$(${TART} ip "$vm_name" 2>/dev/null || echo "")
    
    if [ -z "$vm_ip" ]; then
        log_error "Cannot get IP for $vm_name"
        ((FAILED_TESTS++))
        return 1
    fi
    
    local successful_connections=0
    
    for i in $(seq 1 $attempts); do
        log_debug "SSH attempt $i/$attempts"
        
        if portable_timeout 10 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "admin@$vm_ip" "date && echo 'Connection $i successful'" >/dev/null 2>&1; then
            ((successful_connections++))
            log_debug "✅ Connection $i successful"
        else
            log_debug "❌ Connection $i failed"
        fi
        
        # Small delay between attempts
        [ $i -lt $attempts ] && sleep 2
    done
    
    local success_rate=$((successful_connections * 100 / attempts))
    log_info "SSH success rate: $successful_connections/$attempts ($success_rate%)"
    
    if [ $success_rate -ge 80 ]; then
        log_info "✅ SSH resilience test passed"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "❌ SSH resilience test failed (success rate below 80%)"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Main test execution
echo "=== VM Readiness Test Suite ==="
echo "Testing VM boot sequences and SSH availability..."
echo ""

# Test all running VMs
vm_list=$(${TART} list 2>/dev/null | tail -n +2 | awk '{print $1}' || true)

if [ -z "$vm_list" ]; then
    log_warn "No VMs found to test"
    exit 0
fi

log_info "Found VMs to test:"
echo "$vm_list" | while read -r vm; do
    [ -n "$vm" ] && log_info "  - $vm"
done
echo ""

# Test each VM
while IFS= read -r vm_name; do
    if [ -n "$vm_name" ]; then
        test_vm_boot_sequence "$vm_name"
        
        # Only test SSH resilience if VM is running
        local vm_status
        vm_status=$(${TART} list 2>/dev/null | grep "^$vm_name" | awk '{print $2}' || echo "unknown")
        if [ "$vm_status" = "running" ]; then
            test_ssh_resilience "$vm_name" 3
        fi
        
        echo ""
    fi
done <<< "$vm_list"

echo "=== VM Readiness Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ All VM readiness tests passed!"
    exit 0
else
    echo "❌ Some VM readiness tests failed"
    exit 1
fi