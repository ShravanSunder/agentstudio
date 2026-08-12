# Repository-Branch Pull Request Facts — Specification

Requirements: [requirements.md](requirements.md)

## Observable Contract

R1. For a pane or sidebar worktree with a known repository and non-empty current branch, Agent Studio MUST use the PR facts for that exact `(repository ID, branch)` pair.

R2. Two worktrees at the same repository branch MUST present the same PR count and URL without duplicating independently owned facts.

R3. The pane GitHub control MUST be enabled and use the established active presentation only when an exact open-PR URL exists. Otherwise it MUST remain visible, disabled, and use the established neutral presentation. It MUST NOT fall back to the repository pull-request list.

R4. Before a branch has a confirmed GitHub result, its sidebar PR chip MUST present an unknown/not-fetched state using the existing `arrow.clockwise` system-symbol vocabulary, distinct from confirmed zero PRs. Entering demand MUST request a fetch and MUST NOT require a render action to start it.

R5. Automatic PR demand MUST be the union of worktrees represented by visible sidebar rows and worktrees represented by visible panes in the active tab. Hidden sidebar rows, inactive tabs, closed panes, and ordinary rendering MUST NOT create demand.

R6. When a demanded repository has no confirmed result, Agent Studio MUST request an immediate refresh. Thereafter automatic refresh MUST NOT begin until the repository's last successful result is at least three minutes old. Losing all demand MUST stop future automatic refreshes without discarding the last memory-only result.

R7. Demand changes, branch changes, origin changes, manual refresh, and a freshness deadline MAY request PR refresh through one admission path. For one repository, overlapping or burst requests MUST produce at most one active provider request and one pending follow-up refresh. Duplicate signals MUST NOT create an unbounded task, command, or event backlog. Manual refresh MAY bypass freshness but MUST obey the concurrency bound.

R8. One admitted repository refresh MUST query open PRs once for that repository and locally project results onto its demanded branches. It MUST NOT invoke one GitHub command per branch. A bounded or truncated response MUST NOT confirm an unmatched demanded branch as having zero PRs.

R9. A follow-up refresh MUST use the latest known origin and complete demanded-branch set. Results from an obsolete origin or superseded refresh generation MUST NOT become visible. Completion MUST also discard facts for requested branches that no longer have live worktree membership.

R10. Only a known-complete successful refresh MUST publish one repository-scoped result and update branch facts. Demanded branches with no matching open PR in that complete result MUST resolve to confirmed empty facts. Facts absent because a branch is no longer represented by any live worktree MUST be removed; merely losing visibility MUST NOT turn a confirmed result into unknown.

R11. Provider failure, timeout, cancellation, or rate limiting MUST NOT replace facts confirmed for the current origin with empty facts. Facts from a prior origin MUST NOT survive an origin change. Automatic retry MUST respect both provider backoff and the three-minute minimum; a later eligible trigger MUST allow recovery.

R12. Repository removal, origin change, or origin unavailability MUST clear that repository's prior-origin PR facts and cancel or invalidate its active and pending refresh work. Worktree removal alone MUST NOT clear shared branch facts still represented by another worktree.

## Proof Obligations

- Automated behavior: unknown versus confirmed-empty state, visible-demand union, three-minute admission boundary, repository batching, key isolation, branch switch, stale removal, unchanged-result suppression, and exact-URL enablement.
- Concurrency integration: many trigger kinds prove one active request plus at most one follow-up; an obsolete completion cannot publish.
- Pipeline integration: visibility demand reaches Forge without render-triggered calls, and one Forge result reaches toolbar/sidebar through repository-branch keys.
- Manual native proof: not-fetched chip transition, active/disabled toolbar color and icon, exact browser URL, and toolbar/sidebar agreement in the debug app.
