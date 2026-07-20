# RUNBOOK — manual steps for the four-eyes hardening POC

Steps that neither Terraform nor `bootstrap.sh` can perform, in the order
they must happen.

## 1. Prerequisites (one-time, manual)

> **Control note — App/bot creation is owner-gated.** Installing a GitHub App on
> the org (the only way a bot gains repo access) requires an **org owner**. A
> maintainer-level insider therefore cannot stand up a new bot to author PRs;
> combined with the bot-namespace locks (`rulesets.tf`) and workflow-authorship
> CODEOWNERS (`/.github/workflows/` → security-team), the set of automation
> identities is closed and change-controlled. Keep org membership admin count
> minimal and require approval for member-requested app installations
> (Org → Settings → GitHub Apps / OAuth App policy — UI only, no TF resource).

### 1.1 Create the IaC GitHub App

1. Org → Settings → Developer settings → GitHub Apps → **New GitHub App**.
2. Permissions:
   - Repository: **Administration: read/write**
   - Organization: **Administration: read/write**, **Members: read/write**
   - Repository + Organization: **Actions: read/write**
3. No webhook needed; disable it.
4. **Install the App on the org** (all repositories, or at least the POC repo
   plus org-level permissions).
5. Generate a private key; store the PEM **in the secrets manager only** —
   never on disk, never in git.
6. Record:
   - **App ID** → `var.iac_app_id`
   - **Installation ID** (from the installation URL or
     `gh api /orgs/<org>/installations`) → `var.iac_app_installation_id`
   - PEM → exported at apply time as `TF_VAR_iac_app_pem`.

### 1.2 Create Bot A — `poc-ci-bot` (well-configured, positive control)

1. New GitHub App named `poc-ci-bot`.
2. Permissions: **Contents: read/write**, **Pull requests: read/write** —
   nothing else.
3. Install it on the org **scoped to the POC repository only**.
4. Record its **installation ID** → `var.bot_namespaces.poc_ci_bot.app_id`.
5. Store its App ID and private key as **`bot-automation` environment** secrets
   under the exact names the workflow reads
   (`.github/workflows/poc-ci-bot.yml`): **`GH_LEGIT_APP_ID`** and
   **`GH_LEGIT_APP_PRIVATE_KEY`**. Environment-scoped (not repo-wide) so the key
   is released only to runs on protected branches (see `environments.tf`):
   ```
   gh secret set GH_LEGIT_APP_ID --env bot-automation --repo <ORG>/<REPO> --body "<app-id>"
   gh secret set GH_LEGIT_APP_PRIVATE_KEY --env bot-automation --repo <ORG>/<REPO> < poc-ci-bot.private-key.pem
   ```

### 1.3 Create the origin-policy App — `origin-policy` (fork PR gatekeeper)

1. New GitHub App named `origin-policy`.
2. Permissions: **Pull requests: read**, **Commit statuses: write** — no
   Contents, no Members. It never checks out code or writes to the repo; it
   only reads PR/review data and posts a commit status
   (`.github/workflows/origin-policy.yml`).
3. Install it on the org **scoped to the POC repository only**.
4. Record its App ID and private key as **`origin-policy` environment**
   variable/secret under the exact names the workflow reads
   (`.github/workflows/origin-policy.yml`): **`ORIGIN_POLICY_APP_ID`**
   (variable) and **`ORIGIN_POLICY_APP_PRIVATE_KEY`** (secret).
   Deliberately a *different* environment from `bot-automation` — that one
   carries a branch-scoped deployment policy meant for `poc-ci-bot`'s
   push flow, which would silently block this App's token on fork PRs
   (GitHub evaluates environment branch policies for fork-triggered
   `pull_request_target` runs against the PR merge ref, not the base
   branch). See `environments.tf`.
   ```
   gh variable set ORIGIN_POLICY_APP_ID --env origin-policy --repo <ORG>/<REPO> --body "<app-id>"
   gh secret set ORIGIN_POLICY_APP_PRIVATE_KEY --env origin-policy --repo <ORG>/<REPO> < origin-policy-app.private-key.pem
   ```

### 1.4 Create Bot B — `poc-rogue-bot` (negative control)

1. New GitHub App named `poc-rogue-bot` with intentionally broad
   **Contents: read/write** and no namespace discipline.
2. Install on the POC repo **only** — do not grant this App any privilege
   outside the POC repo.
3. Do **not** register it as a bypass actor anywhere. Its `app_id` in
   `var.bot_namespaces` stays `0` forever; it exists purely so test
   scenarios #7 and #8 can demonstrate that an unregistered bot is blocked.

### 1.5 Sign up test user accounts

- **This cannot be automated.** GitHub has no API for creating user
  accounts; each must be signed up manually at github.com (unique email,
  password, 2FA).
- **Recommendation: use the minimal identity set of two humans, not
  three** —
  1. one **org-member human** (plays attacker, codeowner-by-turns via team
     reassignment, and approver), and
  2. one **external fork-contributor human** (never joins the org).
  This halves the signup/2FA burden versus the three-account default in
  `var.test_users`. If you keep the three-account default, all three
  usernames must exist before `terraform apply`.
- Until the accounts exist, set `test_users = {}` in `terraform.tfvars`.

### 1.6 Accept org invitations

After the first `terraform apply` creates `github_membership` invitations,
**each invited user must accept manually** (email link or
github.com/orgs/&lt;org&gt;/invitation). Team membership resources may show
as pending until acceptance; re-apply afterwards if needed.

## 2. Apply order

1. `terraform apply -var 'ruleset_enforcement=evaluate'`
   — everything lands in observe-only mode.
2. `bash infra/bootstrap.sh` (with `ORG`/`REPO` set)
   — API-only Actions settings.
3. Run the scenarios in `infra/TEST_SCENARIOS.md`.
   **Expected:** the repo's *Rules → Insights* page shows
   **"would have been blocked"** entries; nothing actually blocks yet.
   Any scenario that does NOT produce an insight entry means the ruleset is
   miswired — fix before proceeding.
4. `terraform apply -var 'ruleset_enforcement=active'`
5. Re-run the test scenarios.
   **Expected:** every scenario now actually blocks (or is rejected by
   GitHub natively, per the scenario doc).

## 3. Audit log streaming (enterprise-level — manual, next phase)

There is no Terraform resource for enterprise audit-log streaming. When
ready: **Enterprise → Settings → Audit log → Log streaming** and configure
an endpoint (Splunk / Azure Event Hubs / S3 / Datadog…).

Wiring the stream into a SIEM with detection rules (e.g. alert on
`protected_branch.policy_override`, ruleset edits, bypass-actor changes) is
the **next-phase task and deliberately out of scope for this module** — this
POC only validates preventive controls.
