# PR0 Review Comparison — Program Design

> Comparison-target discovery, catalog transport, bounded candidate production,
> and selector materialization are superseded by
> [`../2026-08-10-bridge-review-comparison-target-loading/program-design.md`](../2026-08-10-bridge-review-comparison-target-loading/program-design.md).
> This document remains authoritative for durable target intent, comparison
> calculation, publication, invalidation, and comparison-origin realization.

## What this design realizes

This Program Design realizes the observable contract in
[`pr0-specification.md`](./pr0-specification.md), authorized by
[`pr0-user-requirements.md`](./pr0-user-requirements.md).

PR0 changes how Review View defines, selects, refreshes, identifies, and
presents a worktree comparison. It does not implement annotations in this PR;
PR1 consumes the origin contract added here to implement them. The design
keeps three kinds of state separate:

```text
┌─ Selected target intent ─────────────────────────────────────────┐
│ durable pane: BridgePaneState in core.sqlite                    │
│ Zoom companion: BridgePaneState in its retained controller      │
│ lifetime: pane restore, or retained Zoom companion lifetime      │
└──────────────────────────────────────────────────────────────────┘

┌─ Transient comparison attempt ──────────────────────────────────┐
│ freshly resolved target OID + HEAD OID + contribution-base OID │
│ lifetime: cancelled or superseded                               │
└──────────────────────────────────────────────────────────────────┘

┌─ Published snapshot ────────────────────────────────────────────┐
│ immutable origin + file set + content identities               │
│ lifetime: may remain visibly stale                              │
└──────────────────────────────────────────────────────────────────┘
```

The smallest sufficient structure is:

1. keep comparison intent in the existing Bridge pane state, persisted when
   that pane belongs to the durable workspace graph;
2. add one bounded Review-target catalog read and one correlated contribution
   read to `agentstudio-git`;
3. carry captured comparison origin in the existing Review package and
   metadata stream;
4. use the existing Bridge product-call path for the Review header control;
5. extend existing filesystem invalidation for repository-wide Git history
   changes.

No new database, table, service, daemon, IPC endpoint, comparison-history
store, or general review lifecycle is introduced. The later
[Incremental Review Git Refresh design](../2026-09-03-incremental-review-git-refresh/2026-09-03-program-design.md)
supersedes only this design's no-Git-result-cache mechanism with one bounded,
opaque calculation seed owned by the existing Review calculation lifecycle.

## Current system constraints

The design is compatibility-bound by these current owners and call paths:

- `BridgePaneState` is encoded as pane content and restored through the
  existing workspace `core.sqlite` payload route.
- `WorkspacePaneGraphAtom` is the in-memory authority for durable pane content;
  App and feature callers mutate it through the existing `WorkspacePaneAtom`
  facade.
- `WorkspaceSurfaceCoordinator` creates each `BridgePaneController` from that
  pane content.
- three App paths currently create workspace-backed Bridge pane sources: the
  dedicated Review opener used the cached main-worktree checkout name or a
  `HEAD` fallback, the ordinary File View opener hardcodes `main`, and the Zoom
  companion uses the same cached-checkout-or-`HEAD` resolver as Review. None of
  those paths reads a repository-designated default branch.
- `BridgePaneController` currently captures an immutable `bridgePaneState` and
  builds Review endpoints from its stored `WorkspaceBaseline`.
- contribution-shaped baselines currently become a resolved Git-ref endpoint
  directly compared with the working tree; this is the target-tip behavior
  PR0 replaces.
- the controller's full-load path checks its Review generation, while the
  publication coordinator, refresh admission, and cancellation supply their
  existing admission boundaries. Source invalidation does not yet advance the
  Review generation before queued catch-up, and the catch-up path does not read
  that generation.
- the current catch-up Review path rebuilds from the committed package's
  already-resolved endpoints and original generation. It cannot re-resolve a
  living contribution target, HEAD, or contribution base.
- an unresolved legacy `ref("HEAD")` full load currently retries as
  a different comparison meaning. PR0 removes that fallback.
- Review metadata already resets to a full snapshot when package source
  identity or endpoints change.
- `{packageId, reviewGeneration, revision}` already identifies a published
  Review snapshot, and content handles already identify file-side content.
- BridgeWeb already has a Review header-control slot, owned shadcn-style menu
  primitives, and a typed product-call path whose session commits a call
  effect, applies its native committed-call handler, and only then returns the
  response.
- the current `pane.presentation` frame carries only native activity and
  refreshing lanes; it has no comparison pending/stale/unavailable facts.
- raw filesystem events already identify repository/worktree and whether Git
  internals changed, but Review refresh currently targets only the exact event
  worktree.
- the standalone Bridge development server builds the production
  `AgentStudioBridge` target, which already depends on `AgentStudioCore`, plus a
  thin Hummingbird carrier. It deliberately does not build or boot the
  `AgentStudio` executable, App resources, windows, Terminal/Ghostty, or sibling
  feature targets.
- the development host currently invents pane/repository/worktree identities
  and treats `--worktree + --base` as comparison authority. It does not hydrate
  or flush the production workspace store, so it cannot prove durable intent.

Source anchors:

- `Sources/AgentStudio/Core/Models/BridgePaneState.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/CoreAtoms.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreFactory.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeReviewOpening.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ZoomCompanion.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeViewLifecycle.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+RefreshAdmission.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+ReviewProductPublication.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewFoundation/AgentStudioGitBridgeReviewDataClient.swift`
- `Sources/AgentStudio/Features/Bridge/Models/ReviewFoundation/BridgeReviewPackage.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductReviewMetadataSource.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSchemeControlDispatcher.swift`
- `Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductSchemeProvider.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneRefreshAdmissionCoordinator.swift`
- `Sources/AgentStudio/Features/Bridge/Models/Transport/BridgeProductStreamFrame.swift`
- `Sources/AgentStudio/Features/Bridge/Runtime/Development/BridgeDevelopmentProductHost.swift`
- `Sources/AgentStudioBridgeDevelopmentServer/AgentStudioBridgeDevelopmentServerMain.swift`
- `Sources/AgentStudioBridgeDevelopmentServer/BridgeDevelopmentHTTPApplication.swift`
- `BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx`
- `BridgeWeb/src/app/bridge-viewer-content-header.tsx`
- `BridgeWeb/src/review-viewer/shell/review-viewer-shell.tsx`
- `Package.resolved` pin `fdeb5b3e822f49e97b44df6d9267565d8c353f7d`
- pinned `agentstudio-git` contracts and implementations:
  `AgentStudioGitSDK.swift`, `GitStatusContracts.swift`,
  `GitDiffContentContracts.swift`, `LibGit2BranchReader.swift`,
  `LibGit2RevisionResolver.swift`, and `LibGit2DiffReader.swift`

## Component ownership

Reader question: which existing owner gains which responsibility, and why does
each boundary exist?

```text
Agent Studio App
│
├─ WorkspacePaneGraphAtom                          durable authority
│    owns: one BridgePaneState per pane
│    adds: typed Bridge-pane-state mutation and one atomic
│          set-initial-contribution-target-if-absent mutation
│    changes when: persisted comparison intent changes
│
├─ WorkspacePaneAtom                               mutation facade
│    owns: the supported caller path into the pane graph
│    adds: typed Bridge-pane-state mutation forwarding
│    changes when: pane callers gain a supported mutation
│
├─ WorkspaceSurfaceCoordinator                     App composition owner
│    owns: Review-capable pane construction and Core mutation injection
│    adds: selection-required initial intent, injected commit callback,
│          controller-lifetime Zoom callback, and repository-wide Git
│          invalidation routing
│    changes when: App-level pane/runtime composition changes
│
├─ BridgePaneController                            active runtime coordinator
│    owns: active attempt, refresh, stale/current presentation facts
│    adds: guarded initial-default lookup on the existing initial Review-load
│          trigger, committed-intent adoption, contribution request
│          construction, and same-repository Git-internal invalidation admission
│    changes when: one pane's Review runtime behavior changes
│
├─ BridgePaneProductCommittedCallTarget             committed-call adapter
│    owns: forwarding a protocol-committed Review call to its active controller
│    adds: comparison-intent apply forwarding
│    changes when: committed Bridge product calls reach pane runtime differently
│
├─ BridgePaneRefreshAdmissionCoordinator            presentation order owner
│    owns: monotonic pane-presentation revision and activity/refresh facts
│    adds: controller-supplied Review comparison presentation slice
│    changes when: admitted pane presentation changes
│
├─ BridgePaneProductSchemeProvider                  product transport owner
│    owns: correlated control responses and committed-effect dispatch
│    adds: comparison update call case
│    changes when: BridgeWeb product calls cross the native boundary
│
├─ BridgeDevelopmentProductHost                     focused Debug composition
│    owns: Core + Bridge-only development runtime behind the HTTP carrier
│    adds: exact persisted-pane hydration and durable committed-intent callback
│    changes when: the focused Bridge development journey changes
│
├─ AgentStudioGitBridgeReviewDataClient            Bridge ↔ Git adapter
│    owns: mapping one correlated Git result into Review endpoints, files, and origin
│    adds: contribution request/result mapping
│    changes when: Bridge and agentstudio-git contracts meet differently
│
├─ Bridge resolved-contribution request builder     shared pure mapping
│    owns: intent + captured Git result + subject label → one resolved
│          pipeline request and comparison origin
│    consumed by: BridgePaneController and BridgeDevelopmentProductHost
│    changes when: prepared contribution data enters Review differently
│
├─ agentstudio-git local client                     sole Git semantics owner
│    owns: recorded default designation, local/remote-tracking branch catalog,
│          ref/HEAD resolution, unique merge base, base→working-tree diff
│    adds: one bounded Review-target catalog read and one correlated
│          contribution read
│    changes when: native Git read semantics change
│
├─ BridgeReviewPipeline                             sole package assembly owner
│    owns: consuming prepared comparison data and building Review packages
│    adds: one prepared-contribution input path that skips endpoint comparison
│    changes when: Review comparison data enters package assembly differently
│
├─ BridgeReviewPackage + metadata source           snapshot contract owner
│    owns: immutable origin + files + content IDs + publication identity
│    adds: discriminated comparison origin and reviewed-subject display label
│          on snapshot/reset
│    changes when: Review snapshot meaning changes
│
└─ BridgeWeb Review View                           human interaction owner
     owns: visible subject/kind/target/pending/stale/unavailable presentation
     adds: origin-aware title and compact Branch/Commit comparison selector in
           the existing header
     changes when: reviewer interaction or presentation changes
```

Dependency rules:

- BridgeWeb requests changes; it never becomes the comparison owner.
- For a durable pane, `BridgePaneController` may mirror only an App-committed
  pane intent. It must not maintain a second independently writable target.
  A Zoom companion has no durable pane-graph member, so its retained controller
  owns that companion's target for the same lifetime as the companion.
- `BridgePaneProductCommittedCallTarget` forwards a committed call; it does not
  validate targets, write pane state, or own refresh policy.
- `BridgePaneRefreshAdmissionCoordinator` orders the combined presentation;
  it does not decide comparison meaning or persist intent.
- For durable panes, `WorkspaceSurfaceCoordinator` and the focused development
  host write through `WorkspacePaneAtom`, which forwards to canonical
  `WorkspacePaneGraphAtom`; neither Bridge runtime may bypass that path to
  claim persistence. The initial-default write evaluates target absence inside
  the pane-graph mutation; a controller-side check followed by an unconditional
  durable write is forbidden. Zoom supplies an explicit transient callback
  instead of treating a missing pane-graph member as a persistence failure.
- dedicated Review, ordinary File View, and Zoom-companion creation all start
  with no fabricated target. No pane creator may write a literal `main`, the
  main worktree's current checkout, or automatic `HEAD` into durable comparison
  intent.
- `BridgePaneController` may request one initial default only while contribution
  target intent remains absent. The request reads through the existing Review
  Git provider and asks App/Core to conditionally commit any identified target.
  `WorkspacePaneGraphAtom` rechecks target absence and writes in one
  non-suspending `MainActor` mutation, so a late result cannot overwrite reviewer
  intent.
- Bridge code consumes Git DTOs through `AgentStudioGitBridgeReviewDataClient`;
  it does not shell out or reimplement merge-base policy.
- `BridgeReviewPipeline` remains the only Review package assembler. Neither the
  provider nor the shared-template binder builds a second package path.
- snapshot metadata is captured data. Menu-open state is not snapshot origin
  and must not be stored in it.

## Pane intent stores the selected target, not calculated Git results

Reuse the workspace pane's existing durable `WorkspaceBaseline?` slot as the
symbolic contribution-target intent. Extend its target-bearing cases with the
matching `WorkspaceReviewContributionTarget` vocabulary:

```text
nil                                           selection requires attention
localDefaultBranch(branchName)                moving local branch
originDefaultBranch(remoteName, branchName)   moving remote-tracking branch
branch(name)                                  moving selected branch
ref(name)                                     other symbolic Git reference
commit(oid)                                   pinned exact commit
```

The invariants are:

- a non-nil target-bearing baseline resolves that symbolic target afresh;
- nil means selection requires attention and no fallback target is fabricated;
- reviewer selection replaces the target through `WorkspacePaneGraphAtom`;
- persistence stores only the symbolic target, never its resolved target, HEAD,
  or contribution-base OID;
- restoration resolves the saved branch/ref or exact commit target afresh, as
  required by P0-R8.

Staged-only and unstaged-only selection or persistence are outside PR0. Their
existing baseline cases remain compatibility data and are not redesigned by
this change.

Every path that creates a Review-capable workspace Bridge pane constructs the
same selection-required comparison intent: the dedicated Review opener, the
ordinary File View opener, and the Zoom companion. On the same existing initial
Review-package-load trigger used for every foreground workspace-backed Bridge
pane, `BridgePaneController` asks its existing Git provider for the repository's
designated remote-tracking default. This includes File View panes because their webview can
switch to Review and the current controller deliberately prepares Review before
that switch. If one is identified, a durable pane asks App/Core to conditionally
commit its `origin/<branch>` target; a Zoom companion adopts it in its retained
controller state. If no designation or matching
remote-tracking branch exists, the intent remains selection-required. PR0 adds
no separate Review-surface-activation hook.

The initial lookup is asynchronous and carries the controller's current intent
generation. Before requesting its write, the controller requires that the pane
admission and lookup generation are current. For a durable pane, the App/Core
callback atomically writes only if contribution target intent is still absent
and returns the canonical intent or an explicit not-applied disposition. For a
Zoom companion, the injected callback returns canonical controller-local state;
the same controller admission prevents a retired companion from accepting it.
A reviewer selection, restore with a retained durable target, pane or companion
retirement, or a newer lookup makes the result ineligible. This reuses the
controller's existing task/admission lifetime and the existing Bridge Git-read
scheduler; PR0 adds no App task registry, default-branch cache, watcher, or
background service.

For a stored File or Review pane this is durable product intent because restore
behavior depends on it. A Zoom companion is intentionally absent from the
durable pane graph: its selected target survives hide and re-entry while the
companion controller is retained, then disappears when that companion is
retired. Menu open/closed state, highlighted control options, draft text,
focus, and temporary selection are BridgeWeb-local UI state and are not
persisted.

The selected target is the only Git selection persisted with the pane: branch
and ref variants retain symbolic names, while the commit variant retains its
exact OID. Resolved branch target, HEAD, and contribution-base OIDs are
calculated from current Git state for each attempt and captured in the resulting
immutable snapshot. They are not restored as current truth. If the Git data
plane retains calculation material, it is disposable acceleration, not pane
authority or snapshot evidence. PR0 originally added no Git-result cache; the
later
[Incremental Review Git Refresh design](../2026-09-03-incremental-review-git-refresh/2026-09-03-program-design.md)
defines the bounded opaque seed that supersedes that mechanism while preserving
fresh identity resolution.

The intent stays inside the existing `BridgePaneState`: the workspace Core
repository stores it for durable panes, while the retained Zoom controller
holds the same state shape without joining the pane graph. PR0 adds a typed
`updateBridgePaneState` mutation to `WorkspacePaneGraphAtom` and exposes it
through `WorkspacePaneAtom`; it adds no SQL table or migration.

The comparison intent belongs to the shared Bridge pane source because a File
View pane can enter its Review surface. File View continues to browse and
render from the existing workspace root; it does not apply contribution
comparison semantics until Review is active. PR0 therefore does not add a
parallel File View source model or change File View rendering behavior.

## Captured comparison origin is immutable snapshot data

Add a discriminated origin to `BridgeReviewPackage` and to the Review metadata
snapshot/reset contract:

```text
BridgeReviewComparisonOrigin.contribution
  selected branch/ref kind + name or pinned commit OID
  resolved target OID
  reviewed HEAD OID
  unique contribution-base OID
  base role: contribution base
  compared role: captured working-tree result
```

Common origin remains composed from existing package/query/item data:

- repository and worktree identities;
- comparison kind and endpoint roles;
- `{packageId, reviewGeneration, revision}` snapshot identity;
- each shown side's repository-relative path, role, and content handle/hash.

The contribution origin's selected target identity, resolved target OID, and unique
contribution-base OID are also the sole inputs for human-facing current facts
and live transition explanations. PR0 does not add parallel display-only Git
identities.

`reviewGeneration` advances for every intent-changing attempt and every fresh
contribution capture. A published package never changes its origin. Review
metadata may use deltas only within the same
generation and equal origin. A contribution refresh therefore uses the
existing source-change reset/snapshot path while the current active projection
remains displayed until its successor is admitted. PR0 does not relax delta
identity, add an origin-only delta operation, or introduce a second
metadata-continuity rule.

That reset is an intentional correctness cost. The existing refresh admission
coalesces a later invalidation but does not revoke an already-running refresh
token merely because new dirty work arrived. Advancing `reviewGeneration`
immediately is therefore the fence that prevents that captured predecessor from
publishing. PR0 does not keep a generation stable merely to preserve item deltas
and does not add a second attempt epoch to recover that optimization.

## One native read identifies the default and selectable branches

Extend `AgentStudioGitLocalClient` with one bounded Review-target catalog read:

```text
reviewComparisonTargets(repositoryPath)
  open repository once
  ├─ lookup symbolic refs/remotes/origin/HEAD
  │    └─ resolvable refs/remotes/origin/<branch> → designated default target
  ├─ enumerate resolvable refs/heads/*             → local branch rows
  └─ enumerate resolvable refs/remotes/* except */HEAD
                                                     → remote-tracking rows

row: branch kind + displayed name + full ref name + resolved commit OID
```

The read uses one opened repository handle and libgit2 reference APIs. It does
not fetch, contact a remote, calculate ahead/behind counts, inspect another
worktree's checkout, infer a stack parent, or fall back to a conventional
branch name. The target designated by `refs/remotes/origin/HEAD` is selected as
its `origin/<branch>` remote-tracking ref. Repositories without that exact,
unambiguous mapping remain selection-required.

`BridgeReviewSourceProvider` exposes the same catalog and
`AgentStudioGitBridgeReviewDataClient` schedules it through the existing
`BridgeGitReadScheduler` as Review metadata work. Initial target adoption uses
only the catalog's designated default row. The existing initial Review-package
load captures that same catalog once and publishes it inside
`pane.presentation.reviewComparison`. Opening the comparison control reads the
already-published presentation slice; BridgeWeb filters those rows locally as
the user types. It does not perform a Git read on open or per keystroke.

The catalog is transient display data. It is neither pane intent nor snapshot
origin and is not stored in SQLite. PR0 does not introduce a cross-pane catalog
cache, watcher, or refresh service. Sharing and coalescing one catalog per
worktree remains the explicitly deferred selector optimization; PR0 performs
one bounded catalog read for each pane controller's initial Review load.

## One native contribution read owns Git coherence

Extend `AgentStudioGitLocalClient` with one operation whose result correlates
all contribution inputs and the file projection:

```text
GitContributionDiffRequest
  reviewedWorktreePath
  selectedTarget

GitContributionDiffSnapshot
  resolvedTarget
  reviewedHead
  uniqueContributionBase
  baseToWorkingTreeDiff
```

The local implementation performs one bounded correlated native read through
one opened repository handle:

```text
resolve selected target ─┐
resolve reviewed HEAD ───┼─► find all best merge bases
                         │          │
                         │          ├─ exactly one ─► diff base → working tree
                         │          ├─ none ─────────► no-shared-history error
                         │          └─ multiple ─────► ambiguous-base error
                         └──────────────► captured result identities
```

The read returns no partial successful snapshot. Unborn/missing HEAD,
unresolvable target, missing objects, no best merge base, or multiple best
merge bases are typed failures. It does not lock refs, the index, or working
tree against external mutation and is not a transactional repository snapshot.
When existing filesystem observation reports a repository or worktree
invalidation, the controller advances contribution generation before catch-up;
that generation prevents the superseded captured result from publishing. A
later observed change schedules a fresh capture. The Git read does not
introduce repository locks or a second watcher.

Bridge must not emulate contribution behavior by issuing separate target
resolution, HEAD resolution, merge-base, and diff calls: that would expose
incoherent inputs and duplicate policy outside `agentstudio-git`.

The existing Bridge provider boundary gains one contribution-specific read:

```text
BridgeReviewSourceProvider
  captureContributionComparison(request)
    → resolved Bridge endpoints + changed files + contribution origin
```

`BridgeGitReviewSourceProvider` delegates this operation to the same
`AgentStudioGitBridgeReviewDataClient` already used by `BridgeReviewPipeline`.
Construction passes the same supplied provider instance to the pipeline and
content loader as it does today; the controller does not add another retained
provider or Git client for the control. The adapter maps
`captureContributionComparison` to the new correlated `agentstudio-git` read.

The captured result enters package assembly once. One Bridge-owned pure builder,
shared by `BridgePaneController` and `BridgeDevelopmentProductHost`, maps the
committed intent, captured contribution result, and optional subject label into
the resolved `BridgeReviewPipelineRequest` plus its bound comparison origin:

```text
prepared comparison  resolved base/working-tree endpoints + changed files
bound origin         selected target + resolved target/HEAD/base revisions
reviewed subject     existing pane/worktree display label, or absent
```

`BridgePaneController` derives `reviewed subject` from its existing native pane
metadata: prefer a non-empty `worktreeName`, then a non-empty `checkoutRef`, and
otherwise omit it. Package construction projects the label as presentation
data; BridgeWeb falls back to `Current worktree`. The label is not persisted
comparison intent, Git authority, or anchor identity. It triggers no new Git
read, cache, store, service, or stream.

The builder owns mapping only. It does not resolve Git, retain state, assemble a
package, publish metadata, or become a generalized host factory. Sharing this
mapping prevents the focused Debug carrier from constructing a different
origin than production for the same captured comparison.

For that request, `BridgeReviewPipeline` consumes the prepared comparison and
does not call the existing endpoint-comparison operation again. It converges on
the existing package builders; there is no second package assembler.

The same capture path owns every contribution refresh. The existing catch-up
reservation still coalesces filesystem work:

```text
contribution invalidation → new generation → fresh identity resolution
  → proportional Git calculation when exact and safe, otherwise complete
```

A contribution invalidation never rebuilds from the committed package's
resolved endpoints. Every attempt therefore re-resolves the selected target,
reviewed HEAD, and unique base before package assembly. The later
[Incremental Review Git Refresh design](../2026-09-03-incremental-review-git-refresh/2026-09-03-program-design.md)
may reuse opaque complete Git metadata only after those fresh identities and
the exact affected scope are validated; uncertainty performs this design's
complete direct comparison.

Shared Review construction keeps `BridgeSharedReviewPackageTemplate`
projection-only. The resolved request, not the reusable template, owns the
attempt-specific contribution origin. Binding always writes that request's
exact origin into the rebuilt package. Template reuse is therefore permitted
when the contribution base and file projection are unchanged even if the
selected branch resolves to a new target OID. Package/metadata origin equality
still changes, so the existing reset/snapshot path publishes the successor
origin rather than reusing the old one. The active projection remains available
while that successor is pending; reset begins the candidate lineage rather than
clearing the displayed predecessor.

At the pinned `agentstudio-git` revision, `GitBranchSnapshot` supplies local
branch names and known upstream names but no default-branch designation. PR0
adds the bounded designation read above rather than promoting rebuildable
main-worktree checkout enrichment into default authority. A committed default
target must still resolve during contribution capture before it can publish
current; failure produces unavailable presentation rather than a `HEAD`
fallback.

## Current and proposed call paths

Reader question: what exact runtime edges change from reviewer action to
published result?

Legend: `[+]` added, `[~]` changed, `[=]` intentionally unchanged.

```text
CURRENT CONTRIBUTION-SHAPED PATHS

Review pane or Zoom-companion creation
  → WorkspaceSurfaceCoordinator.defaultBridgeReviewBaseline
      → cached main-worktree checkout OR ref("HEAD") fallback

Ordinary File View creation
  → literal localDefaultBranch("main")

Either creation path
  → BridgePaneState.workspace(baseline)
  → BridgePaneController.makeWorkspaceEndpointSelection
      → Git-ref endpoint + working-tree endpoint
  → AgentStudioGitBridgeReviewDataClient
      → resolve ref
      → diff resolved target tip → working tree          incorrect meaning
  → BridgeReviewPackage
  → [=] publication coordinator → metadata stream → Review View

Unresolved automatic ref("HEAD")
  → BridgePaneController.shouldRetryUnresolvedHeadBaseline
  → unstaged endpoint override                                  wrong fallback

Filesystem contribution invalidation
  → refresh catch-up reservation
  → BridgePaneController.refreshCurrentReviewPackage
  → replay committed resolved endpoints + original generation   stale meaning

PROPOSED CONTRIBUTION PATH

[~] Review, File View, or Zoom-companion pane creation
  → [~] BridgePaneState.workspace(selection-required comparisonIntent)
  → [-] no cached checkout, literal main, or automatic HEAD fallback
  → [+] initial Review-package load asks existing Bridge Git provider
      for the Review-target catalog's designated default
      → [+] agentstudio-git resolves refs/remotes/origin/HEAD designation
      ← identified origin/<branch> OR no designation / Git error
  → [+] controller rechecks absent target + current generation + pane admission
  → [+] identified target requests the conditional App/Core mutation
      → [+] pane graph atomically rechecks target absence and writes or declines
      ← canonical committed intent, not-applied, or pane/admission error
  → no designation/error/late result leaves selection-required unchanged

[+] Compare Worktree control opens
  → [=] existing worker panelChrome projection
  → [+] reads target catalog from pane.presentation.reviewComparison
  ← [+] BridgeWeb renders rows and filters them locally as text changes
  ← null catalog renders selector-local unavailability; current comparison is unchanged

[+] Review header action
  → typed Bridge review control command
  → [=] comm-worker product-call transport
  → [=] BridgePaneProductSchemeProvider builds correlated response
  → [=] BridgeProductSession commits the product-call effect
  → [=] BridgePaneProductSchemeProvider.applyCommittedControlEffect
  → [+] BridgePaneProductCommittedCallTarget
  → [+] BridgePaneController committed-call handler
  → [+] injected WorkspaceSurfaceCoordinator callback
      ├─ durable pane → WorkspacePaneAtom.updateBridgePaneState
      │                  → WorkspacePaneGraphAtom.updateBridgePaneState
      └─ Zoom companion → canonical controller-lifetime BridgePaneState
  ← canonical pane intent or pane/admission error
  → [+] controller adopts only the returned canonical intent
  ← [=] product-call dispatcher returns after the committed handler completes

[~] BridgePaneController begins a new contribution generation
  → [+] agentstudio-git contribution operation
      → resolved target + reviewed HEAD + unique merge base + diff
  → [+] shared resolved-contribution builder binds the pipeline request + origin
  → [~] BridgeReviewPipeline consumes it once; no endpoint re-comparison
  → [~] shared-template bind writes request origin into BridgeReviewPackage
  → [~] controller rechecks attempt generation before publication staging
  → [~] controller rechecks attempt generation immediately before commit
  → [=] publication coordinator applies its existing admission guards
  → [~] metadata reset/snapshot includes origin and retains the active
        predecessor until the successor is admitted
  → [~] Review View renders target/kind and current validity

[~] Contribution invalidation
  → [=] existing catch-up admission/coalescing
  → [+] fresh contribution attempt; never endpoint replay
  → fresh target + HEAD + base + working-tree capture

Error return:
  Default designation absent, malformed, or without a resolvable
  remote-tracking branch
  ← controller leaves selection-required intent unchanged
  ← Review View exposes choose-target; no checkout/name fallback is built

  Git or admission failure
  ← controller retains old committed snapshot only as stale, or unavailable
  ← Review View exposes choose/retry; no substitute comparison is built
  ← [-] unresolved HEAD never retries as a different comparison meaning
```

## Review control transport

Use the existing pane-presentation path for transient catalog data and the
existing Bridge product-call and worker-RPC path for committed selection; do
not add a second WebKit message handler or Agent Studio IPC command.

One typed Review operation reuses the existing product-call path:

```text
review.comparison.update
  input:  one selected branch/ref or exact commit target
  effect: protocol commit → controller → App callback → pane graph → adopt → refresh
  output: null acknowledgement returned only after that committed effect completes
```

The update response is not a second source of truth and carries no copied
intent. A successful return only acknowledges that the exact validated request
completed the committed native effect; the pane graph remains authoritative
and the existing pane-presentation stream publishes the canonical active
intent.
The injected callback returns the resulting canonical intent to the controller.
For a durable pane it commits through App/Core; for a Zoom companion it returns
controller-lifetime state without consulting the durable pane graph. The
controller adopts and refreshes only for `applied` or exact `unchanged`; closed
pane or companion admission prevents a successful acknowledgement for an
ineligible intent.

The target catalog is transient worker/UI data. The native controller reads it
during the existing initial Review-package load, retains it in the existing
Review comparison presentation owner, and publishes it through
`pane.presentation.reviewComparison.targetCatalog`. The worker's existing
panelChrome projection copies that slice to the UI. The UI neither calls native
code directly nor adds another request/result lifecycle. Catalog failure
publishes `null`, is contained to the selector, and does not invalidate the
currently displayed comparison.

Branch rows submit their typed branch/ref target immediately. Commit mode
accepts a full Git object ID after bounded hexadecimal validation and submits a
typed pinned-commit target; the ordinary comparison attempt establishes object
existence and commit peelability. Canonical active intent still arrives on the
initial and subsequent `pane.presentation` frames rather than through a
duplicate current-state call.

BridgeWeb composes one comparison control into the existing Review header:

```text
Review View header
└─ Review  feature/annotations changes / Sources/App.swift  [Files | Review]  [Compare: origin/main ▾]  [View settings]

menu
  Compare Worktree
    [ Branch ] [ Commit ]

    Branch
      Search branches…
      ✓ origin/main                         DEFAULT · REMOTE-TRACKING
        M2
        main                                             LOCAL
        L1

      Review starts from B1
      Latest commit shared with default branch origin/main

    Commit
      Enter a full commit hash…
      [Compare to this commit]

  Comparison refreshed
    origin/main updated       M1 → M2
    Review starts from        B1

    or, when the common commit also changed:

    origin/main updated       M1 → M2
    Review starts from        B1 → B2
    Files may have entered or left this review.
```

The target name and revision values change with the displayed snapshot. The
product keeps the title and controls in this existing single flex row; PR0 does
not add a second toolbar row or increase header height. The control and popover
reuse the existing owned trigger, popover, input, button, and toggle-group
primitives plus the focus, selected, and muted-description styling of existing
Review filters and view settings. It does not hand-roll a route-local segmented
control.

For contribution snapshots, BridgeWeb replaces its current generic endpoint
title (`Head vs Base`, including `Current worktree vs Default`) with
`<reviewed subject> changes`; the selected file path remains the title suffix.
The compare control supplies `Compare: <target>`. The opened control has no
separate chooser heading, current-comparison heading, or explanatory paragraph.
Instead it places the selected branch/commit and exact target revision in the
selection content, followed by `Review starts from <base>` and `Latest commit
shared with <target>`. For the designated target, that second line says
`default branch <remote/name>` without replacing the actual branch name.
Assistive text carries the same meaning so it is not hover-only. Target and base
OIDs may be visually abbreviated only while their full values remain available
to assistive technology. The reviewed HEAD OID remains package metadata rather
than normal UI text.

When BridgeWeb admits a successor contribution package, it compares that
package's resolved target and contribution-base OIDs with the package it was
already displaying, but only when repository, worktree, comparison kind, and
selected target identity match. A source-change reset retains that immediately
displayed predecessor origin until the successor is admitted; it does not
create durable history. Before replacing the old projection, BridgeWeb derives
one transient `comparisonChangeSummary` for the successor:

```text
compare target independently    → if changed, target M1 → M2
compare base independently      → if equal, shared point remains B1
                                → if changed, B1 → B2; files may differ
both changed                    → include both old-to-new pairs
no matching predecessor         → current facts only; no movement claim
```

This summary is BridgeWeb UI state associated with the displayed successor. It
is not added to pane intent, package origin, `pane.presentation`, SQLite, or a
history service. It requires no Git call: both immutable origins already contain
the compared OIDs. Closing or restoring the pane may discard the summary; the
restored current package still exposes its exact current target and shared
starting point.

Pending and stale presentation keeps two facts distinct: the active requested
intent and the origin of any still-rendered prior snapshot.

## Comparison state uses the existing pane-presentation stream

The Review metadata stream publishes immutable successful snapshots, but a
pending or failed attempt is not itself a snapshot. Extend the existing
`pane.presentation` product metadata frame rather than adding polling or a new
stream:

```text
BridgePaneProductPresentationSnapshot
  presentationRevision                         replaces activity-only revision
  nativeActivity
  refreshingLanes
  reviewComparison:                            nil for non-Review surfaces
    activeIntent                               App-committed runtime mirror
    attempt:
      selectionRequired
      pending(reviewGeneration)
      settled(reviewGeneration)
      unavailable(failureKind, retryable)
    displayedSnapshot:
      none
      current(packageId, reviewGeneration, revision)
      stale(packageId, reviewGeneration, revision)
```

`presentationRevision` orders every pane-presentation change, including
activity and comparison changes; Swift and the bundled BridgeWeb contract cut
over together. `displayedSnapshot` contains only the identity needed to
associate the presentation with the Review package. The package's immutable
comparison origin remains the source for the stale snapshot's original target
and resolved revisions; those fields are not copied into transient
presentation state.

BridgeWeb derives menu-open state, focus, highlighted control options, and
draft text locally. It renders choose-target for `selectionRequired`, retry or
choose-target for `unavailable`, and the prior package as stale only when the
presentation identity matches that package. This is transient product
presentation, not another durable model.

## Existing transport and executor boundaries stay intact

PR0 adds typed messages to the two existing generic Bridge directions; it does
not add another communication system:

```text
BridgeWeb → native
  existing comm-worker product-call transport
    review.comparison.update

native → BridgeWeb
  existing product metadata transport
    pane.presentation with optional Review comparison state + target catalog
    Review metadata reset/snapshot with immutable comparison origin
  existing worker Review display-patch transport
    transient comparison target catalog
```

Only small state transitions that already belong to application UI authority
run on `MainActor`:

```text
MainActor
  WorkspacePaneAtom → WorkspacePaneGraphAtom intent mutation
  BridgePaneController adoption, generation, and presentation transition

off MainActor on existing owners
  target/HEAD/base/diff read      agentstudio-git blocking read executor
  package assembly               BridgeReviewPipeline actor
  metadata reservation/delivery  existing product metadata actors
  BridgeWeb projection/render     existing comm worker + web runtime
```

The MainActor path never calculates a merge base, enumerates branches, walks a
diff, reads file content, assembles a package, or waits synchronously for Git.
It starts asynchronous work and later applies only the admitted result or
failure state.

## Intent commit and refresh sequence

Reader question: how does a user selection become the only durable intent and
then a current immutable snapshot?

```text
1  Reviewer ──select B──────────────────────────────► BridgeWeb

2  BridgeWeb ──update(B)────────────────────────────► Provider/session
   Provider/session ──commit effect─────────────────► Call target
   Call target ──forward committed call─────────────► Controller

3  Controller ──commit callback────────────────────► App/Core
   App/Core ──canonical committed intent────────────► Controller

4  Controller
     adopt B → publish pending generation G
     └─ async contribution request──────────────────► Git

5  Git ──captured result or error───────────────────► Controller
   Controller
     ├─ if G is current: publish package/reset
     └─ otherwise: discard predecessor result

6  Provider/session ──ack after committed handler──► BridgeWeb
   Native metadata ──intent + validity + origin─────► BridgeWeb
   BridgeWeb ──pending/current/stale/unavailable────► Reviewer
```

The App/Core write occurs before the controller treats the intent as accepted.
If pane/session admission closes, no controller adoption or refresh occurs.
The controller's in-memory intent is therefore a runtime mirror, not a second
authority. The product-call response leaves the dispatcher only after this
committed handler returns; the response does not outrank the pane graph or the
pane-presentation stream.

## Focused Debug carrier uses production Core and Bridge owners

The standalone development server exists to keep the Bridge development loop
fast. It builds and loads the production `AgentStudioCore` and
`AgentStudioBridge` targets plus its minimal Hummingbird carrier. It does not
depend on or boot the `AgentStudio` executable, load the packaged Bridge app
resources, create an AppKit window, start Terminal/Ghostty, or compose unrelated
feature targets.

This speed boundary is also the implementation boundary. PR0 extends the
existing `AgentStudioBridgeDevelopmentServer` and
`BridgeDevelopmentProductHost`; it does not introduce another development
server, Bridge host, persistence facade, or generalized product-runtime
composition. The existing Debug executable may add a direct
`AgentStudioCore` target dependency when it must name Core types, but its
runnable graph remains Core + Bridge + the existing HTTP carrier.

The development process uses an exclusive isolated data root. It must never
open the same live `core.sqlite` as an Agent Studio app process: each
`WorkspaceStore` owns an independent in-memory workspace snapshot and the
existing repository save replaces the full workspace composition.

```text
Vite process owner
  ├─ exclusive data root
  ├─ exact pane UUID
  ├─ initial worktree + initial target only when seeding a missing pane
  └─ backend process lifecycle
          │
          ▼
AgentStudioBridgeDevelopmentServer
  ├─ existing Core composition
  │    ├─ CoreAtoms
  │    └─ WorkspacePaneAtom
  ├─ WorkspaceSQLiteDatastoreFactory
  │    ├─ <data-root>/core.sqlite       durable pane authority
  │    └─ <data-root>/local.sqlite      production datastore companion
  ├─ WorkspaceStore
  │    ├─ prepare + load canonical composition
  │    ├─ require exact Bridge pane UUID
  │    ├─ WorkspacePaneAtom comparison-intent mutation
  │    └─ existing observation + graceful-shutdown flush
  ├─ BridgeDevelopmentProductHost
  │    └─ existing product session, Git adapter, pipeline, and publication owners
  └─ Hummingbird routes                       carrier only
```

The dependency and persistence edges are closed:

```text
allowed
  existing Debug server ──► existing BridgeDevelopmentProductHost
  existing Debug server ──► CoreAtoms + WorkspaceStore
  WorkspaceStore ──► existing WorkspaceSQLiteDatastoreFactory
  WorkspaceSQLiteDatastoreFactory ──► isolated core.sqlite + local.sqlite

forbidden
  Debug ──► AgentStudio executable or packaged app resources
  Debug ──► live production/beta data root
  Debug ──► direct SQL writer or Debug-specific repository
  Debug ──► new persistence facade, host framework, service, or daemon
  local.sqlite ──► comparison-intent authority
```

`core.sqlite` remains the sole durable authority for the Bridge pane payload
and its branch or pinned-commit comparison intent. `local.sqlite` is opened only as the
required companion of the existing production datastore composition; PR0 does
not store comparison intent there. Both files live under the same explicit,
isolated development data root.

Fixture initialization uses production Core owners to create the exact pane
UUID in an otherwise isolated development workspace. `worktree` and
`initial target` are seed inputs only. After that pane exists, its restored
`BridgePaneState` is the sole comparison authority; restart inputs may validate
its worktree identity but may not replace its persisted intent. Missing,
mismatched, or non-Bridge pane identity fails startup. The host never chooses a
pane by worktree path, recency, dictionary order, or “first Bridge pane.”

The existing Debug host remains the Bridge runtime composition. PR0 replaces
its synthetic pane identity and server-local `reviewBase` authority with the
exact Core-restored pane and injects the same typed committed-intent effect used
by the production controller. It does not instantiate `BridgePaneController`,
because that controller owns WebKit page and packaged-resource lifecycle. It
also does not add a generalized Bridge-host factory: the existing product
session, provider, and call seams are reused directly. If current source cannot
support that bounded composition, implementation stops on a design break
rather than inventing a new host system inside PR0.

For Review construction, the Debug host calls the same Bridge-owned pure
resolved-contribution request builder as `BridgePaneController`. It supplies the
exact restored intent, captured Git result, and subject label; it does not keep
or recreate its current independent `makeDevelopmentReviewPipelineRequest`
mapping. Production and Debug may own different lifecycle composition while
sharing the origin-bearing request mapping that P0-R7 requires.

The committed product-call handler mutates the exact pane on `MainActor` before
returning acknowledgement. Durability then uses the normal production
`WorkspaceStore` observation and flush lifecycle; graceful development-server
shutdown requires the existing `WorkspaceStore.flushAsync()` result to succeed
before process A counts as durably complete. A failed flush fails that Debug
run and its restart proof; PR0 adds no recovery framework around it. No direct
SQL writer, row-level Debug repository, second persistence model, process lock,
daemon, or watcher is added.

Restart proof deliberately creates a new process:

```text
process A
  restore pane I0 → browser commits I1 → Core observes I1 → shutdown flushes
                                                               │
                                                               ▼
process B, same isolated root + pane UUID
  restore I1 → resolve current target/HEAD/base again → publish fresh snapshot
```

Only selected-target intent crosses that restart. A branch crosses as its
symbolic identity and a commit as its pinned OID. Resolved branch target,
reviewed HEAD, contribution base, file set, and content identities remain
runtime snapshot truth.

## State and legal transitions

Reader question: which transitions affect correctness, and which identity is
shown at each point?

```text
selection required
      │ default resolved or reviewer commits a target
      ▼
pending(intent I, generation G)
      ├─ success; G still newest ─────────────► current(snapshot S, origin I)
      ├─ failure; no prior snapshot ──────────► unavailable(intent I)
      └─ failure; prior snapshot S retained ──► stale(S, original origin)

current     ── refresh/change ────────────────► pending(new intent/generation)
unavailable ── retry/change ──────────────────► pending(new intent/generation)
stale       ── retry/change ──────────────────► pending(new intent/generation)
```

Guards and illegal paths:

- only a committed pane intent can start a target-change refresh;
- an automatic default may commit only through the pane graph's atomic
  target-if-absent mutation; an explicit target update is never replaced by a
  controller-side check followed by an unconditional write;
- only the newest admitted generation may publish current;
- a failed attempt cannot relabel an older snapshot with the pending target;
- pane presentation pairs a retained stale snapshot only with its exact
  `{packageId, reviewGeneration, revision}` identity;
- an origin change cannot be applied as an item-only delta;
- restore never marks a decoded snapshot current; it starts a fresh attempt.

## Refresh and repository invalidation

Ordinary files affect only their exact reviewed worktree. Git-internal changes
may move a branch/ref used as a target by any worktree in the same repository.
Extend the existing raw-envelope routing accordingly:

```text
filesystem event
│
├─ ordinary worktree content/status change
│    └─ Review-capable Bridge panes for the exact worktree
│         └─ contribution → fresh target/HEAD/base capture          changed path
│
└─ Git-internal change or suppressed Git-internal path
     └─ same-repository contribution panes                          added scope
          └─ each pane starts a fresh target/HEAD/base capture
```

The router reuses `FileChangeset.containsGitInternalChanges`, suppressed
Git-internal count, repository identity, each controller's persisted intent,
and existing refresh admission/coalescing. It does not create a repository
observer, polling loop, or cross-pane coordinator. Duplicate invalidations are
coalesced by the existing per-pane refresh admission. That admission remains a
scheduler, not a comparison-semantics owner: it starts the fresh contribution
capture path.

The changed edge spans both owners. `WorkspaceSurfaceCoordinator` widens routing
to same-repository contribution panes. `BridgePaneController` correspondingly
relaxes its current exact-worktree equality guard only for Git-internal changes
admitted to an active contribution comparison; ordinary file changes retain
exact-worktree admission. Without both changes the widened
route would be silently discarded at the controller.

Observation of either relevant event immediately advances the affected
controller's existing Review comparison generation before catch-up is queued.
That same transition publishes pending presentation and makes any in-flight or
already-leased predecessor generation ineligible to become current. Native
task cancellation remains best effort; publication must recheck the generation
after package construction and before commit. The widened same-repository route
uses this same controller-owned invalidation transition rather than adding a
second epoch or admission owner.

The prepared publication retains the generation of the attempt that captured
its origin. `BridgePaneController` compares that generation with its current
generation after package construction and again immediately before the
publication coordinator commit. The existing publication coordinator continues
to own reservation, commit, and delivery admission; it is not redefined as the
comparison-generation owner. The final generation check and coordinator commit
run in one non-suspending `MainActor` critical section, so invalidation cannot
interleave between them. A mismatch rejects any staged reservation, releases
the artifact pin, and leaves the successor attempt pending.

## Failure and recovery

Reader question: where is failure detected, how is it contained, and what does
the reviewer see?

```text
no repository default target
  agentstudio-git designation read ──► selection required
                                     └─ never substitute checkout, main, or HEAD

target catalog unavailable
  initial Review load / agentstudio-git ──► null presentation catalog
                                         ├─ selector explains unavailability
                                         └─ current comparison remains unchanged

invalid target / missing HEAD / missing object
  agentstudio-git ──► unavailable, or retain prior snapshot as stale
                    └─ never retry as a different comparison meaning

no shared history / multiple best bases
  agentstudio-git ──► unavailable; choose target; never choose a base

worktree or target changes during attempt
  controller generation ──► invalidate before commit; schedule latest

pane or session closes
  admission gates ──► cancel/drop; no later pane mutation

metadata delivery cannot commit
  publication coordinator ──► retain last committed snapshot or error
```

Retry is owned by the existing manual refresh, intent change, and repository
invalidation paths. PR0 adds no retry daemon, backoff policy, or persisted job.
When a prior snapshot is retained, its captured origin remains the label source
and the active intent is shown separately as pending/failed.

## Restore and data cutover

`BridgePaneState` remains encoded in the existing pane payload. Its decoder
maps the old `WorkspaceBaseline` representation into the contribution target:

```text
old localDefaultBranch            → no target; run guarded default lookup
old branch/origin/ref except HEAD → same target
old headMinusOne                  → ref("HEAD~1")
old ref("HEAD")                   → no target; run guarded default lookup
```

An active restored contribution always resolves its saved branch, ref, or
pinned commit target. A
legacy explicit branch, origin, or non-`HEAD` ref remains the retained
contribution target. Legacy
`localDefaultBranch` cannot establish explicit reviewer provenance: current
writers derived it from the canonical main-worktree checkout or a literal
`main`, so the decoder treats it as absent target intent and runs the guarded
repository-default lookup.

Current source has no reviewer target selector and creates both
`localDefaultBranch` and `ref("HEAD")` as automatic defaults. The codec must not
promote either token to a reviewer-explicit choice. It maps both to absent
target intent; the initial Review-package load then runs the same guarded
repository-default lookup as a new pane and otherwise remains
selection-required. New panes never create either fallback. All writers emit
only the new intent shape, and all runtime callers cut over to that shape in
the same change. This is a payload-codec cutover, not a second runtime path and
not a SQL migration.

On restore:

1. the pane graph decodes the intent;
2. the coordinator creates the controller from it;
3. the controller starts a new generation;
4. contribution re-resolves target/HEAD/base;
5. only the new publication can become current.

## Cross-cutting realization

- Reliability: pane-graph intent is singular; the widened pane-presentation
  revision, generations, refresh admission, cancellation, and publication
  commit retain one ordered path to BridgeWeb.
- Performance: repository-wide invalidation is limited to contribution panes
  in the affected repository and is coalesced per pane.
- Accessibility: the owned menu primitive provides keyboard operation, focus,
  accessible name/current value, and existing Review header visual scale.
- Data lifecycle: selected-target intent joins durable pane content only for
  stored File and Review panes. Branches/refs persist symbolically and commits
  persist as pinned OIDs. A Zoom companion retains the same intent only in its
  controller and loses it when the companion is retired. Resolved branch OIDs
  and file content identities live in immutable runtime snapshots; PR0 adds no
  historical retention.
- Security/privacy: all reads remain local and use existing repo/worktree
  authority. There is no new actor, network transport, secret, privilege, or
  externally callable IPC surface.
