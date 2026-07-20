output "repo_full_name" {
  description = "Full name (org/repo) of the POC repository."
  value       = github_repository.poc.full_name
}

output "four_eyes_ruleset_id" {
  description = "ID of the core four-eyes ruleset."
  value       = github_repository_ruleset.four_eyes_core.ruleset_id
}

output "bot_namespace_ruleset_ids" {
  description = "Map of bot key -> namespace-lock ruleset ID."
  value       = { for k, r in github_repository_ruleset.bot_namespace : k => r.ruleset_id }
}

output "workflow_authorship_lock_ruleset_id" {
  description = "ID of the ruleset restricting .github/workflows authorship to the security team."
  value       = github_repository_ruleset.workflow_authorship_lock.ruleset_id
}

output "team_slugs" {
  description = "Slugs of the managed teams."
  value = {
    maintainers   = github_team.maintainers.slug
    security_team = github_team.security_team.slug
  }
}
