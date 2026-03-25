package spacelift_test

import rego.v1

import data.spacelift

# ── helpers ──────────────────────────────────────────────────────────────────

resource_change(addr, rtype, actions) := {
	"address": addr,
	"type": rtype,
	"change": {"actions": actions},
}

base_input(changes) := {
	"spacelift": {"run": {"user_provided_metadata": {}}},
	"terraform": {"resource_changes": changes},
}

override_input(changes) := {
	"spacelift": {"run": {"user_provided_metadata": {"allow_destruction": "true"}}},
	"terraform": {"resource_changes": changes},
}

# ── deny: protected resource destruction ─────────────────────────────────────

test_deny_eks_cluster_deletion if {
	some _ in spacelift.deny with input as base_input([resource_change("aws_eks_cluster.main", "aws_eks_cluster", ["delete"])])
}

test_deny_vpc_deletion if {
	some _ in spacelift.deny with input as base_input([resource_change("aws_vpc.main", "aws_vpc", ["delete"])])
}

test_deny_kms_key_deletion if {
	some _ in spacelift.deny with input as base_input([resource_change("aws_kms_key.eks", "aws_kms_key", ["delete"])])
}

# A forced replacement (delete + create) is equally dangerous and must be blocked.
test_deny_protected_replacement if {
	some _ in spacelift.deny with input as base_input([resource_change("aws_vpc.main", "aws_vpc", ["delete", "create"])])
}

# ── deny: override lifts the block ───────────────────────────────────────────

test_no_deny_with_override if {
	count(spacelift.deny) == 0 with input as override_input([resource_change("aws_eks_cluster.main", "aws_eks_cluster", ["delete"])])
}

# ── warn: override active ────────────────────────────────────────────────────

test_override_active_emits_warn if {
	some _ in spacelift.warn with input as override_input([])
}

# ── warn: non-protected destruction ──────────────────────────────────────────

test_warn_non_protected_deletion if {
	inp := base_input([resource_change("aws_security_group.nodes", "aws_security_group", ["delete"])])
	some _ in spacelift.warn with input as inp
	count(spacelift.deny) == 0 with input as inp
}

# ── warn: large blast radius ─────────────────────────────────────────────────

test_warn_large_blast_radius if {
	changes := [resource_change(sprintf("r%d", [i]), "aws_instance", ["update"]) |
		some i in numbers.range(1, 21)
	]
	some _ in spacelift.warn with input as base_input(changes)
}

test_no_blast_radius_warn_for_small_change if {
	changes := [resource_change(sprintf("r%d", [i]), "aws_instance", ["update"]) |
		some i in numbers.range(1, 5)
	]
	count(spacelift.warn) == 0 with input as base_input(changes)
}

# ── no issues for create-only plan ───────────────────────────────────────────

test_no_issues_create_only if {
	inp := base_input([resource_change("aws_eks_cluster.main", "aws_eks_cluster", ["create"])])
	count(spacelift.deny) == 0 with input as inp
	count(spacelift.warn) == 0 with input as inp
}
