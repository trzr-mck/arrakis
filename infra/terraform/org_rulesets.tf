resource "github_organization_ruleset" "four_eyes_org" {
  name        = "four-eyes-org"
  target      = "branch"
  enforcement = var.ruleset_enforcement # same evaluate -> active staging as the repo ruleset

  conditions {
    # Apply to all current and future repositories in the org.
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
    ref_name {
      # Each repo's default branch, plus the shared protected patterns.
      include = concat(["~DEFAULT_BRANCH"], var.protected_branch_patterns)
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count   = var.required_approving_review_count
      require_last_push_approval        = true
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = true
      required_review_thread_resolution = true
    }
  }

  # bypass_actors DELIBERATELY EMPTY — identical philosophy to four_eyes_core
  # (rulesets.tf): no org-wide identity may skip the second pair of eyes.
}
