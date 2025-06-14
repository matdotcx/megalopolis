.PHONY: help init up down rebuild clean status test-automation validate vms vm-create vm-connect vm-rebuild vm-status

CLUSTER_NAME := homelab
KUBECONFIG := ~/.kube/config

# Use project-local binaries
KUBECTL := ./kubectl
HELM := ./helm
KIND := ./kind-binary
TART := ./tart-binary
ORCHARD := ./orchard-binary

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize the homelab environment (Kind cluster + Tart VMs)
	@echo "Checking homelab setup..."
	@make ensure-tools
	@./scripts/check-cluster-exists.sh; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		make setup-vms; \
		exit 0; \
	elif [ $$EXIT_CODE -eq 1 ]; then \
		exit 1; \
	elif [ $$EXIT_CODE -eq 2 ]; then \
		echo ""; \
		make bootstrap; \
		make setup-vms; \
	elif [ $$EXIT_CODE -eq 3 ]; then \
		echo ""; \
		echo "Setting up new homelab environment..."; \
		make create-cluster; \
		make bootstrap; \
		make setup-vms; \
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
	./scripts/validate-cluster.sh

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
