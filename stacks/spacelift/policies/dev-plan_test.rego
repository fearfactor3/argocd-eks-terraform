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
	"spacelift": {"run": {}},
	"terraform": {"resource_changes": changes},
}

# ── warn: any deletion is surfaced ───────────────────────────────────────────

# Dev has no hard blocks — even protected resource types only warn.
test_warn_protected_type_deletion if {
	some _ in spacelift.warn with input as base_input([resource_change("aws_eks_cluster.main", "aws_eks_cluster", ["delete"])])
}

test_warn_any_deletion if {
	some _ in spacelift.warn with input as base_input([resource_change("aws_security_group.nodes", "aws_security_group", ["delete"])])
}

test_warn_replacement if {
	some _ in spacelift.warn with input as base_input([resource_change("aws_vpc.main", "aws_vpc", ["delete", "create"])])
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

# ── no warnings for create-only plan ─────────────────────────────────────────

test_no_warn_create_only if {
	count(spacelift.warn) == 0 with input as base_input([resource_change("aws_eks_cluster.main", "aws_eks_cluster", ["create"])])
}
