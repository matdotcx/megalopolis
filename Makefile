.PHONY: help init up down rebuild clean status test-automation validate vms vm-create vm-connect vm-rebuild vm-status comprehensive-status auto-provision vm-health deploy-full monitoring

CLUSTER_NAME := homelab
KUBECONFIG := ~/.kube/config

# Use project-local binaries
KUBECTL := ./kubectl
HELM := ./helm
KIND := ./kind-binary
TART := ./tart-binary
ORCHARD := ./orchard-binary

help: ## Show this help message
	@echo '🏙️  Megalopolis - Homelab Infrastructure'
	@echo '========================================'
	@echo ''
	@echo 'Quick Start:'
	@echo '  make init              Initialize everything (includes dashboard launch)'
	@echo '  make deploy-full       Full high-resource deployment'
	@echo ''
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'Note: Setup commands automatically launch the status dashboard'
	@echo '      at http://localhost:8090 for easy monitoring.'

init: ## Initialize the homelab environment (Kind cluster + Tart VMs)
	@echo "Checking homelab setup..."
	@make ensure-tools
	@./scripts/check-cluster-exists.sh; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		make setup-vms; \
		make launch-dashboard; \
	elif [ $$EXIT_CODE -eq 1 ]; then \
		exit 1; \
	elif [ $$EXIT_CODE -eq 2 ]; then \
		echo ""; \
		make bootstrap; \
		make setup-vms; \
		make launch-dashboard; \
	elif [ $$EXIT_CODE -eq 3 ]; then \
		echo ""; \
		echo "Setting up new homelab environment..."; \
		make create-cluster; \
		make bootstrap; \
		make setup-vms; \
		make launch-dashboard; \
	fi

ensure-tools: ## Ensure required tools are available
	./scripts/ensure-tools.sh

create-cluster: ## Create Kind cluster
	@./scripts/check-docker.sh || exit 1
	@if $(KIND) get clusters | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster '$(CLUSTER_NAME)' already exists."; \
		echo "Run 'make rebuild' to recreate it, or 'make status' to check its status."; \
		exit 1; \
	fi
	$(KIND) create cluster --config kind/config.yaml --name $(CLUSTER_NAME)

delete-cluster: ## Delete Kind cluster
	@./scripts/check-docker.sh || exit 1
	@if $(KIND) get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Deleting cluster '$(CLUSTER_NAME)'..."; \
		$(KIND) delete cluster --name $(CLUSTER_NAME); \
	else \
		echo "Cluster '$(CLUSTER_NAME)' does not exist."; \
	fi

bootstrap: ## Bootstrap ArgoCD and core services
	./scripts/bootstrap.sh

up: ## Start the homelab
	docker start kind-control-plane || make create-cluster

down: ## Stop the homelab
	docker stop kind-control-plane

rebuild: ## Rebuild everything from scratch
	make delete-cluster
	make create-cluster
	make bootstrap

clean: ## Clean up everything (Kind cluster + Tart VMs)
	-$(KIND) delete cluster --name $(CLUSTER_NAME)
	-$(TART) list 2>/dev/null | grep -E '^(macos-dev|macos-ci)' | awk '{print $$1}' | xargs -I {} $(TART) delete {} 2>/dev/null || true
	rm -rf ~/.kube/config

validate: ## Validate cluster and VM health
	@echo "Running comprehensive validation tests..."
	@cd tests && ./run-all-tests.sh

test-automation: ## Test the automation works without manual intervention
	@echo "Testing full automation cycle..."
	@make clean
	@echo "Starting timer..."
	@date +%s > /tmp/homelab-start-time
	@make init
	@make validate
	@echo "Automation test complete."
	@echo "Time taken: $$(($$(/bin/date +%s) - $$(cat /tmp/homelab-start-time))) seconds"
	@rm -f /tmp/homelab-start-time
	@echo ""
	@echo "🎯 Test completed! Dashboard should be running for review."

status: ## Check cluster and VM status
	@echo "=== Kubernetes Cluster Status ==="
	$(KUBECTL) cluster-info
	$(KUBECTL) get nodes
	$(KUBECTL) get pods -A
	@echo ""
	@echo "=== Virtual Machine Status ==="
	@make vm-status

setup-vms: ## Setup Tart VMs
	./scripts/setup-vms.sh

vms: ## List all VMs
	@$(TART) list 2>/dev/null || echo "No VMs found or Tart not available"

vm-status: ## Show VM status
	@echo "Tart VMs:"
	@if command -v $(TART) >/dev/null 2>&1; then \
		$(TART) list 2>/dev/null | head -20 || echo "No VMs found"; \
	else \
		echo "Tart not available"; \
	fi

vm-create: ## Create new VM from template
	@echo "Available VM templates:"
	@ls -1 tart/vm-configs/ 2>/dev/null || echo "No VM configs found"
	@echo "Usage: make vm-create VM_NAME=<name> VM_CONFIG=<config-file>"
	@if [ -n "$(VM_NAME)" ] && [ -n "$(VM_CONFIG)" ]; then \
		./scripts/setup-vms.sh create "$(VM_NAME)" "$(VM_CONFIG)"; \
	fi

vm-connect: ## SSH/VNC to VM
	@echo "Usage: make vm-connect VM_NAME=<name>"
	@if [ -n "$(VM_NAME)" ]; then \
		echo "Attempting to connect to $(VM_NAME)..."; \
		$(TART) ip "$(VM_NAME)" 2>/dev/null | xargs -I {} ssh user@{} || echo "Failed to connect"; \
	fi

