# trzr-mck — Branch Protection POC

This is a **security-engineering proof-of-concept repository**, not a real
application. It exists to validate GitHub branch-protection / ruleset
configuration against a known bypass pattern: **self-approval via pushing to a
bot-authored PR branch**.

The application code is a throwaway fictional stand-in. There is no real
business logic, no real crypto/financial/auth code — just enough realistic
monorepo structure (pnpm workspace, one app + one shared lib) to exercise CI,
CODEOWNERS, and bot workflows.

## Why this repo exists

A malicious or compromised contributor with normal write access can defeat a
naive "N approvals" branch-protection rule two ways:

- **Vector A — push onto someone else's PR branch, then self-approve.**
  Trigger (or wait for) a bot-authored PR, push an extra commit onto its
  branch, then approve as yourself. A rule that only counts *approvals* — not
  *who pushed last* — treats your own approval as the second pair of eyes,
  because the PR's author-of-record is still the bot.
- **Vector B — open a fork PR from a sockpuppet account, approve it yourself.**
  One operator controls two identities: a throwaway external account (or a
  second, colluding human) opens a PR from a fork, and the operator's real org
  account approves it. If nobody pushes after that approval, a naive
  `require_last_push_approval` check is satisfied (the approver isn't the last
  pusher) — and one team-membership-based approval is enough to merge.

This repo, plus the Terraform in `../infra/terraform` and the collector in
`../infra/scripts`, is the fix: a GitHub ruleset + a custom App-backed status
check that close both vectors **without requiring 2 reviewers on every PR and
without disabling forks** (the target repo is meant to go public/OSS, where
forks are the only contribution path there is).

## Controls, in depth

| Control | Where | What it closes |
|---|---|---|
| `require_last_push_approval` | `infra/terraform/rulesets.tf` | The most recent pusher's own approval never counts, even if they aren't the PR's author-of-record. Closes the "push onto someone else's branch" half of Vector A. |
| `dismiss_stale_reviews_on_push` | `rulesets.tf` | Any existing approval is invalidated the instant new commits land, so an approval obtained *before* a hijacking push can't be reused after it. |
| Bot-namespace lock (`poc-ci-bot/**`) — `update`/`non_fast_forward`/creation blocked, sole bypass actor is the bot's own App installation | `rulesets.tf` (`bot_namespace` ruleset) | Removes Vector A's premise entirely: a human **cannot** push onto or create branches under the bot's namespace at all, regardless of the approval rules. Verified live — S4/S5 in the testing reports. |
| `origin-policy` custom App + required status check, pinned by `integration_id` (not just the check's string name) | `.github/workflows/origin-policy.yml`, environment `origin-policy` | Classifies every PR by **origin** (internal write-access author, scoped-bot branch, or fork/external) and requires **2** write-access approvals — excluding the author *and* whoever pushed the head commit — only on fork-originated PRs. Internal and scoped-bot PRs stay at the baseline of 1, so there's no blanket "2 reviewers everywhere" tax. Because the check is pinned to the App's numeric `integration_id`, a write-access user cannot forge a passing status by posting their own `origin-policy=success` (verified live — S9). |
| Empty `bypass_actors` on every ruleset (core, org-wide, both bot namespaces) | `rulesets.tf`, `org_rulesets.tf` | No silent break-glass for anyone, including org owners/admins. `gh pr merge --admin` on a zero-approval PR is rejected with a rule violation, not merged (verified live). |
| `can_approve_pull_request_reviews = false` + `default_workflow_permissions: read` | `bootstrap.sh` | A workflow's own `GITHUB_TOKEN` can never itself be the second reviewer. |
| Org-level ruleset applied to all repos + `members_can_create_repositories = false` | `org_rulesets.tf`, `org.tf` | Closes the "spin up a brand-new, unprotected repo" end-run — the four-eyes rules aren't opt-in per repo. |
| CODEOWNERS: `.github/**` and workflow authorship owned by `security-team` | `.github/CODEOWNERS` | The controls that enforce four-eyes are themselves change-controlled by a second team, not editable unilaterally by whoever wants to weaken them. |
| `ci.yml` on `pull_request` only, `contents: read`, never `pull_request_target` | `.github/workflows/ci.yml` | Untrusted fork code never runs with repo secrets or write access (CICD-SEC-4). |
| Fork-PR workflow-run approval (`fork-pr-contributor-approval = all_external_contributors`) | `bootstrap.sh` | A maintainer must explicitly approve a fork PR's Actions run before any of its workflow code executes at all — a second, independent gate from the merge-time approval count. |

Full asset/identity inventory, STRIDE-lite breakdown, and a line-by-line
configuration audit (12 gaps found and tracked, G1–G11) live in
[`../infra/THREAT_MODEL.md`](../infra/THREAT_MODEL.md).

## Testing suites

Two layers of testing validate the controls above:

1. **[`../infra/TEST_SCENARIOS.md`](../infra/TEST_SCENARIOS.md)** — the
   scenario catalog: 11 manual, falsifiable test cases (attack + positive
   control), each naming the identity to use, exact steps, and the specific
   rule under test. Designed to be run twice — once with
   `ruleset_enforcement = evaluate` (expect "would have been blocked"
   insights, nothing actually blocks) and again with `active` (expect real
   rejections) — see `../infra/RUNBOOK.md` §2 for the apply order.
2. **Dated evidence reports** (`../infra/Testing-<UTC-timestamp>.md`) — each a
   full live execution of the scenario catalog against the real repo, using
   three identities run inside disposable containers so no operator credential
   is ever touched directly:
   - `0x64nl` — org admin, drives everything needing an API token (`gh`).
   - a **write-access** collaborator, SSH-key-only, driven from an ephemeral
     `rbac-poc-test` container (`--rm`, key bind-mounted read-only).
   - a **read-only external** collaborator with an existing fork, same
     container pattern, never both users' keys mounted in one container run.

   Every entry records the actual command run and the actual GitHub response
   (`GH013` rule-violation text, API status payloads, PR URLs) — not just the
   expected outcome. The most recent report is the current source of truth;
   look for the highest timestamp in `../infra/Testing-*.md`.

   **What's fully live-exercised:** both named attack vectors end-to-end (the
   bot-branch hijack in all its forms, the fork-PR approval gate, forged
   required-status attempts, and — as of the latest run — an explicit
   `--admin`-flag break-glass attempt against a zero-approval PR).

   **What's structurally out of reach of this harness, by design:** the two
   test identities are SSH-only (no API token), which is deliberate — it
   proves the *real* RBAC boundary rather than some separately-scoped
   credential — but it also means a **second, independent PR review** can't be
   submitted by script. The "does a real second approval actually flip the PR
   to mergeable" and "does pushing after one real approval actually dismiss
   it" paths are therefore config-verified (read the ruleset's live settings
   directly) rather than click-by-click reproduced. Closing this requires
   either a manual pass with a second human reviewer, or issuing the write-user
   a scoped PAT for future runs — the latter trades a bit of blast radius for
   full automation and hasn't been done here on purpose.

## What can't be covered without adding friction

Two genuinely cooperating, vetted org members (**Vector B2** — two real
humans, not one operator with a sockpuppet) will always satisfy *any* N-eyes
rule, by definition — no branch-protection configuration can distinguish
"two independent reviewers" from "two willing collaborators." That residual is
accepted, not solved, and is only *raised in cost* and made *detectable*:

- **Raising the cost:** the fork-only 2-approval gate (rather than a blanket
  requirement) means collusion on an external contribution needs to buy off 2
  distinct write-access identities, not 1 — without taxing every ordinary
  internal PR.
- **Making it detectable, not preventable:** ruleset edits, bypass-actor
  changes, and protected-ref override attempts should stream to a SIEM for
  alerting (`repository_ruleset.update`, `bypass` actions, etc.) so collusion
  leaves an audit trail even though it can't be blocked at merge time. A
  collector for this (`../infra/scripts/github_audit_to_wazuh.py`) exists and
  is built, but **is not currently deployed** — treat it as a designed-but-not-
  running next step, not a live control, until it's actually stood up.

