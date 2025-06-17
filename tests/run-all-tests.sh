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

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
START_TIME=$(date +%s)

echo -e "${BLUE}=== Megalopolis Comprehensive Test Suite ===${NC}"
echo "Starting automated testing of the entire infrastructure..."
echo "Date: $(date)"
echo ""

# Function to run a test
run_test() {
    local test_name=$1
    local test_script=$2
    
    echo -e "${YELLOW}Running: ${test_name}${NC}"
    echo "----------------------------------------"
    
    ((TOTAL_TESTS++))
    
    if [ -f "${test_script}" ]; then
        if bash "${test_script}"; then
            echo -e "${GREEN}✅ ${test_name} PASSED${NC}"
            ((PASSED_TESTS++))
        else
            echo -e "${RED}❌ ${test_name} FAILED${NC}"
            ((FAILED_TESTS++))
        fi
    else
        echo -e "${RED}❌ Test script not found: ${test_script}${NC}"
        ((FAILED_TESTS++))
    fi
    
    echo ""
}

# Pre-flight checks
echo -e "${BLUE}=== Pre-flight Checks ===${NC}"

# Check if we're in the right directory
if [ ! -f "${PROJECT_ROOT}/Makefile" ]; then
    echo -e "${RED}Error: Not in megalopolis project root${NC}"
    exit 1
fi

# Check if tools exist
check_tool() {
    local tool=$1
    local path=$2
    if [ -f "${path}" ]; then
        echo -e "  ✅ ${tool} found"
    else
        echo -e "  ❌ ${tool} not found at ${path}"
        return 1
    fi
}

echo "Checking required tools..."
check_tool "kubectl" "${PROJECT_ROOT}/kubectl"
check_tool "tart" "${PROJECT_ROOT}/tart-binary"
check_tool "kind" "${PROJECT_ROOT}/kind-binary"

echo ""

# Run platform compatibility tests first
run_test "Platform Compatibility" "${SCRIPT_DIR}/test-platform-compatibility.sh"

# Run infrastructure state test
run_test "Infrastructure State Check" "${SCRIPT_DIR}/test-infrastructure-state.sh"

# Run Kubernetes tests
run_test "Kubernetes Services" "${SCRIPT_DIR}/test-kubernetes-services.sh"

# Run VM operator tests
run_test "VM Operator" "${SCRIPT_DIR}/test-vm-operator.sh"

# Run VM readiness tests
run_test "VM Readiness" "${SCRIPT_DIR}/test-vm-readiness.sh"

# Run VM connectivity tests
run_test "VM Connectivity" "${SCRIPT_DIR}/test-vm-connectivity.sh"

# Run end-to-end tests
run_test "End-to-End Validation" "${SCRIPT_DIR}/test-e2e-validation.sh"

# Calculate runtime
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Generate test report
echo -e "${BLUE}=== Test Report ===${NC}"
echo "Test execution completed in ${DURATION} seconds"
echo ""
echo "Total Tests Run: ${TOTAL_TESTS}"
echo -e "Passed: ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed: ${RED}${FAILED_TESTS}${NC}"
echo ""

# Generate summary report file
REPORT_FILE="${SCRIPT_DIR}/test-report-$(date +%Y%m%d-%H%M%S).txt"
{
    echo "Megalopolis Test Report"
    echo "======================="
    echo "Date: $(date)"
    echo "Duration: ${DURATION} seconds"
    echo ""
    echo "Test Results:"
    echo "- Total Tests: ${TOTAL_TESTS}"
    echo "- Passed: ${PASSED_TESTS}"
    echo "- Failed: ${FAILED_TESTS}"
    echo ""
    echo "Infrastructure Summary:"
    echo "- Kubernetes Cluster: $(${PROJECT_ROOT}/kubectl cluster-info &>/dev/null && echo "Running" || echo "Not Available")"
    echo "- VMs Running: $(${PROJECT_ROOT}/tart-binary list 2>/dev/null | grep -c "running" || echo "0")"
    echo ""
} > "${REPORT_FILE}"

echo "Detailed report saved to: ${REPORT_FILE}"
echo ""

# Exit with appropriate code
if [ ${FAILED_TESTS} -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed! The infrastructure is fully operational.${NC}"
    exit 0
else
    echo -e "${RED}❌ ${FAILED_TESTS} tests failed. Please review the output above.${NC}"
    exit 1
fi