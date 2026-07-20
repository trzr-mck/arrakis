# THREAT MODEL — Four-Eyes / Bot-Namespace Hardening POC

**Repo under test:** `trzr-mck/arrakis` (a.k.a. `four-eyes-poc`)
**Config sources:** `infra/terraform/*`, `infra/bootstrap.sh`, `ci-cd-interview/.github/*`
**Framework:** OWASP CICD-SEC Top 10 (extends the CICD-SEC mapping already annotated across the Terraform)
**Scope:** Full config-surface audit — the two named attack vectors plus every gap that materially affects the four-eyes / insider-threat objective.
**Enforcement state at time of writing:** `ruleset_enforcement = evaluate` (`terraform.tfvars:20`) — controls are **observe-only**, not blocking.

> Objective (from the exercise brief): model two insider/compromise attacks and
> identify configuration gaps needed to mitigate them *entirely*:
> **A.** a contributor pushes onto a bot-authored PR branch, then self-approves,
> defeating four-eyes; **B.** a fake account forks the repo, opens a PR, and it is
> merged on the approval of the operator's "work" account.

---

## 1. System overview

### 1.1 Assets (what an attacker wants to reach)
| Asset | Where | Why it matters |
|---|---|---|
| Protected branch history (`develop`, `main`, `release/**`) | `variables.tf:72-76` | Merging here = shipping code; the whole four-eyes gate exists to protect this. |
| Bot App installation token (`poc-ci-bot`) | env `bot-automation` secrets (`environments.tf:55-83`) | Mints a `Contents:write` identity that can push to the bot namespace. |
| IaC App private key (`porcupine-tf-provider`) | `terraform.tfvars:14` → on-disk PEM | Org+repo **admin**; owning it = owning the controls themselves. |
| CODEOWNERS + ruleset definitions | `rulesets.tf`, `.github/CODEOWNERS` | Editing either weakens the gate; both are change-controlled via PR. |

### 1.2 Identities & trust boundaries
| Identity | Trust | Grant |
|---|---|---|
| Org **admin/owner** | Highest | Bound by the ruleset — `bypass_actors` is empty (`rulesets.tf:58-68`). |
| **maintainers** team member | Write | `push` on the repo (`teams.tf:51-55`); default CODEOWNER for `*` (`CODEOWNERS:5`). |
| **security-team** member | Write + codeowner | Owns `/.github/**`, manifests (`CODEOWNERS:8-14`). |
| **poc-ci-bot** (Bot A) | Scoped automation | Sole bypass actor on its own namespace (`rulesets.tf:107-114`). |
| **poc-rogue-bot** (Bot B) | Negative control | `app_id = 0`; bypass nowhere (`variables.tf:103-107`). |
| **External fork contributor (X)** | Untrusted | No org membership; interacts via fork; CI gated (`bootstrap.sh:61-71`). |
| Workflow `GITHUB_TOKEN` | Machine | Cannot approve PRs (`bootstrap.sh:35-47`). |

**Primary trust boundary:** the pull-request merge gate onto protected branches.
Every attack below is an attempt to cross it with fewer than two genuinely
independent human reviewers.

---

## 2. Threat actors & assumptions

- **TA-1 — Malicious insider (single operator).** Holds one legitimate org
  identity (write). May also control secondary identities (a bot, a sockpuppet
  external account). Goal: land code with only self-review.
- **TA-2 — Two colluding insiders.** Two distinct humans, each with a
  legitimate identity, cooperating. This is the design ceiling of four-eyes.
- **TA-3 — Compromised account.** An attacker who has stolen one contributor's
  credentials/session; behaves as TA-1 with that identity.

