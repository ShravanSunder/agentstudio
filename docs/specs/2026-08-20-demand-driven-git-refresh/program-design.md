# Demand-Driven Repository Fact Refresh Program Design

Requirements: [Demand-Driven Repository Fact Refresh Requirements](requirements.md)

Specification: [Demand-Driven Repository Fact Refresh Specification](specification.md)

## Integrated design

Agent Studio answers repository-fact consumers from keyed accepted atoms first. One App-owned demand projection derives the complete attention snapshot once and forwards content-changed demand to three independent source owners:

```text
workspace/window/pane/sidebar state
              │
              ▼
RepositoryFactDemandCoordinator (App)
  ├─ active pane worktree
  ├─ sidebar-attended worktrees
  ├─ visible active-tab pane worktrees
  ├─ open worktrees
  └─ demanded repository identities
              │
              ├──────── local worktree demand ────────┐
              │                                       ▼
              │                         GitWorkingDirectoryProjector
              │                           freshness + exact-clean admission
              │                                       │
              │                                       ▼
              │                         AgentStudioGitWorkingTreeStatusProvider
              │                           ├─ agentstudio-git exact clean proof
              │                           └─ Darwin loss-aware continuity witness
              │                              ├─ worktree-local subtree streams
              │                              └─ shared exact-item parent observers
              │
              ├──────── demanded repositories ───────┐
              │                                       ▼
              │                         RemoteReferenceRefreshActor
              │                           noninteractive git fetch
              │
              └──────── demanded worktree IDs ──────┐
                                                      ▼
                                                ForgeActor
                                  actor-resolved branch-scoped gh GraphQL

all validated changed results
              │
              ▼
WorkspaceCacheCoordinator
              │
              ▼
RepoEnrichmentCacheAtom / RepoCacheAtom
  ├─ AtomFamily<worktreeId, WorktreeEnrichment>
  ├─ AtomFamily<repoId, RepoEnrichment>
  └─ AtomFamily<RepoBranchKey, PullRequestFacts>
              │
              ▼
keyed eager derived atoms and UI readers — no source calls
```

The three source owners share the same stage vocabulary—cache check, contraction, freshness admission, single-flight, physical execution, generation validation, changed-only publication—but they do not share mutable scheduling state or one generic scheduler. Local filesystem truth, remote-tracking refs, and GitHub PR facts have different authorities, costs, failure modes, and recovery rules.

## Why this structure

The structural crux is where “good enough” becomes a decision. Putting that decision in views recreates render-triggered work; putting product demand in `agentstudio-git` mixes product policy into the data plane; treating event silence as Git truth would make the filesystem observer a second source of repository facts; putting every source behind one scheduler erases authority and recovery differences. The selected design keeps product demand and freshness policy in the projector, exact-clean semantics and dependency identity in `agentstudio-git`, loss-aware continuity evidence in the existing Darwin observation boundary, proof composition in the local status provider, and accepted values in keyed atoms.

| Alternative | Gain | Cost | Decision |
| --- | --- | --- | --- |
| Views call sources when data looks missing | Minimal plumbing | Render-triggered work, duplicated policy, no reliable capacity | Reject |
| One repository-fact scheduler owns local Git, fetch, and Forge | One queue and vocabulary | Mixed authority, coupled failures, complex priority across unrelated sources | Reject |
| Independent source actors consume one App demand snapshot | Singular demand semantics with source-owned freshness/recovery | Adds one demand model and one remote-ref actor | Select |
| Every finite checkpoint performs exact Git | Simple correctness story | One 0.6–3.8 second read can breach idle p99; complete attended demand produces continuous fleet waves | Reject |
| Treat missing filesystem events as unchanged | Minimal implementation | Silent stale facts after drops, gaps, linked-worktree metadata mutation, or unsupported observation | Reject |
| Exact-clean baseline plus loss-aware continuity | Keeps Git as truth while avoiding repeated unchanged traversals | Requires observer uncertainty/epoch semantics and package/app proof composition | Select |
| Repeat every shared exact-item parent in every worktree stream | Reuses one stream shape | A shared config parent recursively wakes and classifies once per worktree for unrelated events | Reject |
| Shared exact-item parent observers with selective subscriber fan-out | One recursive callback and one exact-path lookup for unrelated parent activity | Adds internal composite-binding and shared-observer lifecycle | Select |
| Per-file vnode observers or metadata-only validation | Narrow apparent wake or simple checkpoint read | Replacement/re-arm ambiguity or loss of uninterrupted observation proof | Reject |
| Process-isolated local status helper | Hard kill boundary | IPC, worker lifecycle, cost relocation, wider proof | Defer unless in-process design fails its falsifiers |

The design reuses `RepoCacheAtom`, `AtomFamily`, `WorkspaceCacheCoordinator`, `GitWorkingDirectoryProjector`, `DarwinFSEventStreamClient`, `AgentStudioGitWorkingTreeStatusProvider`, `ForgeActor`, `PullRequestDemandProjection` semantics, the `agentstudio-git` remote process runner and parsing foundation, `EagerDerivedAtomFamily`, the EventBus, and the exact-debug proof path. New durable machinery is limited to the holistic demand snapshot, `RemoteReferenceRefreshActor`, process-wide source capacity owners, local status fact/detail, exact-clean proof, loss-aware continuity, and staged-fetch contracts, plus the deadline/governor state required to replace fixed polling. Exact-clean and continuity authority is runtime-only and never persisted.

Revisit process isolation only if one admitted local operation still violates the action CPU target after duplicated detail work and fleet admission are absent, or a native read demonstrably cannot finish within the accepted process lifecycle. Any future helper CPU must be included in user-capacity proof.

## Component ownership

### RepositoryFactDemandCoordinator

The App composition layer owns one read-only `RepositoryFactDemandSnapshot`. It derives demand from canonical workspace/window/pane/sidebar state and sends a new snapshot only when its complete value changes.

The snapshot contains:

- active-pane worktree identity;
- sidebar-attended worktree identities: the sidebar's semantic worktree membership before search, grouping, scrolling, or row materialization;
- visible-pane worktrees in the active tab, honoring management, drawer, zoom, occlusion, minimization, and window visibility semantics already defined by PR-fact demand;
- open worktrees;
- demanded worktree identities with their attention class for Forge;
- demanded repository identities for remote-reference refresh.

The coordinator owns no freshness, provider, cache, or retry state. It does not read `ViewRegistry`, `RepoExplorerTableMaterializer`, viewport rows, search state, grouping presentation, or row materialization; render bookkeeping never creates source demand. Sidebar attention comes from canonical sidebar presentation state plus canonical repository/worktree membership. Empty attention is delivered on hiding, minimization, occlusion, topology removal, and shutdown; the local projector independently retains registered worktrees as background self-heal inventory.

The current separate `setActivePaneWorktree`, `setActivity`, `setSidebarVisibleWorktrees`, and PR-demand observations become one content-equal capture followed by narrow projections to each owner. `FilesystemGitPipeline` accepts the complete snapshot once and projects it to filesystem-ingress attention, local-Git attention, remote-reference repository demand, and Forge worktree demand. This prevents the local and remote definitions of “visible” from drifting without making those owners share scheduling state.

The capture is ID-only and uses dedicated association-only keyed facts rather than composite pane or worktree models. `WorkspacePaneGraphAtom` owns `paneID -> (repoID?, worktreeID?)` association slots plus their membership revision; it updates a slot only when pane membership or that association changes. `RepositoryTopologyAtom` owns `worktreeID -> repoID` membership slots plus their membership revision; it updates a slot only when repository/worktree membership changes. These are narrow read interfaces over the existing canonical atoms, not new mutable truth owners. They prevent CWD, path, name, note, residency, content, drawer placement, or other unrelated changes from invalidating demand capture.

The coordinator observes active tab/window/sidebar presentation state, pane-association membership, repository/worktree membership, and the association slots needed for the complete snapshot. `FilesystemProjectionIndex` remains a filesystem event/topology projection owner and is not attention authority. The capture does not observe `SidebarVisibleWorktreesRuntimeAtom`, composite `PaneStructuralFacts`, composite `Pane`/`Worktree` values, branch or enrichment facts, filesystem paths, cache dictionaries, search, grouping, viewport rows, row presentation, or every pane's display state. `ForgeActor` retains its existing actor-owned worktree membership and resolves current non-empty branches after receiving demanded worktree IDs; branch changes therefore alter Forge scope without creating a second MainActor branch owner. Membership/topology changes may rebuild the compact identity projection; search, grouping, scrolling, row rendering, unrelated pane facts, and unrelated enrichment writes do not rebuild or deliver demand. Content equality runs before any source-owner call.

The same complete snapshot preserves filesystem ingress priority without restoring a second demand path. `FilesystemGitPipeline` projects active-pane and open-worktree IDs to one `FilesystemActor` attention update, and projects the full active/sidebar-attended/active-tab-visible/open classification to one `GitWorkingDirectoryProjector` attention update. The current `FilesystemProjectionIndex -> setActivity -> FilesystemActor + GitWorkingDirectoryProjector` fan-out is removed; the index no longer writes attention to either owner. `FilesystemActor` still prioritizes active/open worktree flushes, but those IDs now come from the coordinator's canonical snapshot. A failed or cancelled delivery commits no partial owner state; latest-value delivery retries the complete snapshot, including an A -> B -> A reversion, before accepting it as delivered.

### RepoEnrichmentCacheAtom and RepoCacheAtom

The existing keyed atom families remain the accepted-value owners:

- `worktreeId -> WorktreeEnrichment` owns the last complete current local worktree candidate, including branch, sync, file counts, line counts, and entries;
- `repoId -> RepoEnrichment` owns repository-level accepted enrichment;
- `RepoBranchKey -> PullRequestFacts` owns current-origin confirmed PR/check/review facts;
- existing keyed loading/unavailable state owns presentable remote refresh honesty.

Atoms do not own source TTLs, retry clocks, provider tasks, or demand. Those remain in source actors. A cache lookup is keyed and content-equal; full dictionaries remain cold snapshot/persistence/proof bridges. UI and eager projections read atoms only.

Freshness expiry does not delete accepted current-identity facts. Source owners keep their stable accepted baseline visible while loading or unavailable. Identity invalidation removes or rejects the exact old key through existing coordinator/cache ownership.

### GitWorkingDirectoryProjector

The projector remains the sole owner of local worktree intent, affected-path union, attention tier, freshness, admission, currentness, failure recovery, and EventBus publication.

It replaces the fixed 15-second fleet tick with per-worktree deadlines and one reschedulable earliest-deadline task. Per key it owns:

- current topology/root identity;
- accepted status-fact and line-detail baselines;
- requested and active attempt generations;
- at most one scope-unioning pending intent;
- immutable admission class captured at start;
- next status-fact, line-detail, capacity, and failure deadline;
- unchanged-result adaptation and automatic-start governor state;
- one opaque verified-clean authority for each accepted exact-clean worktree.

Attention changes update tier and deadlines. They create physical intent only when the accepted local fact is missing, invalidated, or stale for the new tier. Ordinary tab/sidebar changes with fresh facts perform no Git work.

Registration creates missing-baseline intent. Active and visible registrations receive priority; background registrations enter the same paced automatic governor and finite deadline path rather than bypassing admission as one eager fleet seed.

At a finite freshness checkpoint the projector first asks the status provider to renew the accepted verified-clean authority. A renewed authority advances the complete empty fact/detail freshness and adaptive cadence without acquiring Git capacity. A result that requires exact work retains one scope-preserving exact fallback intent under the existing priority, governor, capacity, and currentness rules. Known invalidations and explicit refreshes do not take the continuity fast path.

### AgentStudio local status composition

Agent Studio composes a single process-scoped local status physical gate and injects it into every production `AgentStudioGitWorkingTreeStatusProvider`, including filesystem and Bridge status consumers. Independent default provider construction may not create independent physical caps in production.

The gate owns:

- canonical-root same-read exclusion;
- process-wide physical status capacity;
- active native operation identities and true-completion release;
- completion wakeups for capacity-deferred owners;
- bounded physical lifecycle observation.

It does not choose product demand, tier, retry, publication, or UI behavior. The projector owns automatic pacing; other explicit status consumers use the same physical safety gate without inheriting background refresh policy.

`AgentStudioGitWorkingTreeStatusProvider` composes package-owned exact-clean proof with the Darwin continuity witness. It owns no demand, cadence, cache, retry, or publication policy. Before a full exact scan it asks the package for an opaque observation plan containing the complete Git dependency identity and the paths/scopes the platform must observe. It binds that exact plan into the witness and completes a stable start barrier before calling status. The facts read re-resolves and compares its Git dependency identity with the prepared plan; drift rejects clean authority while preserving ordinary exact facts. After an exact-clean result the provider completes a post-scan flush barrier and mints authority only when registration, mutation, uncertainty, and dependency identity epochs still match. For checkpoint renewal it returns exactly one typed outcome: `renewed(authority)` or `requiresExact(reason)`. A raced, unsupported, incomplete, or uncertain observation always returns `requiresExact`.

