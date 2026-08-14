# Repository-Branch Pull Request Facts — Requirements

## Need

Agent Studio users need the visible pane toolbar and visible repository sidebar rows to agree about the pull request for a worktree's current branch, without spending GitHub API or CPU on hidden work or repeated triggers.

## Outcomes

- PR identity is `(repository, branch)`, shared by every worktree on that branch.
- The toolbar opens the exact open PR and is disabled when no exact URL exists.
- Sidebar PR state comes from the same fact.
- Before first fetch, the sidebar communicates that PR state is unknown rather than implying no PR.
- Only worktrees visible in the sidebar or visible panes of the active tab create automatic demand.
- A demanded repository is automatically refetched only when its last successful PR result is at least three minutes old.
- Refresh work is repository-batched and bounded, stale results never replace current-origin results, and failures do not erase the last confirmed facts.

## Boundaries

- Reuse the existing Forge actor, runtime event, coordinator, topology, cache, command presentation, and GitHub CLI provider.
- Keep Forge PR-only in this change while leaving one trigger-admission path that later events can call.
- PR facts may remain memory-only.
- No global repository polling, CLI watch process, new service, persistence, or worktree-keyed compatibility path.
- This design does not change general git-status refresh policy or GitHub authentication.
