.DEFAULT_GOAL := help

STACKS     := network eks eks-addons argo-cd prometheus spacelift
ENV_STACKS := network eks eks-addons argo-cd prometheus

.PHONY: help \
        init validate \
        fmt fmt-check tflint check-policies markdownlint lint \
        test test-modules test-policies \
        plan-dev plan-prod plan-spacelift \
        clean

# ─── Help ────────────────────────────────────────────────────────────────────

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

# ─── Setup ───────────────────────────────────────────────────────────────────

init: ## Run tofu init for all stacks (use after provider/module changes)
	@for stack in $(STACKS); do \
		echo "→ init stacks/$$stack"; \
		tofu -chdir=stacks/$$stack init -upgrade; \
	done

validate: ## Validate all stacks (requires tofu init first)
	@for stack in $(STACKS); do \
		echo "→ validate stacks/$$stack"; \
		tofu -chdir=stacks/$$stack validate; \
	done

# ─── Code Quality ─────────────────────────────────────────────────────────────

fmt: ## Format all OpenTofu files recursively
	@tofu fmt -recursive .

fmt-check: ## Check OpenTofu formatting without writing changes
	@tofu fmt -check -recursive .

tflint: ## Run tflint against all stacks (requires tflint --init first)
	@tflint --recursive --config "$(CURDIR)/.github/linters/.tflint.hcl"

check-policies: ## Format-check and unit-test all Spacelift Rego policies
	@opa fmt --fail stacks/spacelift/policies/*.rego
	@$(MAKE) --no-print-directory test-policies

markdownlint: ## Lint all Markdown files using .github/linters/.markdownlint.json
	@markdownlint --config .github/linters/.markdownlint.json "**/*.md"

lint: fmt-check tflint check-policies markdownlint ## Run all static checks (mirrors CI validate — no tofu init required)

# ─── Testing ──────────────────────────────────────────────────────────────────

test: lint test-modules test-policies ## Run all checks including module and policy tests (full local CI)

test-modules: ## Run native OpenTofu tests for all modules (no AWS credentials required)
	@tofu -chdir=modules/network test
	@tofu -chdir=modules/eks test

test-policies: ## Test Spacelift Rego policies with OPA
	@opa test stacks/spacelift/policies/dev-plan.rego stacks/spacelift/policies/dev-plan_test.rego -v
	@opa test stacks/spacelift/policies/prod-plan.rego stacks/spacelift/policies/prod-plan_test.rego -v
	@opa test stacks/spacelift/policies/prod-approval.rego stacks/spacelift/policies/prod-approval_test.rego -v

# ─── Planning ─────────────────────────────────────────────────────────────────

plan-dev: ## Plan all environment stacks (dev)
	@for stack in $(ENV_STACKS); do \
		echo "→ plan stacks/$$stack (dev)"; \
		tofu -chdir=stacks/$$stack plan -var-file=dev.tfvars; \
	done

plan-prod: ## Plan all environment stacks (prod)
	@for stack in $(ENV_STACKS); do \
		echo "→ plan stacks/$$stack (prod)"; \
		tofu -chdir=stacks/$$stack plan -var-file=prod.tfvars; \
	done

plan-spacelift: ## Plan the spacelift management stack
	@tofu -chdir=stacks/spacelift plan

# ─── Maintenance ──────────────────────────────────────────────────────────────

clean: ## Remove .terraform plugin cache directories (lock files are preserved)
	@find stacks -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
