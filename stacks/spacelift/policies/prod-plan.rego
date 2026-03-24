package spacelift

import rego.v1

# Resource types that are never safe to destroy in production without an explicit
# override. Destroying these can cause data loss, prolonged outages, or require
# hours of manual recovery.
protected_types := {
	"aws_eks_cluster",
	"aws_vpc",
	"aws_kms_key",
	"aws_iam_role",
	"aws_iam_role_policy_attachment",
	"aws_subnet",
	"aws_nat_gateway",
	"aws_internet_gateway",
}

# Matches both outright deletes and forced replacements (["delete", "create"]).
is_destructive(change) if {
	"delete" in change.actions
}

# Emergency override — active only when the run is triggered with:
#   spacectl stack run trigger --id <stack> --metadata '{"allow_destruction": "true"}'
# This is a last-resort escape hatch. See docs/operating-guide.md for the full procedure.
destruction_allowed if {
	input.spacelift.run.user_provided_metadata.allow_destruction == "true"
}

# Hard block. Cannot be approved or otherwise overridden — only the metadata flag
# above lifts this gate.
deny contains msg if {
	some resource in input.terraform.resource_changes
	is_destructive(resource.change)
	resource.type in protected_types
	not destruction_allowed
	msg := sprintf(
		"Destruction of protected resource blocked: %s (%s) — see operating guide for override procedure",
		[resource.address, resource.type],
	)
}

# Warn on destruction of non-protected resources. The approval policy gates these —
# they do not auto-apply.
warn contains msg if {
	some resource in input.terraform.resource_changes
	is_destructive(resource.change)
	not resource.type in protected_types
	msg := sprintf("Resource will be destroyed: %s (%s)", [resource.address, resource.type])
}

# Emit a visible warning when the emergency override is active so the audit log
# is unambiguous about what happened and why.
warn contains msg if {
	destruction_allowed
	msg := "EMERGENCY OVERRIDE ACTIVE: protected resource destruction permitted for this run only"
}

# Warn on large blast radius.
warn contains msg if {
	changing := [r |
		some r in input.terraform.resource_changes
		r.change.actions != ["no-op"]
	]
	count(changing) > 20
	msg := sprintf("Large blast radius — %d resources changing", [count(changing)])
}
