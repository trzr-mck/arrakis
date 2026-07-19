# trzr-mck — Branch Protection POC

This is a **security-engineering proof-of-concept repository**, not a real
application. It exists to validate GitHub branch-protection / ruleset
configuration against a known bypass pattern: **self-approval via pushing to a
bot-authored PR branch**.

The application code is a throwaway fictional stand-in. There is no real
business logic, no real crypto/financial/auth code — just enough realistic
monorepo structure (pnpm workspace, one app + one shared lib) to exercise CI,
CODEOWNERS, and bot workflows.

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
