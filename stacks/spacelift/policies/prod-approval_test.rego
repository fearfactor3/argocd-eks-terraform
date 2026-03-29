package spacelift_test

import rego.v1

import data.spacelift

# ── helpers ──────────────────────────────────────────────────────────────────

normal_input(reviews) := {
	"spacelift": {"run": {"user_provided_metadata": {}}},
	"reviews": reviews,
}

emergency_input(reviews) := {
	"spacelift": {"run": {"user_provided_metadata": {"allow_destruction": "true"}}},
	"reviews": reviews,
}

approval := {"decision": "approve"}

rejection := {"decision": "reject"}

# ── normal run ────────────────────────────────────────────────────────────────

test_no_approvals_not_approved if {
	not spacelift.approve with input as normal_input([])
}

test_one_approval_approved if {
	spacelift.approve with input as normal_input([approval])
}

test_rejection_blocks_approval if {
	not spacelift.approve with input as normal_input([rejection])
}

test_rejection_overrides_approval if {
	not spacelift.approve with input as normal_input([approval, rejection])
}

# ── emergency destruction run ─────────────────────────────────────────────────

test_one_approval_sufficient_for_emergency if {
	spacelift.approve with input as emergency_input([approval])
}

test_no_approvals_not_enough_for_emergency if {
	not spacelift.approve with input as emergency_input([])
}

test_rejection_blocks_emergency_approval if {
	not spacelift.approve with input as emergency_input([approval, approval, rejection])
}

test_no_reviews_not_approved_for_emergency if {
	not spacelift.approve with input as emergency_input([])
}
