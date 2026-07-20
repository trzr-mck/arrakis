# RM
Manages the GitHub org/repo controls that defeat the Trezor-style
self-approval bypass. Authenticates as a **GitHub App installation**
(`app_auth`) — no PATs anywhere.

## Apply order (evaluate → validate → active)

1. Complete the manual prerequisites in `../RUNBOOK.md` (create the IaC App
   and both bot Apps, sign up test users, collect IDs).
2. `cp terraform.tfvars.example terraform.tfvars`, fill it in; inject the
   App key via `TF_VAR_iac_app_pem` from your secrets manager.
3. `terraform init && terraform plan`
4. **First apply — observe only:**
   `terraform apply -var 'ruleset_enforcement=evaluate'`
5. `bash ../bootstrap.sh` (API-only settings the provider doesn't cover).
6. Run `../TEST_SCENARIOS.md`. In evaluate mode, expect **"would have been
   blocked"** rows on the repo's *Rules → Insights* page, not actual blocks.
7. **Flip to enforcing:**
   `terraform apply -var 'ruleset_enforcement=active'`
8. Re-run the test scenarios — every scenario must now actually block.

## Rotating the IaC App key

1. In the org's App settings, **generate a new private key** (GitHub allows
   two concurrent keys, so this is zero-downtime).
2. Store the new PEM in the secrets manager under a new version.
3. Update `TF_VAR_iac_app_pem` sourcing to the new version; run
   `terraform plan` to confirm auth works.
4. **Delete the old key** in the App settings.
5. Record the rotation in the change log. Rotate on a fixed cadence (90 days)
   and immediately on any suspicion of exposure.

## Resource → OWASP CI/CD Top 10 mapping

| Resource | Control | Mitigates |
|---|---|---|
| `github_repository_ruleset.four_eyes_core` | `require_last_push_approval`, `dismiss_stale_reviews_on_push`, 1 approval, code-owner review, empty `bypass_actors` | **CICD-SEC-1** Insufficient Flow Control Mechanisms |
| `github_organization_settings` | `default_repository_permission = "read"`, no member-created public repos | **CICD-SEC-2** Inadequate Identity & Access Management |
| `github_team*` resources | Write access only via explicit team grants | **CICD-SEC-2** |
| `github_repository_ruleset.bot_namespace` | Bot branch prefixes locked to the owning App installation only | **CICD-SEC-5** Insufficient PBAC (pipeline identities can only write where registered) |
| `github_repository.security_and_analysis` | Secret scanning + push protection | **CICD-SEC-6** Insufficient Credential Hygiene |
| Provider `app_auth` (no PATs), PEM via env only | Short-lived installation tokens instead of long-lived PATs | **CICD-SEC-6** |
| `ruleset_enforcement` staging + empty `bypass_actors` + `non_fast_forward`/`deletion` | No unaudited loosening path; history immutable on protected refs | **CICD-SEC-7** Insecure System Configuration |
| `github_actions_organization_permissions` | `allowed_actions = "selected"` allowlist, enforced org-wide (no repo-level override — see note below) | **CICD-SEC-8** Ungoverned Usage of 3rd Party Services |
| `../bootstrap.sh` (`default_workflow_permissions=read`, `can_approve_pull_request_reviews=false`) | `GITHUB_TOKEN` cannot write or approve PRs | **CICD-SEC-5** / **CICD-SEC-2** |

## Notes

- **CODEOWNERS is not managed by Terraform** — it lives in the repo and is
  edited via PR, which itself exercises the ruleset.
- **Terraform cannot create user accounts.** `github_membership` only invites
  existing accounts; invitations are accepted manually. Keep
  `test_users = {}` until the accounts exist on github.com.
- `bot_namespaces.*.app_id` is the App **installation** ID used as the
  `Integration` bypass actor. `poc_rogue_bot.app_id` stays `0` by design —
  it is never a bypass actor anywhere (negative control).
- State is security-critical: see the commented S3/DynamoDB backend block in
  `providers.tf`.
- **No repo-level `github_actions_repository_permissions` resource.** Once
  `github_actions_organization_permissions.org` enforces `allowed_actions =
  "selected"` org-wide, GitHub returns `409` on any attempt to set a repo-level
  `selected-actions` pattern list independently (confirmed against the REST
  API docs — a repo cannot override an org-enforced allowlist, not a
  transient error). The org-level allowlist already governs this repo.
