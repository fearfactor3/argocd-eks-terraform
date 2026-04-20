# The management stack (the stack running this code) was created manually in the
# Spacelift UI with Administrative = enabled. The administrative flag is deprecated
# and will be auto-disabled on June 1st 2026. This file migrates to explicit role
# attachments before that date.
#
# Migration sequence:
#   1. Apply this change (creates role + attachment while administrative is still on)
#   2. Verify the role appears in the Spacelift UI: stack Settings → Roles
#   3. Disable Administrative in the Spacelift UI: stack Settings → General
#   4. Trigger a test run to confirm the management stack still functions
#
# Step 3 is a manual UI action — the management stack is not in TF state so it
# cannot manage its own administrative flag.

resource "spacelift_role" "space_admin" {
  name        = "space-admin"
  description = "Full admin access to the root space — replaces the deprecated administrative flag on the management stack."

  # SPACE_ADMIN is the direct equivalent of the deprecated administrative = true flag.
  # Spacelift's own deprecation guide states that administrative stacks are migrated
  # to a Space Admin role attachment on their own space.
  # Use the spacelift_role_actions data source to enumerate all available actions.
  actions = ["SPACE_ADMIN"]
}

resource "spacelift_role_attachment" "management_stack" {
  stack_id = var.spacelift_management_stack_id
  role_id  = spacelift_role.space_admin.id
  space_id = var.spacelift_space_id
}
