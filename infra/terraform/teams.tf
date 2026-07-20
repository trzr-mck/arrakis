# -----------------------------------------------------------------------------
# This is rather redundant, made my life easier when provisioning. Normally
# users should be added based on groups from IdP (if there's one)
# -----------------------------------------------------------------------------

resource "github_membership" "test_users" {
  for_each = var.test_users

  username = each.value.username
  role     = each.value.org_role
}

resource "github_team" "maintainers" {
  name        = "maintainers"
  description = "General maintainers — default reviewers/owners for most paths."
  privacy     = "closed"
}

resource "github_team" "security_team" {
  name        = "security-team"
  description = "Owns CI config, workspace manifests, and CODEOWNERS-gated paths."
  privacy     = "closed"
}

locals {
  # Map the `team` key in var.test_users onto the team resources above.
  team_ids = {
    maintainers   = github_team.maintainers.id
    security_team = github_team.security_team.id
  }
}

resource "github_team_membership" "test_users" {
  for_each = var.test_users

  team_id  = local.team_ids[each.value.team]
  username = each.value.username
  role     = "member"

  depends_on = [github_membership.test_users]
}

# Maintainers get push; nobody gets admin on the POC repo via teams.
resource "github_team_repository" "maintainers_push" {
  team_id    = github_team.maintainers.id
  repository = github_repository.poc.name
  permission = "push"
}
