############################################
# Provider / App auth
############################################

variable "iac_app_id" {
  description = "App ID of the GitHub App used by Terraform to authenticate (not a PAT)."
  type        = string
}

variable "iac_app_installation_id" {
  description = "Installation ID of the IaC GitHub App on this org."
  type        = string
}

variable "iac_app_pem" {
  description = "Private key (PEM) *contents* for the IaC GitHub App. Prod path: inject from secrets manager via TF_VAR_iac_app_pem; never commit. Leave empty and use iac_app_pem_file to read from a local file instead (test only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "iac_app_pem_file" {
  description = "TEST-ONLY: path to the IaC GitHub App private-key .pem on disk. Used only when iac_app_pem is empty. Replace with a secrets-manager-sourced iac_app_pem before prod. The file itself must be gitignored."
  type        = string
  default     = ""
}

############################################
# Org / repo identity
############################################

variable "org_name" {
  description = "Target GitHub organization (greenfield POC org)."
  type        = string
}

variable "billing_email" {
  description = "Org billing contact email."
  type        = string
}

variable "repo_name" {
  description = "Name of the POC repository."
  type        = string
  default     = "four-eyes-poc"
}

variable "repo_visibility" {
  description = "Repository visibility."
  type        = string
  default     = "public"
  validation {
    condition     = contains(["public", "private", "internal"], var.repo_visibility)
    error_message = "repo_visibility must be public, private, or internal."
  }
}

############################################
# Ruleset enforcement staging
############################################

variable "ruleset_enforcement" {
  description = "Set to 'evaluate' during bootstrap/testing to observe without blocking, 'active' once validated."
  type        = string
  default     = "evaluate"
  validation {
    condition     = contains(["active", "evaluate", "disabled"], var.ruleset_enforcement)
    error_message = "ruleset_enforcement must be active, evaluate, or disabled."
  }
}

variable "protected_branch_patterns" {
  description = "Ref patterns covered by the core four-eyes ruleset."
  type        = list(string)
  # security/** is deliberately NOT in this list: it is an environment-only
  # allowance (see environments.tf bot_env_branches), not a PR-gated ref —
  # sweeping it in here would block direct pushes to security/* working
  # branches once enforcement is active.
  default     = ["refs/heads/develop", "refs/heads/main", "refs/heads/release/**"]
}

variable "required_status_checks" {
  description = "CI check contexts required before merge, mapped to the integration (App) ID whose statuses are trusted for that context. 0 means 'any source' — avoid it: anyone with write access can POST a forged success status, so always pin to the App that legitimately posts the check."
  type        = map(number)
  # origin-policy is the fork-only 2-approval gate (origin-policy.yml, formerly
  # fork-review-policy.yml) that rulesets cannot express natively. Pin it to
  # the gatekeeper App's ID in tfvars; 0 here is only a bootstrap placeholder.
  default = { "origin-policy" = 0 }
}

# Baseline approvals on the ruleset. Kept at 1 to hold developer overhead low
# for internal branch PRs (Vector A is already closed by the namespace lock +
# require_last_push_approval, not by a second approval). The extra approval that
# Vector B1 needs is applied to FORK PRs only, via a custom policy check —
# rulesets cannot vary the count by PR source. See THREAT_MODEL.md G3 / §2.5.
variable "required_approving_review_count" {
  description = "Baseline approvals required on protected branches (applies to all PRs regardless of source; fork-specific escalation is a separate policy check)."
  type        = number
  default     = 1
  validation {
    condition     = var.required_approving_review_count >= 1
    error_message = "required_approving_review_count must be >= 1."
  }
}

############################################
# Bot namespace registry
# Registering here is a prerequisite for any automation being installed —
# treat this map as the source of truth for "what bots exist and where they write."
############################################

variable "bot_namespaces" {
  description = "Map of bot key -> branch namespace + owning App installation, used to lock branch prefixes to their bot."
  type = map(object({
    pattern     = string # e.g. "refs/heads/poc-ci-bot/**"
    app_id      = number # GitHub App installation ID, sole bypass actor for this namespace
    description = string
  }))
  default = {
    poc_ci_bot = {
      pattern     = "refs/heads/poc-ci-bot/**"
      app_id      = 0 # placeholder, fill after App install
      description = "Well-configured automation bot (positive control)."
    }
    poc_rogue_bot = {
      pattern     = "refs/heads/poc-rogue-bot/**"
      app_id      = 0 # deliberately left unregistered as bypass actor in rulesets.tf — see test plan
      description = "Deliberately over-permissioned bot for negative testing only."
    }
  }
}

############################################
# Test identities (see test plan doc)
############################################

variable "test_users" {
  description = "Org member test accounts and their team/role assignment. External fork-contributor account is intentionally NOT included here — it stays outside org management."
  type = map(object({
    username = string
    org_role = string # "member" | "admin"
    team     = string # key into github_team resources, e.g. "maintainers" | "security_team"
  }))
  default = {
    attacker = {
      username = "poc-attacker"
      org_role = "member"
      team     = "maintainers"
    }
    codeowner = {
      username = "poc-codeowner"
      org_role = "member"
      team     = "security_team"
    }
    bystander = {
      username = "poc-bystander"
      org_role = "member"
      team     = "maintainers"
    }
  }
}

############################################
# Actions / Apps
############################################

variable "allowed_action_patterns" {
  description = "Allowlisted Actions, pinned by owner/repo@sha where possible."
  type        = list(string)
  default     = ["actions/checkout@*", "actions/setup-node@*"]
}
