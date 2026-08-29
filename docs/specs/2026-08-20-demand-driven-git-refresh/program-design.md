# Demand-Driven Repository Fact Refresh Program Design

Requirements: [Demand-Driven Repository Fact Refresh Requirements](requirements.md)

Specification: [Demand-Driven Repository Fact Refresh Specification](specification.md)

## Integrated design

Agent Studio answers repository-fact consumers from keyed accepted atoms first. One App-owned demand projection derives the complete attention snapshot once and forwards content-changed demand to three independent source owners:

```text
Darwin FSEvents (paths + IDs + loss flags)
  + Agent Studio owned-fetch mutation attribution
              │
              ▼
RepositoryLocalActivityProjector (off-main, repository-keyed contraction)
              │
              ├─ factual SQLite activity/cursor persistence
              └─ changed-only RepositoryLocalActivityAtom publication
                                      │
workspace/window/pane/sidebar state  │
              + repository-local-activity evidence
              │
              ▼
RepositoryActivityClassifier (Core, pure and off-main)
  ├─ complete repository/worktree topology
  ├─ open pane associations
  ├─ repository-keyed qualifying activity + coverage authority
  ├─ warm / unknown / locally inactive by repository
  └─ next sixty-day transition instant
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

targeted fetch-only repository AppCommand
              │
              ▼
FilesystemGitPipeline remote-reference update join
  └─ one canonical-repository staged fetch
       └─ represented-worktree local ref/status recomputation
              │
              ▼
RepoCacheAtom keyed update progress
              │
              ▼
Repo Explorer: memorychip status / revealed Refresh chip / progress indicator

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

The three source owners share the same stage vocabulary—cache check, contraction, freshness admission, single-flight, physical execution, generation validation, changed-only publication—but they do not share mutable scheduling state or one generic scheduler. Local filesystem truth, remote-tracking refs, and GitHub PR facts have different authorities, costs, failure modes, and recovery rules. The explicit Refresh join owns one fetch-only user-visible attempt and its resulting local recomputation lifetime; it does not become a second source-freshness owner.

## Why this structure

The structural crux is where “good enough” becomes a decision. Putting that decision in views recreates render-triggered work; putting product demand in `agentstudio-git` mixes product policy into the data plane; treating event silence as Git truth would make the filesystem observer a second source of repository facts; putting every source behind one scheduler erases authority and recovery differences. The selected design keeps product demand and freshness policy in the projector, exact-clean semantics and dependency identity in `agentstudio-git`, loss-aware continuity evidence in the existing Darwin observation boundary, proof composition in the local status provider, and accepted values in keyed atoms.

| Alternative | Gain | Cost | Decision |
| --- | --- | --- | --- |
| Views call sources when data looks missing | Minimal plumbing | Render-triggered work, duplicated policy, no reliable capacity | Reject |
| One repository-fact scheduler owns local Git, fetch, and Forge | One queue and vocabulary | Mixed authority, coupled failures, complex priority across unrelated sources | Reject |
| Existing independent source actors consume one App demand snapshot | Singular demand semantics with source-owned freshness/recovery | Current foundation to preserve | Select |
| Every finite checkpoint performs exact Git | Simple correctness story | One 0.6–3.8 second read can breach idle p99; complete attended demand produces continuous fleet waves | Reject |
| Treat missing filesystem events as unchanged | Minimal implementation | Silent stale facts after drops, gaps, linked-worktree metadata mutation, or unsupported observation | Reject |
| Exact-clean baseline plus loss-aware continuity | Keeps Git as truth while avoiding repeated unchanged traversals | Requires observer uncertainty/epoch semantics and package/app proof composition | Select |
| Repeat every shared exact-item parent in every worktree stream | Reuses one stream shape | A shared config parent recursively wakes and classifies once per worktree for unrelated events | Reject |
| Shared exact-item parent observers with selective subscriber fan-out | One recursive callback and one exact-path lookup for unrelated parent activity | Adds internal composite-binding and shared-observer lifecycle | Select |
| Per-file vnode observers or metadata-only validation | Narrow apparent wake or simple checkpoint read | Replacement/re-arm ambiguity or loss of uninterrupted observation proof | Reject |
| Unconditionally fail every shared-parent ancestor event to exact Git | Simple fail-closed disposition | The strict real-root run never reached quiescence, while exact-PID sampling showed concurrent full status work and repeated UI layout | Reject |
| Authority-bound stable exact-item fingerprints for ancestor-only ambiguity | Resolves ordinary shared-parent noise before full Git while preserving exact fallback for change, loss, unsupported state, or race | Adds bounded off-executor file reads, content digests, ambiguity epochs, and interleaving proof inside the continuity owner | Select |
| Repository-root mtime or recurring tree scan determines inactivity | No activity ledger | Deep changes are missed by root mtime; a recurring scan recreates the work being removed | Reject |
| Persist local Git/PR snapshots for inactive rows | Rich chips survive restart | New schema and stale facts look current; storage work exceeds the compact UX need | Reject |
| Application-open recency determines inactivity | Reuses current table and atom | Viewing is not repository activity; missing history falsely classifies active repositories cold | Reject |
| Dedicated positive-evidence activity ledger plus replayable FSEvents coverage | Actual local activity controls admission; missing/gapped evidence stays truthful | Adds one keyed atom, factual SQLite records, off-main contraction, cursor replay, and cutover proof | Select |
| One generic cross-source refresh transaction | One apparent success bit | Violates the selected fetch-only promise and couples independent authorities | Reject |
| One canonical-repository fetch intent plus represented-worktree recomputation | One truthful loading lifetime and one network operation regardless of worktree count | Requires remote settlement to include downstream recomputation | Select |
| Process-isolated local status helper | Hard kill boundary | IPC, worker lifecycle, cost relocation, wider proof | Defer unless in-process design fails its falsifiers |

The design reuses `RepoCacheAtom`, `AtomFamily`, `WorkspaceCacheCoordinator`, `GitWorkingDirectoryProjector`, `DarwinFSEventStreamClient`, `AgentStudioGitWorkingTreeStatusProvider`, `ForgeActor`, `PullRequestDemandProjection` semantics, the `agentstudio-git` remote process runner and parsing foundation, `EagerDerivedAtomFamily`, the EventBus, and the exact-debug proof path. The inactivity correction adds one dedicated `RepositoryLocalActivityAtom`, factual application-local SQLite activity and FSEvents cursor records through one `RepositoryLocalActivityStore`, one off-main keyed activity contractor, the pure classifier, and the existing earliest-boundary demand/projection lanes. It adds no EventBus case, generic scheduler, cross-source coordinator, persisted Git/PR snapshot, repository tree scan, or polling loop. SQLite stores stable keys, timestamps, cursors, and checked booleans only; `pending`, `validating`, `authoritative`, and `unknown` remain typed application state rather than database enum strings or magic integer variants.

Revisit process isolation only if one admitted local operation still violates the action CPU target after duplicated detail work and fleet admission are absent, or a native read demonstrably cannot finish within the accepted process lifecycle. Any future helper CPU must be included in user-capacity proof.

## Component ownership

### RepositoryLocalActivityAtom, store, and classifier

`ApplicationEntityRecencyAtom`, `EntityRecencyStore`, and `local_entity_recency` remain launcher/command-bar UI memory and no longer participate in repository-fact admission. `RepositoryLocalActivityAtom` is the sole observable owner of compact repository-keyed activity evidence. It accepts already-contracted immutable replacements on MainActor, equal-write suppresses them, and performs no I/O, classification, scheduling, or persistence.

`RepositoryLocalActivityStore` owns one application-local persistence boundary with two factual tables that follow the existing `local_` naming convention. `local_repository_activity` stores `repository_stable_key`, nullable `last_qualifying_activity_at`, `continuous_coverage_started_at`, `updated_at`, and the factual owned-promotion crash marker: nullable `owned_promotion_attempt_id`, nullable `owned_promotion_started_at`, and `owned_promotion_unsettled INTEGER NOT NULL CHECK (owned_promotion_unsettled IN (0, 1))`. `local_repository_activity_cursor` stores volume identity, last conservatively committed FSEvent ID, and `updated_at`. Neither table stores paths, branches, refs, status/PR facts, source freshness, or multi-state enum strings/integers. Every richer state remains a Swift enum derived from hydration, cursor validation, replay outcome, coverage timestamps, the crash marker, and current topology.

`RepositoryLocalActivityProjector` runs off MainActor. It maps admitted filesystem/Git evidence to canonical repository stable keys, retains the maximum qualifying timestamp, contracts bursts by repository, and produces `RepositoryLocalActivityCommit` candidates. Qualifying evidence is a projected non-ignored worktree mutation or an external Git mutation affecting worktree content, local `HEAD`, local branch, index, `FETCH_HEAD`, or canonical remote refs. Cache/database writes occur outside watched repository scopes and never enter the projector.

`DarwinFSEventStreamClient` retains event IDs and required loss flags in its internal batches and owns the runtime participation map from each repository stable key to every current worktree-local and shared-parent stream identity. A barrier flushes every participating stream and records its processed latest event ID; the conservative per-volume watermark is the minimum processed ID across every current participant on that volume. Scope addition/removal, root replacement, unregistration, or a stream that cannot join the barrier resets only affected repository coverage.

The store exposes one atomic `commitActivity` transaction accepting repository-keyed maximum qualifying timestamps, coverage start/reset facts, owned-promotion marker changes, and conservative per-volume watermarks. Activity/coverage rows commit before or in the same transaction as cursor advancement. Only successful durable acknowledgement may publish authoritative atom state. Replay duplication is idempotent because timestamps combine by maximum, resets are generation-checked, and cursor equality suppresses writes. Persistence failure leaves affected repositories unknown and advances no cursor. Shutdown stops new activity admission, flushes every participating stream, drains projector contraction, atomically commits or deliberately leaves the next launch unknown, then retires streams.

At ordinary boot the owner hydrates factual rows/cursors, binds the complete current scope map, starts replay from the committed cursor with `FullHistory`, consumes through `HistoryDone`, atomically commits the replay watermark, and only then publishes authoritative coverage. A gap, wrap, unavailable journal, scope replacement, crash marker, cursor/store failure, or future/suspect timestamp makes affected activity `unknown`; it never proves inactivity.

At first cutover, one temporary replay stream per volume is created inside the same `DarwinFSEventStreamClient` owner. It uses `FSEventsGetLastEventIdForDeviceBeforeTime(device, cutoff)` and `FSEventStreamCreateRelativeToDevice` with `FullHistory` across the current repository/worktree scopes. `HistoryDone` plus zero loss/wrap/root/scope flags proves coverage from the cutoff; journal retention failure remains unknown. Historical events do not carry source time, so any qualifying historical event conservatively records replay-completion time, while a complete replay with no qualifying event may set `continuous_coverage_started_at` to the cutoff. The temporary stream remains live until current worktree/shared streams cross its handoff watermark, preventing a replay/live gap, then retires. Recursive repository scans and absence-only Git/reflog inference remain forbidden.

Live owned-fetch attribution is structural. Streams request `MarkSelf`. The `agentstudio-git` hard cut moves only final canonical remote-ref promotion from child `git update-ref` into an in-process libgit2 multi-ref transaction: lock every captured ref, re-read and compare the captured old targets under lock, apply the complete update/delete set, and atomically commit. Private child-written staging refs remain identifiable by the reserved package namespace and are excluded from activity without suppressing correctness. Before promotion, the store durably installs the owned-promotion marker. Only `OwnEvent` canonical-ref events matching the active attempt's exact returned mutation set are excluded from activity; non-own same-path events qualify, and loss/overlap/mismatch becomes unknown. The marker clears only in the atomic activity/cursor commit after every participating stream crosses the promotion barrier. Because `OwnEvent` does not apply to historical replay, a crash leaving the marker set resets affected coverage to unknown rather than guessing provenance.

`RepositoryActivityClassifier` is a pure Sendable Core function, not mutable state. Its immutable input contains activity hydration/coverage disposition, complete current repository/worktree membership, open-pane associations, repository-keyed last qualifying activity and continuous-coverage start, a reference instant, and the sixty-day policy duration. Pending, missing, gapped, or unavailable evidence returns `unknown`; it never enters the inactive sets. An open associated pane yields an ephemeral `warm` disposition without changing persisted activity. Authoritative evidence yields `warm` until the inclusive `lastActivity + 60 days` boundary, and yields `locallyInactive` only after both the last activity and continuous-coverage start precede the cutoff. One worktree event warms the complete repository. Search, grouping, disclosure, viewport, row materialization, enrichment, cached Git facts, and Forge values are absent from the input.

The classifier is reused rather than its results becoming a second persisted truth. `RepositoryFactDemandCoordinator` evaluates it off MainActor for source admission. `RepoExplorerProjectionWorker` evaluates the same function off MainActor for presentation. Both receive the same canonical topology, activity/coverage evidence, open-pane associations, reference instant, and policy threshold. Equality at `latestQualifyingActivity + 60 days` remains warm, so the next legal cold transition is the first representable `Date` after equality (`expiration.timeIntervalSinceReferenceDate.nextUp`). Closed authoritative warm repositories contribute that instant; open-pane and unknown repositories contribute no inactivity deadline. The demand lane owns one reschedulable earliest boundary wake, and Repo Explorer folds the same instant into its existing deadline task. Waiting stays off MainActor. Activity, coverage, topology, or pane-association change replaces the pending complete input; stale generations have no authority.

### RepositoryFactDemandCoordinator

The App composition layer owns one read-only `RepositoryFactDemandSnapshot`. It derives demand from canonical workspace/window/pane/sidebar state and sends a new snapshot only when its complete value changes.

The coordinator accepts a compact immutable input capture and publishes a classified snapshot. MainActor capture copies IDs, stable keys, keyed activity/coverage facts, and presentation facts only; repository grouping and cutoff comparison run off-main. The classified snapshot contains:

- active-pane worktree identity;
- sidebar-attended worktree identities: the sidebar's semantic worktree membership before search, grouping, scrolling, or row materialization;
- visible-pane worktrees in the active tab, honoring management, drawer, zoom, occlusion, minimization, and window visibility semantics already defined by PR-fact demand;
- open worktrees;
- warm, unknown, and locally inactive repositories/worktrees;
- demanded worktree identities with their attention class for Forge;
- demanded repository identities for remote-reference refresh.

The coordinator owns no source freshness, provider, accepted fact cache, or retry state. It owns only latest complete demand/activity input, the derived semantic snapshot, and one earliest sixty-day transition deadline. It does not read `ViewRegistry`, `RepoExplorerTableMaterializer`, viewport rows, search state, grouping presentation, or row materialization; render bookkeeping never creates source demand. Sidebar attention comes from canonical sidebar presentation state plus canonical repository/worktree membership, then inactivity admission removes cold repositories from automatic source demand without removing membership. Empty attention is delivered on hiding, minimization, occlusion, topology removal, and shutdown. The local projector retains only warm registered worktrees as periodic self-heal inventory; locally inactive registrations remain available for mutation-triggered correctness and explicit work but own no periodic deadline.

Boot restores activity rows and cursor facts before activity-dependent demand begins, validates/replays cursor coverage through the filesystem owner, and only then permits confirmed inactivity. Pending or failed restore/replay remains unknown and follows bounded warm eligibility. It never suppresses the fleet by interpreting an empty array or unavailable store as negative activity evidence.

Current HEAD already uses one content-equal demand capture followed by narrow projections to each owner. `FilesystemGitPipeline` accepts the complete snapshot once and projects it to filesystem-ingress attention, local-Git attention, remote-reference repository demand, and Forge worktree demand. The cold slice preserves that foundation and adds activity input/classification before the existing source projections; it does not restore the retired separate setters or any viewport-owned demand path.

The capture is ID-only and uses dedicated association-only keyed facts rather than composite pane or worktree models. `WorkspacePaneGraphAtom` owns `paneID -> (repoID?, worktreeID?)` association slots plus their membership revision; it updates a slot only when pane membership or that association changes. `RepositoryTopologyAtom` owns `worktreeID -> repoID` membership slots plus their membership revision; it updates a slot only when repository/worktree membership changes. These are narrow read interfaces over the existing canonical atoms, not new mutable truth owners. They prevent CWD, path, name, note, residency, content, drawer placement, or other unrelated changes from invalidating demand capture.

The coordinator observes active tab/window/sidebar presentation state, pane-association membership, repository/worktree membership, and the association slots needed for the complete snapshot. `FilesystemProjectionIndex` remains a filesystem event/topology projection owner and is not attention authority. The capture does not observe `SidebarVisibleWorktreesRuntimeAtom`, composite `PaneStructuralFacts`, composite `Pane`/`Worktree` values, branch or enrichment facts, filesystem paths, cache dictionaries, search, grouping, viewport rows, row presentation, or every pane's display state. `ForgeActor` retains its existing actor-owned worktree membership and resolves current non-empty branches after receiving demanded worktree IDs; branch changes therefore alter Forge scope without creating a second MainActor branch owner. Membership/topology changes may rebuild the compact identity projection; search, grouping, scrolling, row rendering, unrelated pane facts, and unrelated enrichment writes do not rebuild or deliver demand. Content equality runs before any source-owner call.

The same complete snapshot preserves the already-landed filesystem ingress priority without restoring a second demand path. `FilesystemGitPipeline` continues to project active-pane and open-worktree IDs to one `FilesystemActor` attention update. The remaining change adds warm periodic eligibility to the existing `GitWorkingDirectoryProjector` update and removes locally inactive repositories/worktrees from the existing remote-reference and Forge automatic-demand projections. `FilesystemActor` still observes every registered worktree and prioritizes active/open flushes. A relevant cold-repository FSEvent therefore retains ordinary local affected-scope correctness while creating no remote or Forge demand. A failed or cancelled delivery commits no partial owner state; latest-value delivery retries the complete snapshot, including an A -> B -> A reversion, before accepting it as delivered.

### RepoEnrichmentCacheAtom and RepoCacheAtom

The existing keyed atom families remain the accepted-value owners:

- `worktreeId -> WorktreeEnrichment` owns the last complete current local worktree candidate, including branch, sync, file counts, line counts, and entries;
- `repoId -> RepoEnrichment` owns repository-level accepted enrichment;
- `RepoBranchKey -> PullRequestFacts` owns current-origin confirmed PR/check/review facts;
- existing keyed loading/unavailable state owns presentable remote refresh honesty.
- `repoId -> RepositoryFactUpdateProgress` owns the runtime-only status of one fetch-only repository refresh: attempt identity, remote admission/settlement, and represented-worktree recomputation settlement.

Atoms do not own source TTLs, retry clocks, provider tasks, demand, or fetch/recomputation policy. Those remain in source actors and the App-owned repository-refresh join. The update-progress slot only assigns an already-decided immutable value, equal-write suppresses it, and removes it after the settled result has been presented; it is not persisted. A cache lookup is keyed and content-equal; full dictionaries remain cold snapshot/persistence/proof bridges. UI and eager projections read atoms only.

Freshness expiry does not delete accepted current-identity facts. Source owners keep their stable accepted baseline visible while loading or unavailable. Identity invalidation removes or rejects the exact old key through existing coordinator/cache ownership.

### Targeted fetch-only repository Refresh command

One targeted repository `AppCommand` owns the Refresh verb and its interactive display contract. The inactive memorychip is a local status action that reveals the dispatcher-backed `Refresh` chip for thirty seconds. The command remains inline-only and is not exposed to headless IPC; no parallel menu verb or view-owned source call exists.

`AppDelegate` through its existing `ShellCommandHandling` role is the narrow execution owner because the action targets App-composed remote and local owners without mutating workspace topology. It validates the repository target and active-attempt exclusion, installs captured progress, and asks `FilesystemGitPipeline` to start one explicit fetch-only repository update with a UUIDv7 attempt identity. It does not write launcher recency or repository-local activity. Command-scoped intent carries captured repository/topology/origin scope, so activity-demand delivery ordering cannot make the explicit fetch a no-op.

`FilesystemGitPipeline` remains the composition owner and starts exactly one attempt-scoped admission at `RemoteReferenceRefreshActor`. The actor is keyed by canonical `repoId`, so any number of represented worktrees still produces one staged network fetch and one promotion. `GitWorkingDirectoryProjector` is not separately admitted as an explicit local refresh; it implements a typed `RemoteReferenceRecomputationApplying` interface. Applying one promoted token captures the complete represented-worktree set and returns a `RemoteReferenceRecomputationLease` whose aggregate settles only after each captured current worktree completes, genuinely fails, becomes obsolete, or is cancelled. Topology/identity changes settle affected members obsolete and cannot add uncaptured work to the attempt. `ForgeActor` receives no explicit Refresh request.

The start returns terminal `notApplicable`/`obsolete` or one accepted lease carrying captured repository/origin/topology scope. Capacity and same-repository occupancy are nonterminal for an accepted intent. After current promotion, the remote actor awaits the returned recomputation lease before resolving its explicit attempt settlement. Automatic fetches also await recomputation for currentness/physical accounting but do not create UI progress. Explicit scope bypasses successful-result freshness and cold automatic-demand suppression but not identity/currentness validation, repository single-flight, process capacity, failure backoff, child custody, local recomputation custody, or changed-only publication. Existing sufficient same-key work may absorb the attempt; otherwise the request becomes the one bounded follow-up.

`AppDelegate` synchronously installs captured progress, then assigns admission and final settlement through `RepoCacheAtom`; `FilesystemGitPipeline` does not import, retain, or read that atom. Repo Explorer keeps the compact progress indicator visible while the lease remains unsettled. Failure preserves prior current-identity remote/local facts. The join never publishes Git facts or changes activity. While an attempt is active, command enablement rejects a second click for that repository.

### GitWorkingDirectoryProjector

The projector remains the sole owner of local worktree intent, affected-path union, attention tier, freshness, admission, currentness, failure recovery, and EventBus publication.

Current HEAD already uses per-worktree deadlines and one reschedulable earliest-deadline task rather than a fixed fleet tick. Per key it owns:

- current topology/root identity;
- accepted status-fact and line-detail baselines;
- requested and active attempt generations;
- at most one scope-unioning pending intent;
- immutable admission class captured at start;
- next status-fact, line-detail, capacity, and failure deadline;
- unchanged-result adaptation and automatic-start governor state;
- one opaque verified-clean authority for each accepted exact-clean worktree.

Attention and activity changes update tier and deadlines. They create physical intent only when the accepted local fact is missing, invalidated, stale for the new tier, or explicitly requested. Ordinary tab/sidebar changes with fresh facts perform no Git work. A locally inactive worktree retains registration, current accepted facts, observer continuity, and mutation ingress, but has no status-fact or detail freshness deadline. Transitioning to inactivity removes only future automatic deadline eligibility; it does not cancel in-process work, release capacity, clear pending known mutation, or weaken generation validation.

Registration creates missing-baseline intent only when the repository is warm or when current topology has not yet received its activity disposition. Active and visible registrations receive priority; warm background registrations enter the same paced automatic governor and finite deadline path rather than bypassing admission as one eager fleet seed. Once classified locally inactive, an unmaterialized registration waits for a relevant filesystem mutation, explicit repository update, or warm transition instead of retaining an automatic checkpoint.

At a finite warm freshness checkpoint the projector first asks the status provider to renew the accepted verified-clean authority. A renewed authority advances the complete empty fact/detail freshness and adaptive cadence without acquiring Git capacity. A result that requires exact work retains one scope-preserving exact fallback intent under the existing priority, governor, capacity, and currentness rules. Known invalidations do not take the continuity fast path. A relevant cold-repository filesystem mutation retains its safe affected scope and admits local correctness work through the same gate; it also advances qualifying activity when coverage is current, but does not itself create remote-reference or Forge demand.

### AgentStudio local status composition

Current HEAD composes a single process-scoped local status physical gate and injects it into every production `AgentStudioGitWorkingTreeStatusProvider`, including filesystem and Bridge status consumers. Independent default provider construction may not create independent physical caps in production.

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

At the current resolved package revision `29d0d93a99c300881c166f8aad3878f9259451b4`, `agentstudio-git` is Git-shaped and product-agnostic and exposes separate capabilities:

- status facts scoped by the existing safe pathspec contract, excluding full-worktree line-count detail;
- exact full-worktree line-count detail;
- an explicit complete-status composition for consumers that always require both.

Typed results distinguish facts from detail; optional integers do not encode “not requested,” “unknown,” and “failed.” The status-fact reader does not perform `git_diff_tree_to_workdir_with_index` as a hidden side effect. The detail reader owns that exact operation. The current pin already returns package-owned observation-plan and exact-clean proof information consumed by Agent Studio's continuity path. The cold slice preserves this package boundary and requires no `agentstudio-git` revision change.

The retained v0.0.89 sample attributed 165 of 404 inclusive status-reader samples to the then-unconditional shortstat and 229 to status-entry collection. Current HEAD and the current package pin already removed that hidden coupling and consume exact-clean continuity so a proven clean result skips the separate detail call and later unchanged checkpoints skip both physical reads. This is preservation-critical existing behavior, not remaining cold-slice work.

Only a successful full facts read tied to the same prepared `GitStatusObservationPlan` may mint the opaque `GitExactCleanBaseline`. Its exact-clean predicate requires no staged change, tracked worktree change, conflict, rename, type change, unreadable entry, or recursively discovered untracked entry. Path-scoped and non-clean reads never mint it. An exact-clean baseline logically implies exact `0/0`, so the package skips the line-detail diff for that result.

The package observation plan records a complete dependency identity rather than paths inferred by Agent Studio: the worktree subtree; resolved per-worktree Git directory and index; common refs, configuration, packed refs, and `info/exclude`; applicable resolved ignore dependencies; and every transitive submodule HEAD, index, worktree, configuration, ignore, and Git-directory input consulted by the selected libgit2 status options. If the package cannot enumerate any consulted top-level or submodule input, or the platform cannot observe one of the supplied scopes, continuity is unsupported for that worktree while ordinary exact status remains available.

### Darwin Git clean continuity capability

Current HEAD's `DarwinFSEventStreamClient` provides the narrow `GitCleanContinuityWitness` capability consumed directly by the local status provider. App composition creates exactly one process-scoped client and injects the same object into both `FilesystemActor` and `AgentStudioGitWorkingTreeStatusProvider`; production defaults cannot silently construct a second witness. It is not routed through `FilesystemActor` or EventBus, because those lossy presentation/invalidation paths cannot prove the absence of a mutation. This existing foundation adds no atom, store, EventBus case, generic scheduler, helper process, persistence owner, or coordinator responsibility.

For each admitted observation scope the witness retains registration generation, per-volume event cursor, mutation epoch, uncertainty epoch, stable barriers, and coverage state. Start and post-scan barriers flush the stream without holding the lifecycle lock, then revalidate every generation and epoch so delayed kernel delivery cannot create a false-clean interval. Relevant mutations advance the mutation epoch before ordinary filesystem delivery. FSEvent IDs and flags remain intact through classification. User/kernel drops, event-ID wrap, root change, mount/unmount discontinuity, stream-start failure, buffer overflow, registration replacement, and unsupported scope advance uncertainty and fail renewal closed. `MustScanSubDirs` remains fail-closed for local subtree coverage, while a shared exact-parent event carrying only `MustScanSubDirs` follows the authority-bound ancestor recheck below. Git administrative mutations use the existing full-scope Git-internal invalidation semantics rather than a new EventBus fact. Shutdown first drains projector/provider renewal and retires all authorities, then shuts down the shared witness.

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

`DarwinFSEventStreamClient` remains the one process-scoped owner. Each internal worktree continuity binding retains its root, observation identity, binding generation, local stream generation, local scopes, participating shared-parent generations, mutation and uncertainty epochs, observed/resolved ancestor-ambiguity epochs, and witness-owned fingerprints for its current verified-clean authority. Each shared parent observer retains its canonical parent and volume identity, stream generation, event cursor, coverage state, exact-path subscriber index, subscriber references, one active recheck snapshot, and one complete unresolved-scope map from which the next snapshot is derived. The compact `GitCleanContinuityAuthority` token exposed to the provider/projector carries generations and epochs, not raw paths, metadata, digests, or the fingerprint map; those remain private to the witness. This state is runtime-only. It adds no atom, store, coordinator, EventBus case, timer, persistence, helper process, or second Git-fact authority.

The package remains the only owner of Git dependency identity: Agent Studio fingerprints only package-declared `.item` scopes realized through a shared parent and never infers another Git input. A private filesystem helper reads those exact items `@concurrent nonisolated`; it owns no Git fact, admission policy, or mutable lifecycle. For one parent/ambiguity generation, the helper reads each unique canonical exact item once regardless of dependent-worktree count, and the witness compares that one result with every dependent authority baseline. It never repeats the same shared-file read or digest once per worktree. Fingerprint equality uses versioned SHA-256 over the exact bytes; process-randomized `Hasher` and metadata-only equality are forbidden. The initial `AppPolicies` envelope is 8 MiB per item, 64 unique items, and 32 MiB total bytes per recheck. The helper streams bytes without allocating the declared maximum, stops before reading beyond any bound, and classifies an exceeded item/count/transaction bound as unsupported so the witness retains exact fallback.

A stable regular-file fingerprint includes canonical scope identity, missing/present state, file type and mode, device and inode identity, generation when exposed, native-resolution birth/change/modify times, length, the `sha256-v1` digest, and the digest algorithm version. Stable-read validation compares pre-read `lstat(path)`, the opened descriptor's pre/post `fstat`, and post-read `lstat(path)` and requires every identity/type/size/change field to describe the same still-current path object; an atomic path replacement therefore cannot hide behind a stable descriptor for the old inode. A symbolic-link fingerprint includes exact `readlink` bytes and matching pre/post `lstat(path)` identity and uses the same versioned SHA-256 equality for target bytes. Unsupported type, unreadable or unstable state, policy-bound exhaustion, and every `.subtree` scope fail closed. Fingerprints are process-local authority evidence: they are not persisted, rendered, or exported, and raw paths, metadata, digests, and algorithm inputs never cross OTLP.

The changed callback path is selective:

```text
current repeated-parent path
  parent event -> N worktree callbacks -> N scope classifications -> N ledger candidates

shared exact-item path
  parent event -> one shared callback -> normalize once
               -> unrelated exact-path miss -> no worktree ledger mutation
               -> exact-path hit -> record mutation for indexed dependents
                                 -> enqueue existing full-scope Git invalidation
               -> loss/cursor/root/mount event -> mark dependents uncertain
                                               -> enqueue exact fallback
               -> ancestor-only ambiguity -> capture authority/binding/stream/epoch
                                          -> coalesced off-executor item recheck
                                          -> equal stable sequence end: no Git
                                          -> changed/error/race: exact fallback
```

An actual shared-file mutation may invalidate many worktrees because those authorities genuinely depend on that file. For every exact-path hit, the shared callback first advances the dependent continuity-ledger mutation epochs and then submits one coalescible full-scope Git-internal invalidation per dependent through the existing filesystem ingress and debounce boundary. That scheduling disposition carries no fabricated filesystem path and introduces no EventBus case or second authority. Ingress overflow retains its full-scope disposition so a dropped presentation/invalidation batch cannot narrow the pending exact fallback. Unrelated activity under the same recursive parent touches neither worktree mutation epochs nor ordinary ingress.

The shared observer tracks cursor regression, wrap, drop, root, mount, and coverage uncertainty even for events that miss the exact-path index; those signals bypass fingerprint recheck and fan out uncertainty only to registrations dependent on that parent. Every local or shared FSEvents hierarchy stream participating in continuity uses `WatchRoot` in addition to file-level delivery. `RootChanged` advances uncertainty and retires the affected stream and binding generation before ordinary routing; no new authority may mint until complete rebinding and a current exact scan.

An ancestor-only event with otherwise healthy stream continuity is initially ambiguous. Before a verified-clean authority exists, it fails closed to exact Git; that later exact scan may supersede ambiguity already captured by its start barrier. An ancestor event arriving after the barrier while the baseline is preparing rejects commit. After authority exists, the callback advances the registration's monotonic observed-ambiguity epoch, captures immutable authority/binding/stream/scope evidence, and returns without filesystem I/O or a MainActor hop. The continuity owner may advance the resolved-ambiguity epoch only after the off-executor recheck proves every affected declared exact item equals its committed fingerprint and a sequence-end validation proves no newer ambiguity, mutation, uncertainty, authority, binding, stream, plan, scope, removal, or shutdown change. Equality resolves only that captured ambiguity; it does not advance freshness, decrement an epoch, create a Git fact, or overwrite a newer event. Any changed item, missing fingerprint coverage, unsupported state, read error, unstable read, stale generation, concurrent event, cancellation, or shutdown advances uncertainty once for that generation and retains the existing one coalesced exact fallback.

The unresolved-scope map is keyed by dependent registration and stores its latest observed ambiguity epoch plus the union of affected canonical exact items. An active recheck captures one complete snapshot of that map. New A, B, then A events while it runs update epochs and union scope in the map; they never replace the pending value with the final event packet or narrow B away. Completion removes or resolves an entry only when its current epoch and scope still equal the captured snapshot. Any newer or disjoint unresolved entry remains in the map, and the parent starts exactly one successor from the newest complete unresolved snapshot. Binding replacement/removal may delete only the entries whose authority no longer exists. A failed recheck advances uncertainty and requests at most one fallback per affected worktree uncertainty generation through the existing outstanding-delivery gate.

Binding and barriers form one composite coverage transaction. A shared parent stream must start and establish coverage before its subscriber is installed or any baseline barrier may begin. `prepare` flushes coverage and captures the current observed-ambiguity epoch before exact Git begins. Post-scan `commit` retains the same composite streams, flushes delayed delivery, requires the observed ambiguity to remain equal to the prepared epoch, captures current mutation/uncertainty epochs, reads complete shared-item fingerprints off-executor, flushes again, and then revalidates the binding generation, observation identity, contributing stream generations, mutation/uncertainty epochs, and unchanged prepared ambiguity epoch. A successful exact commit atomically sets the resolved-ambiguity epoch to that prepared observed epoch and attaches the fingerprints; the exact scan, not fingerprint equality, is the authority for pre-barrier ambiguity. An event during the scan, fingerprint read, or either flush advances the observed epoch and prevents commit. `renew` likewise requires no pending recheck, equal observed/resolved ambiguity epochs, and an authority carrying the current resolved epoch. No file I/O occurs while holding the lifecycle condition or continuity-ledger lock. Plan replacement, subscriber remapping, late callbacks from retired generations, shared-stream start failure, mutation, or unresolved ambiguity during any barrier makes the affected registration require exact Git. There is no fallback that recreates one broad parent stream per worktree.

Unregister performs one lifecycle-serialized retirement: it first advances the worktree binding generation and retires authority so no new barrier or renewal can begin, then removes exact-path subscriber references and tears down the local registration. A shared parent observer remains live while any subscriber depends on it and stops at zero references. Shutdown first forbids new bindings and drains witness consumers, then retires worktree and shared-parent generations and tears down both stream classes. The cutover is internal and runtime-only: existing authorities are invalid after a binding-topology change, and the next accepted exact scan may mint authority only through the complete new composite binding.

The AgentStudioCore proof boundary must demonstrate selective ownership rather than only final Git correctness:

- many worktree plans sharing one external exact-item parent create one shared parent stream, and no worktree-local stream retains that broad parent;
- unrelated activity under the parent produces one callback/index miss, or one equal ancestor recheck that reads each unique shared item once regardless of dependent count, with no ordinary worktree batch, dependent mutation epoch change, or Git read;
- an exact-item mutation advances each indexed dependent's ledger before one coalesced full-scope invalidation enters existing ingress; overflow preserves that scope and unrelated misses enqueue nothing;
- loss, cursor, mount, root, and unresolved ancestor coverage invalidate all dependents of that parent without taking the equality path;
- content change with equal length, deletion, atomic replacement, symbolic-link replacement, unreadable/unsupported or policy-bound-exhausted state, stale binding, and a second event during recheck each preserve one exact fallback;
- a blocked A recheck followed by B then A retains the complete unresolved A+B scope and resolves or falls back exactly once per affected worktree generation;
- no-authority and exact-scan-preparing ancestor events reject equality, while committed authority plus unchanged fingerprints preserves authority;
- `commit` and `renew` cannot pass while applicable ancestor ambiguity remains unresolved;
- every continuity hierarchy stream requests root-change delivery; watched-parent or ancestor rename/deletion retires authority before routing and recovers only through rebinding plus exact Git;
- delete, rename, atomic replacement, stream-start failure, plan replacement, late-generation callback, unregister/renew overlap, and mutation across every barrier fail authority closed;
- local subtree delivery, deepest-owner routing, and ordinary filesystem debounce remain unchanged;
- real disposable repositories sharing a disposable external config file prove both positive renewal and exact fallback without mutating user repositories or global Git configuration;
- the complete real-root exact-PID workload proves that unrelated shared-parent activity no longer creates worktree-count callback fan-out and that idle and action CPU remain inside the declared budgets.

### RemoteReferenceRefreshActor

The existing Core actor owns demanded server-current remote-tracking refs per repository. It already consumes repository demand, current origin/remote name, canonical repository path, topology generation, and explicit refresh. The cold slice changes only automatic-demand admission and adds attempt-scoped explicit settlement.

Per repository it owns:

- last successful fetch time and freshness deadline;
- origin/topology generation;
- the accepted remote-reference origin/generation token required by local ahead/behind composition;
- cleanup custody for the reserved generation-scoped ref namespace;
- one active fetch and one latest complete pending intent;
- process-wide fetch-capacity admission;
- failure/rate/timeout backoff;
- completion-triggered targeted local recomputation.

It calls a typed `agentstudio-git` staged-fetch contract with noninteractive prompt policy. Registration first captures the current remote configuration and canonical ref tips as one immutable local snapshot, establishing the immediate last-fetched acceptance token without claiming server freshness. Admission captures that exact origin URL, remote name, repository identity, and topology generation. The child fetches captured remote refs into a reserved generation-scoped private namespace without updating `FETCH_HEAD` or canonical `refs/remotes/*`. After child exit, the actor revalidates origin and generation; only a current completion may promote the complete staged update/delete set to canonical remote-tracking refs through the in-process libgit2 transaction described by activity provenance, then create a new `RemoteReferenceAcceptance` token for that exact origin/generation. Stale, cancelled, removed, or shutdown completions clean their staging namespace and cannot promote. Startup and shutdown also sweep abandoned refs under only that reserved namespace; cleanup failure remains observable and retryable, while staged refs stay invisible to canonical readers. Default automatic freshness is three minutes for active/visible demand, aligned with the confirmed product promise and PR freshness floor. Hidden or locally inactive automatic demand stops future fetches without deleting current-origin accepted remote refs or ahead/behind facts. Explicit repository-update scope is a bounded attempt-scoped demand lease for the captured current repository identity; it may start before the activity-derived automatic-demand snapshot arrives and ends only after fetch plus represented-worktree recomputation settle. Explicit refresh bypasses freshness but not identity, capacity, active single-flight, or failure policy.

One successfully promoted repository fetch refreshes shared remote refs exactly once per repository, independent of the number of represented worktrees or their `.git` indirection. `RemoteReferenceRefreshActor` is keyed by `repoId` and owns one active operation plus one pending repository intent; canonicalized worktree Git-directory paths never create another network-fetch key. After promotion, the actor requests targeted local status recomputation for all currently represented worktrees because each may have a different `HEAD`, index, branch, or dirty state. The recomputation carries the accepted remote-reference token; local ahead/behind composition publishes counts only while that token still matches the repository's current origin/topology generation. Origin change invalidates the prior token and ahead/behind publication authority before any new local self-heal can read old refs. The actor does not emit ahead/behind directly or duplicate local Git materialization authority.

Deterministic remote proof registers one canonical repository with multiple linked worktrees using distinct roots and `.git` indirection, demands one refresh, and observes exactly one staged network fetch, one promotion, and one accepted repository authority token followed by targeted local recomputation for the complete represented-worktree set. Reordering the topology input must not create a second fetch key.

The selected initial physical policy is one automatic fetch process at a time, a 120-second child-process timeout inherited from the current `agentstudio-git` remote contract, and the three-minute automatic retry floor. These are `AppPolicies` values at composition; provider defaults are not hidden product policy.

### ForgeActor and GitHubCLIForgeStatusProvider

`ForgeActor` retains repository membership, current origin generation, demanded branch scope, stable presentation, one active request plus one latest complete follow-up per repository, freshness, recovery, and Forge publication.

The successful automatic freshness floor remains three minutes. Forge's existing owner-local manual API may bypass freshness for its own callers but is not invoked by the repository Refresh command. Losing automatic demand cancels work that has no separately owned Forge intent, clears pending automatic intent, stops future automatic deadlines, and preserves current-origin accepted facts. Cold sidebar membership itself never creates automatic Forge demand.

Forge already has one process-wide GitHub CLI capacity of two child processes. Capacity-deferred repositories retain their latest intent and are woken by child completion or the single earliest deadline. Capacity is not failure.

An equivalent automatic trigger received during an active request may schedule one eligibility recheck after the existing one-second contraction delay, but success freshness still gates physical work until `lastSuccessfulRefreshAt + 180 seconds`. A changed complete demanded-branch set containing an unconfirmed branch and explicit manual intent use their separately defined freshness bypass while still obeying single-flight, CLI capacity, and rate/failure policy.

The current provider uses a demanded-branch query plan rather than repository-wide `pullRequests(first: 100)` pagination. GitHub supports `Repository.pullRequests(headRefName:)`; one GraphQL request uses bounded aliases for multiple demanded branches. The provider:

- normalizes and stably orders demanded branch names;
- groups them into bounded alias batches under GitHub node and response limits;
- requests only open PRs for each aliased `headRefName`;
- returns a typed per-branch completeness map;
- treats the complete multi-batch query as one repository-scoped transaction: every demanded alias connection must completely paginate and validate before any branch publishes;
- rejects the entire plan on any truncated, incomplete, failed, or rate-limited batch, retaining all prior or unknown branch facts;
- records branch count, alias batch count, node bound, and result completeness under scrubbed telemetry.

The old page-size-100 repository-wide path is no longer the ordinary demanded path. A bounded repository-wide fallback remains permitted only when branch filtering cannot express the requested complete scope, and its use is an observable outcome rather than a silent widening.

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

Repo Explorer captures keyed repository activity/coverage evidence, topology stable keys, open-pane associations, and keyed repository Refresh progress as immutable input. `RepoExplorerProjectionWorker` runs the shared classifier off-main before filtering/grouping and projects confirmed locally inactive repository headers without changing canonical membership. In By Repo, the existing unique `SidebarRepoGroupHeader` trailing-content seam renders the memorychip status, temporarily revealed `Refresh` chip, or progress indicator; inactive worktree rows omit ordinary Git/PR chips. Unknown and warm rows retain their truthful accepted presentation. In By Tab and By Pane, affected inactive rows omit ordinary cold Git/PR chips but do not repeat the repository-level control. Existing materialized row-height remains stable across inactive, updating, unknown, and warm states; classification or progress changes invalidate only affected repository/group rows. Grouping changes presentation only and retains the same activity/progress input. The view dispatches the command and renders keyed accepted state—it never creates demand or calls a source.

## Current-to-target call paths

### Consumer cache path

```text
CURRENT
UI/derived reader
  -> exact keyed RepoCacheAtom/AtomFamily read
  -> existing off-main Repo Explorer projection
  <- accepted value / loading / unavailable presentation
  [preserved] render/body has no Git, fetch, gh, or demand side effect
  [missing] repository activity and explicit-update progress inputs

TARGET
UI/derived reader
  -> [unchanged] exact keyed accepted-value read
  -> [added] immutable activity facts + keyed RepositoryFactUpdateProgress
  -> [changed] affected repository/group projection only
  <- warm chips | inactive header | admitted loading | settled source outcomes
  [unchanged] no source or demand side effect from presentation
```

### Repository-fact attention path

```text
CURRENT
canonical window/tab/pane/sidebar/topology IDs
  -> captureRepositoryFactDemandSnapshot
  -> RepositoryFactDemandCoordinator complete-value equality/latest delivery
  -> FilesystemGitPipeline.setRepositoryFactDemand
       active/open ingress IDs ------> FilesystemActor
       all semantic local attention -> GitWorkingDirectoryProjector
       attended repository IDs -----> RemoteReferenceRefreshActor
       attended worktree IDs --------> ForgeActor
  -> every registered worktree retains background local deadlines
  [missing] recency classification, cold suppression, and cutoff wake

TARGET
canonical window/tab/pane/sidebar/topology IDs
  + repository-keyed activity/coverage facts
  -> [added] one compact complete RepositoryFactDemandInput capture
  -> [added] off-main RepositoryActivityClassifier
       -> warm/unknown/inactive repository and worktree sets + next boundary
  -> [unchanged] complete-value equality and latest-value contraction
  -> [changed] one pipeline fan-out
       active/open ingress IDs ------> FilesystemActor
       warm local attention IDs -----> GitWorkingDirectoryProjector
       warm attended repository IDs -> RemoteReferenceRefreshActor
       warm attended worktree IDs --> ForgeActor
  -> [added] one earliest sixty-day boundary wake reclassifies the latest input
  [unchanged] viewport/search/grouping/row-materialization have no demand edge
  <- fresh cache suppresses physical work; changed attention alone is not a source call
```

### Locally inactive presentation path

```text
CURRENT
application-open recency incorrectly drives repository inactivity
Repo Explorer capture -> topology/enrichment/PR/pane facts -> off-main projection
  [wrong] viewing/opening and missing history determine classification

TARGET
persisted qualifying-activity + cursor coverage + topology/open-pane associations
  -> [added] off-main repository-keyed activity contraction and replay validation
  -> [added] immutable Repo Explorer activity input
  -> [added] shared pure RepositoryActivityClassifier in existing off-main worker
  -> [changed] repository header projection
       warm -> ordinary Git/PR chips unchanged
       unknown -> no inactive claim; accepted presentation retained
       inactive By Repo -> memorychip; click reveals Refresh for 30s
       inactive By Tab/Pane -> ordinary cold Git/PR chips suppressed; no repeated control
       updating -> progress indicator only, same header geometry
  -> [changed] existing Repo Explorer recency deadline selects the earlier pane-text or inactivity boundary
  <- keyed changed-only materialization for affected repository/group rows
  [intentionally unchanged] canonical membership, ordering, filtering, grouping, focus, and row height
```

### Explicit fetch-only repository Refresh path

```text
CURRENT
targeted command writes `.opened` recency and admits remote refs only
  -> promotion callback queues represented-worktree recomputation
  -> remote lease settles when the enqueue callback returns
  [wrong] false activity write and loading ends before local recomputation

TARGET
Repo Explorer memorychip -> reveal Refresh -> click
  -> targeted repository AppCommand through command catalog/dispatcher
  -> AppDelegate validates target; writes no activity/launcher recency
  -> AppDelegate publishes captured keyed progress
  -> FilesystemGitPipeline.startRepositoryFactUpdate(repoId, attemptId)
       -> RemoteReferenceRefreshActor only
       -> one canonical-repository staged fetch + promotion
       -> GitWorkingDirectoryProjector recomputes every represented worktree
       <- terminal only after fetch custody and recomputation settle
  -> AppDelegate publishes keyed settlement
  -> Repo Explorer progress/read-back for that repository only
  <- complete | failed | obsolete | cancelled, prior facts retained
  [forbidden] pull, merge, checkout, fast-forward, checked-out HEAD mutation, explicit Forge refresh
```

### Local filesystem and self-heal path

```text
CURRENT
FSEvent -> 500ms debounce / 10s max flush
  -> 500ms derived coalescing
  -> projector pending changeset
  -> existing per-worktree earliest deadline + governor
  -> separate status-facts call
  -> detail call when changed/missing/explicit/due
  -> exact-clean continuity may renew unchanged checkpoints without Git
  -> mutation/uncertainty falls back to exact Git
  -> changed-only EventBus/cache publication
  [preserved] one-second threshold is slow observation; native completion retains custody
  [defect] every registered worktree still contributes automatic background deadlines

TARGET
classified activity snapshot
  -> [added] warm automatic-eligible worktree set
  -> [changed] locally inactive worktree removes registration/periodic/visibility/retry
       automatic deadlines and automatic-attributed pending work
  -> [preserved] active native work retains custody and currentness validation
  -> [preserved] filesystem, explicit, and admitted remote-reference recomputation intent

cold FSEvent / known mutation
  -> [unchanged] bounded debounce + affected-scope union
  -> [unchanged] invalidate clean authority before delivery
  -> [changed] local correctness admission with no successor automatic deadline
  -> [unchanged] exact/scoped Git + complete changed-only publication
  [removed] cold mutation creating remote-reference or Forge demand

warm checkpoint and exact-clean continuity
  -> [unchanged] package-declared dependency identity and exact baseline
  -> [changed] shared-parent ancestor-only ambiguity
       -> committed authority + stable equal exact-item fingerprints
            -> preserve authority; no Git and no publication
       -> no authority / changed / loss / unsupported / error / race
            -> one fail-closed exact fallback
  -> [unchanged] projector renewal and currentness validation advance freshness
  [unchanged] exact hit, stream loss, root/mount change, and subtree ambiguity
              bypass equality and require exact Git
```

### Demanded remote-reference path

```text
CURRENT
RepositoryFactDemandSnapshot.demandedRepositoryIds
  -> existing RemoteReferenceRefreshActor freshness/single-flight/capacity admission
  -> existing staged noninteractive fetch
  -> current origin/generation validation + atomic canonical-ref promotion
  -> accepted RemoteReferenceAcceptance token
  -> targeted local recomputation for represented worktrees
  <- last-fetched ahead/behind publication or equality suppression
  [defect] attended cold repositories remain automatic demand
  [defect] explicit refresh requires ambient demand and exposes no attempt settlement lease

TARGET
activity-classified demand
  -> [changed] warm repositories only enter automatic remote demand
  -> [added] explicit command-scoped source admission independent of ambient cold demand
  <- terminal not-applicable/obsolete or accepted SourceAttemptLease
  -> [unchanged] staged fetch/promotion/currentness/capacity/backoff
  <- terminal settlement only after child exit and promoted local recomputation custody
  [unchanged] accepted last-fetched facts survive demand loss/failure
```

### Demanded Forge path

```text
CURRENT
sidebar/active-tab worktree demand + actor-owned branch/origin scope
  -> existing ForgeActor three-minute freshness + per-repo single-flight
  -> existing process-wide gh capacity two
  -> existing bounded demanded-branch alias query plan
  -> existing exact child settlement + current origin/generation/demand validation
  <- atomic repository-plan result + keyed changed-only publication
  [defect] attended cold worktrees remain automatic demand

TARGET
activity-classified demand
  -> [changed] warm worktrees only enter automatic Forge demand
  -> [unchanged] freshness, one active/one pending, capacity, alias query,
       rate/backoff, exact child settlement, atomic plan, and currentness validation
  <- unchanged keyed PR/check/review publication
  [no edge] repository Refresh never invokes Forge
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
| Exact clean preparing | Observation barrier surrounds a full exact scan and captures its starting ambiguity epoch | verified clean current when that epoch remains unchanged, exact fallback pending, removal |
| Verified clean current | Accepted exact-clean facts and matching witness authority | continuity renewal, mutation, uncertainty, explicit refresh, identity change |
| Continuity renewed | Checkpoint accepted with no physical Git | verified clean current at next deadline, mutation, uncertainty |
| Ancestor recheck pending | One authority-bound complete unresolved-scope snapshot is being fingerprinted off-executor while newer/disjoint scope unions in the parent-owned map; freshness cannot advance | verified clean current with newer resolved epoch, one successor snapshot, exact fallback pending/running, removal |
| Mutated | Relevant dependency changed | exact fallback pending/running |
| Uncertain | Coverage, cursor, registration, or dependency proof failed | exact fallback pending/running |
| Exact fallback pending/running | One retained exact intent owns recovery | verified clean current, accepted non-clean, failure recovery, removal |
| Removed | No baseline or publication authority | new authoritative registration only |

Renewal without an exact baseline, renewal across epoch or identity mismatch, unresolved ambiguity treated as unchanged, metadata-only or subtree equality, a path-scoped result minting a baseline, fallback loss during coalescing, and late authority advancing freshness are illegal and fail closed. An equal authority-bound ancestor recheck resolves only its captured ambiguity; it does not itself renew freshness.

Repository activity classification is derived from persisted positive facts plus runtime coverage authority:

| Activity state | Guard | Source effect | Presentation |
| --- | --- | --- | --- |
| Unknown | hydration/replay pending, missing row, cursor gap/wrap, unavailable journal/store, or suspect timestamp | bounded warm correctness eligibility; no inactivity deadline | no locally inactive claim; accepted presentation retained |
| Warm | associated open pane, or authoritative qualifying activity is inside sixty days | ordinary tiered local self-heal; attended/active remote and Forge demand | ordinary accepted Git/PR chips |
| Locally inactive | no open pane and authoritative continuous coverage plus last activity both precede the cutoff | no periodic local/detail deadline; no automatic remote/Forge demand; relevant FSEvent still admits local correctness and activity | memorychip status; revealed fetch-only Refresh; ordinary chips hidden |
| Explicitly updating | valid Refresh has one remote-reference lease outstanding | one canonical-repository fetch plus represented-worktree recomputation | progress indicator only while unsettled |

Warm-to-inactive is driven by the earliest authoritative classifier boundary and removes future automatic eligibility only. Qualifying activity drives inactive-to-warm; an associated pane supplies only a current-session warm override. Coverage loss drives `unknown`, never inactive. Refresh itself does not change activity. Search, grouping, scrolling, disclosure, and materialization are illegal initiators. A stale classifier or deadline generation publishes nothing.

Repository Refresh progress is keyed by repository and attempt identity:

| Update state | Meaning | Valid transition |
| --- | --- | --- |
| None | no explicit repository fetch is outstanding | command accepted |
| Captured | current repository/topology/origin scope recorded; no remote outcome yet | remote admission or not applicable/obsolete |
| In progress | remote lease admitted; fetch or resulting recomputation remains unsettled | settlement; identity removal; cancellation/shutdown |
| Settled | remote fetch and represented-worktree recomputation completed or returned a truthful terminal disposition | presentation acknowledgement/next command |
| Obsolete/removed | target identity no longer has publication authority | new authoritative command only |

Only the newest attempt for a repository owns visible progress. A superseding command merges with sufficient same-key physical work or replaces the one pending follow-up; it never starts a second repository fetch. Late outcomes update neither a newer progress attempt nor obsolete fact identity.

Remote fetch and Forge use killable child processes. Cancellation requests termination through the owning executor; the executor retains exit and pipe observation, escalates to a bounded hard kill when required, and settles the async call only after exact child exit. Source actors may revoke logical publication authority immediately but retain physical capacity until that settled return. Remote fetch writes only generation-scoped staging refs before currentness validation; stale completion cleanup cannot promote them. Forge rejects an incomplete repository plan as a unit. Both owners reject any completion after demand/origin/topology generation changed.

Illegal transitions fail closed: publication from obsolete identity/generation/scope, second same-key physical work, capacity release before true completion/exit, capacity counted as failure, partial local publication, canonical-ref promotion before currentness validation, automatic remote work without demand, and rendering-triggered source work.

Demand delivery is one complete-value consistency boundary. No source owner observes a mixture of old active-pane, sidebar, open-pane, or Forge demand fields. A cancelled or superseded delivery does not advance the delivered baseline; the coordinator retains one latest complete pending snapshot and replays it after the in-flight delivery settles. Shutdown delivers and drains `.empty` before source-owner shutdown, then rejects late observation callbacks.

## Deadline and admission model

Each source actor owns exactly one reschedulable next-deadline task. The demand coordinator separately owns exactly one earliest authoritative repository-activity transition task; Repo Explorer folds the same transition instant into its existing presentation deadline rather than adding a poll. Deadline waiting and rescheduling run outside MainActor through the injected clock seam; only compact generation-checked state application returns to MainActor. A state change cancels the prior wait, recomputes the earliest useful instant, and installs one successor. A stale wake recomputes and has no authority.

Local deadline candidates include warm status freshness, warm line-detail freshness, verified-clean checkpoint renewal, automatic governor, capacity fallback, and genuine failure. Locally inactive keys contribute none of the first three. Remote-ref and Forge candidates include warm demanded freshness, capacity fallback, provider backoff, and authoritative retry-after. Forge's one-second equivalent-follow-up candidate is an eligibility recheck only; it never advances a same-scope automatic physical start ahead of the three-minute successful-result floor.

Local automatic pacing uses completed physical duty:

```text
nextAutomaticStartAt = max(
  previousAutomaticStart + minimumAutomaticStartInterval,
  lastAutomaticCompletion + durationDerivedDutyGap
)
```

Foreground invalidation may bypass automatic time pacing but never same-root exclusion, physical capacity, generation validation, or foreground reservation. Explicit fetch-only Refresh may bypass remote freshness but never repository/origin identity, active single-flight, child capacity, failure policy, or resulting local recomputation currentness.

The selected policy set remains centralized in `AppPolicies`:

- local filesystem debounce 500ms and maximum flush latency 10s;
- local derived coalescing 500ms and visibility contraction 200ms;
- repository local-inactivity threshold 60 days, evaluated from authoritative qualifying-activity/coverage evidence with an ephemeral open-pane override;
- local freshness bases active 15s, visible 60s, open 180s, background 240s with finite 1x/2x/4x adaptation;
- local physical status capacity four process-wide, with per-class reservations preserved and automatic governor proof-tuned;
- remote-ref and Forge automatic freshness floor 180s;
- remote fetch capacity one and child timeout 120s;
- Forge CLI capacity two, child timeout 8s, pending equivalent eligibility recheck delay 1s, and failure honesty threshold three;
- source capacity recheck remains short and bounded; automatic source failure never retries faster than its source freshness floor.

## Failure, recovery, and consistency

### Cache expiry and demand loss

Expiry changes source-owner state, not accepted atom content. A stale accepted value remains visible while demanded refresh proceeds. Demand loss cancels remote interest and future deadlines, clears pending automatic remote intent, and preserves accepted current-identity facts. Warm local correctness intent survives attention demotion and returns to its background deadline. Locally inactive classification removes that periodic deadline but preserves known mutation intent, accepted facts, registration, and observer continuity.

### Inactivity transition and explicit update

A warm-to-inactive transition increments only the activity/demand generation and retracts future automatic source eligibility. Already-admitted local native work and remote/Forge children retain physical custody; source owners may revoke obsolete publication authority but do not release capacity or classify cancellation as failure before actual settlement. A current late result may publish only if its ordinary source identity/generation remains valid. Accepted current-identity facts remain stored but Repo Explorer hides their ordinary chips while inactive.

An explicit Refresh captures one attempt identity and repository/origin/topology scope. If no current remote applies, it returns `notApplicable` and creates no false loading. If capacity or same-repository work delays the admitted fetch, progress remains unsettled without marking failure. Loading ends only after fetch custody and resulting represented-worktree recomputation settle. Repository removal cancels logical interest, waits for remote child and local recomputation custody, removes keyed progress, and rejects late publication.

### Local slow or failed work

The one-second local threshold becomes slow observation rather than physical completion. Non-cancellable libgit2 work retains same-root and capacity custody until return. New invalidation advances requested generation and merges one follow-up. Current complete success may publish; stale success changes no accepted/freshness/equality baseline; genuine SDK failure enters local failure backoff.

Fact success followed by detail failure publishes nothing partial. The prior complete candidate remains visible, complete-detail demand survives, and genuine failure recovery owns the next eligible attempt.

Observer uncertainty preserves the last accepted facts and retains exactly one exact fallback intent. One uncertainty generation cannot enqueue fleet duplicates. Direct exact-item mutation, loss, cursor regression/wrap, root or mount lifecycle change, stream failure, unsupported scope, and unresolved ancestor ambiguity retain that fail-closed behavior. A healthy ancestor-only event may be resolved only against a committed authority's complete shared-item fingerprints at a stable sequence end; no authority, baseline preparation, changed content or identity, read instability/error, unsupported type, subtree scope, stale generation, concurrent ambiguity, removal, cancellation, or shutdown retains exact fallback. A global observer restart may invalidate many authorities, but recovery still flows through the existing attention priority, automatic governor, process capacity, and same-root exclusion. Mutation or unresolved ambiguity during the baseline scan, fingerprint transaction, or either renewal barrier rejects the authority. Any non-clean exact result clears it. Worktree removal and shutdown clear authority, fingerprints, pending recheck, and observer scope. Continuity outcomes are validation outcomes and never enter source-failure backoff.

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

- activity: warm, unknown, locally-inactive, qualifying-observed, owned-fetch-excluded, coverage-replayed, coverage-gap/reset, boundary-reclassified, activity-reactivated, pane-override, stale-boundary-suppressed;
- demand: projected, content-equal, delivered, cleared, inactive-suppressed;
- cache: hit-fresh, hit-stale, unknown, unavailable, wrong-identity;
- source selection: topology, local-ref, local-status, line-detail, remote-fetch, Forge;
- contraction: coalesced, replaced, retained-scope count, max-flush admission;
- admission: fresh-suppressed, no-demand, automatic-paced, capacity-deferred, same-key-deferred, admitted by class;
- physical: started, slow, caller-cancelled, settled, truly completed/exited, failed, active-at-shutdown;
- query: path/full, fact/detail, avoided-fact-read, avoided-detail-read, fetch-staged/promoted/abandoned/cleaned, demanded-branch alias count, fallback-wide, returned node/result count, atomic-plan completeness;
- validation: current, stale-generation, stale-root/origin/branch/demand, exact-clean-baseline prepared/accepted/rejected, continuity-renewed, mutation-invalidated, uncertainty by bounded reason, exact-fallback admitted/coalesced, removed, shutdown;
- shared-ancestor continuity: candidate, equal-resolved, changed, missing-baseline, unsupported, policy-bound-exhausted, unstable, raced, stale-generation, fail-closed, active-recheck count, unresolved registration/item count, latest pending epoch, bytes/items read, and resulting full-refresh emission count;
- publication: published, content-equal, partial-rejected;
- recovery: capacity-rearmed, failure-opened/closed, rate-limited, unavailable/available;
- explicit repository Refresh: captured, remote-applicable, remote-admitted, fetch-settled, recomputation-settled, superseded;
- debt: pending count by source/reason, physical count, current verified-clean authority count, oldest authority/checkpoint age, oldest physical age, next deadline distance.

```text
DETERMINISTIC PROOF
injected clocks + controllable local/child providers
  -> real demand projection and source actor state
  -> activity/store hydration, cursor replay/gap/reset, exact cutoff equality, nextUp wake
  -> edit/commit/pull/external-fetch positive evidence and owned-fetch exclusion
  -> multi-stream conservative watermark; crash before/after activity/cursor transaction;
     activity/coverage publication only after durable acknowledgement
  -> first-cutover device/time event-ID replay through HistoryDone; retained-history failure unknown
  -> MarkSelf/OwnEvent current-process promotion, non-own same-ref collision, owned-promotion
     crash marker, loss/overlap ambiguity, and private staging namespace classification
  -> warm/unknown/cold transition and zero automatic cold deadlines/source demand
  -> cache hit/no-call, debounce, freshness, capacity, generation flows
  -> positive continuity renewal makes zero physical calls
  -> uncertainty retains exactly one exact fallback and foreground priority
  -> committed authority plus unchanged shared-item fingerprints resolves ancestor-only
     ambiguity with zero Git; no authority, ambiguity during baseline preparation, same-length content
     change, delete, atomic/symlink replacement, unsupported/error/oversized state, loss flags,
     stale generation, and overlapping ambiguity each retain one exact fallback
  -> blocked A recheck followed by B then A preserves complete unresolved A+B scope
     and one fallback maximum per affected worktree uncertainty generation
  -> SHA-256 known vectors and item/count/transaction limits prove deterministic equality
     and bounded unique bytes/items read
  -> commit/renew cannot certify authority while an ancestor recheck is pending
  -> one repo with multiple linked worktrees issues one staged network fetch and promotion,
     then recomputes every represented worktree under one accepted repository token
  -> fetch-only admission, zero explicit Forge, admission-before-loading, checked-out HEAD preservation,
     represented-worktree aggregate lease settlement, pending intent, publication, recovery

AGENTSTUDIO-GIT PACKAGE PROOF
agentstudio-git real disposable repositories/remotes
  -> status-fact versus detail cost/contract
  -> differential exact-clean cases: nested untracked, staged, conflict, rename,
     type change, unreadable, linked index, HEAD/ref/config/ignore mutation,
     and transitive submodule HEAD/index/worktree/config/ignore/Git-directory mutation
  -> package observation-plan completeness/identity and exact-clean compatibility
  -> path/full compatibility and zero detail read for exact clean
  -> staged noninteractive fetch, current promotion, stale cleanup, and cancellation/timeout
  -> complete package check before revision consumption

AGENTSTUDIOCORE FILESYSTEM PROOF
real Darwin streams plus package-backed disposable repository plans
  -> observer drop/wrap/root-change/start-failure/re-registration/barrier races fail closed
  -> event-ID replay and cursor gaps produce unknown activity, never inactive
  -> owned staged-fetch promotion events remain Git-correctness input but do not advance activity
  -> real shared-parent ancestor delivery plus stable exact-item fingerprint differential
     against immediate exact Git; subtree scopes never take the fingerprint path
  -> mutation before registration, during scan, between scan and post-barrier,
     during renewal, and between provider return and freshness acceptance fails closed
  -> exact-item stable-read identity/content cases, SHA-256 vectors, policy bounds,
     unique-read cardinality, A→B→A scope union, and shutdown/cancellation settlement

RUNTIME PROOF
strict verifier
  -> real isolated debug identity
  -> both complete watched roots, 5 tabs, 20 pane models, zero/one PTY
  -> warm, unknown, and locally inactive repositories in canonical membership
  -> real demand projection, local Git, remote fetch, gh GraphQL, EventBus,
     keyed atoms, eager projections, native sidebar/toolbar
  -> Victoria outcomes + exact-PID CPU + native read-back
  -> graceful exact-candidate retirement and zero required loss
```

Final runtime proof may use controlled disposable remotes for staged-fetch and activity mutation while topology scale comes from the complete real watched roots. It must not mutate user repositories or global Git configuration. The fixture records warm, unknown, and locally inactive repository/worktree counts; proves unknown evidence never claims inactivity; proves cold membership survives every grouping/search mode; and observes a full inactivity interval with zero periodic local, automatic remote-reference, or automatic Forge starts for cold keys. Controlled edit, commit, pull, and external-fetch evidence in any disposable worktree must warm its repository, while one Agent Studio automatic fetch must leave activity unchanged. The native Refresh control must produce one fetch, preserve checked-out `HEAD`, exclude Forge, keep one loading lifetime through represented-worktree recomputation, and preserve prior facts on failure without moving the row.

Immediately before the timed idle interval, the verifier injects one controlled local observer uncertainty and ends that proof action; it starts idle sampling before the retained exact fallback settles. The measured interval therefore includes fallback CPU and complete recovery without including the injection action. The same interval includes at least one complete maximum warm local self-heal checkpoint and positive continuity renewals. With the selected 240-second warm-background base and 4x adaptation, retain at least 1,000 usable one-second samples; if policy tuning lengthens the maximum, the proof horizon lengthens with it. Settlement requires no overdue warm deadline, no automatic deadline for locally inactive keys, physical work within source gates, preparation debt classified by reason, and oldest debt plus next deadline within policy. Inventory and include every debug-owned descendant/helper process so cost cannot pass by relocation. The final marker must meet idle p99 and action p95 CPU targets with zero hidden loss or uncertainty. No fake substitutes for production watched-folder discovery, production provider wiring, native UI materialization, exporter delivery, or exact process identity.

## Requirement, realization, and proof trace

| Requirement | Structural realization | Proof seam |
| --- | --- | --- |
| U-GIT-IDLE-CPU-1 | cache-first reads, local governor, hidden-remote stop, bounded physical gates | real-root policy-derived full-self-heal-cycle zero-PTY exact-PID population plus source metrics |
| U-GIT-ACTION-CPU-1 | content-equal demand, fresh-cache suppression, keyed projections | native action/read-back populations with exact-PID samples |
| U-GIT-CACHE-FIRST-1 | RepoCacheAtom families, source-owner freshness, keyed eager reads | cache hit/no-source and keyed revision proof |
| U-GIT-SOURCE-SUFFICIENCY-1 | three source owners consuming one demand snapshot | source-selection behavior and end-to-end fact provenance |
| U-GIT-SELF-HEAL-1 | finite local/detail deadlines, verified-clean renewal, authority-bound ancestor resolution, fail-closed exact fallback, and first-demand remote deadlines | injected-clock renewal/fallback longitudinal, ancestor race/loss, and demanded-checkpoint proof |
| U-GIT-COLD-1 | dedicated activity/coverage atom and store, off-main projector, shared classifier, warm-only automatic demand/deadlines, fetch-only command join, keyed progress, stable inactive header | schema/replay/gap/provenance/classifier/deadline tests, cold mutation/no-work integration, native fetch-only/geometry proof, marker CPU evidence |
| U-GIT-FOREGROUND-1 | shared demand class, immutable admission, source capacity/reservation | blocked-background/remote interleavings and stressed action proof |
| U-GIT-ADMISSION-1 | bounded contraction, one active/one pending, deadline owners | outcome-accounted state tests and telemetry ratios |
| U-GIT-LOCAL-EFFICIENCY-1 | fact/detail package cutover, exact-clean baseline, loss-aware continuity, shared exact-item fingerprint admission, safe pathspec, complete materialization | package differential/observer/fingerprint proof, compatibility/timing, and app zero-call renewal proof |
| U-GIT-REMOTE-REF-1 | repoId-keyed RemoteReferenceRefreshActor and targeted per-worktree local recomputation | demanded fetch/cache/failure integration plus one-fetch/multi-worktree cardinality proof and read-back |
| U-GIT-FORGE-1 | existing branch cache plus alias query plan/global CLI capacity | GraphQL plan, recovery, cache, and toolbar/sidebar agreement |
| U-GIT-CURRENTNESS-1 | per-source captured generations/scopes and changed-only applier | A/B/C identity/invalidation interleavings and integration publication |
| U-GIT-PHYSICAL-BOUND-1 | shared status gate, exact-settling `DefaultProcessExecutor`, and child-process capacity owners | non-cooperative native plus cancellation/timeout exact child-exit lifecycle proof |
| U-GIT-OBSERVABILITY-1 | bounded owner-local aggregation and marker snapshots | aggregation bounds, perturbation check, zero-loss runtime marker |
| U-GIT-PROOF-1 | exact-debug fixture/lifecycle and package/app real boundaries | complete two-root 5/20 proof chain and native evidence |

## Hard cutover and compatibility

The current checkpoint foundation is preservation-critical and is not remaining implementation work:

- one content-equal App demand snapshot already feeds filesystem, local Git, remote-reference, and Forge owners independently of search, grouping, scrolling, or rendering;
- local Git already uses an earliest-deadline path, slow observation with true native custody, a shared process-scoped status gate, split fact/detail reads, exact-clean continuity, and fail-closed exact fallback;
- remote references already use demand/freshness admission, generation-scoped staged fetch, currentness validation, atomic promotion, and targeted local recomputation;
- Forge already uses global CLI capacity two, bounded branch-alias query plans, atomic repository publication, and the three-minute automatic recovery floor;
- process execution, changed-only cache publication, bounded telemetry, and reasoned preparation/physical debt proof already exist;
- `Package.swift` already pins `agentstudio-git` at `29d0d93a99c300881c166f8aad3878f9259451b4` with the package contracts consumed by current HEAD.

The remaining hard cutover is:

- launcher/command-bar application-open recency is removed from repository-fact admission without changing its own UI consumers;
- dedicated repository-local-activity and per-volume FSEvents cursor facts are persisted through the application-local SQLite boundary with no database enum strings/magic variants;
- FSEvents retains event IDs/required loss flags, replays from validated cursors, resets coverage on gaps, and attributes Agent Studio-owned ref promotion without suppressing Git correctness;
- an off-main keyed projector contracts qualifying activity before changed-only atom/store publication;
- the shared pure activity classifier supplies warm/unknown/inactive sets and the earliest authoritative cutoff boundary to existing demand and Repo Explorer projection lanes;
- locally inactive worktrees stop contributing automatic local/detail deadlines while preserving registration, observation, FSEvent/explicit intent, currentness, and physical custody;
- locally inactive repositories/worktrees stop contributing automatic remote-reference and Forge demand while accepted facts remain retained;
- one targeted fetch-only repository command admits only the repository-keyed remote owner and joins progress through represented-worktree local recomputation;
- Repo Explorer gains the By Repo header status/update control and grouping-specific cold-chip suppression through existing keyed/off-main materialization.
- shared-parent ancestor-only ambiguity changes from unconditional fleet fallback to one authority-bound, coalesced, off-executor exact-item fingerprint recheck; every unresolved case preserves the existing exact fallback.

There is one additive application-local schema migration for factual activity/cursor records and no dual runtime scheduler or compatibility path. Deadline, demand, capacity, classification, continuity fingerprints/epochs, and physical state rebuild from current topology, hydrated activity/cursor evidence, package-declared observation plans, and accepted runtime facts at launch. Existing Git/Forge EventBus facts and source-fact shapes remain stable; no new EventBus case is added.

The current exact package pin `29d0d93a99c300881c166f8aad3878f9259451b4` is the pre-cutover baseline. Implementation requires one deliberate `agentstudio-git` contract/revision update for in-process atomic canonical-ref promotion with captured old-target verification; staging, remote child execution, and cleanup contracts remain unchanged. The app consumes only the new revision after its package tests and consumer compatibility proof pass. There is no simultaneous old/new promotion, activity, or ancestor-disposition path. Rollback restores the prior package pin and App activity/demand/command/projection behavior without reinterpreting new activity rows as launcher recency.

Architecture enforcement prevents:

- source calls from render/body/materialization paths;
- viewport, search, grouping, or row-materialization state from owning repository-fact demand;
- enrichment, path, cache-dictionary, or fleet presentation reads inside demand capture;
- a second local fleet timer or generic cross-source scheduler;
- hidden line-detail work inside status-fact reads;
- a path-scoped, non-clean, raced, unsupported, or observation-uncertain result minting or renewing exact-clean authority;
- an ancestor fingerprint originating a Git fact, advancing freshness directly, covering a subtree, running on MainActor/callback/lifecycle lock, exporting raw evidence, or suppressing a changed, unresolved, raced, or loss-bearing event;
- more than one active ancestor recheck or one complete unresolved-scope map per shared parent/scope generation;
- replacing the unresolved scope with a latest event packet, narrowing an A→B→A union, or leaving an observed epoch without a scheduled successor/fallback;
- fingerprint equality using process-randomized hashing, an unversioned/non-collision-resistant digest, or reads beyond the policy item/count/transaction envelope;
- repeated reads or digests of one canonical shared exact item per dependent worktree within the same ancestor generation;
- treating missing events, event loss, observer restart, or identity drift as proof of no Git change;
- advancing a persisted activity cursor beyond any current participating stream or before the same SQLite transaction durably accepts qualifying activity/coverage facts;
- publishing authoritative activity before durable commit acknowledgement, or retiring streams before activity/projector/store drain;
- excluding canonical-ref activity without current-process `OwnEvent`, the exact active mutation set, a cleared crash marker, and a completed conservative barrier;
- independent production status providers bypassing the shared physical gate;
- automatic remote work without demand;
- a remote-reference network fetch keyed by worktree ID, Git-directory path, symlink target, or anything other than the canonical repository identity;
- a locally inactive repository retaining periodic local/detail deadlines or automatic remote/Forge demand;
- application-open recency, missing activity rows, cursor gaps, or unavailable persistence proving inactivity;
- Agent Studio-owned automatic fetch/promotion advancing repository-local activity;
- SQLite multi-state enums encoded as strings or magic integer variants;
- search, grouping, scrolling, disclosure, viewport, or materialization affecting activity classification;
- repository-root mtime, tree scanning, or missing persisted Git/PR facts being used as activity truth;
- a view calling local Git, remote fetch, Forge, or pipeline refresh directly;
- an explicit Refresh reporting settled before remote child custody and represented-worktree recomputation settle;
- explicit Refresh admitting local status/detail or Forge as independent source work, or mutating checked-out `HEAD`;
- one source's update success presenting another source as newly confirmed;
- direct demanded fetch mutation of canonical remote-tracking refs before origin/generation validation;
- ahead/behind publication without the current accepted remote-reference token;
- repository-wide GitHub fallback without bounded observable justification;
- partial publication from an incomplete multi-batch Forge repository plan;
- capacity reasons entering failure backoff;
- capacity release before native completion or child exit;
- process-executor cancellation returning before exact child exit and pipe settlement;
- partial or obsolete publication;
- stable/beta targeting from strict proof.
