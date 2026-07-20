# -----------------------------------------------------------------------------
# The POC repository itself.
# -----------------------------------------------------------------------------

resource "github_repository" "poc" {
  name        = var.repo_name
  description = "Security-engineering POC: validating rulesets against the four-eyes self-approval bypass."
  visibility  = var.repo_visibility

  delete_branch_on_merge = true
  allow_update_branch    = true
  allow_forking          = true

  has_issues = true
  has_wiki   = false

  security_and_analysis {
    secret_scanning {
      status = "enabled"
    }
    secret_scanning_push_protection {
      status = "enabled"
    }
  }
}

# develop is the integration branch and the default; main is release-only.
resource "github_branch" "develop" {
  repository = github_repository.poc.name
  branch     = "develop"
}

resource "github_branch_default" "default" {
  repository = github_repository.poc.name
  branch     = github_branch.develop.branch
}

