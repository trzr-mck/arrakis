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



