#!/bin/bash

set -euo pipefail

# Test suite for minimal VM API
# Tests each endpoint individually with real HTTP requests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED_TESTS=0
PASSED_TESTS=0
API_PORT=8082
API_URL="http://localhost:${API_PORT}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test helper functions
test_endpoint() {
    local endpoint="$1"
    local expected_status="$2"
    local test_name="$3"
    
    log_info "Testing: $test_name"
    
    # Make HTTP request and capture status code
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}${endpoint}" || echo "000")
    
    if [ "$status_code" = "$expected_status" ]; then
        log_info "✅ $test_name - Status: $status_code"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "❌ $test_name - Expected: $expected_status, Got: $status_code"
        ((FAILED_TESTS++))
        return 1
    fi
}

test_json_response() {
    local endpoint="$1"
    local test_name="$2"
    
    log_info "Testing: $test_name"
    
    # Make request and check if response is valid JSON
    local response
    response=$(curl -s "${API_URL}${endpoint}" || echo "")
    
    if echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
        log_info "✅ $test_name - Valid JSON response"
        echo "   Response: $response"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "❌ $test_name - Invalid JSON response"
        echo "   Response: $response"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Check if VM API is running
check_api_running() {
    log_info "Checking if VM API is running on port $API_PORT..."
    
    if curl -s --connect-timeout 2 "${API_URL}/health" >/dev/null 2>&1; then
        log_info "✅ VM API is running"
        return 0
    else
        log_error "❌ VM API is not running on port $API_PORT"
        log_error "Please start the VM API server first:"
        log_error "  python3 scripts/minimal-vm-api.py"
        exit 1
    fi
}

# Test /health endpoint
test_health_endpoint() {
    log_info "=== Testing /health Endpoint ==="
    
    # Test 1: Health endpoint returns 200
    test_endpoint "/health" "200" "Health endpoint responds with 200"
    
    # Test 2: Health endpoint returns JSON
    test_json_response "/health" "Health endpoint returns valid JSON"
    
    # Test 3: Health response contains expected fields
    local response
    response=$(curl -s "${API_URL}/health")
    
    if echo "$response" | grep -q '"status"' && echo "$response" | grep -q '"message"'; then
        log_info "✅ Health response contains expected fields"
        ((PASSED_TESTS++))
    else
        log_error "❌ Health response missing expected fields"
        log_error "   Expected: status and message fields"
        log_error "   Got: $response"
        ((FAILED_TESTS++))
    fi
}

# Main test execution
echo "=== Minimal VM API Test Suite ==="
echo "Testing minimal VM operator HTTP API..."
echo ""

check_api_running
test_health_endpoint

echo ""
echo "=== Test Summary ==="
echo "Passed: ${PASSED_TESTS}"
echo "Failed: ${FAILED_TESTS}"
echo ""

if [ ${FAILED_TESTS} -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi