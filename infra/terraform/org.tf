# -----------------------------------------------------------------------------
# Organization-wide hardening.
# Mitigates: CICD-SEC-1 (insufficient flow control), CICD-SEC-2 (inadequate
# IAM — least-privilege default repo permission), CICD-SEC-8 (ungoverned
# usage of 3rd-party services via the Actions allowlist).
# -----------------------------------------------------------------------------

resource "github_organization_settings" "org" {
  billing_email = var.billing_email

  # Members get read by default; write is granted explicitly via teams.
  default_repository_permission = "read"

  # Prevent shadow repos outside the governed set. Blocking ALL member repo
  # creation (not just public) removes the unprotected-repo flank: only admins
  # provision repositories, and every repo is then born under the org ruleset
  # in org_rulesets.tf.
  members_can_create_repositories          = false
  members_can_create_public_repositories   = false
  members_can_create_private_repositories  = false
  members_can_create_internal_repositories = false

  # Every web-UI commit carries a signoff — cheap provenance signal.
  web_commit_signoff_required = true

  # Allow members to fork private/internal repos too. Only takes effect when
  # repo_visibility is set to private or internal; public repos fork per the
  # repo-level allow_forking setting regardless of this flag.
  members_can_fork_private_repositories = true
}

# Only allowlisted actions may run anywhere in the org. GitHub-owned actions
# are permitted; everything else must match var.allowed_action_patterns.
resource "github_actions_organization_permissions" "org" {
  allowed_actions = "selected"
  enabled_repositories = "all"

  allowed_actions_config {
    github_owned_allowed = true
    verified_allowed     = false
    patterns_allowed     = var.allowed_action_patterns
  }
}
