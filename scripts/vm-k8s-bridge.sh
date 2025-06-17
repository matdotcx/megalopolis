#!/bin/bash
set -euo pipefail

# VM Kubernetes Bridge
# This script provides a bridge between Kubernetes and Tart VM management
# It's designed to be called from within the cluster to manage VMs on the host

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TART_BIN="${PROJECT_ROOT}/tart-binary"
KUBECTL="${PROJECT_ROOT}/kubectl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" >&2
}

# HTTP response helpers
http_response() {
    local status_code="$1"
    local content_type="${2:-application/json}"
    local body="$3"
    
    echo "HTTP/1.1 $status_code"
    echo "Content-Type: $content_type"
    echo "Content-Length: ${#body}"
    echo "Access-Control-Allow-Origin: *"
    echo "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS"
    echo "Access-Control-Allow-Headers: Content-Type"
    echo ""
    echo "$body"
}

# Get all VMs as JSON
get_vms_json() {
    local vms_json="["
    local first=true
    
    while IFS= read -r line; do
        # Skip header and empty lines
        [[ "$line" =~ ^NAME ]] && continue
        [ -z "$line" ] && continue
        
        local vm_name vm_status vm_ip
        vm_name=$(echo "$line" | awk '{print $1}')
        vm_status=$(echo "$line" | awk '{print $2}')
        
        if [ "$vm_status" = "running" ]; then
            vm_ip=$("$TART_BIN" ip "$vm_name" 2>/dev/null || echo "")
        else
            vm_ip=""
        fi
        
        # Get detailed status if available
        local detailed_status="$vm_status"
        if [[ -x "${PROJECT_ROOT}/scripts/vm-readiness-monitor.sh" ]]; then
            detailed_status=$("${PROJECT_ROOT}/scripts/vm-readiness-monitor.sh" status "$vm_name" 2>/dev/null || echo "$vm_status")
        fi
        
        if [ "$first" = true ]; then
            first=false
        else
            vms_json+=","
        fi
        
        vms_json+="{\"name\":\"$vm_name\",\"status\":\"$vm_status\",\"detailedStatus\":\"$detailed_status\",\"ip\":\"$vm_ip\"}"
        
    done < <("$TART_BIN" list 2>/dev/null || echo "")
    
    vms_json+="]"
    echo "$vms_json"
}

# Get VM details as JSON
get_vm_json() {
    local vm_name="$1"
    
    # Check if VM exists
    if ! "$TART_BIN" list 2>/dev/null | grep -q "^$vm_name[[:space:]]"; then
        echo "{\"error\":\"VM not found\",\"name\":\"$vm_name\"}"
        return 1
    fi
    
    local vm_info vm_status vm_ip=""
    vm_info=$("$TART_BIN" list 2>/dev/null | grep "^$vm_name[[:space:]]" || echo "")
    vm_status=$(echo "$vm_info" | awk '{print $2}')
    
    if [ "$vm_status" = "running" ]; then
        vm_ip=$("$TART_BIN" ip "$vm_name" 2>/dev/null || echo "")
    fi
    
    # Get detailed status
    local detailed_status="$vm_status"
    if [[ -x "${PROJECT_ROOT}/scripts/vm-readiness-monitor.sh" ]]; then
        detailed_status=$("${PROJECT_ROOT}/scripts/vm-readiness-monitor.sh" status "$vm_name" 2>/dev/null || echo "$vm_status")
    fi
    
    echo "{\"name\":\"$vm_name\",\"status\":\"$vm_status\",\"detailedStatus\":\"$detailed_status\",\"ip\":\"$vm_ip\"}"
}

