.DEFAULT_GOAL := help

STACKS := network eks eks-addons argo-cd prometheus

.PHONY: help init validate fmt fmt-check tflint check-policies lint plan-network plan-eks plan-argo-cd plan-prometheus test-policies test-modules clean

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

fmt-check: ## Check OpenTofu formatting without writing changes
	tofu fmt -check -recursive .

tflint: ## Run tflint against all stacks (requires tflint --init first)
	tflint --recursive --config "$(CURDIR)/.github/linters/.tflint.hcl"

check-policies: ## Format-check and unit-test all Spacelift Rego policies
	opa fmt --check stacks/spacelift/policies/*.rego
	$(MAKE) --no-print-directory test-policies

lint: fmt-check tflint check-policies ## Run all static checks locally (mirrors CI — no tofu init required)

plan-network: ## Plan the network stack
	tofu -chdir=stacks/network plan

plan-eks: ## Plan the eks stack
	tofu -chdir=stacks/eks plan

plan-eks-addons: ## Plan the eks-addons stack
	tofu -chdir=stacks/eks-addons plan

plan-argo-cd: ## Plan the argo-cd stack
	tofu -chdir=stacks/argo-cd plan

plan-prometheus: ## Plan the prometheus stack
	tofu -chdir=stacks/prometheus plan

test-modules: ## Run native OpenTofu tests for all modules (no AWS credentials required)
	tofu -chdir=modules/network test
	tofu -chdir=modules/eks test

test-policies: ## Test Spacelift Rego policies with OPA
	opa test stacks/spacelift/policies/dev-plan.rego stacks/spacelift/policies/dev-plan_test.rego -v
	opa test stacks/spacelift/policies/prod-plan.rego stacks/spacelift/policies/prod-plan_test.rego -v
	opa test stacks/spacelift/policies/prod-approval.rego stacks/spacelift/policies/prod-approval_test.rego -v

clean: ## Remove all .terraform directories and lock files
	@find stacks -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find stacks -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@echo "Cleaned stacks/.terraform directories"