The projector captures the accepted authority identity before awaiting renewal and revalidates the same worktree, root, request generation, authority, and pending invalidation after the provider returns. The witness conditionally commits the renewal against its still-current epoch before projector freshness can advance. A mutation between provider return and freshness acceptance therefore makes the commit fail and preserves one exact fallback rather than being overwritten by a late renewal.

### agentstudio-git local contracts

At the current resolved package revision `56690acb6e9ac410d9ad5ade977c47395d7c9583`, `agentstudio-git` is already Git-shaped and product-agnostic and already exposes separate capabilities:

- status facts scoped by the existing safe pathspec contract, excluding full-worktree line-count detail;
- exact full-worktree line-count detail;
- an explicit complete-status composition for consumers that always require both.

Typed results already distinguish facts from detail; optional integers do not encode “not requested,” “unknown,” and “failed.” The status-fact reader does not perform `git_diff_tree_to_workdir_with_index` as a hidden side effect. The detail reader owns that exact operation. This existing foundation remains unchanged except that the fact read now returns package-owned observation-plan and exact-clean proof information required by the new continuity contract.

The retained v0.0.89 sample attributed 165 of 404 inclusive status-reader samples to the then-unconditional shortstat and 229 to status-entry collection. Revision `56690acb` already removed that hidden coupling; continuity extends this shipped split so a proven exact-clean result also skips the now-separate detail call and later unchanged checkpoints skip both physical reads.

Only a successful full facts read tied to the same prepared `GitStatusObservationPlan` may mint the opaque `GitExactCleanBaseline`. Its exact-clean predicate requires no staged change, tracked worktree change, conflict, rename, type change, unreadable entry, or recursively discovered untracked entry. Path-scoped and non-clean reads never mint it. An exact-clean baseline logically implies exact `0/0`, so the package skips the line-detail diff for that result.

The package observation plan records a complete dependency identity rather than paths inferred by Agent Studio: the worktree subtree; resolved per-worktree Git directory and index; common refs, configuration, packed refs, and `info/exclude`; applicable resolved ignore dependencies; and every transitive submodule HEAD, index, worktree, configuration, ignore, and Git-directory input consulted by the selected libgit2 status options. If the package cannot enumerate any consulted top-level or submodule input, or the platform cannot observe one of the supplied scopes, continuity is unsupported for that worktree while ordinary exact status remains available.

### Darwin Git clean continuity capability

The existing `DarwinFSEventStreamClient` gains a narrow `GitCleanContinuityWitness` capability consumed directly by the local status provider. App composition creates exactly one process-scoped client and injects the same object into both `FilesystemActor` and `AgentStudioGitWorkingTreeStatusProvider`; production defaults cannot silently construct a second witness. It is not routed through `FilesystemActor` or EventBus, because those lossy presentation/invalidation paths cannot prove the absence of a mutation. This adds no atom, store, EventBus case, generic scheduler, helper process, persistence owner, or coordinator responsibility.

For each admitted observation scope the witness retains registration generation, per-volume event cursor, mutation epoch, uncertainty epoch, stable barriers, and coverage state. Start and post-scan barriers flush the stream without holding the lifecycle lock, then revalidate every generation and epoch so delayed kernel delivery cannot create a false-clean interval. Relevant mutations advance the mutation epoch before ordinary filesystem delivery. FSEvent IDs and flags remain intact through classification. `MustScanSubDirs`, user/kernel drops, event-ID wrap, root change, mount/unmount discontinuity, stream-start failure, buffer overflow, registration replacement, and unsupported scope advance uncertainty and fail renewal closed. Git administrative mutations use the existing full-scope Git-internal invalidation semantics rather than a new EventBus fact. Shutdown first drains projector/provider renewal and retires all authorities, then shuts down the shared witness.

#### Shared exact-item observation

Package observation plans may contain exact item scopes outside repository-local subtrees, including resolved Git configuration origins and global ignore files. FSEvents watch roots are recursive directory hierarchies, so the witness must not realize an exact item by adding its parent directory independently to every worktree stream. That topology multiplies unrelated parent activity by the number of registered worktrees before exact-path classification and violates the process CPU contract.

The witness partitions one worktree plan into two internal coverage classes without changing the package contract:

```text
subtree scope or exact item already covered by that subtree
  -> worktree-local FSEvents registration
  -> existing continuity classification and ordinary worktree ingress

exact item not covered by a local subtree
  -> SharedExactItemParentObserver keyed by canonical parent + volume
  -> one FSEvents stream for that parent
  -> canonical exact-path subscriber index
       exact path -> dependent worktree registrations
```

`DarwinFSEventStreamClient` remains the one process-scoped owner. Each internal worktree continuity binding retains its root, observation identity, binding generation, local stream generation, local scopes, and participating shared-parent generations. Each shared parent observer retains its canonical parent and volume identity, stream generation, event cursor, coverage state, exact-path subscriber index, and subscriber references. This state is runtime-only. It adds no atom, store, coordinator, EventBus case, timer, persistence, or second Git-fact authority.

The changed callback path is selective:

```text
current repeated-parent path
  parent event -> N worktree callbacks -> N scope classifications -> N ledger candidates

shared exact-item path
  parent event -> one shared callback -> normalize once
               -> unrelated exact-path miss -> no worktree ledger mutation
               -> exact-path hit -> record mutation for indexed dependents
                                 -> enqueue existing full-scope Git invalidation
               -> ambiguous/loss event -> mark that parent's dependents uncertain
```

An actual shared-file mutation may invalidate many worktrees because those authorities genuinely depend on that file. For every exact-path hit, the shared callback first advances the dependent continuity-ledger mutation epochs and then submits one coalescible full-scope Git-internal invalidation per dependent through the existing filesystem ingress and debounce boundary. That scheduling disposition carries no fabricated filesystem path and introduces no EventBus case or second authority. Ingress overflow retains its full-scope disposition so a dropped presentation/invalidation batch cannot narrow the pending exact fallback. Unrelated activity under the same recursive parent touches neither worktree mutation epochs nor ordinary ingress.

The shared observer tracks cursor regression, wrap, drop, root, mount, and coverage uncertainty even for events that miss the exact-path index; uncertainty fans out only to registrations dependent on that parent. Every local or shared FSEvents hierarchy stream participating in continuity uses `WatchRoot` in addition to file-level delivery. `RootChanged` advances uncertainty and retires the affected stream and binding generation before ordinary routing; no new authority may mint until complete rebinding and a current exact scan. An ancestor or coalesced event that cannot prove which indexed item changed likewise fails that parent's dependents closed rather than consulting metadata and claiming uninterrupted continuity.

Binding and barriers form one composite coverage transaction. A shared parent stream must start and establish coverage before its subscriber is installed or any baseline barrier may begin. `prepare`, post-scan `commit`, and `renew` retain and flush the worktree-local stream plus every shared parent participating in the binding without holding the lifecycle lock, then revalidate the binding generation, observation identity, all contributing stream generations, mutation epoch, and uncertainty epoch before authority can mint or freshness can advance. Plan replacement, subscriber remapping, late callbacks from retired generations, shared-stream start failure, or a mutation during any barrier makes the affected registration require exact Git. There is no fallback that recreates one broad parent stream per worktree.

Unregister performs one lifecycle-serialized retirement: it first advances the worktree binding generation and retires authority so no new barrier or renewal can begin, then removes exact-path subscriber references and tears down the local registration. A shared parent observer remains live while any subscriber depends on it and stops at zero references. Shutdown first forbids new bindings and drains witness consumers, then retires worktree and shared-parent generations and tears down both stream classes. The cutover is internal and runtime-only: existing authorities are invalid after a binding-topology change, and the next accepted exact scan may mint authority only through the complete new composite binding.

The proof boundary must demonstrate selective ownership rather than only final Git correctness:

- many worktree plans sharing one external exact-item parent create one shared parent stream, and no worktree-local stream retains that broad parent;
- unrelated activity under the parent produces one callback/index miss, no ordinary worktree batch, and no dependent mutation epoch change;
- an exact-item mutation advances each indexed dependent's ledger before one coalesced full-scope invalidation enters existing ingress; overflow preserves that scope and unrelated misses enqueue nothing;
- loss, cursor, mount, or ambiguous coverage invalidates all dependents of that parent;
- every continuity hierarchy stream requests root-change delivery; watched-parent or ancestor rename/deletion retires authority before routing and recovers only through rebinding plus exact Git;
- delete, rename, atomic replacement, stream-start failure, plan replacement, late-generation callback, unregister/renew overlap, and mutation across every barrier fail authority closed;
- local subtree delivery, deepest-owner routing, and ordinary filesystem debounce remain unchanged;
- real disposable repositories sharing a disposable external config file prove both positive renewal and exact fallback without mutating user repositories or global Git configuration;
- the complete real-root exact-PID workload proves that unrelated shared-parent activity no longer creates worktree-count callback fan-out and that idle and action CPU remain inside the declared budgets.

### RemoteReferenceRefreshActor

This new Core actor owns demanded server-current remote-tracking refs per repository. It consumes repository demand, current origin/remote name, canonical repository path, topology generation, and explicit refresh.

Per repository it owns:

- last successful fetch time and freshness deadline;
- origin/topology generation;
- the accepted remote-reference origin/generation token required by local ahead/behind composition;
- cleanup custody for the reserved generation-scoped ref namespace;
- one active fetch and one latest complete pending intent;
- process-wide fetch-capacity admission;
- failure/rate/timeout backoff;
- completion-triggered targeted local recomputation.

It calls a typed `agentstudio-git` staged-fetch contract with noninteractive prompt policy. Registration first captures the current remote configuration and canonical ref tips as one immutable local snapshot, establishing the immediate last-fetched acceptance token without claiming server freshness. Admission captures that exact origin URL, remote name, repository identity, and topology generation. The child fetches captured remote refs into a reserved generation-scoped private namespace without updating `FETCH_HEAD` or canonical `refs/remotes/*`. After child exit, the actor revalidates origin and generation; only a current completion may promote the complete staged update/delete set to canonical remote-tracking refs in one ref transaction and create a new `RemoteReferenceAcceptance` token for that exact origin/generation. Stale, cancelled, removed, or shutdown completions clean their staging namespace and cannot promote. Startup and shutdown also sweep abandoned refs under only that reserved namespace; cleanup failure remains observable and retryable, while staged refs stay invisible to canonical readers. Default automatic freshness is three minutes for active/visible demand, aligned with the confirmed product promise and PR freshness floor. Hidden demand stops future fetches without deleting current-origin accepted remote refs or ahead/behind facts. Explicit refresh bypasses freshness but not capacity, active single-flight, or failure/rate policy.

One successfully promoted repository fetch refreshes shared remote refs once, then requests targeted local status recomputation for all currently represented worktrees in that repository. The recomputation carries the accepted remote-reference token; local ahead/behind composition publishes counts only while that token still matches the repository's current origin/topology generation. Origin change invalidates the prior token and ahead/behind publication authority before any new local self-heal can read old refs. The actor does not emit ahead/behind directly or duplicate local Git materialization authority.

The selected initial physical policy is one automatic fetch process at a time, a 120-second child-process timeout inherited from the current `agentstudio-git` remote contract, and the three-minute automatic retry floor. These are `AppPolicies` values at composition; provider defaults are not hidden product policy.

### ForgeActor and GitHubCLIForgeStatusProvider

`ForgeActor` retains repository membership, current origin generation, demanded branch scope, stable presentation, one active request plus one latest complete follow-up per repository, freshness, recovery, and Forge publication.

The successful automatic freshness floor remains three minutes. Manual refresh bypasses freshness but not active single-flight, process capacity, or authoritative rate-limit/backoff. Losing demand cancels active child work, clears pending automatic intent, stops future deadlines, and preserves current-origin accepted facts.

Forge adds one process-wide GitHub CLI capacity of two child processes. Capacity-deferred repositories retain their latest intent and are woken by child completion or the single earliest deadline. Capacity is not failure.

An equivalent automatic trigger received during an active request may schedule one eligibility recheck after the existing one-second contraction delay, but success freshness still gates physical work until `lastSuccessfulRefreshAt + 180 seconds`. A changed complete demanded-branch set containing an unconfirmed branch and explicit manual intent use their separately defined freshness bypass while still obeying single-flight, CLI capacity, and rate/failure policy.

The provider changes from repository-wide `pullRequests(first: 100)` pagination to a demanded-branch query plan. GitHub officially supports `Repository.pullRequests(headRefName:)`; one GraphQL request may use bounded aliases for multiple demanded branches. The provider:

- normalizes and stably orders demanded branch names;
- groups them into bounded alias batches under GitHub node and response limits;
- requests only open PRs for each aliased `headRefName`;
- returns a typed per-branch completeness map;
- treats the complete multi-batch query as one repository-scoped transaction: every demanded alias connection must completely paginate and validate before any branch publishes;
- rejects the entire plan on any truncated, incomplete, failed, or rate-limited batch, retaining all prior or unknown branch facts;
- records branch count, alias batch count, node bound, and result completeness under scrubbed telemetry.

The current page size 100 and repository-wide 200-result cap cease to be the ordinary demanded path. A bounded repository-wide fallback is permitted only when branch filtering cannot express the requested complete scope, and its use is an observable outcome rather than a silent widening.

Each `gh` child retains the current eight-second process timeout. Automatic failure, truncation, and rate-limit recovery uses:

```text
nextEligibleAt = max(
  lastAutomaticAttempt + 180 seconds,
  exponentialFailureBackoff,
  authoritativeRetryAfter
)
```

The existing 5/10/20/40/60-second backoff still constrains manual reattempt after ordinary failure, but automatic retry never runs faster than three minutes. After three unsuccessful outcomes, presentation may become unavailable while retaining prior current-origin confirmed facts.

### DefaultProcessExecutor child settlement

`DefaultProcessExecutor` remains the sole owner of generic child launch, pipe draining, timeout, cancellation termination, and exact exit observation. Its async `execute` boundary settles only after the launched child has exited and both output pipes have finished. Task cancellation requests `SIGTERM`, retains the existing bounded `SIGKILL` escalation, and records cancellation as the caller result only after that physical settlement. Cancellation does not remove the process-exit or pipe sources early. The executor latches the first accepted termination cause: timeout produces `ProcessError.timedOut`, cancellation produces `CancellationError`, and a later competing cause cannot replace the first while physical settlement remains in progress.

This contract lets source owners distinguish logical interest from physical custody without a Forge-specific process runner. `ForgeActor` may clear publication authority and pending automatic intent immediately on demand or identity loss, but its process-wide capacity lease remains held until the provider call returns after exact child settlement. Existing consumers such as `ZmxBackend` keep the same `ProcessExecutor` interface and result/error vocabulary; they gain the stronger guarantee that a returned cancellation never leaves the owned child running. Timeout continues to return `ProcessError.timedOut` after the same exact-exit settlement.

### WorkspaceCacheCoordinator and derived projections

The coordinator remains the only EventBus-to-cache applier. Local, remote-ref-triggered local, and Forge results converge through existing typed events; the coordinator performs keyed changed-only atom writes and exact invalidation. It owns no source admission or freshness.

Repo Explorer, tab bar, toolbar, command surfaces, and other hot readers use keyed `AtomFamily.value(for:)` or demanded eager-derived slots. Whole-cache snapshots are permitted only for cold bridges, persistence, isolated off-main capture, and proof. Source freshness changes that do not alter presentable accepted content do not wake unrelated UI keys.

## Current-to-target call paths

### Consumer cache path

```text
CURRENT
UI/derived reader -> RepoCacheAtom keyed or bulk read -> presentation
some broad captures rebuild whole snapshots after unrelated fact writes

TARGET
UI/derived reader
  -> [unchanged] exact keyed RepoCacheAtom/AtomFamily read
  -> [added] accepted-value state is always the immediate answer
  -> [changed] demanded eager projection captures affected keys only
  <- cached value / loading / unavailable presentation
  [removed] render/body -> any Git, fetch, gh, or demand side effect
```

### Repository-fact attention path

```text
CURRENT
active-pane observation ---------------------> setActivePaneWorktree
filesystem projection activity --------------> setActivity
rendered viewport rows -> visible-worktree atom -> setSidebarVisibleWorktrees
separate PR-demand observation --------------> ForgeActor.setDemand
  [defect] four partial values can disagree, and scrolling/rendering owns source attention

TARGET
canonical window/tab/pane/sidebar/topology IDs
  -> [added] one complete RepositoryFactDemandSnapshot capture
  -> [added] complete-value equality and latest-value contraction
  -> [changed] one pipeline fan-out
       active/open ingress IDs ------> FilesystemActor
       local attention IDs ----------> GitWorkingDirectoryProjector
       attended repository IDs -----> RemoteReferenceRefreshActor
       attended worktree IDs --------> ForgeActor
  [removed] FilesystemProjectionIndex as attention authority
  [removed] setActivity fan-out from FilesystemProjectionIndex to filesystem + Git owners
  [removed] viewport/search/grouping/row-materialization -> demand
  <- fresh cache suppresses physical work; changed attention alone is not a source call
```

### Local filesystem and self-heal path

```text
CURRENT
FSEvent -> 500ms debounce / 10s max flush
  -> 500ms derived coalescing
  -> projector pending changeset
  -> per-worktree deadline + governor
  -> separate status-facts call
  -> detail call when changed/missing/explicit/due
  -> one-second threshold is slow observation; native completion retains custody

TARGET
initial full exact baseline
  -> package resolve GitStatusObservationPlan(identity + opaque scopes)
  -> shared Darwin witness bind scopes + flush start barrier
  -> package full status-facts read tied to prepared identity
       ├─ identity drift / non-clean / unsupported -> no authority
       └─ exact clean -> candidate baseline + implied exact 0/0
  -> shared Darwin witness flush post-scan barrier
       ├─ epoch/generation changed -> requiresExact(reason)
       └─ stable -> mint verified-clean authority
  -> projector validates worktree/root/request/current invalidation
  -> accept complete candidate and authority or retain exact fallback

finite tier-specific checkpoint
  -> provider renew(verified-clean authority)
       ├─ renewed
       │    -> exact empty candidate + exact 0/0
       │    -> no physical Git and no Git-capacity acquisition
       └─ requiresExact(reason)
            -> existing priority/governor/capacity admission
            -> safe path-scoped or full status facts
            -> detail only when invalidated/changed/missing/explicit/due
            -> full exact clean may mint replacement authority
  -> witness conditionally commits still-current renewal
  -> projector revalidates generation/root/authority/pending invalidation after await
  <- exact fallback when raced; otherwise changed EventBus fact or content-equal suppression

FSEvent / known mutation / explicit refresh
  -> bounded debounce and scope-preserving changeset union
  -> invalidate clean authority before ordinary delivery
  -> existing exact/scoped admission path above
```

### Demanded remote-reference path

```text
CURRENT
local status reads ahead/behind from whatever remote-tracking refs exist
  [missing] no Agent Studio demand-owned fetch path

TARGET
RepositoryFactDemandSnapshot changed
  -> [added] RemoteReferenceRefreshActor cache/freshness admission
  -> fresh local refs: no work
  -> stale demanded repo: process-capacity admission
  -> agentstudio-git noninteractive fetch into generation-scoped refs
  <- success / timeout / failure / cancellation
  -> generation/origin validation
  -> current success atomically promotes refs and accepts origin/generation token
  -> stale success cleans staged refs without mutating canonical refs
  -> promoted success requests token-carrying targeted local recomputation
  <- changed ahead/behind atom publication or equality suppression
```

### Demanded Forge path

```text
CURRENT
visible demand / branch / origin / manual / deadline
  -> ForgeActor freshness and per-repo single-flight
  -> unbounded-across-repositories gh child start
  -> repository-wide open-PR GraphQL pages
  -> local demanded-branch filtering
  <- generation/current-demand validation and keyed publication

TARGET
same triggers
  -> [unchanged] one Forge admission owner and three-minute freshness
  -> [added] global gh capacity two
  -> [changed] demanded-branch alias query plan
  -> [changed] DefaultProcessExecutor cancellation retains physical custody through child exit
  <- typed atomic repository-plan complete/truncated/rate/failure outcome
  -> [changed] equivalent one-second follow-up rechecks eligibility but cannot bypass success freshness
  -> [changed] automatic retry floor always at least three minutes
  -> [unchanged] current origin/generation/demand validation
  <- [unchanged] keyed changed-only PR/check/review publication
```

## State and lifecycle

Each source owner uses the same semantic states but owns separate instances and deadlines:

| State | Meaning | Valid transitions |
| --- | --- | --- |
| Cached current | Accepted complete current-identity value; no required work | invalidation, demanded freshness expiry, explicit refresh, identity removal |
| Cached stale | Accepted value remains presentable; refresh intent exists or awaits demand | admission, demand loss, identity removal |
| Pending | One latest complete/scope-unioning intent, no physical work | admit, merge/replace, capacity defer, identity removal |
| Physically running | Immutable source identity, generation, scope, class, start time | completion, slow observation, pending merge, cancellation interest, shutdown |
| Capacity deferred | Pending intent retained; no source health change | physical completion wake, capacity deadline, priority change, demand loss |
| Failure backed off | Accepted value retained; genuine failure and eligible-at deadline | deadline, explicit request subject to policy, identity change |
| Unavailable | Presentable honesty state after bounded unsuccessful attempts; accepted prior facts may remain | successful recovery, identity change |
| Removed/wrong identity | No publication authority | new authoritative registration/origin only |

Local status additionally composes fact and detail phases inside one materialization attempt. Fact completion may release its physical slot before detail starts, but the projector retains same-worktree single-flight and does not admit the follow-up between phases. Automatic duty accounting sums both native phases.

Verified-clean continuity adds the following local substates without changing the shared source lifecycle:

| Local continuity state | Meaning | Valid transition |
| --- | --- | --- |
| No baseline | No accepted exact-clean authority | full exact scan, removal |
| Exact clean preparing | Observation barrier surrounds a full exact scan | verified clean current, exact fallback pending, removal |
| Verified clean current | Accepted exact-clean facts and matching witness authority | continuity renewal, mutation, uncertainty, explicit refresh, identity change |
| Continuity renewed | Checkpoint accepted with no physical Git | verified clean current at next deadline, mutation, uncertainty |
| Mutated | Relevant dependency changed | exact fallback pending/running |
| Uncertain | Coverage, cursor, registration, or dependency proof failed | exact fallback pending/running |
| Exact fallback pending/running | One retained exact intent owns recovery | verified clean current, accepted non-clean, failure recovery, removal |
| Removed | No baseline or publication authority | new authoritative registration only |

Renewal without an exact baseline, renewal across epoch or identity mismatch, uncertainty treated as unchanged, a path-scoped result minting a baseline, fallback loss during coalescing, and late authority advancing freshness are illegal and fail closed.

Remote fetch and Forge use killable child processes. Cancellation requests termination through the owning executor; the executor retains exit and pipe observation, escalates to a bounded hard kill when required, and settles the async call only after exact child exit. Source actors may revoke logical publication authority immediately but retain physical capacity until that settled return. Remote fetch writes only generation-scoped staging refs before currentness validation; stale completion cleanup cannot promote them. Forge rejects an incomplete repository plan as a unit. Both owners reject any completion after demand/origin/topology generation changed.

Illegal transitions fail closed: publication from obsolete identity/generation/scope, second same-key physical work, capacity release before true completion/exit, capacity counted as failure, partial local publication, canonical-ref promotion before currentness validation, automatic remote work without demand, and rendering-triggered source work.

Demand delivery is one complete-value consistency boundary. No source owner observes a mixture of old active-pane, sidebar, open-pane, or Forge demand fields. A cancelled or superseded delivery does not advance the delivered baseline; the coordinator retains one latest complete pending snapshot and replays it after the in-flight delivery settles. Shutdown delivers and drains `.empty` before source-owner shutdown, then rejects late observation callbacks.

## Deadline and admission model

Each source actor owns exactly one reschedulable next-deadline task. A state change cancels the prior wait, recomputes the earliest useful instant, and installs one successor through the injected clock seam. A stale wake recomputes and has no authority.

Local deadline candidates include status freshness, line-detail freshness, verified-clean checkpoint renewal, automatic governor, capacity fallback, and genuine failure. Remote-ref and Forge candidates include demanded freshness, capacity fallback, provider backoff, and authoritative retry-after. Forge's one-second equivalent-follow-up candidate is an eligibility recheck only; it never advances a same-scope automatic physical start ahead of the three-minute successful-result floor.

Local automatic pacing uses completed physical duty:

```text
nextAutomaticStartAt = max(
  previousAutomaticStart + minimumAutomaticStartInterval,
  lastAutomaticCompletion + durationDerivedDutyGap
)
```

Foreground invalidation and explicit local refresh may bypass automatic time pacing but never same-root exclusion, physical capacity, generation validation, or foreground reservation. Explicit remote refresh may bypass freshness but never demand identity, active single-flight, child capacity, or rate/failure policy.

The selected policy set remains centralized in `AppPolicies`:

- local filesystem debounce 500ms and maximum flush latency 10s;
- local derived coalescing 500ms and visibility contraction 200ms;
- local freshness bases active 15s, visible 60s, open 180s, background 240s with finite 1x/2x/4x adaptation;
- local physical status capacity four process-wide, with per-class reservations preserved and automatic governor proof-tuned;
- remote-ref and Forge automatic freshness floor 180s;
- remote fetch capacity one and child timeout 120s;
- Forge CLI capacity two, child timeout 8s, pending equivalent eligibility recheck delay 1s, and failure honesty threshold three;
- source capacity recheck remains short and bounded; automatic source failure never retries faster than its source freshness floor.

## Failure, recovery, and consistency

### Cache expiry and demand loss

Expiry changes source-owner state, not accepted atom content. A stale accepted value remains visible while demanded refresh proceeds. Demand loss cancels remote interest and future deadlines, clears pending automatic remote intent, and preserves accepted current-identity facts. Local correctness intent survives demotion and returns to its background deadline.

### Local slow or failed work

The one-second local threshold becomes slow observation rather than physical completion. Non-cancellable libgit2 work retains same-root and capacity custody until return. New invalidation advances requested generation and merges one follow-up. Current complete success may publish; stale success changes no accepted/freshness/equality baseline; genuine SDK failure enters local failure backoff.

Fact success followed by detail failure publishes nothing partial. The prior complete candidate remains visible, complete-detail demand survives, and genuine failure recovery owns the next eligible attempt.

Observer uncertainty preserves the last accepted facts and retains exactly one exact fallback intent. One uncertainty generation cannot enqueue fleet duplicates. A global observer restart may invalidate many authorities, but recovery still flows through the existing attention priority, automatic governor, process capacity, and same-root exclusion. Mutation during the baseline scan or either renewal barrier rejects the authority. Any non-clean exact result clears it. Worktree removal and shutdown clear both authority and observer scope. Continuity outcomes are validation outcomes and never enter source-failure backoff.

### Remote fetch failure

Fetch failure, timeout, or noninteractive credential failure preserves current-origin accepted remote refs and ahead/behind. The actor records a genuine failure deadline and presentable remote freshness remains last-fetched, never fabricated as server-current. Rate/auth failure does not trigger interactive prompts. Stale or cancelled completion cleans only its generation-scoped staging refs. A crash may leave private staged refs, but startup cleanup owns them and canonical readers never observe them. Successful current-generation fetch atomically promotes its complete staged update/delete set, accepts one origin/generation token, closes failure state, and requests token-carrying local recomputation.

### Forge failure, truncation, and rate limiting

Incomplete branch responses preserve the entire prior repository presentation: no completed sibling batch publishes early. Ordinary failure, truncation, and rate limiting reject the repository plan atomically and retain current-origin stable presentation. Automatic next eligibility is never before last attempt plus three minutes and respects longer `Retry-After`. An equivalent automatic follow-up after success cannot bypass successful-result freshness; manual refresh and a changed demanded set containing an unconfirmed branch cannot bypass active child, capacity, or authoritative rate limit.

### Identity and ordering changes

Local work captures worktree/root generation. Fetch captures repository/origin/topology generation and cannot mutate canonical remote-tracking refs before validation. Forge captures repository/origin generation and complete demanded branch set. Origin change, origin loss, repository removal, worktree replacement, branch change, and shutdown advance or invalidate the appropriate generation before cancellation. Origin change also invalidates the accepted remote-reference token before local recomputation. Late results cannot promote refs, publish, or update freshness/equality baselines.

### Shutdown

Shutdown first stops demand observation, forbids new starts, cancels all deadline tasks, invalidates publication generations, requests child-process cancellation, and cancels logical interest in native reads. Child capacity releases only after exit; native capacity releases only after true completion or owning process exit. Existing exact AppKit termination and trace-drain sequencing remains authoritative.

`DefaultProcessExecutor` keeps its process and pipe dispatch sources alive during cancellation and shutdown until exit plus pipe settlement. A caller awaiting cancellation therefore cannot finish shutdown or release its source capacity while the child remains alive. Timeout and cancellation racing during settlement preserve the first accepted termination cause while sharing the same termination, hard-kill, exit, and pipe-drain path.

## Observability and proof architecture

Every often/heavy stage aggregates bounded owner-local counters/histograms before the trace queue. Exact per-attempt events are limited to the marker-scoped performance diagnostic path.

Required outcome families:

- demand: projected, content-equal, delivered, cleared;
- cache: hit-fresh, hit-stale, unknown, unavailable, wrong-identity;
- source selection: topology, local-ref, local-status, line-detail, remote-fetch, Forge;
- contraction: coalesced, replaced, retained-scope count, max-flush admission;
- admission: fresh-suppressed, no-demand, automatic-paced, capacity-deferred, same-key-deferred, admitted by class;
- physical: started, slow, caller-cancelled, settled, truly completed/exited, failed, active-at-shutdown;
- query: path/full, fact/detail, avoided-fact-read, avoided-detail-read, fetch-staged/promoted/abandoned/cleaned, demanded-branch alias count, fallback-wide, returned node/result count, atomic-plan completeness;
- validation: current, stale-generation, stale-root/origin/branch/demand, exact-clean-baseline prepared/accepted/rejected, continuity-renewed, mutation-invalidated, uncertainty by bounded reason, exact-fallback admitted/coalesced, removed, shutdown;
- publication: published, content-equal, partial-rejected;
- recovery: capacity-rearmed, failure-opened/closed, rate-limited, unavailable/available;
- debt: pending count by source/reason, physical count, current verified-clean authority count, oldest authority/checkpoint age, oldest physical age, next deadline distance.

```text
DETERMINISTIC PROOF
injected clocks + controllable local/child providers
  -> real demand projection and source actor state
  -> cache hit/no-call, debounce, freshness, capacity, generation flows
  -> positive continuity renewal makes zero physical calls
  -> uncertainty retains exactly one exact fallback and foreground priority
  -> observed starts, query scopes, pending intent, publication, recovery

PACKAGE PROOF
agentstudio-git real disposable repositories/remotes
  -> status-fact versus detail cost/contract
  -> differential exact-clean cases: nested untracked, staged, conflict, rename,
     type change, unreadable, linked index, HEAD/ref/config/ignore mutation,
     and transitive submodule HEAD/index/worktree/config/ignore/Git-directory mutation
  -> observer drop/wrap/root-change/start-failure/re-registration/barrier races fail closed
  -> mutation before registration, during scan, between scan and post-barrier,
     during renewal, and between provider return and freshness acceptance fails closed
  -> path/full compatibility and zero detail read for exact clean
  -> staged noninteractive fetch, current promotion, stale cleanup, and cancellation/timeout
  -> complete package check before revision consumption

RUNTIME PROOF
strict verifier
  -> real isolated debug identity
  -> both complete watched roots, 5 tabs, 20 pane models, zero/one PTY
  -> real demand projection, local Git, remote fetch, gh GraphQL, EventBus,
     keyed atoms, eager projections, native sidebar/toolbar
  -> Victoria outcomes + exact-PID CPU + native read-back
  -> graceful exact-candidate retirement and zero required loss
```

Final runtime proof may use controlled disposable remotes for staged-fetch mutation while the topology scale comes from the complete real watched roots. It must not mutate user repositories or global Git configuration. Immediately before the timed idle interval, the verifier injects one controlled local observer uncertainty and ends that proof action; it starts idle sampling before the retained exact fallback settles. The measured interval therefore includes fallback CPU and complete recovery without including the injection action. The same interval includes at least one complete maximum local self-heal checkpoint and positive continuity renewals. With the selected 240-second background base and 4x adaptation, retain at least 1,000 usable one-second samples; if policy tuning lengthens the maximum, the proof horizon lengthens with it. Settlement requires no overdue deadline, physical work within source gates, preparation debt classified by reason, and oldest debt plus next deadline within policy. Inventory and include every debug-owned descendant/helper process so cost cannot pass by relocation. The final marker must meet idle p99 and action p95 CPU targets with zero hidden loss or uncertainty. No fake substitutes for production watched-folder discovery, production provider wiring, native UI materialization, exporter delivery, or exact process identity.

## Requirement, realization, and proof trace

| Requirement | Structural realization | Proof seam |
| --- | --- | --- |
| U-GIT-IDLE-CPU-1 | cache-first reads, local governor, hidden-remote stop, bounded physical gates | real-root policy-derived full-self-heal-cycle zero-PTY exact-PID population plus source metrics |
| U-GIT-ACTION-CPU-1 | content-equal demand, fresh-cache suppression, keyed projections | native action/read-back populations with exact-PID samples |
| U-GIT-CACHE-FIRST-1 | RepoCacheAtom families, source-owner freshness, keyed eager reads | cache hit/no-source and keyed revision proof |
| U-GIT-SOURCE-SUFFICIENCY-1 | three source owners consuming one demand snapshot | source-selection behavior and end-to-end fact provenance |
| U-GIT-SELF-HEAL-1 | finite local/detail deadlines, verified-clean renewal, fail-closed exact fallback, and first-demand remote deadlines | injected-clock renewal/fallback longitudinal and demanded-checkpoint proof |
| U-GIT-FOREGROUND-1 | shared demand class, immutable admission, source capacity/reservation | blocked-background/remote interleavings and stressed action proof |
| U-GIT-ADMISSION-1 | bounded contraction, one active/one pending, deadline owners | outcome-accounted state tests and telemetry ratios |
| U-GIT-LOCAL-EFFICIENCY-1 | fact/detail package cutover, exact-clean baseline, loss-aware continuity, safe pathspec, complete materialization | package differential/observer proof, compatibility/timing, and app zero-call renewal proof |
| U-GIT-REMOTE-REF-1 | RemoteReferenceRefreshActor and targeted local recomputation | demanded fetch/cache/failure integration and read-back |
| U-GIT-FORGE-1 | existing branch cache plus alias query plan/global CLI capacity | GraphQL plan, recovery, cache, and toolbar/sidebar agreement |
| U-GIT-CURRENTNESS-1 | per-source captured generations/scopes and changed-only applier | A/B/C identity/invalidation interleavings and integration publication |
| U-GIT-PHYSICAL-BOUND-1 | shared status gate, exact-settling `DefaultProcessExecutor`, and child-process capacity owners | non-cooperative native plus cancellation/timeout exact child-exit lifecycle proof |
| U-GIT-OBSERVABILITY-1 | bounded owner-local aggregation and marker snapshots | aggregation bounds, perturbation check, zero-loss runtime marker |
| U-GIT-PROOF-1 | exact-debug fixture/lifecycle and package/app real boundaries | complete two-root 5/20 proof chain and native evidence |

## Hard cutover and compatibility

This is one holistic internal cutover:

- one App demand snapshot replaces independently drifting visibility/demand observations, and sidebar attention changes only with canonical sidebar presentation or semantic membership rather than search, grouping, scrolling, or rendering;
- the already-landed earliest-deadline path remains authoritative; no local fixed fleet tick returns;
- the already-landed slow-observation threshold continues to retain native physical custody;
- the already-landed `agentstudio-git` fact/detail split remains authoritative;
- `agentstudio-git` exact-clean baseline and Darwin continuity capability land together with provider/projector consumption;
- all production local status consumers share one process-scoped physical gate;
- demanded remote refs acquire staged-fetch/promotion ownership without changing local-status truth ownership;
- Forge gains global CLI capacity, branch-scoped GraphQL planning, and consistent three-minute automatic recovery;
- the verifier replaces zero-debt settlement with reasoned preparation debt plus bounded automatic/physical activity.

There is no persisted migration and no dual runtime scheduler. Deadline, demand, capacity, and physical state rebuild from current topology and accepted runtime facts at launch. Existing Git/Forge EventBus facts and UI fact shapes remain stable except for deliberate source-detail contract changes internal to the package/app boundary.

The package cutover starts from Agent Studio's current exact pin `56690acb6e9ac410d9ad5ade977c47395d7c9583`, itself a verified descendant of `474bf34210dd8e176f9b3585b061161a8e8b50d4`. The already-shipped fact/detail and staged-fetch contracts remain the foundation. One reviewed descendant adds only exact-clean proof and complete observation-dependency discovery while preserving the blocking-read executor and every unrelated discovery/review/remote contract. Agent Studio verifies ancestry and API/content preservation, updates its exact revision, and cuts the provider/projector to that proof contract. The package baseline contract, shared Darwin witness, provider composition, and projector consumption are a hard cutover with no compatibility path. Rollback restores the prior app provider/projector and prior exact package revision together.

Architecture enforcement prevents:

- source calls from render/body/materialization paths;
- viewport, search, grouping, or row-materialization state from owning repository-fact demand;
- enrichment, path, cache-dictionary, or fleet presentation reads inside demand capture;
- a second local fleet timer or generic cross-source scheduler;
- hidden line-detail work inside status-fact reads;
- a path-scoped, non-clean, raced, unsupported, or observation-uncertain result minting or renewing exact-clean authority;
- treating missing events, event loss, observer restart, or identity drift as proof of no Git change;
- independent production status providers bypassing the shared physical gate;
- automatic remote work without demand;
- direct demanded fetch mutation of canonical remote-tracking refs before origin/generation validation;
- ahead/behind publication without the current accepted remote-reference token;
- repository-wide GitHub fallback without bounded observable justification;
- partial publication from an incomplete multi-batch Forge repository plan;
- capacity reasons entering failure backoff;
- capacity release before native completion or child exit;
- process-executor cancellation returning before exact child exit and pipe settlement;
- partial or obsolete publication;
- stable/beta targeting from strict proof.
