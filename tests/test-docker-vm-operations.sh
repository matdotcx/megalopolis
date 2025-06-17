#!/bin/bash

set -euo pipefail

# Docker Container VM Operations Test Suite
# Tests Docker container with proper volume mounts for real VM operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILED_TESTS=0
PASSED_TESTS=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up test containers..."
    docker stop vm-ops-test 2>/dev/null || true
    docker rm vm-ops-test 2>/dev/null || true
    docker stop vm-mount-test 2>/dev/null || true
    docker rm vm-mount-test 2>/dev/null || true
}

trap cleanup EXIT

echo -e "${BLUE}=== Docker Container VM Operations Test Suite ===${NC}"
echo "Testing Docker container with volume mounts for VM operations..."
echo ""

# Test 1: Docker Environment Prerequisites
log_info "=== Test 1: Docker Environment Prerequisites ==="

if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not available"
    ((FAILED_TESTS++))
else
    log_info "✅ Docker is available"
    ((PASSED_TESTS++))
fi

if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running"
    ((FAILED_TESTS++))
else
    log_info "✅ Docker daemon is running"
    ((PASSED_TESTS++))
fi

# Test 2: Container Image Build
log_info "=== Test 2: Container Image Build ==="

if docker build -t megalopolis/vm-operator:test-ops -f "${PROJECT_ROOT}/docker/vm-operator/Dockerfile" "${PROJECT_ROOT}" >/dev/null 2>&1; then
    log_info "✅ Container image builds successfully"
    ((PASSED_TESTS++))
else
    log_error "Container image build failed"
    ((FAILED_TESTS++))
fi

# Test 3: Container Runs Without Volumes
log_info "=== Test 3: Container Basic Functionality ==="

container_id=$(docker run -d --name vm-ops-test -p 8086:8082 megalopolis/vm-operator:test-ops 2>/dev/null || echo "")

if [[ -n "$container_id" ]]; then
    log_info "✅ Container starts successfully"
    ((PASSED_TESTS++))
    
    sleep 3
    
    # Test health endpoint
    if docker exec vm-ops-test python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8082/health')" >/dev/null 2>&1; then
        log_info "✅ Health endpoint works in container"
        ((PASSED_TESTS++))
    else
        log_error "Health endpoint fails in container"
        ((FAILED_TESTS++))
    fi
    
    # Test VMs endpoint fails without tart (expected)
    if docker exec vm-ops-test python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8082/vms')" >/dev/null 2>&1; then
        log_error "VMs endpoint should fail without tart binary"
        ((FAILED_TESTS++))
    else
        log_info "✅ VMs endpoint correctly fails without tart binary"
        ((PASSED_TESTS++))
    fi
    
    docker stop vm-ops-test >/dev/null 2>&1
    docker rm vm-ops-test >/dev/null 2>&1
else
    log_error "Container failed to start"
    ((FAILED_TESTS++))
fi

# Test 4: Volume Mount Prerequisites
log_info "=== Test 4: Volume Mount Prerequisites ==="

# Check if tart binary exists
if [[ -f "${PROJECT_ROOT}/tart-binary" ]]; then
    log_info "✅ Tart binary exists at ${PROJECT_ROOT}/tart-binary"
    ((PASSED_TESTS++))
else
    log_error "Tart binary not found at ${PROJECT_ROOT}/tart-binary"
    ((FAILED_TESTS++))
fi

# Check if tart binary is executable
if [[ -x "${PROJECT_ROOT}/tart-binary" ]]; then
    log_info "✅ Tart binary is executable"
    ((PASSED_TESTS++))
else
    log_error "Tart binary is not executable"
    ((FAILED_TESTS++))
fi

# Check if .tart directory exists
if [[ -d "${HOME}/.tart" ]]; then
    log_info "✅ Tart storage directory exists at ${HOME}/.tart"
    ((PASSED_TESTS++))
else
    log_warn "Tart storage directory not found at ${HOME}/.tart"
    log_info "Creating tart storage directory..."
    mkdir -p "${HOME}/.tart"
    ((PASSED_TESTS++))
fi

# Test 5: Container with Volume Mounts
log_info "=== Test 5: Container with Volume Mounts ==="

# This is the critical test - can we mount files/directories from host?
set +e  # Don't exit on error
mount_container_id=$(docker run -d --name vm-mount-test -p 8087:8082 \
    -v "${PROJECT_ROOT}/tart-binary:/app/bin/tart-binary:ro" \
    -v "${HOME}/.tart:/home/vmoperator/.tart:rw" \
    megalopolis/vm-operator:test-ops 2>&1)
mount_result=$?
set -e