Options that *would* close B2 outright were deliberately **rejected** because
their friction cost outweighs the marginal security gain for this repo's
threat model:

| Rejected option | Why it was rejected |
|---|---|
| **Require 2 reviewers on every branch/PR, not just forks** | Doubles review latency and reviewer load on every single internal change, forever, to defend against a threat (two colluding trusted insiders) that a 2-reviewer rule doesn't even close — B2 is satisfied by exactly 2 colluders either way. All cost, no additional closure. |
| **Disable forks** | Not viable at all here: the production repo is meant to go **public/OSS**, where fork → PR is the *only* external contribution model there is. Blocking forks means blocking all outside contribution, which isn't a security trade-off, it's a different product. |
| **Require signed commits on protected branches** | Blocks external fork contributors outright — most don't have commit signing set up, and it's the mandatory path for an OSS repo. A bot-only signing exception is possible but doesn't rescue the human-forker case, so this was dropped in favor of audit-log non-repudiation instead. |
| **Org-wide 2FA/SSO/SCIM identity assurance** | This one is **not** rejected — it's recommended (closes the "free sockpuppet" root cause of Vector B1) but isn't Terraform-expressible via the `integrations/github` provider; it's an Enterprise/IdP UI configuration step, tracked as a manual follow-up rather than a merged control. |

See [`../infra/THREAT_MODEL.md`](../infra/THREAT_MODEL.md) §6–8 for the full
gap list, prioritized recommendations, and the residual-risk statement this
table summarizes.

## Layout

```
packages/
  lib/   test-package  — trivial shared formatter
  app/   test-app  — trivial entrypoint importing the lib
```

## Test fixtures

- `packages/app/src/components/HelloWorld.tsx` is a **trivial test fixture**
  with no real logic. It exists solely to be targeted by a single-user
  `CODEOWNERS` rule so we can validate CODEOWNERS review enforcement.

## Workflows

- `.github/workflows/ci.yml` — build/test on `pull_request` only. Read-only
  default permissions (`contents: read`). Never uses `pull_request_target`.
- `.github/workflows/poc-ci-bot.yml` — simulates a benign automation bot
  (`workflow_dispatch` only). Uses a GitHub App installation token to open a
  PR that updates `.github/poc-ci-bot/last-run.json` — a routine,
  legitimate-looking bot edit that happens to land in a security-team-owned
  path. That overlap is the point of the POC.
- `.github/workflows/origin-policy.yml` — the fork-gate classifier (see
  "Controls, in depth" above). Runs on `pull_request_target` +
  `pull_request_review` using a scoped App token (PR/review read, status
  write only — no `Contents` permission, never checks out code), and posts a
  required `origin-policy` status.

All `uses:` references are pinned to full 40-character commit SHAs with a
trailing human-readable version comment. The SHA values in this scaffold are
`*_SHA_PLACEHOLDER` tokens and **must be resolved before merging**, e.g.:

```
gh api repos/actions/checkout/git/ref/tags/v4.2.2
```

## Running / testing locally (Docker)

`test-app` has no HTTP server — it's a one-shot script that
imports the greeting formatter from `test-package` and logs the
result. Running it in Docker confirms the workspace installs correctly and
the entrypoint executes end-to-end; it does not stand up anything
long-running.

```bash
docker build -t four-eyes-poc-app .
docker run --rm four-eyes-poc-app
```

Expected output:

```
Hello, world!
```

The container installs the workspace, then runs
`pnpm --filter <app-name> start`, which uses `tsx` to execute
`packages/app/src/index.ts` directly (there is no compiled build output yet —
`build`/`test` are still no-op stubs, see Roadmap).

## Secrets

No real secrets, tokens, or credentials appear anywhere in this repo. Workflow
secrets are referenced by name via `${{ secrets.PLACEHOLDER_NAME }}` syntax
only.

## Roadmap

- **OIDC-based npm publish workflow** — intentionally deferred. Once OIDC
  trusted publishing is configured for the `trzr-mck` npm scope, a
  publish workflow will be added. It is deliberately omitted from this pass.
