# Scenario 1: 
Based on: https://github.com/trezor/trezor-suite/pull/24825
Evidence PR: https://github.com/trzr-mck/arrakis/pull/47
<img width="1415" height="464" alt="image" src="https://github.com/user-attachments/assets/3170de54-9272-4a81-8184-f85d1312a6e7" />

This scenario assumes that bots are created with least privilege, proper scope and provisioned for specific needs. Therefore that there are multiple bots. If a bot has write access or PR creating abilities, it's credentials should be locked down and its use should be scoped to a workflow.

Also they assume that a regular contributor does not have access to credentials of the github bot -> therefore can't use it to manipulate repository. 

Evidence: 
Protection 1: User can't push to bot created branch. 
Protection 2: Even if he could (I would propose a different ruleset with a different bot), he can't approve it, as the last commit needs to be reviewed by someone else. 
<img width="793" height="81" alt="image" src="https://github.com/user-attachments/assets/d62d04fe-1213-4a58-9294-e9ba50bb4075" />
Protection 3: Require review from CODEOWNERS, first line of defense to protect workflows file. 
Protection 4: [Only possible in private repos] push-based ruleset to lock workflows with bypass only from security-team, which adds another layer of protection. 

When pushing to branches created by bots, a separate ruleset will be created enforcing only the review of last commit is enough. There are edge cases where it would be possible to commit to a branch and then let bot commit to the branch again, but that's about workflow / credential hygiene. Mechanisms to check this do not natively exist and their implementation would be a **"šelmostroj"**. 

# Scenario 2:
The same attack vector just via fork is handled. However, there's one vector that can't be handled. A malicious user creates a sockpuppet account, forks the repo, creates the PR and approves it from his own work account. 
The issue with this is that it can't be solved with native Github functionality. Branch rulesets only consider *target* branches, not source branches. Therefore trying to raise minimal PR count to 2 would increase it globally.
Also creating a separate branch to merge forks into would create overhead with reconciling splits between develop and fork-develop. 
The only thing that works for this usecase is a custom workflow, that is heavily guarded, runs only in context of the target branch and never executes user provided commands (should be also secure against command injection via metadata). 
This workflow is defined in a ruleset as a check required to pass the PR. 

<img width="901" height="534" alt="image" src="https://github.com/user-attachments/assets/b72a0329-a6cf-4d12-a3f8-bfc48c5f208c" />

In this PR it failed, because I was the last commiter, so I don't count towards approves.
[40](https://github.com/trzr-mck/arrakis/pull/49)
In this PR the chceks ran successfully:
[51](https://github.com/trzr-mck/arrakis/pull/51)
Sanity check:
[52](https://github.com/trzr-mck/arrakis/pull/52)
