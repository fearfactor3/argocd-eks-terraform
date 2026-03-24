package spacelift

import rego.v1

# All submitted approvals for this run.
approvals := [review |
	some review in input.reviews
	review.decision == "approve"
]

# All submitted rejections for this run.
rejections := [review |
	some review in input.reviews
	review.decision == "reject"
]

# Active when the run was triggered with the emergency destruction override.
# Must match the flag checked in prod-plan.rego.
is_emergency_destruction if {
	input.spacelift.run.user_provided_metadata.allow_destruction == "true"
}

# Standard production apply — requires 1 explicit approval before the run
# proceeds to apply. Autodeploy is disabled on prod stacks so every tracked
# run stops here until approved.
approve if {
	not is_emergency_destruction
	count(rejections) == 0
	count(approvals) >= 1
}

# Emergency destruction run — requires 2 approvals to force a deliberate pause
# before infrastructure is destroyed.
#
# NOTE: In a single-operator setup where only one person can approve, lower this
# threshold to 1. The value is the deliberate confirmation step, not the headcount.
approve if {
	is_emergency_destruction
	count(rejections) == 0
	count(approvals) >= 2
}