vm-rebuild: ## Rebuild VMs from base images
	@echo "Rebuilding VMs from base images..."
	./scripts/setup-vms.sh rebuild

comprehensive-status: ## Show detailed system status dashboard
	./scripts/comprehensive-status.sh

auto-provision: ## Automatically provision VMs based on resource availability
	./scripts/auto-provision-vms.sh

vm-health: ## Check and repair VM health
	@echo "Checking VM health and connectivity..."
	@if command -v ./tart-binary >/dev/null 2>&1; then \
		./tart-binary list 2>/dev/null | tail -n +2 | while read -r line; do \
			vm_name=$$(echo "$$line" | awk '{print $$1}'); \
			vm_status=$$(echo "$$line" | awk '{print $$2}'); \
			echo "Checking $$vm_name ($$vm_status)..."; \
			if [ "$$vm_status" = "running" ]; then \
				vm_ip=$$(./tart-binary ip "$$vm_name" 2>/dev/null || echo ""); \
				if [ -n "$$vm_ip" ]; then \
					echo "  IP: $$vm_ip"; \
					timeout 3 ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "admin@$$vm_ip" "echo 'SSH OK'" 2>/dev/null && echo "  SSH: ✅ OK" || echo "  SSH: ❌ Failed"; \
				else \
					echo "  IP: Not available"; \
				fi; \
			fi; \
		done; \
	else \
		echo "Tart not available"; \
	fi

deploy-full: ## Full deployment optimized for high-resource systems (128GB RAM)
	@echo "🚀 Starting full high-resource deployment for 128GB system..."
	@echo "This will:"
	@echo "  - Ensure all tools are installed"
	@echo "  - Create/verify Kind cluster"
	@echo "  - Bootstrap core services (ArgoCD, Orchard)"
	@echo "  - Auto-provision VMs based on available resources"
	@echo "  - Launch status dashboard"
	@echo ""
	@read -p "Continue? [y/N] " -n 1 -r; echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		make ensure-tools && \
		make init && \
		make auto-provision && \
		echo "" && \
		echo "🎉 Full deployment completed!" && \
		echo "🏙️  Status dashboard should now be running at http://localhost:8090"; \
	else \
		echo "Deployment cancelled."; \
	fi

monitoring: ## Start continuous monitoring (runs in background)
	@echo "Starting continuous monitoring..."
	@echo "Logs will be written to /tmp/megalopolis-*.log"
	@(while true; do \
		date >> /tmp/megalopolis-monitoring.log; \
		./scripts/comprehensive-status.sh >> /tmp/megalopolis-status.log 2>&1; \
		./scripts/setup-vms.sh list >> /tmp/megalopolis-vms.log 2>&1; \
		sleep 300; \
	done) &
	@echo "Monitoring started in background (PID: $$!)"
	@echo "To stop: pkill -f 'megalopolis.*monitoring'"
	@echo "View logs: tail -f /tmp/megalopolis-status.log"

dashboard: ## Start the web status dashboard
	@echo "🏙️  Starting Megalopolis Status Dashboard..."
	@echo "📊 Dashboard will be available at http://localhost:8090"
	@echo "⏹️  Press Ctrl+C to stop"
	@python3 dashboard/server.py

dashboard-bg: ## Start dashboard in background
	@echo "🏙️  Starting Megalopolis Status Dashboard in background..."
	@nohup python3 dashboard/server.py > /tmp/megalopolis-dashboard.log 2>&1 &
	@echo "📊 Dashboard running at http://localhost:8090"
	@echo "📝 Logs: tail -f /tmp/megalopolis-dashboard.log"
	@echo "⏹️  To stop: pkill -f 'dashboard/server.py'"

launch-dashboard: ## Launch dashboard after setup completion
	@echo ""
	@echo "🎉 Megalopolis setup completed!"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "🏙️  Launching Status Dashboard..."
	@echo ""
	@echo "The dashboard will show you:"
	@echo "  ✅ What's working correctly"
	@echo "  ⚠️  What needs attention"
	@echo "  ❌ What's not working"
	@echo ""
	@echo "🔍 Checking for port conflicts..."
	@DASHBOARD_PORT=$$(bash -c 'check_port_available() { if lsof -Pi :$$1 -sTCP:LISTEN -t >/dev/null 2>&1; then return 1; else return 0; fi; }; check_kind_conflicts() { if [[ "$$1" == "8080" ]] || [[ "$$1" == "8443" ]]; then return 1; fi; return 0; }; port=8090; if ! check_kind_conflicts $$port || ! check_port_available $$port; then port=8091; fi; if ! check_port_available $$port; then port=$$((9000 + RANDOM % 1000)); fi; echo $$port'); \
	echo "📊 Starting dashboard at http://localhost:$$DASHBOARD_PORT"; \
	echo "🔄 Auto-refreshes every 30 seconds"; \
	echo "⏹️  Press Ctrl+C to stop when you're done reviewing"; \
	echo ""; \
	sleep 2; \
	if command -v open >/dev/null 2>&1; then \
		echo "🌐 Opening browser..."; \
		(sleep 3 && open http://localhost:$$DASHBOARD_PORT) & \
	fi; \
	DASHBOARD_PORT=$$DASHBOARD_PORT python3 dashboard/server.py

