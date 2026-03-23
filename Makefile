.DEFAULT_GOAL := help

STACKS := network eks argo-cd prometheus

.PHONY: help init validate fmt plan-network plan-eks plan-argo-cd plan-prometheus clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

init: ## Run tofu init for all stacks
	@for stack in $(STACKS); do \
		echo "→ init stacks/$$stack"; \
		tofu -chdir=stacks/$$stack init -upgrade; \
	done

validate: ## Validate all stacks
	@for stack in $(STACKS); do \
		echo "→ validate stacks/$$stack"; \
		tofu -chdir=stacks/$$stack validate; \
	done

fmt: ## Format all OpenTofu files recursively
	tofu fmt -recursive .

plan-network: ## Plan the network stack
	tofu -chdir=stacks/network plan

plan-eks: ## Plan the eks stack
	tofu -chdir=stacks/eks plan

plan-argo-cd: ## Plan the argo-cd stack
	tofu -chdir=stacks/argo-cd plan

plan-prometheus: ## Plan the prometheus stack
	tofu -chdir=stacks/prometheus plan

clean: ## Remove all .terraform directories and lock files
	@find stacks -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find stacks -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "Cleaned stacks/.terraform directories"