# Create VM from JSON spec
create_vm_from_json() {
    local vm_spec="$1"
    
    # Parse JSON (simple parsing for demo - in production would use jq)
    local vm_name base_image
    vm_name=$(echo "$vm_spec" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    base_image=$(echo "$vm_spec" | grep -o '"baseImage":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "$vm_name" ] || [ -z "$base_image" ]; then
        echo "{\"error\":\"Invalid VM specification - name and baseImage required\"}"
        return 1
    fi
    
    log_info "Creating VM: $vm_name with base image: $base_image"
    
    # Create VM using existing script
    if "${PROJECT_ROOT}/scripts/setup-vms.sh" create "$vm_name" "${base_image}.yaml" 2>/dev/null; then
        echo "{\"success\":true,\"name\":\"$vm_name\",\"status\":\"created\"}"
        return 0
    else
        echo "{\"error\":\"Failed to create VM\",\"name\":\"$vm_name\"}"
        return 1
    fi
}

# Start VM
start_vm() {
    local vm_name="$1"
    
    log_info "Starting VM: $vm_name"
    
    if "${PROJECT_ROOT}/scripts/setup-vms.sh" start "$vm_name" true 2>/dev/null; then
        echo "{\"success\":true,\"name\":\"$vm_name\",\"action\":\"started\"}"
        return 0
    else
        echo "{\"error\":\"Failed to start VM\",\"name\":\"$vm_name\"}"
        return 1
    fi
}

# Stop VM
stop_vm() {
    local vm_name="$1"
    
    log_info "Stopping VM: $vm_name"
    
    if "${PROJECT_ROOT}/scripts/setup-vms.sh" stop "$vm_name" 2>/dev/null; then
        echo "{\"success\":true,\"name\":\"$vm_name\",\"action\":\"stopped\"}"
        return 0
    else
        echo "{\"error\":\"Failed to stop VM\",\"name\":\"$vm_name\"}"
        return 1
    fi
}

# Delete VM
delete_vm() {
    local vm_name="$1"
    
    log_info "Deleting VM: $vm_name"
    
    if "${PROJECT_ROOT}/scripts/setup-vms.sh" delete "$vm_name" 2>/dev/null; then
        echo "{\"success\":true,\"name\":\"$vm_name\",\"action\":\"deleted\"}"
        return 0
    else
        echo "{\"error\":\"Failed to delete VM\",\"name\":\"$vm_name\"}"
        return 1
    fi
}

# Simple HTTP server
start_http_server() {
    local port="${1:-8080}"
    
    log_info "Starting VM API server on port $port"
    
    while true; do
        # Read HTTP request
        local request_line method path protocol
        read -r request_line
        method=$(echo "$request_line" | awk '{print $1}')
        path=$(echo "$request_line" | awk '{print $2}')
        protocol=$(echo "$request_line" | awk '{print $3}')
        
        # Skip headers
        while read -r line; do
            [ -z "$line" ] && break
        done
        
        log_debug "Request: $method $path"
        
        case "$method $path" in
            "GET /health")
                http_response "200 OK" "text/plain" "OK"
                ;;
            "GET /vms")
                local vms_json
                vms_json=$(get_vms_json)
                http_response "200 OK" "application/json" "$vms_json"
                ;;
            "GET /vms/"*)
                local vm_name
                vm_name=$(echo "$path" | sed 's|^/vms/||')
                local vm_json
                if vm_json=$(get_vm_json "$vm_name"); then
                    http_response "200 OK" "application/json" "$vm_json"
                else
                    http_response "404 Not Found" "application/json" "{\"error\":\"VM not found\"}"
                fi
                ;;
            "POST /vms/"*"/start")
                local vm_name
                vm_name=$(echo "$path" | sed 's|^/vms/||' | sed 's|/start$||')
                local result
                if result=$(start_vm "$vm_name"); then
                    http_response "200 OK" "application/json" "$result"
                else
                    http_response "500 Internal Server Error" "application/json" "$result"
                fi
                ;;
            "POST /vms/"*"/stop")
                local vm_name
                vm_name=$(echo "$path" | sed 's|^/vms/||' | sed 's|/stop$||')
                local result
                if result=$(stop_vm "$vm_name"); then
                    http_response "200 OK" "application/json" "$result"
                else
                    http_response "500 Internal Server Error" "application/json" "$result"
                fi
                ;;
            "DELETE /vms/"*)
                local vm_name
                vm_name=$(echo "$path" | sed 's|^/vms/||')
                local result
                if result=$(delete_vm "$vm_name"); then
                    http_response "200 OK" "application/json" "$result"
                else
                    http_response "500 Internal Server Error" "application/json" "$result"
                fi
                ;;
            "OPTIONS "*|"GET /"|"GET /api")
                local api_info="{\"name\":\"VM Kubernetes Bridge\",\"version\":\"1.0\",\"endpoints\":[\"/health\",\"/vms\",\"/vms/{name}\",\"/vms/{name}/start\",\"/vms/{name}/stop\"]}"
                http_response "200 OK" "application/json" "$api_info"
                ;;
            *)
                http_response "404 Not Found" "application/json" "{\"error\":\"Endpoint not found\"}"
                ;;
        esac
        
    done | nc -l -k -p "$port"
}

# Command-line interface
case "${1:-server}" in
    "server")
        start_http_server "${2:-8080}"
        ;;
    "list")
        get_vms_json | jq . 2>/dev/null || get_vms_json
        ;;
    "get")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 get <vm_name>"
            exit 1
        fi
        get_vm_json "$2" | jq . 2>/dev/null || get_vm_json "$2"
        ;;
    "start")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 start <vm_name>"
            exit 1
        fi
        start_vm "$2"
        ;;
    "stop")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 stop <vm_name>"
            exit 1
        fi
        stop_vm "$2"
        ;;
    "delete")
        if [ $# -lt 2 ]; then
            log_error "Usage: $0 delete <vm_name>"
            exit 1
        fi
        delete_vm "$2"
        ;;
    "help"|"-h"|"--help")
        echo "VM Kubernetes Bridge"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  server [port]       Start HTTP API server (default: port 8080)"
        echo "  list                List all VMs as JSON"
        echo "  get <vm_name>       Get VM details as JSON"
        echo "  start <vm_name>     Start VM"
        echo "  stop <vm_name>      Stop VM"
        echo "  delete <vm_name>    Delete VM"
        echo ""
        echo "API Endpoints:"
        echo "  GET /health         Health check"
        echo "  GET /vms            List all VMs"
        echo "  GET /vms/{name}     Get VM details"
        echo "  POST /vms/{name}/start  Start VM"
        echo "  POST /vms/{name}/stop   Stop VM"
        echo "  DELETE /vms/{name}  Delete VM"
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac