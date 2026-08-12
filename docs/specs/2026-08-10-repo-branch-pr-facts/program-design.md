# Repository-Branch Pull Request Facts — Program Design

Requirements: [requirements.md](requirements.md)
Specification: [specification.md](specification.md)

## Owners

- `ForgeActor` owns tracked origin and worktree-to-branch membership plus the per-repository refresh lifecycle.
- `RepoEnrichmentCacheAtom` owns memory-only `RepoBranchKey -> PullRequestFacts` state and content-equal keyed observation.
- `WorkspaceSurfaceCoordinator` derives one demand snapshot from existing sidebar-visible worktrees and visible panes of the active tab, and sends it only when content changes through `WorkspaceFilesystemSourceManaging` and `FilesystemGitPipeline` to Forge.
- `WorkspaceCacheCoordinator` projects Forge refresh and invalidation events into the cache; it does not own demand or map PRs onto worktrees.
- Pane and sidebar projections resolve `worktree -> repository + current branch -> RepoBranchKey` before reading facts.

`RepoBranchKey` contains `repoId` and the exact non-empty branch string. `PullRequestFacts` contains open count and the exact open PR URL when one exists.

## Demand and Bounded Refresh Flow

```text
visibility / branch / origin / manual / freshness deadline
                 |
                 v
       ForgeActor.requestRefresh(trigger)
                 |
        +--------------+----------------+
        | no demand     | fresh < 3 min |
        v              v                |
      no work        no work            | stale/missing
                                        v
                              one active request
                                        |
                              more eligible triggers
                                        v
                               one pending follow-up
                              |
                              | repeated triggers only
                              | update latest scope
                              v
                     no additional task/event

completion -> reject if origin/generation obsolete
           -> intersect requested branches with current live membership
           -> otherwise emit one complete repository result
           -> record successful freshness time
           -> if pending, clear it and start one refresh
              only if latest demand remains eligible
```

The trigger is a small value describing repository, cause, and whether freshness may be bypassed. Every current and future cause calls the same admission function; it does not own separate tasks or timers. Admission checks current demand, freshness, provider backoff, generation, active request, and pending state. This is the extension seam for later trigger events, not a generalized GitHub-data framework.

The actor remains the state serialization boundary, but it does not await provider work in its event-consumption path. Each repository has at most one provider call in flight and one Boolean pending refresh, not a queue. A single next-deadline task sleeps until the earliest demanded repository becomes three minutes old; it is rescheduled when demand or successful freshness changes. There is no periodic all-repository tick.

`WorkspaceSurfaceCoordinator` owns a `withObservationTracking` loop for pull-request demand, following its existing App-owned activity-observation pattern. The observation reads `SidebarVisibleWorktreesRuntimeAtom.visibleWorktreeIds`, the active tab and arrangement, management-layer state, drawer views, zoom presentation and companion facts, pane-to-worktree context, and the bound workspace window's `WindowPresentationFacts`. A pure `PullRequestDemandProjection` function resolves the pane set with the same rules as `SingleTabContent`: active arrangement, management-mode minimization, expanded drawer active children, and zoom source plus visible companion. It excludes inactive tabs, zoom-excluded layout panes, minimized panes outside management mode, collapsed or minimized drawer children, and the entire sidebar/pane union when the bound window is hidden, miniaturized, or occluded. It does not read `ViewRegistry`; existing SwiftUI `surfaceRenderedIds` callbacks remain render bookkeeping and never create GitHub demand.

The coordinator compares the projected worktree-ID set with its last delivered set before forwarding. `WorkspaceFilesystemSourceManaging.setPullRequestDemandWorktrees` is the single App-to-runtime boundary; `FilesystemGitPipeline` forwards the set to `ForgeActor.setDemand(worktreeIds:)`. The pipeline performs no freshness or refresh policy. Forge resolves demanded IDs through its membership records, groups distinct non-empty branches by repository, and admits refreshes. Empty demand is delivered on window hiding, minimization, occlusion, tab/layout transitions, and shutdown, so future automatic work stops without deleting facts.

Forge maintains one membership record per live worktree containing worktree ID, repository ID, standardized path, and optional current branch. The existing `WorkspaceSurfaceCoordinator -> WorkspaceFilesystemSourceManaging.register/unregister -> FilesystemGitPipeline` lifecycle edge is membership identity authority: the pipeline forwards registration and unregistration to Forge using the same worktree ID, repository ID, and path it already receives. A `snapshotChanged` event, whose snapshot carries ID, repository, path, and branch, upserts the same record and supplies or repairs its branch. `branchChanged` updates the record named by its worktree ID. Path-only `worktreeDiscovered` may update the branch only when its standardized path matches an existing membership; it never creates an ID. Path-only `worktreeRemoved` never deletes or invalidates membership because it cannot distinguish an old worktree from a replacement registered at the same path. Identity-bearing lifecycle unregistration alone removes membership; repeated or reordered unregistration is idempotent by worktree ID. No topology lookup, path-event ordering state, or new membership service is introduced.

The requested branch set is the distinct non-empty branches derived from current memberships. When a switch or removal eliminates the final membership for a branch, Forge emits `pullRequestBranchesInvalidated(repoId:branches:)`; if another worktree still represents that branch, it emits no invalidation. Demand loss alone never changes membership and never emits invalidation.

The provider runs one `gh pr list --repo ... --state open --json headRefName,url --limit 200` command per admitted repository refresh. A result below the cap is complete for projection. A result at the cap is treated as potentially truncated: Forge emits a bounded refresh failure and preserves prior/unknown facts rather than confirming unmatched branches empty. Forge initializes every demanded branch to confirmed empty only from a complete result and maps matching returned rows locally. Branch discovery updates membership without refreshing unless it is demanded; an actual demanded branch change requests refresh. Registration with no demanded branches records the origin but does not call the provider.

