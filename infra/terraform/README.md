# Terraform Security Controls Management

## Apply order (evaluate → validate → active)

3. `terraform init && terraform plan`
   `terraform apply -var 'ruleset_enforcement=evaluate'`
   `terraform apply -var 'ruleset_enforcement=active'`

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

## Rotating environment secrets/variables (gh cli)

The App private keys and `ORIGIN_POLICY_APP_ID` are deliberately NOT managed in
Terraform (would write the PEM into state — see `environments.tf`). Rotate them
out-of-band with `gh`:

```bash
# bot-automation environment (poc-ci-bot App)
gh secret set GH_LEGIT_APP_ID       --env bot-automation --repo <ORG>/<REPO> --body "<app-id>"
gh secret set GH_LEGIT_APP_PRIVATE_KEY --env bot-automation --repo <ORG>/<REPO> < /path/to/poc-ci-bot.private-key.pem

# origin-policy environment (gatekeeper App)
gh variable set ORIGIN_POLICY_APP_ID          --env origin-policy --repo <ORG>/<REPO> --body "<app-id>"
gh secret set   ORIGIN_POLICY_APP_PRIVATE_KEY --env origin-policy --repo <ORG>/<REPO> < /path/to/origin-policy-app.private-key.pem

# verify what's currently set (values are never readable back, names only)
gh secret list   --env bot-automation --repo <ORG>/<REPO>
gh variable list --env origin-policy  --repo <ORG>/<REPO>
```

Generate the new App key in the App's settings first (GitHub allows two
concurrent keys, so rotation is zero-downtime), set it here, confirm a run
succeeds, then delete the old key in the App settings.

