# TEST SCENARIOS — falsification runbook

Manual validation of the ruleset configuration. Each scenario names the
identity to use, the steps to perform by hand, the expected control
behavior, and the specific rule being validated.

Run the full set twice: once with `ruleset_enforcement=evaluate` (expect
"would have been blocked" entries on *Rules → Insights*), then again with
`active` (expect real blocks). "Blocked" below describes the `active` run.

> These are descriptions of manual actions and expected control responses —
> not attack automation. Perform them only in the POC org.

**Identities** (minimal set per RUNBOOK §1.4):
- **M** — org-member human, `maintainers` team (write via team grant)
- **C** — org-member human, `security-team` / codeowner (may be M with
  team reassignment if using the two-account set — but scenarios #1 and #4
  need two distinct org members online, so pair up or use the 3-account set)
- **X** — external human, no org membership, interacts via fork
- **Bot A** — `poc-ci-bot` App; **Bot B** — `poc-rogue-bot` App

---

### 1. Self-approval after own push (core Trezor repro)
- **Identity:** M
- **Steps:** Trigger Bot A's `workflow_dispatch` to open a heartbeat PR
  against `develop`. As M, push any additional commit onto the bot's PR
  branch (if the namespace lock allows in evaluate mode), then approve
  the PR as M and attempt merge.
- **Expected:** Merge blocked — M is the most recent pusher, so M's
  approval does not satisfy the requirement.
- **Validates:** `require_last_push_approval`.

### 2. Human force-push to a bot namespace
- **Identity:** M
- **Steps:** `git push --force origin HEAD:poc-ci-bot/heartbeat-<id>`
  (any ref under `poc-ci-bot/`).
- **Expected:** Push rejected at the ref level — M is not the namespace's
  bypass actor (only Bot A's installation is).
- **Validates:** bot-namespace-lock ruleset (`update`/`non_fast_forward`
  with sole `Integration` bypass actor).

### 3. Stale approval after force-push
- **Identity:** M (author) + C (approver)
- **Steps:** M opens a PR from a normal feature branch; C approves it.
  M then pushes a further commit (or amend + force-push) to the PR branch
  and attempts merge on the old approval.
- **Expected:** C's approval is dismissed the moment the new commits land;
  merge blocked at 0 approvals.
- **Validates:** `dismiss_stale_reviews_on_push`.

### 4. Non-codeowner approval on a codeowner-gated path
- **Identity:** M (author) + any approver who is NOT `@0x64nl`
- **Steps:** M opens a PR modifying
  `packages/app/src/components/HelloWorld.tsx` (single-user codeowner fixture,
  owned by `@0x64nl` per CODEOWNERS last-match). A non-owner approves. Attempt
  merge.
- **Expected:** Merge blocked — the approval does not come from the file's
  designated code owner (`@0x64nl`).
- **Validates:** `require_code_owner_review` (+ CODEOWNERS last-match rule).

### 5. Fork PR + "allow edits by maintainers" self-approval (fork variant of #1)
- **Identity:** X (fork author) + M
- **Steps:** X forks the repo, opens a PR to `develop` with "allow edits by
  maintainers" checked. M pushes a commit directly onto X's fork head via
  that permission, then approves the PR as M and attempts merge.
- **Expected:** Merge blocked — M pushed last, so M's approval is invalid.
- **Validates:** `require_last_push_approval` on fork PR heads.

### 6. Bot A attempts to approve its own PR
- **Identity:** Bot A
- **Steps:** Using Bot A's installation token, attempt
  `gh pr review --approve` on a PR that Bot A itself authored.
- **Expected:** Rejected by GitHub natively — an actor cannot approve its
  own pull request.
- **Validates:** GitHub's built-in author-approval prohibition (baseline
  assumption of the whole model).

### 7. Bot B pushes into Bot A's namespace
- **Identity:** Bot B (`poc-rogue-bot`)
- **Steps:** Using Bot B's installation token, attempt to create or update
  a ref under `poc-ci-bot/`.
- **Expected:** Rejected — the namespace bypass is keyed to Bot A's specific
  App installation; Bot B is not a bypass actor anywhere.
- **Validates:** per-bot keying of the namespace-lock `bypass_actors`.

### 8. Bot B direct push to `develop`
- **Identity:** Bot B
- **Steps:** Using Bot B's installation token, attempt a direct
  `git push origin HEAD:develop`.
- **Expected:** Rejected — core ruleset requires a PR with approvals;
  Bot B has no bypass on the core ruleset (nobody does).
- **Validates:** core four-eyes ruleset applying to App identities, and the
  empty `bypass_actors` block.

### 9. Workflow `GITHUB_TOKEN` attempts PR approval
- **Identity:** any workflow in the repo using the default `GITHUB_TOKEN`
- **Steps:** Add a throwaway `workflow_dispatch` job step that runs
  `gh pr review --approve <PR>` with `GH_TOKEN: ${{ github.token }}`.
  Run it against any open PR. Delete the throwaway workflow afterwards.
- **Expected:** API call fails — Actions is barred from creating/approving
  PR reviews.
- **Validates:** `can_approve_pull_request_reviews=false` set by
  `bootstrap.sh` (org + repo).

### 10. Org admin merges with zero approvals
- **Identity:** org admin (owner account)
- **Steps:** As the org owner, open a PR to `develop` and attempt to merge
  it with no approvals (also try the "merge without waiting" / bypass UI
  affordances).
- **Expected:** Blocked identically to any member — no bypass affordance is
  offered because `bypass_actors` is empty on the core ruleset.
- **Validates:** empty `bypass_actors` (admins are bound; proves there is no
  silent break-glass).

### 11. Fork PR merged on a single approval (Vector B1)
- **Identity:** X (fork author) + C (one org approver)
- **Steps:** X forks the repo and opens a PR to `develop`. C approves once.
  Attempt merge with only that single approval.
- **Expected:** Merge blocked — the `fork-review-policy` required status check
  fails at 1/2 approvals. Add a second distinct org approver → the check flips
  to success and merge is allowed. Repeat as an *internal* branch PR (non-fork):
  the check passes at a single approval (baseline count applies).
- **Validates:** the fork-only 2-approval gate (`fork-review-policy.yml` +
  `fork-review-policy` in `var.required_status_checks`). Confirms a sockpuppet
  fork + one colluding approver cannot merge, while internal-PR overhead is
  unchanged.

---

## Result matrix

| # | Scenario | Rule under test | Evaluate run | Active run |
|---|---|---|---|---|
| 1 | Self-approval after own push | `require_last_push_approval` | insight logged | blocked |
| 2 | Human push to bot namespace | namespace lock | insight logged | blocked |
| 3 | Stale approval after push | `dismiss_stale_reviews_on_push` | insight logged | blocked |
| 4 | Non-codeowner approval | `require_code_owner_review` | insight logged | blocked |
| 5 | Fork-head push + self-approve | `require_last_push_approval` | insight logged | blocked |
| 6 | Bot self-approval | GitHub native | rejected (always) | rejected |
| 7 | Rogue bot → bot namespace | bypass keyed to App ID | insight logged | blocked |
| 8 | Rogue bot → develop | core ruleset, empty bypass | insight logged | blocked |
| 9 | GITHUB_TOKEN approval | `can_approve_pull_request_reviews` | rejected (always)¹ | rejected |
| 10 | Admin zero-approval merge | empty `bypass_actors` | insight logged | blocked |
| 11 | Fork PR on single approval | `fork-review-policy` check | check fails² | blocked |

¹ Scenarios 6 and 9 are not ruleset-driven, so they hard-fail even during
the evaluate phase — that is expected and correct.

² Scenario 11 is enforced by a required status check, not the ruleset, so the
check itself fails independently of `ruleset_enforcement`; the *merge* is only
blocked on that failing check once the ruleset is `active` (required checks are
part of the ruleset). In `evaluate`, expect the red check + a "would have been
blocked" insight.