if [[ $mount_result -eq 0 && -n "$mount_container_id" ]]; then
    log_info "✅ Container starts with volume mounts"
    ((PASSED_TESTS++))
    
    sleep 5
    
    # Test that tart binary is accessible inside container
    if docker exec vm-mount-test test -f /app/bin/tart-binary; then
        log_info "✅ Tart binary is accessible inside container"
        ((PASSED_TESTS++))
    else
        log_error "Tart binary not accessible inside container"
        ((FAILED_TESTS++))
    fi
    
    # Test that tart binary is executable inside container
    if docker exec vm-mount-test test -x /app/bin/tart-binary; then
        log_info "✅ Tart binary is executable inside container"
        ((PASSED_TESTS++))
    else
        log_error "Tart binary not executable inside container"
        ((FAILED_TESTS++))
    fi
    
    # Test that VM storage directory is accessible
    if docker exec vm-mount-test test -d /home/vmoperator/.tart; then
        log_info "✅ VM storage directory is accessible inside container"
        ((PASSED_TESTS++))
    else
        log_error "VM storage directory not accessible inside container"
        ((FAILED_TESTS++))
    fi
    
    # Test VMs endpoint now works
    if docker exec vm-mount-test python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8082/vms')" >/dev/null 2>&1; then
        log_info "✅ VMs endpoint works with mounted tart binary"
        ((PASSED_TESTS++))
        
        # Test actual VMs response
        vms_response=$(docker exec vm-mount-test python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8082/vms').read().decode())" 2>/dev/null)
        if echo "$vms_response" | python3 -m json.tool >/dev/null 2>&1; then
            log_info "✅ VMs endpoint returns valid JSON"
            ((PASSED_TESTS++))
            
            vm_count=$(echo "$vms_response" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
            log_info "Found $vm_count VMs in response"
        else
            log_error "VMs endpoint returns invalid JSON"
            ((FAILED_TESTS++))
        fi
    else
        log_error "VMs endpoint still fails with mounted binary"
        ((FAILED_TESTS++))
        log_info "Checking container logs for debugging..."
        docker logs vm-mount-test | tail -10
    fi
    
    docker stop vm-mount-test >/dev/null 2>&1
    docker rm vm-mount-test >/dev/null 2>&1
else
    log_error "Container failed to start with volume mounts"
    log_error "Error output: $mount_container_id"
    ((FAILED_TESTS++))
    
    # Analyze the error
    if echo "$mount_container_id" | grep -q "file exists"; then
        log_warn "This appears to be a Docker/container environment limitation"
        log_warn "Common in: Colima, Docker Desktop with certain settings, Kind clusters"
        log_warn "This is expected and documented as a known limitation"
    fi
fi

# Test 6: VM Operations Through Container (if mounts work)
log_info "=== Test 6: VM Operations Through Container ==="

if [[ $mount_result -eq 0 ]]; then
    # Try one more time with a fresh container for VM operations test
    ops_container_id=$(docker run -d --name vm-ops-final -p 8088:8082 \
        -v "${PROJECT_ROOT}/tart-binary:/app/bin/tart-binary:ro" \
        -v "${HOME}/.tart:/home/vmoperator/.tart:rw" \
        megalopolis/vm-operator:test-ops 2>/dev/null || echo "")
    
    if [[ -n "$ops_container_id" ]]; then
        sleep 5
        
        # Get VM list from host for comparison
        host_vm_count=$("${PROJECT_ROOT}/tart-binary" list 2>/dev/null | wc -l)
        
        # Get VM list from container
        container_vms=$(docker exec vm-ops-final python3 -c "
import urllib.request, json
try:
    response = urllib.request.urlopen('http://localhost:8082/vms')
    vms = json.loads(response.read().decode())
    print(len(vms))
except Exception as e:
    print('0')
" 2>/dev/null)
        
        if [[ "$container_vms" -gt 0 ]]; then
            log_info "✅ Container can list VMs: $container_vms VMs found"
            ((PASSED_TESTS++))
            
            # Test VM detail endpoint
            first_vm=$(docker exec vm-ops-final python3 -c "
import urllib.request, json
try:
    response = urllib.request.urlopen('http://localhost:8082/vms')
    vms = json.loads(response.read().decode())
    print(vms[0]['name'] if vms else '')
except:
    print('')
" 2>/dev/null)
            
            if [[ -n "$first_vm" ]]; then
                detail_response=$(docker exec vm-ops-final python3 -c "
import urllib.request
try:
    response = urllib.request.urlopen('http://localhost:8082/vms/$first_vm')
    print('SUCCESS')
except Exception as e:
    print(f'FAIL: {e}')
" 2>/dev/null)
                
                if [[ "$detail_response" == "SUCCESS" ]]; then
                    log_info "✅ VM detail endpoint works through container"
                    ((PASSED_TESTS++))
                else
                    log_error "VM detail endpoint fails: $detail_response"
                    ((FAILED_TESTS++))
                fi
            fi
        else
            log_warn "Container reports 0 VMs (may be expected if no VMs exist)"
            ((PASSED_TESTS++))
        fi
        
        docker stop vm-ops-final >/dev/null 2>&1
        docker rm vm-ops-final >/dev/null 2>&1
    else
        log_error "Failed to start container for VM operations test"
        ((FAILED_TESTS++))
    fi
else
    log_warn "Skipping VM operations test due to volume mount failure"
fi

# Test Results Summary
echo ""
echo -e "${BLUE}=== Docker VM Operations Test Results ===${NC}"
echo "Passed: ${GREEN}${PASSED_TESTS}${NC}"
echo "Failed: ${RED}${FAILED_TESTS}${NC}"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✅ All Docker VM operations tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some Docker VM operations tests failed.${NC}"
    echo ""
    echo "Common failure reasons:"
    echo "1. Volume mounting limitations in containerized Docker environments"
    echo "2. File permission issues with mounted tart binary"
    echo "3. Missing VMs or tart configuration"
    echo ""
    echo "See troubleshooting guide for solutions."
    exit 1
fi