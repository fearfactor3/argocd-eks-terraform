package spacelift

import rego.v1

# Dev plan policy — warn-only. No hard blocks. Dev exists for fast iteration;
# destructions are surfaced visibly but never prevented automatically.

# Matches both outright deletes and forced replacements (["delete", "create"]).
is_destructive(change) if {
	"delete" in change.actions
}

# Warn on any destruction so it is visible in the run log and UI.
warn contains msg if {
	some resource in input.terraform.resource_changes
	is_destructive(resource.change)
	msg := sprintf("Resource will be destroyed: %s (%s)", [resource.address, resource.type])
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
