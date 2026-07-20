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

# =============================================================================
# Workflow authorship lock — CI/CD config is security-team territory.
#
# A PUSH ruleset (target = "push"): file-path restrictions are evaluated on the
# push itself, before any ref update, so they apply to EVERY branch by design —
# there is no ref_name condition (and none is allowed on push rulesets). It
# prohibits creating or modifying any file under .github/workflows (see
# var.workflow_restricted_paths) unless the pusher is on the security team.
#
# This is the push-time counterpart to the merge-time gate: CODEOWNERS +
# require_code_owner_review already force security-team *review* of workflow
# changes on protected branches, but this rule is what stops a non-owner from
# *authoring* the change on a feature/bot branch in the first place. Together
# they mean workflow edits can only originate from, and can only merge with the
# blessing of, the security team. (Mitigates CICD-SEC-1 / CICD-SEC-7: tampering
# with the pipeline definition itself.)
#
# Independent of four_eyes_core: rulesets evaluate separately, so the security
# team's bypass here removes ONLY this path restriction. A security-team
# member's workflow PR into a protected branch still faces four_eyes_core's
# empty-bypass gate — a second code-owner approval + last-push approval — so
# "security team owns workflows" never collapses into "one security engineer
# can self-merge a workflow change."
# =============================================================================
resource "github_repository_ruleset" "workflow_authorship_lock" {
  name        = "workflow-authorship-lock"
  repository  = github_repository.poc.name
  target      = "push"
  enforcement = var.ruleset_enforcement # same evaluate -> active staging as the other rulesets

  # No conditions block: push rulesets have no ref_name scope and the repo is
  # implicit for a repository-level ruleset — the restriction covers all pushes.

  rules {
    file_path_restriction {
      restricted_file_paths = var.workflow_restricted_paths
    }
  }

  # Sole bypass: the security team. These are the CODEOWNERS of .github/** —
  # the identities allowed to originate workflow changes. Everyone else
  # (maintainers, bots, org admins) is blocked from pushing to these paths.
  bypass_actors {
    actor_id    = github_team.security_team.id
    actor_type  = "Team"
    bypass_mode = "always"
  }
}