## Result and Invalidation Flow

```text
complete Forge result for refreshed branches
  -> one pullRequestsChanged(repoId, byBranch) event
  -> coordinator normalizes open facts for event keys
  -> cache merges only those refreshed RepoBranchKey values
  -> keyed revisions change only where content changed
  -> toolbar/sidebar recompute only for affected RepoBranchKey readers

final live membership leaves branch
  -> pullRequestBranchesInvalidated(repoId, branches)
  -> cache removes exactly those RepoBranchKey values

origin loss/change or repository removal
  -> cache removes every RepoBranchKey for that repository
```

The provider task captures origin, generation, and demanded branch set. The repository-wide CLI response is totalized locally against that set before emission. Event keys therefore identify only the branches confirmed by that refresh; absence from the event is not deletion authority. `RepoEnrichmentCacheAtom.applyPullRequestFacts(repoId:factsByBranch:)` changes only those keys. Only `pullRequestBranchesInvalidated` or repository-wide origin/removal invalidation deletes retained facts. Thus refreshing demanded branch A cannot change hidden-but-live branch B; B is removed only when its final live membership leaves.

Failure preserves only facts confirmed for the current origin. The provider returns a narrow typed outcome: success, rate-limited with optional retry-after, or ordinary failure. Forge stores repository backoff until `max(lastAutomaticAttempt + 3 minutes, retryAfter)`; when retry-after is unavailable, the three-minute minimum is the fallback. Automatic triggers before eligibility only maintain one pending intent and schedule the next deadline. Origin change, origin loss, and repository removal advance generation, cancel or invalidate the active task, clear pending work, backoff, and cached prior-origin facts, and then allow the new origin to refresh. Shutdown cancels all child tasks before clearing actor state. A worktree branch change changes the consumer's key immediately; it does not copy or mutate PR facts.

## Hard Cutover

Remove worktree-keyed PR count/URL state, `RepoWorktreeCacheFacts.pullRequestCount`, coordinator fan-out, and worktree-keyed PR persistence. Do not add branch persistence. Existing git enrichment remains worktree-keyed and unchanged.

## Current-to-Target Call Edges

```text
DEMAND
[=] RepoExplorer visible-row reporting
    -> SidebarVisibleWorktreesRuntimeAtom
[+] WorkspaceSurfaceCoordinator observation
    -> PullRequestDemandProjection (pure model/window-state read)
    -> WorkspaceFilesystemSourceManaging.setPullRequestDemandWorktrees
    -> FilesystemGitPipeline -> ForgeActor.setDemand
    <- actor admission only; provider completion returns through ForgeEvent
[-] SwiftUI ViewRegistry/surfaceRenderedIds -> any Forge demand effect
[~] demand / branch / origin / manual / deadline trigger
    -> ForgeActor.requestRefresh -> one admission function
    -> one repository-wide provider request
    <- typed success / rate limit / ordinary failure
[-] per-branch provider commands and 45-second global polling

MEMBERSHIP
[=] WorkspaceSurfaceCoordinator source sync
    -> WorkspaceFilesystemSourceManaging.register/unregister
[+] FilesystemGitPipeline -> ForgeActor register/unregister membership
[~] Git snapshot/branch events -> Forge worktree-ID membership update
[~] path-only discovery -> update a matching known branch or no-op
[-] path-only removal -> any membership or branch invalidation effect
    <- branch invalidation event only after final membership leaves

FACT APPLICATION
[~] ForgeActor -> pullRequestsChanged(refreshed branches)
    -> WorkspaceCacheCoordinator -> cache merge for event keys
[+] ForgeActor -> pullRequestBranchesInvalidated(final departed branches)
    -> WorkspaceCacheCoordinator -> exact branch-key removal
[-] coordinator branch-to-worktree fan-out and repository replacement
[=] origin loss/change and repository removal -> repository-wide fact clear
```

Current evidence for these edges is `WorkspaceSurfaceCoordinator+FilesystemSource.swift`, `FilesystemGitPipeline.swift`, `GitWorkingDirectoryProjector+Emission.swift`, `RuntimeEnvelopeCore.swift`, `WorkspaceSurfaceCoordinator+BridgePaneActivity.swift`, `SingleTabContent.swift`, `WindowLifecycleAtom.swift`, `ForgeActor.swift`, and `WorkspaceCacheCoordinator.swift`.

## Failure, Concurrency, and Proof Seams

- Generation plus captured origin and branch set rejects late obsolete completions.
- Actor isolation owns active/pending transitions; no locks or second coordinator are introduced.
- Provider timeout remains at the existing process boundary; failure emits diagnostics and retains confirmed facts.
- An injected monotonic clock proves the exact `< 3 minutes` versus `>= 3 minutes` admission boundary without wall-clock sleeps.
- A controllable provider proves one CLI call per repository, cap/truncation rejection, typed rate-limit suppression/recovery, event ingestion during an active call, cross-trigger active/pending bounds, latest-demand follow-up, cancellation/invalidation, and emitted-event count.
- Membership tests prove registration/snapshot ordering, discovery before/after identity establishment, shared-branch reference behavior, switch, lifecycle unregistration idempotency, path-only removal has no effect, delayed old path removal cannot delete a replacement identity, origin change, and repository removal.
- Demand projection tests prove visible-sidebar union exact rendered-active-tab behavior across minimization, management mode, expanded/collapsed drawers, zoom source/companion, hidden windows, tab switching, and suppression of unchanged snapshots.
- Atom tests prove unknown/confirmed-empty distinction, A-only refresh preserves hidden-but-live B, final B membership removal prunes B, and content-equal writes do not bump unrelated keys; integration and native proof cover the consumer path.
