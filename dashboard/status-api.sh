#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Tool paths
KUBECTL="${PROJECT_ROOT}/kubectl"
TART="${PROJECT_ROOT}/tart-binary"
KIND="${PROJECT_ROOT}/kind-binary"

# Function to check service status
check_service_status() {
    local service_name="$1"
    local check_command="$2"
    
    if eval "$check_command" &>/dev/null; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

# Function to check namespace pods
check_namespace_pods() {
    local namespace="$1"
    local pods=$(${KUBECTL} get pods -n "${namespace}" --no-headers 2>/dev/null | grep "Running" | wc -l | xargs)
    
    if [ "${pods}" -gt 0 ]; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

# Function to get VM count
get_vm_count() {
    local vm_list=$(${TART} list 2>/dev/null || echo "")
    local running_vms=0
    local total_vms=0
    
    if [ -n "${vm_list}" ]; then
        running_vms=$(echo "${vm_list}" | grep "running" | wc -l | xargs || echo "0")
        total_vms=$(echo "${vm_list}" | grep -v "^NAME" | grep -v "^$" | wc -l | xargs || echo "0")
    fi
    echo "${running_vms} running / ${total_vms} total"
}

# Function to get enhanced VM status
get_vm_detailed_status() {
    local vm_name="$1"
    
    # Check if VM readiness monitor is available
    if [[ -x "${PROJECT_ROOT}/scripts/vm-readiness-monitor.sh" ]]; then
        local detailed_status
        detailed_status=$("${PROJECT_ROOT}/scripts/vm-readiness-monitor.sh" status "$vm_name" 2>/dev/null || echo "unknown")
        echo "$detailed_status"
    else
        # Fallback to basic status
        if ${TART} list 2>/dev/null | grep -q "^${vm_name}[[:space:]].*running"; then
            echo "running"
        elif ${TART} list 2>/dev/null | grep -q "^${vm_name}[[:space:]]"; then
            echo "stopped"
        else
            echo "not_found"
        fi
    fi
}

# Generate JSON status
generate_status() {
    echo "{"
    echo '  "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",'
    echo '  "services": {'
    
    # Infrastructure
    docker_status=$(check_service_status "docker" "/opt/local/bin/docker info")
    echo '    "docker": {"status": "'${docker_status}'", "details": "Container runtime"},'
    
    kind_status=$(check_service_status "kind" "${KIND} get clusters | grep -q homelab")
    echo '    "kind": {"status": "'${kind_status}'", "details": "Kubernetes cluster"},'
    
    kubectl_status=$(check_service_status "kubectl" "${KUBECTL} version")
    echo '    "kubectl": {"status": "'${kubectl_status}'", "details": "Kubernetes client"},'
    
    tart_status=$(check_service_status "tart" "${TART} list")
    echo '    "tart": {"status": "'${tart_status}'", "details": "VM management"},'
    
    # Kubernetes Services
    if ${KUBECTL} get namespace argocd &>/dev/null; then
        argocd_status=$(check_namespace_pods "argocd")
        argocd_pods=$(${KUBECTL} get pods -n argocd --no-headers 2>/dev/null | grep "Running" | wc -l | xargs)
        echo '    "argocd": {"status": "'${argocd_status}'", "details": "'${argocd_pods}' pods running"},'
    else
        echo '    "argocd": {"status": "unhealthy", "details": "Namespace not found"},'
    fi
    
    # Core Kubernetes Services
    if ${KUBECTL} get namespace cert-manager &>/dev/null; then
        certmanager_status=$(check_namespace_pods "cert-manager")
        certmanager_pods=$(${KUBECTL} get pods -n cert-manager --no-headers 2>/dev/null | grep "Running" | wc -l | xargs)
        echo '    "cert-manager": {"status": "'${certmanager_status}'", "details": "'${certmanager_pods}' pods running"},'
    else
        echo '    "cert-manager": {"status": "unhealthy", "details": "Namespace not found"},'
    fi
    
    if ${KUBECTL} get namespace ingress-nginx &>/dev/null; then
        ingress_status=$(check_namespace_pods "ingress-nginx")
        ingress_pods=$(${KUBECTL} get pods -n ingress-nginx --no-headers 2>/dev/null | grep "Running" | wc -l | xargs)
        echo '    "ingress-nginx": {"status": "'${ingress_status}'", "details": "'${ingress_pods}' pods running"},'
    else
        echo '    "ingress-nginx": {"status": "unhealthy", "details": "Namespace not found"},'
    fi
    
    # Network - check for kind networks
    if command -v docker >/dev/null 2>&1; then
        if docker network ls 2>/dev/null | grep -q kind; then
            network_status="healthy"
        else
            network_status="unhealthy"
        fi
    elif [ -x "/opt/local/bin/docker" ]; then
        if /opt/local/bin/docker network ls 2>/dev/null | grep -q kind; then
            network_status="healthy"
        else
            network_status="unhealthy"
        fi
    else
        network_status="unhealthy"
    fi
    echo '    "network": {"status": "'${network_status}'", "details": "Docker networking"},'
    
    # Virtual Machines with enhanced status
    macos_dev_detailed=$(get_vm_detailed_status "macos-dev")
    case "$macos_dev_detailed" in
        "ready")
            macos_dev_status="healthy"
            macos_dev_details="Ready"
            ;;
        "ssh-pending")
            macos_dev_status="warning"
            macos_dev_details="SSH pending"
            ;;
        "booting")
            macos_dev_status="warning"
            macos_dev_details="Booting"
            ;;
        "running")
            macos_dev_status="warning"
            macos_dev_details="Running (status unknown)"
            ;;
        "stopped")
            macos_dev_status="warning"
            macos_dev_details="Stopped"
            ;;
        "not_found")
            macos_dev_status="unhealthy"
            macos_dev_details="Not found"
            ;;
        *)
            macos_dev_status="unhealthy"
            macos_dev_details="Unknown"
            ;;
    esac
    echo '    "macos-dev": {"status": "'${macos_dev_status}'", "details": "'${macos_dev_details}'"},'
    
    macos_ci_detailed=$(get_vm_detailed_status "macos-ci")
    case "$macos_ci_detailed" in
        "ready")
            macos_ci_status="healthy"
            macos_ci_details="Ready"
            ;;
        "ssh-pending")
            macos_ci_status="warning"
            macos_ci_details="SSH pending"
            ;;
        "booting")
            macos_ci_status="warning"
            macos_ci_details="Booting"
            ;;
        "running")
            macos_ci_status="warning"
            macos_ci_details="Running (status unknown)"
            ;;
        "stopped")
            macos_ci_status="warning"
            macos_ci_details="Stopped"
            ;;
        "not_found")
            macos_ci_status="unhealthy"
            macos_ci_details="Not found"
            ;;
        *)
            macos_ci_status="unhealthy"
            macos_ci_details="Unknown"
            ;;
    esac
    echo '    "macos-ci": {"status": "'${macos_ci_status}'", "details": "'${macos_ci_details}'"},'
    
    # Total VMs
    vm_count=$(get_vm_count)
    running_count=$(echo "${vm_count}" | cut -d' ' -f1)
    if [ "${running_count}" -gt 0 ]; then
        total_vms_status="healthy"
    elif [ "${running_count}" -eq 0 ] && ${TART} list 2>/dev/null | grep -v "^NAME" | grep -q "."; then
        total_vms_status="warning"
    else
        total_vms_status="unhealthy"
    fi
    echo '    "total-vms": {"status": "'${total_vms_status}'", "details": "'${vm_count}'"}'
    
    echo '  },'
    
    # Calculate summary
    healthy_count=0
    warning_count=0
    unhealthy_count=0
    
    # Count service statuses (this is a simplified count - in real implementation you'd parse the JSON)
    for status in "${docker_status}" "${kind_status}" "${kubectl_status}" "${tart_status}" "${argocd_status}" "${certmanager_status}" "${ingress_status}" "${network_status}" "${macos_dev_status}" "${macos_ci_status}" "${total_vms_status}"; do
        case "${status}" in
            "healthy") ((healthy_count++)) ;;
            "warning") ((warning_count++)) ;;
            "unhealthy") ((unhealthy_count++)) ;;
        esac
    done
    
    echo '  "summary": {'
    echo '    "healthy": '${healthy_count}','
    echo '    "warning": '${warning_count}','
    echo '    "unhealthy": '${unhealthy_count}
    echo '  }'
    echo "}"
}

# Generate the status
generate_status