**Baseline assumptions that must hold (else the model is void):**
- GitHub natively forbids a PR author from approving their own PR (validated by
  scenario #6).
- 2FA is enforced org-wide. **Not currently expressed in Terraform — see G4.**
- The IaC App key is confidential. **Currently on disk — see G8.**

---

## 2.5 Deployment-model constraint — PUBLIC repo, forks are mandatory

The POC repo is private, but the **production repo is public**, and the only
contribution model for external contributors is **fork → PR**. This is a
first-class constraint, not an implementation detail, and it bounds the whole
model:

- **Forks cannot be prevented or restricted.** Any external account can fork a
  public repo into its *personal* namespace at will. Controls premised on
  "block external contribution" or "require org membership to open a PR" are
  invalid. Security lives entirely on the **review side** (org members), never
  the contribution side.
- **Identity assurance reaches only org members.** 2FA/SSO/SCIM (G4) can be
  enforced on *approvers*, never on fork authors. The sockpuppet *fork author*
  in Vector B1 is anonymous **by design** — so the defence is the number and
  assurance of the **approvers**, which is why `required_approving_review_count
  = 2` is load-bearing here, not optional polish.
- **`members_can_create_repositories = false` does not touch forks.** Forks land
  in personal namespaces, not the org; that control (G2) governs *org* repos and
  remains valid. The org ruleset governs the **target** protected branch at
  merge time regardless of PR origin, so fork PRs are still fully gated.
- **Signed commits are NOT required (dropped).** `required_signatures` would
  block external fork contributors, who typically cannot sign — the mandatory
  contribution path. A bot-only exception is possible (a separate signatures
  ruleset with the bot App as a `bypass_actor`), but it does not rescue the
  human-forker case, so signing is left off entirely. Non-repudiation for the
  two-colluder case (B2) is instead pursued via audit-log streaming (R6), not
  commit signatures.
- **Approval count cannot vary by PR source natively.** Rulesets key
  `required_approving_review_count` to the target branch, not fork-vs-internal.
  Baseline stays **1** (low internal overhead; Vector A is closed by the
  namespace lock, not a 2nd approval). The extra approval Vector B1 needs is
  applied to **fork PRs only** via a custom required status check (§ G3).
- **Untrusted fork *code* is the added attack surface (CICD-SEC-4).** Handled
  by: `ci.yml` on `pull_request` (never `pull_request_target`) with
  `contents: read`; env-scoped bot secrets released only to protected-branch
  runs (`environments.tf`); and `fork-pr-contributor-approval =
  all_external_contributors` (`bootstrap.sh`) requiring a maintainer to approve
  *workflow runs* before fork code executes.

---

## 3. Attack Vector A — push-to-bot-branch, then self-approve ("Trezor" bypass)

### 3.1 Flow
1. TA-1 (a `maintainers` member) triggers Bot A's `workflow_dispatch`, which
   opens a bot-authored heartbeat PR (`poc-ci-bot.yml:39-54`).
2. TA-1 pushes an extra commit onto the bot's PR branch `poc-ci-bot/heartbeat-*`.
3. Because TA-1 is *not the PR author of record* (the bot is), a naive
   "1 approval" rule would count TA-1's own approval as the second pair of eyes.
4. TA-1 approves and merges.

### 3.2 STRIDE-lite decomposition → CICD-SEC
| Step | Category | CICD-SEC |
|---|---|---|
| Push onto another identity's PR branch | **Tampering** with the review subject | CICD-SEC-1 (flow control) |
| Self-approval counted as independent | **Elevation** (1 human → "2 eyes") | CICD-SEC-1 |
| Bot identity used as author-of-record cover | **Spoofing** of review independence | CICD-SEC-5 (PBAC) |

### 3.3 Controls in place (this attack is **covered** when enforcement is `active`)
| Control | File | Effect |
|---|---|---|
| `require_last_push_approval = true` | `rulesets.tf:40` | TA-1 is the last pusher → their approval no longer satisfies the requirement. Scenario #1. |
| `dismiss_stale_reviews_on_push = true` | `rulesets.tf:41` | Any prior approval dies when TA-1's commit lands. Scenario #3. |
| Bot-namespace lock (`update`/`non_fast_forward`, sole `Integration` bypass) | `rulesets.tf:84-115` | TA-1 (a human) cannot push into `poc-ci-bot/**` at all. Scenario #2/#7. |
| `can_approve_pull_request_reviews = false` | `bootstrap.sh:35-47` | CI itself can never be the second reviewer. Scenario #9. |
| Empty `bypass_actors` on core ruleset | `rulesets.tf:58-68` | Even org admins get no self-merge affordance. Scenario #10. |

**Residual for Vector A:** *low, once `active`* — the last-push-approval rule
collapses the single-operator case structurally. Remaining residual is TA-2
(two colluders), handled in §5.

---

## 4. Attack Vector B — fake-account fork + merge

The brief frames this two ways; per your instruction both are modelled as
distinct branches.

### 4.1 Branch B1 — single operator + sockpuppet (TA-1)
One human controls **both** the "work" org account **and** a throwaway external
account.

1. Sockpuppet `X` forks `arrakis`, opens a PR to `develop`.
2. Operator's org account (a `maintainers` member) reviews and approves.
3. If nobody pushes after approval and `X` remains the last pusher, then
   `require_last_push_approval` is **satisfied** (approver ≠ last pusher), and a
   single codeowner approval from the operator's own team merges it.

**This is the critical finding.** Four-eyes counts *identities, not humans*.
Vector B1 is **not** closed by the ruleset as configured, because:
- `required_approving_review_count = 1` (`rulesets.tf:39`) — one approval suffices.
- The default codeowner is `@trzr-mck/maintainers` (`CODEOWNERS:5`), and the
  attacker persona is itself a `maintainers` member (`variables.tf:122-138`) —
  so the operator's org account *is* a valid codeowner for the general code path.
- `require_last_push_approval` is defeated, not by pushing, but by simply **not
  pushing** — the two identities look like two people.

| Step | Category | CICD-SEC |
|---|---|---|
| Sockpuppet identity created | **Spoofing** of a second human | CICD-SEC-2 (IAM) |
| Fork PR from untrusted origin | Untrusted input | CICD-SEC-4 (poisoned pipeline execution, if CI runs) |
| One-person "two-eyes" approval | **Elevation** | CICD-SEC-1 |

**Partial mitigations present:** `fork-pr-contributor-approval =
all_external_contributors` (`bootstrap.sh:61-71`) forces a maintainer to approve
*workflow runs* for external forks — but (a) this gates CI execution, not merge,
and (b) the same colluding maintainer can grant it. `ci.yml` never uses
`pull_request_target` (README) so fork code can't read secrets. Neither stops
the merge.

### 4.2 Branch B2 — two independent colluders (TA-2)
Two distinct humans, one external (fork) + one org maintainer/codeowner. This is
the theoretical ceiling of any N=1 approval scheme: two cooperating humans
satisfy any "two independent eyes" rule by definition. **No preventive branch
control can close B2**; it is addressed only by (a) raising the approval bar so
collusion requires *more* participants, (b) diversifying required codeowners
across teams, and (c) *detective* controls + accountability (audit-log
streaming, non-repudiation via signed commits). See §6 recommendations R2–R6.

**Residual for Vector B:** **HIGH as configured** (B1 not closed; B2 only
raisable, never eliminable). Closing B1 to the maximum practical degree is the
main hardening work below.

---

## 5. Control coverage matrix

| Control | Vector A | Vector B1 | Vector B2 | CICD-SEC |
|---|:--:|:--:|:--:|---|
| `require_last_push_approval` | ✅ closes | ⚠️ bypassed by not-pushing | ❌ | 1 |
| `dismiss_stale_reviews_on_push` | ✅ | ➖ | ❌ | 1 |
| Bot-namespace lock | ✅ | ➖ | ➖ | 5 |
| Empty `bypass_actors` | ✅ | ✅ | ✅ (no admin shortcut) | 1 |
| `require_code_owner_review` | ✅ | ⚠️ attacker *is* a codeowner | ❌ | 2 |
| `required_approving_review_count = 1` | ➖ | ❌ one approval merges | ❌ | 1 |
| Fork workflow-run approval | ➖ | ⚠️ approvable by colluder | ❌ | 4 |
| `can_approve_pull_request_reviews=false` | ✅ | ➖ | ➖ | 6 |
| Identity assurance (2FA/SSO/SCIM) | ➖ | **❌ absent (G4)** | ⚠️ raises cost | 2 |

Legend: ✅ closes · ⚠️ partial/bypassable · ❌ no coverage · ➖ n/a.

---

## 6. Configuration gaps (full config-surface audit)

Severity reflects impact on the four-eyes / insider-threat objective.

### G1 — Required status checks have no producer workflow **[High — correctness]**
`required_status_checks = ["build","test"]` with
`strict_required_status_checks_policy = true` (`rulesets.tf:46-55`,
`variables.tf:78-82`), but **`ci.yml` does not exist** — the workflows dir
contains only `poc-ci-bot.yml`. The README (`ci-cd-interview/README.md:28-30`)
documents a `ci.yml` producing `build`/`test`, but it is absent.
**Impact:** in `active` mode, no PR can ever report these contexts → merges block
indefinitely (fail-closed, so not dangerous, but the "build/test gate" is
illusory and operators may be tempted to *remove* the requirement — a
weakening). The required contexts are also unbound to a specific workflow, so any
future workflow emitting a `build`/`test` check name satisfies them.
**Fix:** add the `ci.yml` that emits exactly `build` and `test` on
`pull_request`; keep it `contents: read` and never `pull_request_target`.

### G2 — No org-level ruleset; members can create unprotected repos **[High]**
All rulesets are `github_repository_ruleset` scoped to the single `poc` repo
(`rulesets.tf:20-21,84-90`). `github_organization_settings` blocks only *public*
repo creation (`org.tf:15`), leaving **private/internal** repo creation open to
members. A member can create a new repo with **zero** branch protection and
merge freely.
**Impact:** the objective says "mitigate this attack vector *entirely*" — that
requires org-wide coverage, not one repo. New repos are an unguarded flank.
**Fix:** add a `github_organization_ruleset` (target `branch`, applied to `all`
repositories) carrying the same four-eyes rules, and set
`members_can_create_repositories = false` (or restrict to
`private` + require the org ruleset) in `github_organization_settings`.

### G3 — Single approval + maintainers-as-codeowners lets a 2-account pair pass **[High — design]**
`required_approving_review_count = 1` (`rulesets.tf:39`) plus the default
codeowner being `@trzr-mck/maintainers` (`CODEOWNERS:5`), of which the attacker
persona is a member (`variables.tf:122-138`), means one maintainer identity
approving one sockpuppet/colluder PR merges to `develop`. This is the mechanism
behind Vector B1.
**Fix:** raise `required_approving_review_count` to **2**; require the reviewers
to come from **different teams** on sensitive paths (e.g. security-team must
co-sign anything touching `/.github/**` and manifests — already owned there, but
extend the principle). Two approvals forces collusion to involve ≥2 extra
identities, materially raising cost.

### G4 — No enforced identity assurance (2FA / SSO / SCIM) **[High — design/fundamental]**
Nothing in the Terraform enforces org-wide 2FA, SAML SSO, or SCIM-provisioned
membership. `github_organization_settings` (`org.tf:8-19`) sets repo-permission
defaults but no `advanced_security`/identity guarantees, and there is no
`github_organization_security_manager`/SSO resource.
**Impact:** four-eyes counts identities. Without identity assurance, minting a
sockpuppet (Vector B1) is free, and a stolen credential (TA-3) is
indistinguishable from a real reviewer. This is the *root* enabler of B1 and the
cost-floor for B2.
**Public-model caveat:** identity assurance can only be enforced on **org
members (the approvers)**, never on external fork authors (§2.5). It therefore
does not stop a sockpuppet from *opening* a fork PR — it ensures every
*approval* comes from a vetted, non-repudiable corporate identity. Combined with
G3 (2 approvals), the fork author's anonymity stops mattering because the merge
requires two assured approvers who are not the last pusher.
**Fix:** enforce org-wide 2FA (`Settings → Authentication security → Require
two-factor`), require SAML SSO + SCIM so every identity maps to a vetted
corporate principal, and restrict org invitations to admins. Consider requiring
**verified** commit signatures on protected branches (there is
`web_commit_signoff_required` at `org.tf:18`, but that is a sign-*off* checkbox,
not cryptographic signing — add a `required_signatures` rule to the ruleset).

### G5 — Bot-secret name drift between RUNBOOK and live config **[Medium — operational]**
The workflow and environment reference `GH_LEGIT_APP_ID` /
`GH_LEGIT_APP_PRIVATE_KEY` (`poc-ci-bot.yml:21-22`, `environments.tf:61-65`), but
`RUNBOOK.md:33-35` instructs setting `GH_APP_ID_PLACEHOLDER` /
`GH_APP_PRIVATE_KEY_PLACEHOLDER`.
**Impact:** following the RUNBOOK sets the secrets under names the workflow never
reads → the bot fails to mint a token, and the positive-control scenarios (#1)
cannot be reproduced. Silent-fail operational gap.
**Fix:** align `RUNBOOK.md §1.2` to the `GH_LEGIT_*` names actually consumed.

### G6 — Bot PR base branch contradicts the test scenario **[Medium — test fidelity]**
The bot opens its PR with `--base main` (`poc-ci-bot.yml:53`), but scenario #1
(`TEST_SCENARIOS.md:24-32`) says the heartbeat PR is "against `develop`", and
`develop` is the default branch (`repo.tf:33-41`).
**Impact:** both branches are protected so the *control* still applies, but the
scenario as written won't reproduce against the branch the bot actually targets
— a validation-integrity gap that can mask a real miswire.
**Fix:** make the bot target `develop` (or update scenario #1 to say `main`);
pick one and keep them consistent.

### G7 — Scenario #4 references a renamed fixture **[Medium — test fidelity]**
Scenario #4 targets `packages/app/src/components/ConfirmActionModal.tsx`
(`TEST_SCENARIOS.md:54-56`); that file was renamed to `HelloWorld.tsx`, which is
what exists on disk and is owned by the **single user** `@0x64nl`
(`CODEOWNERS:17`), not a team.
**Impact:** the scenario cannot be executed verbatim, and its wording ("a
non-codeowner maintainer approves") now describes a *single-user* codeowner path,
which is a stronger fixture than it reads. Anyone running the runbook hits a
missing file.
**Fix:** update scenario #4 to `HelloWorld.tsx` and reword to reflect the
single-user (`@0x64nl`) codeowner under test.

### G8 — App private keys in plaintext on disk (not committed) **[Medium — CICD-SEC-6]**
`legitimo-bot.2026-07-18.private-key.pem` and
`porcupine-tf-provider.2026-07-18.private-key.pem` sit in plaintext in
`infra/terraform/`, and `terraform.tfvars:14` deliberately points
`iac_app_pem_file` at one of them. This **contradicts** `RUNBOOK.md:19-24`
("store the PEM in the secrets manager only — never on disk, never in git").
- *Mitigating facts:* both `.gitignore` files exclude `*.pem`
  (`infra/terraform/.gitignore`, `ci-cd-interview/.gitignore`), and `infra/` is
  **not a git repo** — so these are **not committed**. This is an on-disk
  exposure, not a VCS leak.
- *Compounding:* because `infra/` is not under version control at all, the
  security-critical config itself has **no change history / no review trail** —
  ironic for a four-eyes POC, and a governance gap in its own right.
**Fix:** for the IaC App, drop `iac_app_pem_file` and inject
`TF_VAR_iac_app_pem` from a secrets manager (the tfvars comment already
prescribes this). For the bot key, set it via `gh secret set` as
`environments.tf:60-65` documents and delete the on-disk PEM. Put `infra/` under
git so the controls are themselves change-controlled.

### G9 — Enforcement is `evaluate`, not `active` **[Medium — state, expected]**
`ruleset_enforcement = evaluate` (`terraform.tfvars:20`). All ruleset controls
are observe-only; nothing blocks. This is the correct *first* phase per the
RUNBOOK, but until the `active` re-apply (RUNBOOK §2.4), **every Vector-A/B
control above is non-blocking**.
**Fix:** complete the evaluate→active promotion after the evaluate-run insights
are verified; treat "still in evaluate" as an open risk in any status report.

### G10 — Terraform state backend is local **[Low]**
The S3 backend is commented out (`providers.tf:22-28`), so state (which encodes
the ruleset + bypass wiring) lives locally and unversioned. `providers.tf:14-20`
itself notes "tampering with state is equivalent to tampering with the
controls."
**Fix:** enable the encrypted, versioned, access-restricted remote backend
before this is anything but a throwaway sandbox.

### G11 — (checked, not a gap) Actions allowlist vs. `create-github-app-token`
The org allowlist lists only `actions/checkout@*` and `actions/setup-node@*`
(`variables.tf:145-149`), and the bot workflow additionally uses
`actions/create-github-app-token` (`poc-ci-bot.yml:19`). This is **permitted**
because `github_owned_allowed = true` (`org.tf:29`) covers the entire `actions/`
org. No change needed — recorded here so it isn't re-flagged.

---

## 7. Prioritised recommendations

Status: ✅ implemented in this pass · 🟡 partial (Terraform done, manual step remains) · ⛔ not Terraform-expressible (manual).

| # | Recommendation | Closes | Status |
|---|---|---|---|
| R1 | Add the missing `ci.yml` emitting `build`/`test`, fork-safe (`pull_request`, `contents: read`). | G1 | ✅ `ci-cd-interview/.github/workflows/ci.yml` (non-TF) |
| R2 | Add an **org-level** four-eyes ruleset over all repos + block member repo creation. | G2, Vector-B flank | ✅ `org_rulesets.tf`, `org.tf` |
| R3 | Keep baseline approvals at **1**; require a **2nd approval on FORK PRs only** via a custom policy check. Cross-team codeowners on sensitive paths still recommended. | G3, B1 without internal overhead | ✅ baseline `= 1`; `fork-review-policy.yml` + `fork-review-policy` in `required_status_checks`; codeowner diversity ⛔ (CODEOWNERS) |
| R4 | Enforce org-wide **2FA + SAML SSO + SCIM**; restrict invitations to admins. Applies to **approvers only** (§2.5). | G4, root of B1 | ⛔ not in `integrations/github` provider — Enterprise/Org security UI + IdP |
| R5 | ~~Require signed commits~~ **dropped** — blocks external fork contributors (§2.5). Non-repudiation pursued via R6 instead. Bot-only signing exception is possible but does not rescue human forkers. | — | ⛔ n/a (removed) |
| R5a | Restrict GitHub App/bot creation + workflow authorship to security-team. | CICD-SEC-2/5 hygiene | ✅ explicit `/.github/workflows/ → security-team` CODEOWNERS; app-install owner-gating documented (RUNBOOK §1). OAuth/app-request approval ⛔ (UI only) |
| R6 | Stand up **audit-log streaming → SIEM** with detection on ruleset edits, `bypass_actor` changes, `protected_branch.policy_override` (the *only* lever against B2). | Vector B2 residual | ⛔ Enterprise audit-log streaming — no TF resource (RUNBOOK §3) |
| R7 | Move App keys to a secrets manager; delete on-disk PEMs; put `infra/` under git. | G8 | 🟡 TF already supports `TF_VAR_iac_app_pem` injection; key deletion + `git init` are manual |
| R8 | Fix doc/config drift: secret names (G5), scenario #4 fixture (G7); bot base branch (G6). | Test fidelity | ✅ G6 (`--base develop`), G5 (RUNBOOK `GH_LEGIT_*`), G7 (scenario #4 → `HelloWorld.tsx`) |
| R9 | Promote `ruleset_enforcement` to `active` after the evaluate run; enable remote state. | G9, G10 | ⛔ operational (`terraform apply` / backend values) |

---

## 8. Residual risk statement

With **R1–R5 and R7–R9** applied and enforcement `active`:
- **Vector A** (single-operator self-approval): **closed** by
  `require_last_push_approval` + namespace locks + empty bypass actors.
- **Vector B1** (sockpuppet fork): **substantially closed** — 2 approvals +
  identity assurance (SSO/SCIM/2FA) make a free throwaway account no longer
  count as a second reviewer, and cross-team codeowners prevent one team's
  member from single-handedly satisfying the gate.
- **Vector B2** (two genuine colluding humans): **not preventable by
  construction.** Two cooperating vetted humans satisfy any 2-eyes rule. It is
  only *mitigated* — cost raised (R3), and made *detectable/attributable* via
  R6 (audit streaming + SIEM) and R5 (signed commits). Accept this as documented
  residual; it is an accountability/detection problem, not a branch-protection
  one.

## 9. OWASP CICD-SEC coverage summary

| CICD-SEC | Addressed by | Gaps |
|---|---|---|
| 1 — Insufficient flow control | core ruleset, empty bypass | G1, G3 |
| 2 — Inadequate IAM | teams, default read perm | G3, **G4** |
| 4 — Poisoned pipeline execution | fork-run approval, no `pull_request_target` | G1 (no CI present) |
| 5 — Insufficient PBAC | bot-namespace locks, scoped Actions perms | — |
| 6 — Credential hygiene | secret scanning + push protection, env-scoped bot key | **G8** |
| 7 — Insecure system config | org Actions allowlist, read-only `GITHUB_TOKEN` | G9 (evaluate mode) |
| 8 — Ungoverned 3rd-party use | Actions allowlist (`selected`) | — |

*CICD-SEC-3 (dependency chains), -9 (improper artifact integrity), -10 (insufficient logging) are out of scope for this preventive-controls POC; -10 is the subject of the deferred audit-streaming phase (R6 / RUNBOOK §3).*
