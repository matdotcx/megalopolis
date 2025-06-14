#!/bin/bash
set -euo pipefail

# Comprehensive system status dashboard for Megalopolis
# Provides detailed view of Kubernetes cluster, VMs, and system resources

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Status icons
ICON_RUNNING="🟢"
ICON_STOPPED="🔴"
ICON_WARNING="🟡"
ICON_ERROR="❌"
ICON_OK="✅"
ICON_INFO="ℹ️"

# Helper functions
print_header() {
    echo -e "${CYAN}$1${NC}"
    printf '%.0s─' {1..80}
    echo ""
}

print_section() {
    echo ""
    echo -e "${BLUE}$1${NC}"
    printf '%.0s─' {1..80}
    echo ""
}

get_system_resources() {
    # Get total system memory in GB
    local total_memory_bytes
    total_memory_bytes=$(sysctl -n hw.memsize)
    local total_memory_gb=$((total_memory_bytes / 1024 / 1024 / 1024))
    
    # Get CPU count
    local cpu_count
    cpu_count=$(sysctl -n hw.ncpu)
    
    # Get load average
    local load_avg
    load_avg=$(uptime | awk -F'load averages:' '{print $2}' | xargs)
    
    # Get memory pressure (simplified)
    local memory_pressure
    memory_pressure=$(vm_stat | awk '
        /Pages free/ {free = $3}
        /Pages active/ {active = $3} 
        /Pages inactive/ {inactive = $3}
        /Pages speculative/ {spec = $3}
        /Pages wired down/ {wired = $4}
        END {
            if (free && active && inactive && spec && wired) {
                total_pages = free + active + inactive + spec + wired
                used_pages = active + spec + wired
                usage_percent = (used_pages * 100) / total_pages
                print int(usage_percent)
            } else {
                print "unknown"
            }
        }'
    )
    
    echo "$total_memory_gb|$cpu_count|$load_avg|$memory_pressure"
}

