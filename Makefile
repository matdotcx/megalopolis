.PHONY: help init up down rebuild clean status test-automation validate

CLUSTER_NAME := homelab
KUBECONFIG := ~/.kube/config

# Use project-local binaries
KUBECTL := ./kubectl
HELM := ./helm
KIND := ./kind-binary

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize the homelab environment
	@echo "Checking homelab setup..."
	@make ensure-tools
	@./scripts/check-cluster-exists.sh; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		exit 0; \
	elif [ $$EXIT_CODE -eq 1 ]; then \
		exit 1; \
	elif [ $$EXIT_CODE -eq 2 ]; then \
		echo ""; \
		make bootstrap; \
	elif [ $$EXIT_CODE -eq 3 ]; then \
		echo ""; \
		echo "Setting up new homelab environment..."; \
		make create-cluster; \
		make bootstrap; \
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

clean: ## Clean up everything
	-$(KIND) delete cluster --name $(CLUSTER_NAME)
	rm -rf ~/.kube/config

validate: ## Validate cluster health and readiness
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

status: ## Check cluster status
	$(KUBECTL) cluster-info
	$(KUBECTL) get nodes
	$(KUBECTL) get pods -A
