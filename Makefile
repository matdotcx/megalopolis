.PHONY: help init up down rebuild clean status

CLUSTER_NAME := homelab
KUBECONFIG := ~/.kube/config

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

init: ## Initialize the homelab environment
	@echo "Setting up homelab environment..."
	@make install-deps
	@make create-cluster
	@make bootstrap

install-deps: ## Install required dependencies
	@echo "Installing dependencies via MacPorts..."
	sudo /opt/local/bin/port install kubectl helm go-task sops age jq yq
	@echo "Installing Kind..."
	curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-darwin-arm64
	chmod +x ./kind
	sudo mv ./kind /opt/local/bin/kind

create-cluster: ## Create Kind cluster
	kind create cluster --config kind/config.yaml --name $(CLUSTER_NAME)

delete-cluster: ## Delete Kind cluster
	kind delete cluster --name $(CLUSTER_NAME)

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
	make delete-cluster
	rm -rf ~/.kube/config

status: ## Check cluster status
	kubectl cluster-info
	kubectl get nodes
	kubectl get pods -A