check_kubernetes_status() {
    if ./kubectl cluster-info &>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

get_kubernetes_stats() {
    local node_count pod_count running_pods pending_pods failed_pods
    
    node_count=$(./kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    pod_count=$(./kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    running_pods=$(./kubectl get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    pending_pods=$(./kubectl get pods -A --no-headers 2>/dev/null | grep -c "Pending" || echo 0)
    failed_pods=$(./kubectl get pods -A --no-headers 2>/dev/null | grep -c -E "(Failed|Error|CrashLoopBackOff)" || echo 0)
    
    echo "$node_count|$pod_count|$running_pods|$pending_pods|$failed_pods"
}

check_vm_status() {
    if command -v ./tart-binary >/dev/null 2>&1 && ./tart-binary list >/dev/null 2>&1; then
        local total_vms running_vms stopped_vms
        total_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        running_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | grep -c "running" || echo 0)
        stopped_vms=$(./tart-binary list 2>/dev/null | tail -n +2 | grep -c "stopped" || echo 0)
        
        echo "available|$total_vms|$running_vms|$stopped_vms"
    else
        echo "unavailable|0|0|0"
    fi
}

check_service_status() {
    local service_name="$1"
    local namespace="$2"
    local selector="$3"
    
    local pods_count running_count
    pods_count=$(./kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    running_count=$(./kubectl get pods -n "$namespace" -l "$selector" --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    
    if [ "$pods_count" -gt 0 ] && [ "$running_count" -eq "$pods_count" ]; then
        echo "running|$running_count/$pods_count"
    elif [ "$pods_count" -gt 0 ]; then
        echo "degraded|$running_count/$pods_count"
    else
        echo "stopped|0/0"
    fi
}

main() {
    clear
    
    print_header "🏠 MEGALOPOLIS HOMELAB STATUS DASHBOARD"
    echo "Last updated: $(date)"
    echo ""
    
    # System Resources
    print_section "💻 SYSTEM RESOURCES"
    
    IFS='|' read -r total_memory cpu_count load_avg memory_pressure <<< "$(get_system_resources)"
    
    echo "Host Configuration:"
    echo "  RAM: ${total_memory}GB total"
    echo "  CPU: ${cpu_count} cores"
    echo "  Load Average: ${load_avg}"
    
    if [ "$memory_pressure" != "unknown" ]; then
        if [ "$memory_pressure" -lt 70 ]; then
            echo -e "  Memory Usage: ${GREEN}${memory_pressure}%${NC} (healthy)"
        elif [ "$memory_pressure" -lt 85 ]; then
            echo -e "  Memory Usage: ${YELLOW}${memory_pressure}%${NC} (moderate)"
        else
            echo -e "  Memory Usage: ${RED}${memory_pressure}%${NC} (high)"
        fi
    else
        echo "  Memory Usage: Unknown"
    fi
    
    # Docker container resource usage
    echo ""
    echo "Docker Container Resources:"
    if docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -6; then
        :
    else
        echo "  Docker stats unavailable"
    fi
    
    # Kubernetes Cluster Status
    print_section "☸️  KUBERNETES CLUSTER"
    
    local k8s_status
    k8s_status=$(check_kubernetes_status)
    
    if [ "$k8s_status" = "running" ]; then
        echo -e "Status: ${ICON_RUNNING} Running"
        
        IFS='|' read -r node_count pod_count running_pods pending_pods failed_pods <<< "$(get_kubernetes_stats)"
        
        echo "Cluster Metrics:"
        echo "  Nodes: $node_count"
        echo "  Total Pods: $pod_count"
        echo -e "  Running: ${GREEN}$running_pods${NC}"
        
        if [ "$pending_pods" -gt 0 ]; then
            echo -e "  Pending: ${YELLOW}$pending_pods${NC}"
        fi
        
        if [ "$failed_pods" -gt 0 ]; then
            echo -e "  Failed: ${RED}$failed_pods${NC}"
        fi
        
        # Node details
        echo ""
        echo "Node Status:"
        ./kubectl get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[?(@.type=='Ready')].status,ROLES:.metadata.labels['node-role\.kubernetes\.io/control-plane'],AGE:.metadata.creationTimestamp" --no-headers 2>/dev/null | while read -r line; do
            node_name=$(echo "$line" | awk '{print $1}')
            node_status=$(echo "$line" | awk '{print $2}')
            node_role=$(echo "$line" | awk '{print $3}')
            
            if [ "$node_status" = "True" ]; then
                echo -e "  ${ICON_RUNNING} $node_name $([ "$node_role" != "<none>" ] && echo "(control-plane)" || echo "(worker)")"
            else
                echo -e "  ${ICON_ERROR} $node_name $([ "$node_role" != "<none>" ] && echo "(control-plane)" || echo "(worker)") - Not Ready"
            fi
        done
        
        # Resource usage if metrics available
        echo ""
        echo "Resource Usage:"
        if ./kubectl top nodes 2>/dev/null; then
            :
        else
            echo "  Metrics server not available"
            echo "  Install with: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
        fi
        
    else
        echo -e "Status: ${ICON_STOPPED} Not Running"
        echo "Run 'make init' to start the cluster"
    fi
    
    # Virtual Machines Status
    print_section "🖥️  VIRTUAL MACHINES"
    
    IFS='|' read -r vm_availability total_vms running_vms stopped_vms <<< "$(check_vm_status)"
    
    if [ "$vm_availability" = "available" ]; then
        echo "VM Infrastructure: ${ICON_OK} Available"
        echo "VM Summary:"
        echo "  Total VMs: $total_vms"
        echo -e "  Running: ${GREEN}$running_vms${NC}"
        echo -e "  Stopped: ${RED}$stopped_vms${NC}"
        
        if [ "$total_vms" -gt 0 ]; then
            echo ""
            echo "VM Details:"
            ./tart-binary list 2>/dev/null | tail -n +2 | while read -r line; do
                vm_name=$(echo "$line" | awk '{print $1}')
                vm_status=$(echo "$line" | awk '{print $2}')
                
                case "$vm_status" in
                    "running") 
                        status_icon="${ICON_RUNNING}"
                        # Try to get IP if available
                        vm_ip=$(./tart-binary ip "$vm_name" 2>/dev/null || echo "")
                        if [ -n "$vm_ip" ]; then
                            echo "  $status_icon $vm_name ($vm_status) - IP: $vm_ip"
                        else
                            echo "  $status_icon $vm_name ($vm_status)"
                        fi
                        ;;
                    "stopped") 
                        status_icon="${ICON_STOPPED}"
                        echo "  $status_icon $vm_name ($vm_status)"
                        ;;
                    *) 
                        status_icon="${ICON_WARNING}"
                        echo "  $status_icon $vm_name ($vm_status)"
                        ;;
                esac
            done
        fi
        
        # VM resource estimation
        if [ "$total_vms" -gt 0 ]; then
            echo ""
            echo "Estimated VM Resource Usage:"
            local estimated_vm_memory=$((running_vms * 10))  # Rough estimate
            echo "  Memory: ~${estimated_vm_memory}GB allocated to running VMs"
            echo "  Remaining capacity: ~$((100 - estimated_vm_memory))GB available for new VMs"
        fi
        
    else
        echo -e "VM Infrastructure: ${ICON_WARNING} Tart not available"
        echo "Install Tart: sudo port install tart"
    fi
    
    # Core Services Status
    print_section "🔧 CORE SERVICES"
    
    if [ "$k8s_status" = "running" ]; then
        # ArgoCD
        IFS='|' read -r argocd_status argocd_pods <<< "$(check_service_status "ArgoCD" "argocd" "app.kubernetes.io/name=argocd-server")"
        case "$argocd_status" in
            "running") echo -e "ArgoCD: ${ICON_RUNNING} Running ($argocd_pods pods)" ;;
            "degraded") echo -e "ArgoCD: ${ICON_WARNING} Degraded ($argocd_pods pods)" ;;
            *) echo -e "ArgoCD: ${ICON_STOPPED} Not Running" ;;
        esac
        
        # Orchard Controller
        IFS='|' read -r orchard_status orchard_pods <<< "$(check_service_status "Orchard" "orchard-system" "app=orchard-controller")"
        case "$orchard_status" in
            "running") echo -e "Orchard Controller: ${ICON_RUNNING} Running ($orchard_pods pods)" ;;
            "degraded") echo -e "Orchard Controller: ${ICON_WARNING} Degraded ($orchard_pods pods)" ;;
            *) echo -e "Orchard Controller: ${ICON_STOPPED} Not Running" ;;
        esac
        
        # Check if orchard namespace exists
        if ./kubectl get namespace orchard-system &>/dev/null; then
            echo "  Namespace: orchard-system exists"
            if [ "$orchard_status" = "running" ]; then
                echo "  Access: kubectl port-forward -n orchard-system svc/orchard-controller 8081:8080"
            fi
        else
            echo -e "  ${ICON_INFO} Orchard not deployed - run 'make bootstrap' to deploy"
        fi
        
    else
        echo "Services unavailable (cluster not running)"
    fi
    
    # Resource Recommendations
    print_section "💡 RECOMMENDATIONS"
    
    # Check if we can provision more VMs
    if [ "$vm_availability" = "available" ] && [ "$memory_pressure" != "unknown" ] && [ "$memory_pressure" -lt 60 ]; then
        echo -e "${ICON_INFO} System has capacity for additional VMs"
        echo "  Run: make auto-provision"
    fi
    
    # Check for failed pods
    if [ "${failed_pods:-0}" -gt 0 ]; then
        echo -e "${ICON_WARNING} Found $failed_pods failed pods"
        echo "  Run: kubectl get pods -A | grep -E '(Failed|Error|CrashLoop)'"
    fi
    
    # Check for pending pods
    if [ "${pending_pods:-0}" -gt 0 ]; then
        echo -e "${ICON_WARNING} Found $pending_pods pending pods"
        echo "  Run: kubectl describe pods -A | grep -A5 'Events:'"
    fi
    
    # Quick Actions
    print_section "⚡ QUICK ACTIONS"
    echo "Core Commands:"
    echo "  make status              - Refresh this status"
    echo "  make validate            - Run comprehensive health checks"
    echo "  make init                - Initialize everything (if not running)"
    echo ""
    echo "VM Management:"
    echo "  make auto-provision      - Provision VMs automatically"
    echo "  make vm-health           - Check VM health and connectivity"
    echo "  make vms                 - List all VMs"
    echo ""
    echo "Cluster Management:"
    echo "  kubectl get pods -A      - List all pods"
    echo "  kubectl get nodes        - List cluster nodes"
    echo "  kubectl top nodes        - Node resource usage (if metrics available)"
    echo ""
    echo "Service Access:"
    if [ "$k8s_status" = "running" ]; then
        echo "  ArgoCD: kubectl port-forward -n argocd svc/argocd-server 8080:443"
        echo "  Then open: https://localhost:8080"
    fi
    
    print_header ""
    echo -e "${CYAN}Dashboard refresh: ./scripts/comprehensive-status.sh${NC}"
    echo ""
}

# Run main function
main "$@"