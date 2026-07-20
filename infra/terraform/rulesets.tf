# -----------------------------------------------------------------------------
# Rulesets — the core of the POC.
# =============================================================================
# Core four-eyes ruleset on develop / main / release/**
# =============================================================================
resource "github_repository_ruleset" "four_eyes_core" {
  name        = "four-eyes-core"
  repository  = github_repository.poc.name
  target      = "branch"
  enforcement = var.ruleset_enforcement # start "evaluate", flip to "active" after validation

  conditions {
    ref_name {
      include = var.protected_branch_patterns
      exclude = []
    }
  }

  rules {
    # Protected branches cannot be deleted or history-rewritten.
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count   = var.required_approving_review_count
      require_last_push_approval        = true
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = true
      required_review_thread_resolution = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      # integration_id pins each context to the App allowed to satisfy it —
      # without it, any write-access user can forge the status by POSTing
      # state=success with the right context on the head SHA.
      dynamic "required_check" {
        for_each = var.required_status_checks
        content {
          context        = required_check.key
          integration_id = required_check.value
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # bypass_actors: DELIBERATELY EMPTY.
  #
  # Any bypass actor — including a "break-glass" admin team — reintroduces the
  # exact vulnerability this ruleset exists to close: an identity whose merges
  # do not require a second pair of eyes. Org admins are bound identically
  # (validated by test scenario #10). If a break-glass path is ever needed,
  # that is a Phase-2 decision requiring its own audited design (time-boxed
  # bypass, paired approval out-of-band, alerting) — do not add actors here.
  # ---------------------------------------------------------------------------
}

# =============================================================================
# Bot namespace locks.
#
# One ruleset per registered bot namespace: nobody can create, update, or
# force-push refs under the bot's prefix except the bot's own App
# installation. This closes the other half of the bypass — a human pushing
# their commit onto a bot-authored PR branch.

resource "github_repository_ruleset" "bot_namespace" {
  for_each = var.bot_namespaces

  name        = "bot-namespace-${each.key}"
  repository  = github_repository.poc.name
  target      = "branch"
  enforcement = var.ruleset_enforcement

  conditions {
    ref_name {
      include = [each.value.pattern]
      exclude = []
    }
  }

  rules {
    creation         = true
    update           = true
    non_fast_forward = true
  }

  # Sole bypass: the owning bot's App installation. Skipped while app_id is
  dynamic "bypass_actors" {
    for_each = each.value.app_id != 0 ? [each.value.app_id] : []
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }
}
