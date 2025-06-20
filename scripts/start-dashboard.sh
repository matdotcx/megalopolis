#!/bin/bash
set -euo pipefail

# Start dashboard service script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DASHBOARD_LOG="/tmp/megalopolis-dashboard.log"
DASHBOARD_PID="/tmp/megalopolis-dashboard.pid"

# Default port
PORT=${DASHBOARD_PORT:-8090}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if dashboard is already running
check_dashboard_running() {
    if [ -f "$DASHBOARD_PID" ]; then
        local pid=$(cat "$DASHBOARD_PID")
        if ps -p "$pid" > /dev/null 2>&1; then
            log_info "Dashboard already running (PID: $pid) on port $PORT"
            return 0
        else
            log_info "Stale PID file found, removing..."
            rm -f "$DASHBOARD_PID"
        fi
    fi
    return 1
}

# Find available port
find_available_port() {
    local port=$1
    while lsof -Pi ":$port" -sTCP:LISTEN -t >/dev/null 2>&1; do
        port=$((port + 1))
        if [ $port -gt 9090 ]; then
            log_info "Could not find available port in range 8090-9090"
            exit 1
        fi
    done
    echo $port
}

# Start dashboard
start_dashboard() {
    log_info "Starting Megalopolis Dashboard..."
    
    # Find available port
    local available_port
    available_port=$(find_available_port $PORT)
    
    if [ "$available_port" != "$PORT" ]; then
        log_info "Port $PORT in use, using port $available_port instead"
        PORT=$available_port
    fi
    
    # Start dashboard in background 
    cd "$PROJECT_ROOT"
    python3 dashboard/server.py $PORT > "$DASHBOARD_LOG" 2>&1 &
    local pid=$!
    
    # Store PID
    echo $pid > "$DASHBOARD_PID"
    
    # Wait a moment to check if it started successfully
    sleep 2
    if ps -p $pid > /dev/null 2>&1; then
        log_info "Dashboard started successfully (PID: $pid)"
        log_info "Dashboard URL: http://localhost:$PORT"
        log_info "API URL: http://localhost:$PORT/api/status"
        log_info "Log file: $DASHBOARD_LOG"
        
        # Test API endpoint
        if curl -s -f "http://localhost:$PORT/api/status" > /dev/null; then
            log_info "Dashboard API is responding correctly"
        else
            log_info "Warning: Dashboard API not responding yet (may need a moment to start)"
        fi
    else
        log_info "Error: Dashboard failed to start"
        rm -f "$DASHBOARD_PID"
        exit 1
    fi
}

# Stop dashboard
stop_dashboard() {
    log_info "Stopping Megalopolis Dashboard..."
    
    if [ -f "$DASHBOARD_PID" ]; then
        local pid=$(cat "$DASHBOARD_PID")
        if ps -p "$pid" > /dev/null 2>&1; then
            kill $pid
            log_info "Dashboard stopped (PID: $pid)"
        else
            log_info "Dashboard not running"
        fi
        rm -f "$DASHBOARD_PID"
    else
        # Fallback: kill by process name
        pkill -f "dashboard/server.py" && log_info "Dashboard stopped" || log_info "No dashboard process found"
    fi
}

# Restart dashboard
restart_dashboard() {
    log_info "Restarting Megalopolis Dashboard..."
    stop_dashboard
    sleep 1
    start_dashboard
}

# Show status
status_dashboard() {
    if check_dashboard_running; then
        local pid=$(cat "$DASHBOARD_PID")
        local port_info=$(lsof -p $pid 2>/dev/null | grep LISTEN | awk '{print $9}' | head -1)
        log_info "Dashboard Status: RUNNING"
        log_info "PID: $pid"
        log_info "Port: $port_info"
        log_info "Log: $DASHBOARD_LOG"
        
        # Test API
        local api_url="http://localhost:${port_info#*:}/api/status"
        if curl -s -f "$api_url" > /dev/null; then
            log_info "API Status: HEALTHY"
        else
            log_info "API Status: UNHEALTHY"
        fi
    else
        log_info "Dashboard Status: NOT RUNNING"
    fi
}

# Main command handling
case "${1:-start}" in
    "start")
        if check_dashboard_running; then
            exit 0
        else
            start_dashboard
        fi
        ;;
    "stop")
        stop_dashboard
        ;;
    "restart")
        restart_dashboard
        ;;
    "status")
        status_dashboard
        ;;
    "ensure")
        # Ensure dashboard is running (start if not)
        if ! check_dashboard_running; then
            start_dashboard
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|ensure}"
        echo ""
        echo "Commands:"
        echo "  start   - Start dashboard if not running"
        echo "  stop    - Stop dashboard"
        echo "  restart - Restart dashboard"
        echo "  status  - Show dashboard status"
        echo "  ensure  - Ensure dashboard is running (start if needed)"
        exit 1
        ;;
esac