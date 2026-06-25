# Convenience targets around the local kind cluster bootstrap.
# `make up` is the one-shot entrypoint for the E2E demo.

CLUSTER_NAME := shophub-local

.PHONY: up down status reinstall

up: ## Create the kind cluster and install every release in order
	./scripts/bootstrap.sh

down: ## Delete the kind cluster and everything in it
	kind delete cluster --name $(CLUSTER_NAME)

status: ## Show releases, pods and Shop CRs across the cluster
	@helm list --all-namespaces
	@kubectl get pods -A
	@kubectl get shops,discordchannels,wallets -A

reinstall: down up ## Tear down and bring the platform back up from scratch
