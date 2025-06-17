#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TART="${PROJECT_ROOT}/tart-binary"
FAILED_TESTS=0
PASSED_TESTS=0

echo "=== VM Connectivity Test Suite ==="
echo "Testing VM availability and SSH access..."
echo ""

# Function to test VM
test_vm() {
    local vm_name=$1
    local expected_ssh_port=$2
    
    echo "Testing VM: ${vm_name}"
    
    # Check if VM exists
    if ! ${TART} list 2>/dev/null | grep -q "^${vm_name}[[:space:]]"; then
        echo "  ❌ VM ${vm_name} does not exist"
        ((FAILED_TESTS++))
        return 1
    fi
    
    # Check VM status
    local vm_status=$(${TART} list 2>/dev/null | grep "^${vm_name}[[:space:]]" | awk '{print $2}')
    if [ "${vm_status}" != "running" ]; then
        echo "  ❌ VM ${vm_name} is not running (status: ${vm_status})"
        ((FAILED_TESTS++))
        return 1
    fi
    
    echo "  ✅ VM exists and is running"
    ((PASSED_TESTS++))
    
    # Get VM IP
    local vm_ip=$(${TART} ip "${vm_name}" 2>/dev/null || echo "")
    if [ -z "${vm_ip}" ]; then
        echo "  ❌ Could not get IP for ${vm_name}"
        ((FAILED_TESTS++))
        return 1
    fi
    
    echo "  ✅ VM IP: ${vm_ip}"
    ((PASSED_TESTS++))
    
    # Test SSH connectivity
    echo "  Testing SSH connectivity..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p 22 "admin@${vm_ip}" "echo 'SSH test successful'" 2>/dev/null; then
        echo "  ✅ SSH connection successful"
        ((PASSED_TESTS++))
    else
        echo "  ❌ SSH connection failed"
        ((FAILED_TESTS++))
    fi
    
    # Test port forwarding (if applicable)
    if [ -n "${expected_ssh_port}" ] && [ "${expected_ssh_port}" != "22" ]; then
        echo "  Testing SSH port forwarding on port ${expected_ssh_port}..."
        if nc -z localhost "${expected_ssh_port}" 2>/dev/null; then
            echo "  ✅ Port ${expected_ssh_port} is accessible"
            ((PASSED_TESTS++))
        else
            echo "  ❌ Port ${expected_ssh_port} is not accessible"
            ((FAILED_TESTS++))
        fi
    fi
    
    # Test basic commands via SSH
    echo "  Testing basic commands..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -p 22 "admin@${vm_ip}" "uname -a && sw_vers" 2>/dev/null > /tmp/vm_info_${vm_name}.txt; then
        echo "  ✅ Basic commands executed successfully"
        echo "  VM Info:"
        cat /tmp/vm_info_${vm_name}.txt | sed 's/^/    /'
        ((PASSED_TESTS++))
        rm -f /tmp/vm_info_${vm_name}.txt
    else
        echo "  ❌ Failed to execute basic commands"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Test expected VMs
echo "Testing default VMs..."

# Check if any VMs exist first
vm_list=$(${TART} list 2>/dev/null | grep -v "^NAME" || true)
if [ -z "${vm_list}" ]; then
    echo "⚠️  No VMs found. VM creation may require authenticated image access."
    echo "   To create VMs, you need to:"
    echo "   1. Authenticate with GitHub Container Registry"
    echo "   2. Run 'make setup-vms' to create the default VMs"
    echo ""
    echo "Skipping VM connectivity tests."
    exit 0
fi

test_vm "macos-dev" "2222"
test_vm "macos-ci" "2223"

# Check for any additional VMs
echo "Checking for additional VMs..."
additional_vms=$(${TART} list 2>/dev/null | grep -v "^NAME" | grep -v "^macos-dev" | grep -v "^macos-ci" | awk '{print $1}' || true)
if [ -n "${additional_vms}" ]; then
    echo "Found additional VMs:"
    while IFS= read -r vm; do
        if [ -n "${vm}" ]; then
            echo "  - ${vm}"
            test_vm "${vm}" ""
        fi
    done <<< "${additional_vms}"
else
    echo "No additional VMs found"
fi

echo ""
echo "=== Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ All VM connectivity tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi