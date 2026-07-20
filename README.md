# Scenario 1

Based on: https://github.com/trezor/trezor-suite/pull/24825

[Evidence PR:] https://github.com/trzr-mck/arrakis/pull/47

<img width="1415" height="464" alt="image" src="https://github.com/user-attachments/assets/3170de54-9272-4a81-8184-f85d1312a6e7" />

This scenario assumes that bots are created with least privilege, proper scope, and are provisioned for specific needs. Therefore, there are multiple bots. If a bot has write access or PR creation abilities, its credentials should be locked down and its use should be scoped to a single workflow.

It also assumes that a regular contributor does not have access to the credentials of the GitHub bot, and therefore cannot use it to manipulate the repository.

## Evidence

**Protection 1:** A user can't push to a bot created branch.

**Protection 2:** Even if they could (a different ruleset with a different bot would be needed for that), they can't approve it, since the last commit needs to be reviewed by someone else.

<img width="793" height="81" alt="image" src="https://github.com/user-attachments/assets/d62d04fe-1213-4a58-9294-e9ba50bb4075" />

**Protection 3:** Require review from CODEOWNERS, the first line of defense to protect workflow files.

When pushing to branches created by bots, a separate ruleset will be created that only enforces review of the last commit. There are edge cases where it would be possible to commit to a branch and then let the bot commit to the branch again, but that comes down to workflow and credential hygiene. Mechanisms to check for this do not natively exist, and implementing them would be a **"selmostroj"**.


# Scenario 2

The same attack vector, via a fork, is handled. However, there is one vector that can't be handled: a malicious user creates a sockpuppet account, forks the repo, creates the PR, and approves it from their own work account.

The issue is that this can't be solved with native GitHub functionality. Branch rulesets only consider the *target* branch, not the source branch. Raising the minimum PR review count to 2 would therefore increase it globally.

Creating a separate branch to merge forks into would also introduce overhead from reconciling splits between `develop` and `fork-develop`.

The only thing that works for this use case is a custom workflow that is heavily guarded, runs only in the context of the target branch, and never executes user-provided commands (it should also be secure against command injection via metadata). This workflow is defined in a ruleset as a required check for the PR to pass.

<img width="901" height="534" alt="image" src="https://github.com/user-attachments/assets/b72a0329-a6cf-4d12-a3f8-bfc48c5f208c" />

- In [PR #49](https://github.com/trzr-mck/arrakis/pull/49), the check failed because I was the last committer, so my approval didn't count.
- In [PR #51](https://github.com/trzr-mck/arrakis/pull/51), the checks ran successfully.
- [PR #52](https://github.com/trzr-mck/arrakis/pull/52) is a sanity check.
- [PR #59](https://github.com/trzr-mck/arrakis/pull/59) left open for you. 