- Observability: existing refresh/build/publication telemetry remains the
  observation path. Add bounded comparison-kind and failure-reason labels only
  where current source-scrubbing policy permits; never export raw paths or ref
  text through OTLP.

## How each requirement works and how it is proved

Reader question: can every PR0 obligation be traced to an owner and a proof
seam without inventing planning details?

```text
P0-R1  agentstudio-git designation read + controller guard + pane intent
       + Review control
       contract: every Review-capable pane creator starts without a fabricated
                 target; the existing initial Review-package-load trigger
                 adopts the remote-tracking branch designated by
                 refs/remotes/origin/HEAD; durable panes commit it through Core,
                 while Zoom retains it for the companion lifetime; absent or late results remain
                 selection-required; none uses another worktree's checkout,
                 literal main, or HEAD
       proof: designated master while the canonical main worktree is on a hotfix;
              divergent same-name local branch; missing/malformed designation;
              missing designated remote-tracking branch;
              pane-graph target-if-absent interleaving where reviewer selection
              wins a late default result; dedicated Review, File View→Review,
              and Zoom-companion initial Review-package loads

P0-R2  pane facade/graph for durable panes + controller-lifetime Zoom target
       + committed-call target + controller
       + target catalog in pane presentation + Branch/Commit Review control
       + existing pane metadata → package subject-label projection
       contract: commit before acknowledgement; header names subject and target;
                 branch rows distinguish local/remote/default and show revisions;
                 commits persist as pinned OIDs; exact target/base and
                 shared-history meaning are accessible
       proof: committed-call integration plus keyboard/accessibility/visual interaction

P0-R3  correlated agentstudio-git contribution read
       contract: unique shared-history base excludes target-only movement
       proof: agentstudio-git temporary-repository tests own unique-base and
              base-to-working-tree semantics; Agent Studio integration proves
              adapter mapping and the pinned package revision

P0-R4  contribution operation
       contract: committed and dirty worktree state
       proof: native Git integration across every file-state class

P0-R5  raw invalidation routing + controller generation/admission
       + BridgeWeb adjacent-origin transition summary
       contract: target movement and incorporated history re-centre; the UI
                 distinguishes target-only from shared-base movement and shows
                 both old-to-new pairs when both change
       proof: contribution invalidation takes fresh-capture, not endpoint-replay,
              after capture/lease and before commit; the prior projection remains
              displayed while pending and supplies the successor UI transition;
              a Git-internal change from worktree A passes coordinator and
              controller admission for a contribution pane on worktree B in the
              same repository, while ordinary file changes remain worktree-scoped

P0-R6  typed Git failures + observed-invalidation publication guards
       + pane presentation
       contract: unavailable or stale with honest original identity
       proof: pre-commit invalidation, unresolved HEAD without unstaged fallback,
              failure matrix, and visual evidence

P0-R7  shared resolved-contribution builder + package identity
       + item content handles
       contract: immutable kind-specific origin and file-side identities
       proof: equal production/Debug builder results, shared-template rebind,
              plus successor-snapshot integration

P0-R8  pane payload codec + fresh controller build
       contract: intent restores; resolved truth does not
       proof: file-backed process restart across every comparison kind plus
              legacy automatic local-default and ref("HEAD") values restoring
              without selected-target authority, then using the guarded
              default-or-selection-required path
```

The production Git path must be real for P0-R3 through P0-R6. The required
`agentstudio-git` contract and implementation land in that external repository,
and this PR updates the authoritative exact `revision:` requirement in
`Package.swift` plus the resulting `Package.resolved` pin to the containing
revision. Fakes may drive controller ordering and UI failure states, but they
cannot substitute for the temporary-repository history scenarios. Manual visual evidence observes the
actual one-row Review header, subject/target/kind labels, shared-history
description, exact current target/base revisions, target-only and base-movement
summaries, focus, pending, unavailable, and stale presentation.

Three runtime gates remain distinct:

```text
1  Core restart
   isolated file-backed core.sqlite
   → mutate + flush + terminate + reopen
   → exact branch or pinned-commit intent restored; no resolved snapshot persisted

2  Debug + Vite
   production Core + Bridge targets, exact pane, thin HTTP carrier
   → browser update in process A
   → backend restart and fresh Git resolution in process B
   → same origin-bearing request builder as production

3  Packaged Agent Studio
   existing run/verify Bridge packaged-product journey
   → real pane/controller/WebKit UI action
   → WorkspaceSurfaceCoordinator → WorkspacePaneAtom → core.sqlite
   → package/render read-back + observability + PID-targeted Peekaboo
```

The Debug gate cannot substitute for the packaged-app gate, and the packaged
gate cannot substitute for the cross-process SQLite restart. Reuse the existing
`run-bridge-packaged-product-journey` and
`verify-bridge-packaged-product-journey` harnesses; add no parallel proof
infrastructure. No release or tag proof is required for PR0.

## Alternatives and complexity tradeoffs

### Selected — existing owners plus one correlated Git capability

Gain: truthful repository-default selection, correct contribution meaning, one
durable authority, coherent origin, and a discoverable target control. Cost:
one target-catalog read, one correlated contribution read, a guarded controller
lookup, one pane-presentation catalog slice, a pane-payload codec cutover, and
origin propagation through the existing Review package/reset contract.

### Rejected — compose resolve, merge-base, and diff calls in Bridge

This appears smaller in `agentstudio-git` but moves coherence and Git policy
into Bridge. Repository state can change between calls, and every consumer
would need to reproduce unique-best-base behavior. The complexity is displaced,
not removed.

### Rejected — keep direct target-tip diff and hide noise in the UI

Filtering cannot reliably distinguish target-only changes from worktree
contribution after the wrong comparison has already been calculated. It also
cannot produce truthful contribution-base origin.

### Rejected — persist comparison snapshots or create a review service

No PR0 requirement needs historical browsing, synchronization, collaboration,
or a frozen Review object. Such machinery would add lifecycle and recovery
problems without improving the current contribution comparison.

The accepted usability debt is that the catalog is read once per pane
controller's initial Review load. PR0 does not share or coalesce one catalog per
worktree across tabs and panes. That optimization is reconsidered when repeated
Git reads are measured or the selector is reused by another surface; it must
reuse existing Git refresh ownership rather than add a watcher or cache
service. A searchable commit history is also deferred: Commit mode accepts one
exact OID. A historical snapshot store is reconsidered only when a future
annotation or audit requirement needs retrieval, not merely identity.

PR0 also does not infer stacked-branch ancestry. A reviewer working on a stack
pays the explicit cost of choosing that stack's intended base in the same
target control; evidence of a repeated need may justify a later stack-aware
product requirement.

## Explicit non-goals preserved

PR0 does not add annotation sessions, anchors, comments, Markdown/Mermaid
rendering, copy/export, comment delivery or status, agent messages, guided
review, external code-host synchronization, multi-user review, a frozen review
lifecycle, durable comparison-transition history, a manual comparison-update or
reset-base action, a new security model, or a general comparison service. PR1
and PR2 must consume PR0 snapshot origin without moving those features backward
into this design.
