# Repository and Checkout Lifecycle Program Design

[Requirements](requirements.md) · [Specification](specification.md)

## Composition

The source of repository truth remains `RepositoryTopologyAtom` with durable snapshots in core.sqlite. Discovery owns evidence, the mutation coordinator owns domain transitions, persistence owns SQL, and the App composes their effects. There is no move identity, Repair command, or hidden-items screen.

```text
App composition
  |
  +-- FilesystemGitPipeline
  |     +-- FilesystemActor + existing scan scheduler
  |     |     reads authorized roots; owns scan coverage and inventory
  |     |     -> agentstudio-git libgit2 discovery (current-path facts)
  |     +-- Git / Forge producers (registration-scoped facts)
  |
  +-- WorkspaceCacheCoordinator                 existing sequencing owner
  |     -> WorkspaceMutationCoordinator         topology policy and transitions
  |          -> RepositoryTopologyAtom          observable canonical records
  |     -> WorkspaceSurfaceCoordinator          ordered pane/runtime scope effects
  |     -> RepoCacheAtom                        keyed enrichment invalidation
  |
  +-- RepositoryRetentionScheduler              new actor; earliest deadline only
  |     -> request covered authoritative rescan, then collection admission
  |
  +-- RepositoryTopologyStore                   captures/persists existing atom
        -> WorkspaceSQLiteDatastore             serial persistence admission
             +-- WorkspaceCoreRepository        core transaction
             +-- WorkspaceLocalRepository       local cleanup transaction
```

`RepositoryRetentionScheduler` owns scheduling and cancellation only; a pure Core `RepositoryRetentionPolicy` computes deadline eligibility from time and current absence records. It has no SQLite connection or canonical state. `WorkspaceCacheCoordinator` receives its collection request through an injected async closure, not through a bus command. The scheduler may live in Core's runtime services; App owns composition and access to effects. Existing import directions remain unchanged.

A metadata-only database purge was rejected: it would leave atoms, pending snapshots, and active producers capable of recreating rows. A separate lifecycle database/journal was rejected: retained canonical records and deterministic local orphan cleanup provide recovery without another durable ownership system. The added cost is one scheduler, per-location absence records, and revision-checked integration in existing owners, paid by lifecycle code rather than every UI reader.

## Current paths and proposed changes

| Behavior | Current source path | Proposed delta |
|---|---|---|
| Initial scan | `AppDelegate+WorkspaceBoot.replayBootTopology` posts retained `.notScanned` facts, then refreshes watched paths; FilesystemActor inventory starts empty | Changed: pass captured canonical locations as baseline input before initial scan admission; actor groups baseline by authorized source. Existing scanner and complete/partial reducer remain. |
| Live scan | `FilesystemActor+WatchedFolderResultApplication` reduces current evidence and posts discoveries/removals | Changed: emit a current scoped reconciliation outcome including positives, confirmed negatives, coverage receipt and captured baseline revision. Scope removal remains a distinct command disposition. |
| Disappearance | `WorkspaceCacheCoordinator.handleRepoRemoved` marks repo unavailable, clears facets/cache, fires Forge unregister; skips topology effect handler | Changed: accept per-location absence, invalidate membership lifetime, and run one ordered removal effect through the existing surface owner. |
| Rediscovery | Coordinator uses exact path/stable key and sets enrichment | Changed: keep exact canonical-path matching and remove both name-only and main-role fallback branches in `matchCandidatesPreservingExistingWorktreeIdentity` (topology extension around lines 530–546); clear absence and open a new producer lifetime. No cross-path match. |
| Checkout removal | `prepareWorktreeReconciliation` computes existing minus candidates for the whole family | Changed: apply per-location covered negatives; retain omitted outside-scope members and hidden checkout records until expiry. Active projections/scopes exclude hidden members. |
| Same-path family change | Global key collision and cross-repo identity preflights reject a checkout already owned by another family | Added: typed global re-parent transition with expected previous owner; one existing checkout row changes family, never duplicates or changes path identity. |
| Pane re-entry | Undo restore supplies prior facets; surface CWD resolver can preserve them through temporarily-unavailable `.uncertain` | Changed: unavailable/collected checkout is a confident no-match for live facets; restore and SQL writes null invalid pairs rather than rejecting the pane or its bundle. |
| Visible repository list | `RepoExplorerProjectionInputCapture.sidebarRepos` (around line 585) includes all repos; absent enrichment becomes Scanning | Changed: keyed availability capture excludes hidden locations before detached grouping; Panes membership remains independent. |
| Persistence | `RepositoryTopologyStore` captures a whole snapshot; `WorkspaceSQLiteDatastore.saveRepositoryTopologySnapshot` saves it | Changed: capture revision admission and multi-workspace facet invalidation within ordered core save; stale captures rejected. |
| Collection | No repository deadline loop exists | Added: one scheduler requests authoritative validation and a guarded core collection transaction; deterministic local cleanup follows. |
| Pane lifecycle | Surface/Undo owners control panes, tab membership and sessions | Intentionally unchanged. Repository effects clear context only. |

Current anchors: [scan result application](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor+WatchedFolderResultApplication.swift), [mutation coordinator](../../../Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceMutationCoordinator.swift), [cache coordinator](../../../Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift), [ordered persistence](../../../Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore+PersistenceOrder.swift), [topology store](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/RepositoryTopologyStore.swift).

## Canonical absence records

Keep application UUIDs and exact canonical-path stable keys. Extend the existing `unavailable_repo` table; add `unavailable_worktree` for independently retained checkout locations. Both are owned by the existing topology persistence boundary, not new stores or ambient atoms.

Each absence record contains its owning UUID, nullable `first_absent_at_utc` for legacy unknown age, deadline clock anchor (`boot_id`, sleep-inclusive uptime at anchor, retained elapsed duration), and a closed reason (`authoritative_absence` or legacy unavailable awaiting validation). Repository absence and checkout absence have distinct record types to avoid passing one kind's ID to another. Foreign keys cascade from their canonical owning row.

`RepositoryTopologyAtom` holds keyed absence records. Its existing unavailable-ID view is derived from those records for consumers; it is not a separately writable set. All topology snapshot/codecs include the full records so delete-and-reinsert SQL cannot reset dates. `WorkspaceMutationCoordinator` sets first absence only when transitioning into hidden, preserves it on repeated negatives, and clears the record on valid same-path return. Historical unknown age becomes timed only at first fresh authoritative absence.

A family remains visible if any member checkout is valid. Its main path can independently be unavailable; no launch command may use that path merely because the family is visible. Family collection waits for both its own interval and every retained checkout interval to qualify. Removing a hidden member cannot cascade-delete its available siblings. A main-row storage invariant must allow a hidden retained main checkout and later collection of its path record while the family has valid linked members; callers must select an available checkout rather than assume a launchable main path.

Absence records do not store common-directory identities. The pinned package's `common:<path>` key groups current family evidence but cannot join an old absent main clone to a new location. Distinct checkout paths remain one-to-one. Different paths are new records; no candidate queue, guessed metadata transfer, or Repair command exists. A same-path validated family change is a re-parent operation: prepare against the global canonical path index, retain checkout UUID/path-key/note, remove membership from the old family, and attach it exactly once to the current validated family in one replacement. Keep old-family notes/pins/recency separate. Invalidate checkout enrichment and both affected family-scoped projections; worktree recency keyed by the unchanged path remains valid.

Core SQL receives a typed re-parent set containing checkout ID, expected old repo ID, and new repo ID. Within the same topology transaction it validates those preconditions before its ordinary worktree identity preflight, applies the ownership update, then reconciles rows. Ordinary saves still reject unexplained ownership changes. Repeated delivery accepts an already-completed matching transition; conflicting ownership/revision rejects and requests fresh preparation. The global stable-key constraint remains intact throughout; no duplicate checkout is inserted.

The family keeps its root lookup key and repo UUID while linked members survive after main-location collection. Its root path is a family locator, not proof of a launchable main checkout. Replace the available-family validator’s mandatory-present-main assumption with per-checkout availability plus a stable family locator. A returning main location after collection creates a new worktree UUID under this surviving family. Current hidden IDs, matching and launcher consumers must all read this same distinction.

## Scan admission and baseline

The App captures canonical topology values and revision without filesystem work. `FilesystemGitPipeline` passes immutable baseline data to FilesystemActor before the first watched-folder request. The actor partitions known locations by authorized scope off MainActor. Each source inventory begins with known locations for that scope, including retained hidden locations; a baseline is previous knowledge, not positive current evidence.

Reuse `WatchedFolderInventoryReducer`'s complete/partial/current-demand gates. A scoped reconciliation value adds: source registration token, demand coverage, baseline topology revision, validated positives, and authoritative negative locations. It is a topology fact on the existing runtime bus, not a command. A complete empty scan must publish its completion/coverage even when no discovery changed. Without that receipt, expiry cannot treat silence as a fresh absence.

For overlapping scopes, a negative applies only after all still-current covering source observations have been reconciled; current positive evidence wins. A stale overlapping inventory is neither positive current evidence nor authority to erase. Scope registrations removed by user intent invalidate pending absence/expiry receipts and do not start filesystem-absence clocks. A scan response for an obsolete registration or baseline requests fresh reconciliation rather than mutating canonical state.

Family updates are patches over the global topology, never replacement by one source’s positive list. Retain every member outside the receipt’s covered scope; preserve incomplete observations; hide only explicitly covered current negatives not contradicted by another current covering source. Merge validated positives into that preserved set before invoking the domain validator. Expiring rows is a separate guarded transition, never ordinary scan set subtraction.

At the coordinator, source identity and topology revision are checked again. Already-equal facts are ignored. The prepared reconciliation computes domain changes off MainActor from immutable snapshots; a thin mutation apply compares the captured revision and publishes the accepted result synchronously. Changed topology increments its revision. A rejected stale preparation returns to the existing bounded scan demand/single-flight path; it does not create an unbounded retry task per repository.

## Availability and publication sequence

```text
FilesystemActor -- event: current scoped reconciliation --> cache coordinator
  [failure/partial: preserve negative space]                    |
                                                              v
                                       off-main domain preparation
                                       <- mutation policy result / stale
                                                              |
                                                              v
                        MainActor revision guard + canonical publication
                          | hide/restore IDs; change producer lifetime
                          | clear loaded pane facets; invalidate keyed cache
                          v
              TopologyEffectHandler / WorkspaceSurfaceCoordinator
                          | existing off-main filesystem projection
                          v
              FilesystemGitPipeline: unregister/register runtime scopes
                          |
                          v
               ordered persistence capture and durable acknowledgement
```

The bus's existing critical topology subscription remains. The surface coordinator is the sole filesystem projection/effect owner; cache coordinator does not separately derive or register roots. On unavailability, loaded panes clear optional live facets immediately while retaining CWD and source provenance. A core persistence operation clears affected durable facets across every workspace; this is paired with workspace capture revision invalidation so a saved inactive/old pane snapshot cannot reinstate them.

Runtime unregistration is awaited by the lifecycle effect task, not fire-and-forget. Publication guards take effect before any awaits, so queued Git/Forge results are rejected even while physical unregister completes. Unregister failure retains a bounded retry in the pipeline and reports failure; it cannot re-enable the hidden location. Rediscovery creates a newer registration lifetime and supersedes an older unregister effect; actor commands compare their expected lifetime before applying.

Keyed Repo Explorer capture filters unavailable locations before projection, using canonical availability indexes rather than filesystem checks. Expensive grouping/index rebuilding remains in the existing detached worker. Repos/search/activity exclude hidden locations; the Panes screen is sourced from pane membership and cannot filter out panes because their repository is hidden.

## Producer lifetimes and stale saves

Introduce runtime `RepositoryObservationLifetime` and `WorktreeObservationLifetime` values for registered work. They contain a launch epoch plus per-identity monotonic revision and are not durable move identifiers. Each Git/Forge request captures its relevant lifetime at admission, and every result/queued enrichment carries it through bus and coalescing. Consumers compare against the current live lifetime before applying. Coalescers must not merge values from different lifetimes. All origin, snapshot, branch, status, PR and awaiting-origin entrypoints use the same validity predicate.

Repository lifetime invalidates family-scoped work; worktree lifetime invalidates only that checkout. Hide, collection, return and registration replacement advance the relevant lifetime, so a late result from before a hide-return cycle cannot be accepted just because the UUID exists again.

Topology captures acquire monotonically increasing revisions at the MainActor write owner. `WorkspaceSQLiteDatastore` orders topology save and collection with the existing workspace persistence gate and rejects any capture older than the accepted topology revision. Workspace pane snapshots carry the corresponding context revision; the SQL layer also validates live facet targets at write time. Invalid optional repo/worktree pairs are set to NULL together; the valid pane/workspace bundle is not rejected because its contextual target disappeared. The same sanitization runs on Undo restoration before live publication. Remove the CWD resolver’s temporarily-unavailable deferral for these targets; return confidentNoMatch and preserve CWD, source provenance, residency and membership. On a same-path re-parent, refresh the valid current pair via topology/CWD resolution or clear it until resolved; never retain the old-family/new-worktree mismatch. Collection advances the admitted revision before any older capture can be written. On app restart the in-memory epoch changes and old tasks cannot cross the process boundary; durable core rows are the baseline.

## Deadline owner and collection admission

`RepositoryRetentionScheduler` has one reschedulable sleeper, an injected `any Clock<Duration>`, and one latest pending invalidation. Inputs are immutable absence/deadline snapshots and signals from accepted topology/persistence changes, startup and wake. It never reads atoms or scans folders on MainActor. No scheduled command is posted to EventBus.

Use the sleep-inclusive uptime/boot-identity observation pattern in [WorkspaceUndoJournalClock](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceUndoJournalClock.swift); do not change Undo policy. Same-boot elapsed age uses continuous uptime and ignores wall-clock jumps. Across a changed boot, a sane nonnegative UTC interval can establish a new anchor; backward/inconsistent samples defer eligibility, retaining known elapsed time. Observed forward wall jumps within a boot never add age. Offline undetectable clock jumps are outside the Specification's detection promise.

At a due deadline, the scheduler requests the existing authoritative scan capability for affected still-authorized scopes. It awaits its applied receipt, not only task completion. Partial/inaccessible/retired scope defers deletion and keeps a bounded pending invalidation until scope/scan recovery, with no zero-delay expired-deadline loop. Collection reads the latest time, topology revision, and complete coverage receipt; all must still match at commit admission.

`WorkspaceCacheCoordinator` is the one App owner of collection reservations and queued topology publication; its injected scheduler callback enters this owner directly. It uses `WorkspaceMutationCoordinator` for the pure prepared mutation and synchronous atom apply. All App topology write ingress, including explicit user mutations, passes through this admission boundary; explicit commands retain their separate semantics and are not converted into scan negatives. `RepositoryTopologyStore` and the datastore enforce save ordering but do not grant a second reservation. The cache coordinator serializes collection with canonical topology mutations: reserve a bounded candidate set at revision N, queue conflicting topology changes, and submit its core transaction. On failure, release reservation and apply queued positive discoveries before trying again. On success, synchronously publish the committed delta at N+1 before releasing queued mutations. MainActor is not blocked by SQL; unrelated pane interaction proceeds. A positive result already accepted before reservation removes the candidate; a positive received during the in-flight transaction is applied after its committed result, creating a new identity if collection already committed. The commit boundary is the linearization point, not when a scan first began.

The reservation is runtime-only, bounded by one batch (at most 64 locations); it is not a second durable lifecycle owner. Cancellation before commit releases it; cancellation after commit must still deliver the committed outcome before shutdown completes.

## SQL cleanup and crash recovery

core.sqlite is authoritative. The core transaction revalidates candidate IDs/absence records, clears invalid optional pane facets in all workspaces, deletes only eligible checkout rows/families and their owned metadata, and returns the committed revision/delta. Cascades remove repo tags and absence rows. It does not touch pane content, arrangement/tab/drawer membership, terminal ownership, undo records or annotation/history tables.

Then the existing local repository cleans cache, stale repository/worktree recency and collectible activity by comparing against a captured authoritative surviving core ID/key set. It is a separate local.sqlite transaction; there is no claimed cross-database transaction. Local cleanup and existing local save paths share an ordered admission fence. Full cache/recency snapshots captured before the fence are rejected or filtered against the accepted surviving set; applying a stale snapshot cannot recreate orphans.

```text
core commit fails -> canonical record remains hidden -> retry on next valid trigger
core commits, process stops before local cleanup
  -> restart reads surviving core identities
  -> bounded local orphan sweep repeats -> cleanup converges
local unavailable -> core stays authoritative; local projections default
  -> on accepted local reopen/startup, sweep before loading local rows into atoms
```

No per-deletion journal is necessary: orphanhood is derived from the existing authoritative topology. The local sweep runs at startup and after core collection, with bounded continuation batches. It preserves any key still owned by a surviving canonical location. It never scans historical annotation/undo payloads to revive locations. Pending owned promotion/activity work is checked before admission; an unsettled owner excludes that candidate until completion.

| Data | Availability loss | Expiry |
|---|---|---|
| repo/worktree UUID, path, notes, pinning | retain; hide unavailable location | delete eligible row/owned metadata |
| repo_tag / absence rows | tags retained; absence first-write-wins | cascade with owning row |
| repo/worktree enrichment, runtime PR facts | invalidate affected keys | deterministic orphan cleanup, no late resurrection |
| application repo/worktree recency | retained for return | delete only keys with no surviving owner |
| local repository activity | stop admitting absent work; retain owned operations | delete only settled, exclusively stale keys |
| watched_path, volume activity cursor | retained | retained |
| pane live facet IDs | clear affected IDs, every workspace durably | validate again, clear stale leftovers |
| pane, session, undo, annotations/history | unchanged | unchanged |

## Migration and cutover

One core migration extends unavailable repo records and creates checkout absence rows. Existing hidden repo IDs remain hidden, but unknown timestamps remain untimed until fresh authoritative absence; no creation-date backfill. Existing available checkout rows begin available and are reconciled after boot. New code uses full typed absence records exclusively; there is no dual-write set/record path. Repository schema/model validation rejects orphan/wrong-kind absence records.

A failed core migration follows existing authoritative startup failure behavior; no partial schema is hydrated. Local cleanup remains optional when local storage is unavailable and can be reconstructed from surviving core state. Do not roll a mutated database back by launching an old binary that discards the new absence fields. Recovery restores a verified backup or reruns the accepted new migration/version.

## Proof and enforcement

| Contract | Owner and structural enforcement | Observation |
|---|---|---|
| C1 identity | package current-path evidence; exact canonical indexes; no cross-path matcher | real package discovery of aliases, copies, main/linked moves and independent clones |
| C2 admission | actor coverage receipt + domain revision guard; baseline from restored canonical records | cold-start and overlapping-root pipeline with complete/partial/stale scans |
| C3 retention | keyed durable records + pure retention policy + one injected-clock scheduler | repeated absence/save/restart, staggered checkout deadlines, return/commit race |
| C4 panes | mutation owner clears live facets; ordered core validation clears every workspace | active/background/undo pane and terminal ownership readback; no navigation side effect |
| C5 collection | core transaction + deterministic local orphan sweep and stale-save fences | populated migrations, FK integrity, crashes between commits, delayed snapshot/retry |
| C6 runtime/UI | lifetime guards, existing scope effect owner, keyed capture/detached worker | late Git/Forge after hide-return, actual unregister, Repos hidden/Panes present, MainActor occupancy |

The inexpensive policy tests may replace time and scan inputs. Cross-owner proof uses the real bus, mutation owners, SQL files and runtime registration interfaces. Native smoke additionally verifies the actual list and terminal interaction; mocks cannot establish it. Architecture lint is one guard against forbidden Git calls, not exhaustive proof; source/API inspection and the production package path must also be verified. No new Git semantics or filesystem edits are implemented in app helpers.
