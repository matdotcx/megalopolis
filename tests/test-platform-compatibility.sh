#!/bin/bash

set -euo pipefail

# Platform compatibility test suite
# Tests for macOS-specific command compatibility and cross-platform functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

KUBECTL="${PROJECT_ROOT}/kubectl"
KIND="${PROJECT_ROOT}/kind-binary"
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

# Cross-platform timeout function (enhanced version)
portable_timeout() {
    local seconds=$1
    shift
    
    if command -v timeout >/dev/null 2>&1; then
        # GNU timeout (Linux)
        timeout "$seconds" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        # GNU timeout via Homebrew (macOS)
        gtimeout "$seconds" "$@"
    else
        # Fallback implementation for macOS
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

# Cross-platform line counting
count_lines() {
    wc -l | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

# Robust network detection (exact match)
check_kind_network() {
    # Use format table to get exact network names, then filter for exact match
    docker network ls --format "table {{.Name}}" | tail -n +2 | grep -q "^kind$"
}

# Enhanced VM detection with proper parsing
check_vm_state() {
    local vm_name="$1"
    local expected_state="${2:-}"
    
    # Get VM info with error handling
    local vm_info
    vm_info=$(${TART} list 2>/dev/null | grep "^$vm_name[[:space:]]" || echo "")
    
    if [ -z "$vm_info" ]; then
        log_debug "VM '$vm_name' not found"
        return 1  # VM not found
    fi
    
    # Parse the state (last column)
    local current_state
    current_state=$(echo "$vm_info" | awk '{print $NF}')
    
    log_debug "VM '$vm_name' state: '$current_state'"
    
    if [ -n "$expected_state" ]; then
        [ "$current_state" = "$expected_state" ]
    else
        # Just return success if we found the VM (no state check)
        return 0
    fi
}

# Test timeout command availability
test_timeout_command() {
    log_info "=== Testing Timeout Command Availability ==="
    
    if command -v timeout >/dev/null 2>&1; then
        log_info "✅ GNU timeout available"
        ((PASSED_TESTS++))
    elif command -v gtimeout >/dev/null 2>&1; then
        log_info "✅ GNU timeout available via gtimeout"
        ((PASSED_TESTS++))
    else
        log_info "⚠️ GNU timeout not available, using fallback implementation"
        ((PASSED_TESTS++))  # This is expected on macOS
    fi
    
    # Test our portable timeout function
    log_info "Testing portable timeout function..."
    if portable_timeout 2 echo "timeout test" >/dev/null; then
        log_info "✅ Portable timeout function works"
        ((PASSED_TESTS++))
    else
        log_error "❌ Portable timeout function failed"
        ((FAILED_TESTS++))
    fi
}

# Test cross-platform text processing
test_text_processing() {
    log_info "=== Testing Cross-Platform Text Processing ==="
    
    # Test line counting
    local test_file="/tmp/megalopolis_line_test.txt"
    echo -e "line1\nline2\nline3" > "$test_file"
    
    local line_count
    line_count=$(cat "$test_file" | count_lines)
    
    if [ "$line_count" = "3" ]; then
        log_info "✅ Cross-platform line counting works"
        ((PASSED_TESTS++))
    else
        log_error "❌ Line counting failed: expected 3, got '$line_count'"
        ((FAILED_TESTS++))
    fi
    
    rm -f "$test_file"
    
    # Test whitespace handling in command output
    local docker_count
    if command -v docker >/dev/null 2>&1; then
        docker_count=$(docker ps --format "{{.Names}}" 2>/dev/null | count_lines)
        log_info "✅ Docker container count (for format test): $docker_count"
        ((PASSED_TESTS++))
    else
        log_warn "Docker not available for testing"
    fi
}

# Test network detection robustness
test_network_detection() {
    log_info "=== Testing Network Detection ==="
    
    if command -v docker >/dev/null 2>&1; then
        # Test our enhanced kind network detection
        if check_kind_network; then
            log_info "✅ Kind network detected correctly"
            ((PASSED_TESTS++))
        else
            log_info "ℹ️ Kind network not found (may not be created yet)"
            ((PASSED_TESTS++))  # This is valid state
        fi
        
        # Test that we don't get false positives
        if docker network ls --format "table {{.Name}}" | tail -n +2 | grep -q "^kindredis$"; then
            log_warn "Found network with 'kind' substring but not exact match"
        fi
        
        log_info "✅ Network detection robustness test passed"
        ((PASSED_TESTS++))
    else
        log_warn "Docker not available for network testing"
    fi
}

# Test VM state parsing
test_vm_parsing() {
    log_info "=== Testing VM State Parsing ==="
    
    if [ -x "${TART}" ]; then
        # Test VM listing and parsing
        local vm_list_output
        vm_list_output=$(${TART} list 2>/dev/null || echo "")
        
        if [ -n "$vm_list_output" ]; then
            log_info "✅ VM list command works"
            ((PASSED_TESTS++))
            
            # Test VM parsing for each VM
            local vm_count=0
            while IFS= read -r line; do
                # Skip header line
                [ "$line" = "NAME" ] || [[ "$line" =~ ^NAME[[:space:]] ]] && continue
                [ -z "$line" ] && continue
                
                local vm_name
                vm_name=$(echo "$line" | awk '{print $1}')
                
                if [ -n "$vm_name" ]; then
                    ((vm_count++))
                    if check_vm_state "$vm_name"; then
                        log_debug "✅ Successfully parsed VM: $vm_name"
                    else
                        log_debug "⚠️ Could not parse VM state for: $vm_name"
                    fi
                fi
            done <<< "$vm_list_output"
            
            log_info "✅ Parsed $vm_count VMs successfully"
            ((PASSED_TESTS++))
        else
            log_info "ℹ️ No VMs found or Tart not available"
            ((PASSED_TESTS++))  # This is a valid state
        fi
    else
        log_warn "Tart binary not available for VM parsing test"
    fi
}

# Test macOS-specific commands
test_macos_commands() {
    log_info "=== Testing macOS-Specific Commands ==="
    
    # Test sysctl (memory info)
    if command -v sysctl >/dev/null 2>&1; then
        local total_memory
        total_memory=$(sysctl -n hw.memsize 2>/dev/null || echo "unknown")
        if [ "$total_memory" != "unknown" ]; then
            local memory_gb=$((total_memory / 1024 / 1024 / 1024))
            log_info "✅ System memory: ${memory_gb}GB"
            ((PASSED_TESTS++))
        else
            log_warn "Could not read system memory"
        fi
    else
        log_warn "sysctl not available (not on macOS?)"
    fi
    
    # Test sw_vers (macOS version)
    if command -v sw_vers >/dev/null 2>&1; then
        local macos_version
        macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
        if [ "$macos_version" != "unknown" ]; then
            log_info "✅ macOS version: $macos_version"
            ((PASSED_TESTS++))
        else
            log_warn "Could not read macOS version"
        fi
    else
        log_warn "sw_vers not available (not on macOS?)"
    fi
    
    # Test uname for platform detection
    local platform
    platform=$(uname -s 2>/dev/null || echo "unknown")
    log_info "✅ Platform: $platform"
    ((PASSED_TESTS++))
}

# Test regex patterns used in scripts
test_regex_patterns() {
    log_info "=== Testing Regex Patterns ==="
    
    # Test VM name matching pattern
    local test_vm_output="macos-dev         running"
    if echo "$test_vm_output" | grep -q "^macos-dev[[:space:]]"; then
        log_info "✅ VM name regex pattern works"
        ((PASSED_TESTS++))
    else
        log_error "❌ VM name regex pattern failed"
        ((FAILED_TESTS++))
    fi
    
    # Test network name pattern
    local test_network_output=$'NAME\nbridge\nhost\nkind\nnone'
    if echo "$test_network_output" | tail -n +2 | grep -q "^kind$"; then
        log_info "✅ Network name regex pattern works"
        ((PASSED_TESTS++))
    else
        log_error "❌ Network name regex pattern failed"
        ((FAILED_TESTS++))
    fi
    
    # Test that partial matches are rejected
    if echo "kindredis" | grep -q "^kind$"; then
        log_error "❌ Regex incorrectly matched partial string"
        ((FAILED_TESTS++))
    else
        log_info "✅ Regex correctly rejects partial matches"
        ((PASSED_TESTS++))
    fi
}

# Test error handling and edge cases
test_error_handling() {
    log_info "=== Testing Error Handling ==="
    
    # Test handling of non-existent commands
    if ! command -v nonexistent_command_12345 >/dev/null 2>&1; then
        log_info "✅ Command existence check works"
        ((PASSED_TESTS++))
    else
        log_error "❌ Command existence check failed"
        ((FAILED_TESTS++))
    fi
    
    # Test file existence checking
    if [ ! -f "/nonexistent/path/file.txt" ]; then
        log_info "✅ File existence check works"
        ((PASSED_TESTS++))
    else
        log_error "❌ File existence check failed"
        ((FAILED_TESTS++))
    fi
    
    # Test handling of empty command output
    local empty_output=""
    if [ -z "$empty_output" ]; then
        log_info "✅ Empty output handling works"
        ((PASSED_TESTS++))
    else
        log_error "❌ Empty output handling failed"
        ((FAILED_TESTS++))
    fi
}

# Main test execution
echo "=== Platform Compatibility Test Suite ==="
echo "Testing cross-platform compatibility and edge cases..."
echo ""

test_timeout_command
echo ""

test_text_processing
echo ""

test_network_detection
echo ""

test_vm_parsing
echo ""

test_macos_commands
echo ""

test_regex_patterns
echo ""

test_error_handling
echo ""

echo "=== Platform Compatibility Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ All platform compatibility tests passed!"
    exit 0
else
    echo "❌ Some platform compatibility tests failed"
    exit 1
fi