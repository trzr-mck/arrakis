# -----------------------------------------------------------------------------
# Deployment environment for the legitimate automation bot (poc-ci-bot).
# Mitigates: CICD-SEC-6 (credential hygiene) and CICD-SEC-1 (flow control) —
# the bot's App private key is scoped to an environment that only releases its
# secrets to runs from protected branches, so a malicious workflow pushed to an
# attacker's feature branch cannot read the key and mint a bot token.
#
# NOTE: the App private key value is intentionally NOT managed here — see the
# commented secret resources at the bottom. Managing it in Terraform would
# write the PEM into state. Set the secret values out-of-band with `gh`
# (commands in the terraform README / below) so the key never enters state.
# -----------------------------------------------------------------------------

locals {
  # Reuse the ruleset's protected refs as the environment's allowed branches,
  # stripping the refs/heads/ prefix (environment branch policies take bare
  # branch patterns). Keeps env scope and ruleset scope from drifting apart.
  #
  # "security/**" is added on top of the ruleset-derived list: it's an
  # environment-only allowance (e.g. security-team hotfix branches dispatching
  # the bot), not a branch we want swept into the four-eyes PR/review ruleset.
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

  # -- Optional stronger gate: require a human (or the security team) to
  # -- approve every bot dispatch. Adds per-run friction; the branch policy
  # -- below already closes the token-theft path, so this is defense-in-depth,
  # -- not load-bearing. Uncomment to enable.
  #
  # reviewers {
  #   teams = [github_team.security_team.id]
  # }
}

# One deployment policy per allowed branch pattern (develop, main, release/**).
# Only runs on these branches can access the environment's secrets.
resource "github_repository_environment_deployment_policy" "bot_automation" {
  for_each = toset(local.bot_env_branches)

  repository     = github_repository.poc.name
  environment    = github_repository_environment.bot_automation.environment
  branch_pattern = each.value
}

# -----------------------------------------------------------------------------
# Deployment environment for the origin-policy App (origin-policy.yml).
# Mitigates: CICD-SEC-6 (credential hygiene) via environment-scoped secrets,
# same as bot-automation — but deliberately carries NO deployment branch
# policy. origin-policy.yml runs on pull_request_target for fork PRs, and
# GitHub evaluates environment branch policies for fork-triggered
# pull_request_target runs against the PR's merge ref (refs/pull/N/merge),
# never the base branch — so any branch-scoped policy here would silently
# block the check on exactly the PRs it exists to police (see bot-automation
# above, which is scoped to branches for its own different purpose and must
# not be reused for this job).
#
# The security boundary for this App is its own narrow installation
# permissions (Pull requests: read, Commit statuses: write — no Contents),
# not branch matching. See origin-policy.yml's inline comments.
# -----------------------------------------------------------------------------

resource "github_repository_environment" "origin_policy" {
  repository  = github_repository.poc.name
  environment = "origin-policy"

  # Required reviewers turn this credentialed job into a "wait for a write-access
  # human" gate: the origin-policy job (which mints the App token) sits in
  # "Waiting for review" on every fork PR until a maintainer approves the
  # deployment, and only then does the token step run. This is a deployment
  # PROTECTION RULE, evaluated per-actor — NOT a branch policy — so unlike the
  # deliberately-omitted deployment_branch_policy above, it is not evaluated
  # against refs/pull/N/merge and does not misfire on fork pull_request_target
  # runs. Credential-less tests (ci-tests.yml) carry no environment and are
  # unaffected — they auto-run.
  reviewers {
    teams = [github_team.maintainers.id]
  }

  # The fork PR's author is the triggering actor on pull_request_target; this
  # stops them from approving the run of the very gate meant to police them.
  prevent_self_review = true

  # No deployment_branch_policy block at all == "no restriction" (all
  # branches/refs allowed). The GitHub API rejects protected_branches and
  # custom_branch_policies both being false explicitly (422) — omitting the
  # block entirely is the only way to express unrestricted.
}

# -----------------------------------------------------------------------------
# Deployment environment for the "test" workflow (test.yml).
# This job never authenticates as anything (permissions: {} in the workflow,
# no App token step) and only reads files already in its own checkout — there
# are no credentials or write access in scope for a reviewer gate or branch
# policy to protect. It exists as its own environment purely to keep this
# job's identity/scope visible and separate from the credentialed
# environments above, not for access control. Deliberately unrestricted so it
# runs on every push and every PR — including forks — with no maintainer
# trigger required.
# -----------------------------------------------------------------------------

resource "github_repository_environment" "tests" {
  repository  = github_repository.poc.name
  environment = "tests"

  # No reviewers block and no deployment_branch_policy block: unrestricted,
  # on purpose (see comment above).
}

# -----------------------------------------------------------------------------
# Environment secrets — DELIBERATELY NOT MANAGED IN TERRAFORM.
#
# Set these with gh instead, after the environment exists, so the App private
# key never lands in Terraform state:
#
#   gh secret set GH_LEGIT_APP_ID \
#     --env bot-automation --repo <ORG>/<REPO> --body "<app-id>"
#
#   gh secret set GH_LEGIT_APP_PRIVATE_KEY \
#     --env bot-automation --repo <ORG>/<REPO> < /path/to/poc-ci-bot.private-key.pem
#
# origin-policy's App ID is read as a variable, not a secret
# (origin-policy.yml uses vars.ORIGIN_POLICY_APP_ID):
#
#   gh variable set ORIGIN_POLICY_APP_ID \
#     --env origin-policy --repo <ORG>/<REPO> --body "<app-id>"
#
#   gh secret set ORIGIN_POLICY_APP_PRIVATE_KEY \
#     --env origin-policy --repo <ORG>/<REPO> < /path/to/origin-policy-app.private-key.pem
#
# If you ever DO want them in Terraform (accepting the PEM-in-state tradeoff on
# an encrypted, access-restricted backend), the resources would be:
#
# resource "github_actions_environment_secret" "bot_app_id" {
#   repository      = github_repository.poc.name
#   environment     = github_repository_environment.bot_automation.environment
#   secret_name     = "GH_LEGIT_APP_ID"
#   plaintext_value = var.legit_bot_app_id      # would require a new variable
# }
#
# resource "github_actions_environment_secret" "bot_app_key" {
#   repository      = github_repository.poc.name
#   environment     = github_repository_environment.bot_automation.environment
#   secret_name     = "GH_LEGIT_APP_PRIVATE_KEY"
#   plaintext_value = var.legit_bot_app_pem     # sensitive; would enter state
# }
# -----------------------------------------------------------------------------
