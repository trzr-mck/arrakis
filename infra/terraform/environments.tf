
locals {
  bot_env_branches = concat(
    [for p in var.protected_branch_patterns : replace(p, "refs/heads/", "")],
    ["security/**"]
  )
}

resource "github_repository_environment" "bot_automation" {
  repository  = github_repository.poc.name
  environment = "bot-automation"

  # An approver can never approve their own deployment to this environment.
  prevent_self_review = true

  # Restrict to an explicit branch allowlist (defined by the policy resources
  # below), rather than "all protected branches".
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }


# One deployment policy per allowed branch pattern (develop, main, release/**).
# Only runs on these branches can access the environment's secrets.
resource "github_repository_environment_deployment_policy" "bot_automation" {
  for_each = toset(local.bot_env_branches)

  repository     = github_repository.poc.name
  environment    = github_repository_environment.bot_automation.environment
  branch_pattern = each.value
}

resource "github_repository_environment" "origin_policy" {
  repository  = github_repository.poc.name
  environment = "origin-policy"

  reviewers {
    teams = [github_team.maintainers.id]
  }

 prevent_self_review = true

}

resource "github_repository_environment" "tests" {
  repository  = github_repository.poc.name
  environment = "tests"

}

