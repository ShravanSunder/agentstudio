# Command Bar Entity Recency

Status: Draft for product approval
Date: 2026-07-24
Baseline: `5a7bd64690a3566dcb57fdf4d5a6dd34f9ed056c`

## Decision Summary

Command Bar gains small, typed recent-entity sections at empty root scopes:

```text
Main
  Recent Repositories
  Repos
  Panes
  Tabs
  Commands

Repositories (#)
  Recent Repositories
  Recent Worktrees
  Repositories

Panes ($)
  Recent Panes
  existing tab/pane groups

Commands (>)
  Recent Commands
  existing command groups
```

A meaningful query removes recent sections. Search continues over the complete
canonical root candidates for that scope. Clearing the query restores the recent
projection without reopening the panel.

Repository, worktree, and pane recency is non-authoritative local state in the
existing application-root `local.sqlite`. It is split by lifecycle:

- application-global: repository, worktree;
- workspace-owned: pane.

Two tables and two bounded list atoms express those lifecycle boundaries. The
Command Bar reads hydrated atoms and live entity models; it never reads SQLite,
the filesystem, Git, or processes.

Command recency remains Command-Bar-owned UserDefaults history. It does not use
either entity-recency table or atom.

This is not a generic activity ledger or an atom-family system.

## Product Intent

The Command Bar currently exposes several kinds of object through different
roots, but it does not make the last useful locations and panes immediately
available. Repository and worktree navigation also looks like management
hierarchy when the user's immediate goal is often simpler: reopen a terminal or
focus the pane they were just using.

The product should offer a fast continuation surface while preserving the
existing entity tree:

- Main resumes the three most recent repositories without replacing its existing
  entity groups.
- `#` resumes repositories and worktrees.
- `$` resumes panes within the active workspace.
- `>` resumes commands while remaining the verb surface.

Success means the user can identify the current scope, activate a recent target
directly, and begin typing to return to the ordinary complete search model
without duplicates or stale execution.

## Terminology

### Entity recency

Typed local history for a domain entity:

```text
repository  opened     application-global
worktree    opened     application-global
pane        focused    workspace-owned
```

`CWD` is intentionally not an entity-recency kind in this contract. Current
terminal CWD remains pane-owned durable metadata updated from Ghostty
`cwdChanged` events. Turning that fact into a global MRU would introduce a
second meaning and recording lifecycle without an accepted consumer.

### Command recency and search-score history

`CommandBarState.recentItemIds` remains the existing UserDefaults-backed list of
executed Command Bar row IDs used for fuzzy-search score boosting.

Visible Recent Commands use a separate Command-Bar-owned UserDefaults list of
typed `AppCommand` identities. It records commands dispatched from the Commands
root, including a targeted command after its target is chosen. It is not entity
recency and is not reconstructed from entity history.

### Canonical root candidates

The complete existing rows owned by a Command Bar root before recent projection:

- Main: repositories, panes, tabs, commands;
- `#`: repository containers;
- `$`: tab rows and their pane rows;
- `>`: commands.

Recent Worktree rows are empty-root shortcuts into the current worktree action
menu; they do not create a new canonical search group. Recent Repository rows
promote matching canonical repository containers and retain their repository
menu behavior. Recent Pane and Recent Command rows promote matching canonical
rows while the empty-root projection is visible.

### Empty and meaningful queries

At a root, the scope prefix is removed and the remaining text is trimmed of
leading and trailing whitespace/newlines:

- empty normalized text: show the recent projection;
- non-empty normalized text: run meaningful search over canonical candidates.

The same normalized text gates the recent projection and enters fuzzy search.
Internal whitespace is preserved.

## Requirements

### R1. Root surface composition

Recent sections appear only at root levels. Nested repository, worktree, command,
and target levels remain unchanged.

Empty recent groups are omitted. Each visible recent group shows at most five
eligible entities, newest first, except Main Recent Repositories, which shows at
most three.

Normal groups remain uncapped and retain their existing presentation and actions
except where a promoted row is intentionally moved to a recent group.

Every group within a root has a distinct priority matching the declared order.
Existing command-category and tab-group priorities are offset or renumbered
within their root projection as needed to preserve that invariant. Grouping also
uses a deterministic name tie-break as a defensive fallback; the tie-break does
not authorize priority collisions.

### R2. Main root

The empty Main root displays:

1. `Recent Repositories`
2. `Repos`
3. `Panes`
4. `Tabs`
5. `Commands`

`Recent Repositories` contains up to three unique live repositories. It uses the
same live resolution, presentation, repository-menu action, and stale omission
as the Repositories root. Promoted repositories are omitted from `Repos` while
the recent projection is visible.

Main does not add Recent Worktree or Recent Pane groups.

### R3. Repositories root

The empty `#` root displays:

1. `Recent Repositories`
2. `Recent Worktrees`
3. `Repositories`

Recent Repository rows:

- contain up to five unique live repositories;
- derive current title and context from live topology;
- enter the repository's existing menu;
- remain in the Command Bar so the user can choose a worktree or repository
  action;
- are omitted when the repository has no current launchable worktree;
- are promoted out of `Repositories` while the recent projection is visible.

Recent Worktree rows:

- contain up to five unique live worktrees;
- derive current worktree and containing-repository presentation from live
  topology;
- resolve the current worktree and enter its existing worktree action menu;
- remain in the Command Bar so the user can choose open, path, Bridge, or
  existing-pane actions from that menu;
- may coexist with a Recent Repository row because repository and worktree are
  different entity kinds.

`Repositories` contains every remaining live repository exactly once. Its rows
retain current drill-in behavior.

### R4. Panes root

The empty `$` root displays:

1. `Recent Panes`
2. the existing tab/pane groups in current tab order.

Recent Panes:

- contains up to five eligible panes from the active workspace;
- excludes the currently focused pane so the first recent action is useful;
- reuses the canonical pane title, note, type icon, tab, and pane-position
  context;
- focuses through the existing validated targeted command;
- promotes the pane out of its normal tab group while leaving the tab row.

For this contract, a pane is eligible only when it is:

- owned by the active workspace;
- active-residency;
- represented by a canonical `$` pane row in a tab's active arrangement;
- targetable by the existing focus command.

Drawer children, backgrounded panes, pending-undo panes, orphaned panes, and
otherwise unreachable panes are not recorded or displayed by this first
consumer. Expanding the canonical `$` inventory is a separate product decision.

### R5. Commands root

The empty `>` root displays:

1. `Recent Commands`
2. the existing command categories.

Recent Commands:

- contains up to five unique currently visible commands;
- follows the Command-Bar-owned typed command MRU order;
- reuses canonical command presentation, dispatch, shortcut, and drill-in
  behavior;
- includes targeted commands after a target dispatch is initiated from the
  Commands root;
- promotes each command out of its normal category while the recent projection
  is visible.

Existing command visibility, categories, ordering within categories, dispatch,
shortcuts, nested targets, and fuzzy score boosting otherwise remain unchanged.

### R6. Query transition

When a root query becomes meaningful:

- all Recent headers and rows disappear atomically;
- promoted repository, pane, and command rows return to their canonical groups;
- fuzzy search receives every canonical candidate exactly once;
- existing fuzzy matching, keyword coverage, visibility rules, and score
  boosting remain unchanged;
- selection preserves the same stable row identity when possible, otherwise it
  clamps deterministically to a valid row.

Recent-only worktree shortcuts disappear during meaningful search.
Search does not flatten the existing nested repository/worktree hierarchy.

Clearing the query reverses the projection without reopening the panel.
Whitespace-only queries remain in the empty-root recent state.

### R7. Scope and breadcrumb legibility

The current root is visibly and accessibly identifiable as:

- Main;
- Repositories (`#`);
- Panes (`$`);
- Commands (`>`).

Prefix text, placeholder text, or a group header alone is not sufficient for
scope identity. Nested navigation keeps the root scope and current ancestry
legible, for example:

```text
Repositories › repository › worktree/actions
Commands › command › target
```

Recent Repository enters the existing repository breadcrumb. Recent Worktree
enters the existing worktree action breadcrumb. Recent Pane is a leaf that
focuses the pane. A Recent Command reuses its canonical behavior: direct
commands dispatch, while targeted commands enter the existing command-target
breadcrumb. The exact visual styling remains a UI design choice.

### R8. Accessibility

- Recent group labels are exposed as headers.
- A recent row exposes its complete resolved identity even when visible text
  truncates.
- Its action hint communicates `Show repository actions`,
  `Show worktree actions`, `Focus pane`, or the canonical command action.
- Duplicate names remain distinguishable through repository, worktree, tab,
  pane-position, or path context.
- Recency, active state, and open state do not rely on color alone.

### R9. Interaction semantics

Entity recency records completed semantic interactions, never hover, selection,
drill-in, attempted dispatch, or rejected work. Command recency uses the
separate accepted-dispatch boundary below because command execution may continue
after the Command Bar closes.

#### Repository or worktree opened

A successful repository/worktree open records one coherent application
interaction:

- worktree;
- containing repository when a worktree is recorded.

The two facts share one completion timestamp and are applied to live state
coherently. Opening a repository submenu does not count.

#### Pane focused

Pane recency uses one app-owned observer over
`AttendedPaneDerived.attendedPaneId`. It records a transition to a different
non-nil eligible pane after effective focus changes.

The observer retains the last non-nil pane identity across temporary `nil`
states. Window key loss/regain, management-mode entry/exit, semantic no-op,
already-active reassertion, failed focus, and restoration/refocus therefore do
not record the same pane again. A transition to a different eligible pane,
including successful durable-pane creation, records after the derived read
reflects the new pane.

The feature-owned Inbox `PaneFocusTracker` is not reused or generalized. Its
stream already has a feature consumer and is not a shared broadcast contract.

#### Command dispatched

Command recency records the typed `AppCommand` identity when a command dispatch
is initiated from the Commands root. For a targeted command, drill-in alone does
not count; choosing a valid target and initiating the targeted dispatch does.
Rejected or unavailable commands do not count.

### R10. MRU, deduplication, and retention

Each entity kind is an independent MRU feed:

- one row per typed entity identity;
- repeated accepted activity replaces its timestamp;
- sort by `last_interacted_at DESC`, then stable typed `entity_key ASC`;
- asynchronous event delivery order never changes the sort;
- in-memory and post-hydration order are identical.

Equal timestamps have a deterministic identity tie-break and are not claimed to
preserve causal order.

Persistence retains at most 15 rows independently for each:

- application entity kind;
- `(workspace_id, workspace entity kind)` pair.

One kind cannot evict another. The retention cap is an `AppPolicies` behavioral
constant. The visible caps of three or five are separate.

Command history is a separate independent MRU:

- typed `AppCommand` identity, not row title or target-row ID;
- at most eight persisted entries, matching the existing Command Bar history
  bound;
- repeated dispatch moves the command to the front;
- stale or currently invisible commands are omitted without mutating entity
  recency.

## Technical Contract

### Typed domain model

Swift owns the entity and interaction vocabulary:

```text
ApplicationRecentEntity
  repository(repositoryStableKey)
  worktree(worktreeStableKey)

WorkspaceRecentEntity
  pane(paneID)

EntityRecencyInteraction
  opened
  focused
```

Valid combinations are:

```text
application + repository + opened
application + worktree   + opened
workspace   + pane       + focused
```

Future tab recency would add a Swift `tab + selected` combination only after an
accepted consumer exists. The generic workspace table does not require a schema
change for that future case.

Decoders reject unsupported kinds/interactions, invalid lifecycle combinations,
invalid pane/workspace UUIDs, malformed stable keys, non-finite timestamps, and
non-canonical stored entity keys.

Repository and worktree stable keys are lookup fingerprints derived from the
symlink-resolved canonical path, matching current `Repo.stableKey` and
`Worktree.stableKey` semantics. They are not a new global entity registry and
not durable identity across physical path moves. A physical target move produces
a new live stable key; the old non-authoritative recent row becomes stale and is
omitted/pruned.

### Atom composition

`AtomRegistry` composes two direct state owners:

```text
ApplicationEntityRecencyAtom
  owns: bounded ordered repository/worktree facts
  lifecycle: hydrate once; survives workspace switches

WorkspaceEntityRecencyAtom
  owns: bounded ordered facts for one explicit workspace
  lifecycle: flush/clear/hydrate with active workspace transitions
```

These are bounded ordered-list atoms, not `AtomEntityMap` families. Current
consumers read whole small MRU feeds; there is no keyed hot-read consumer that
justifies slot lifecycle and per-entity invalidation.

No general `EntityRecencyState` façade is required. A narrow read projection may
be introduced only where it removes real duplication between Command Bar and
the existing tabless launcher.

The two tables map to two direct-owner atoms because their hydration and cleanup
lifecycles differ. There is no third combined state atom. Command Bar composes
both small feeds with live models through a pure projection.

`RepoCacheAtom`, `RepoCacheStore`, and repo-cache datastore payloads return to
repository/worktree enrichment ownership and do not own entity recency.

### Persistence ownership

One dedicated persistence wrapper observes both atoms but exposes
lifecycle-specific restore/save operations:

```text
application restore/save
  has no workspace parameter

workspace restore/save
  requires explicit workspace ID
```

The application lane restores once. The workspace lane changes with the active
workspace. Observation begins only after the corresponding lane hydrates.
Termination flushes both lanes.

`WorkspaceSQLiteDatastore` remains the actor boundary for local database I/O,
writer reuse, migration, quarantine, and recovery. Atoms do not perform
persistence. Command Bar does not receive repository/datastore objects.

### Storage schema

Both tables live in the existing application-root `local.sqlite`.

```sql
CREATE TABLE local_entity_recency (
    entity_kind        TEXT NOT NULL,
    entity_key         TEXT NOT NULL,
    interaction_kind   TEXT NOT NULL,
    last_interacted_at REAL NOT NULL,
    PRIMARY KEY (entity_kind, entity_key)
);

CREATE INDEX idx_local_entity_recency_kind_time
ON local_entity_recency(
    entity_kind,
    last_interacted_at DESC,
    entity_key ASC
);

CREATE TABLE local_workspace_entity_recency (
    workspace_id       TEXT NOT NULL,
    entity_kind        TEXT NOT NULL,
    entity_key         TEXT NOT NULL,
    interaction_kind   TEXT NOT NULL,
    last_interacted_at REAL NOT NULL,
    PRIMARY KEY (workspace_id, entity_kind, entity_key)
);

CREATE INDEX idx_local_workspace_entity_recency_scope_kind_time
ON local_workspace_entity_recency(
    workspace_id,
    entity_kind,
    last_interacted_at DESC,
    entity_key ASC
);
```

Storage identity:

- repository `entity_key`: current `Repo.stableKey`;
- worktree `entity_key`: current `Worktree.stableKey`;
- pane `entity_key`: canonical pane UUID string, scoped by `workspace_id`.

The tables do not persist display title, subtitle, tab placement, repository
parent ID, repository/worktree path, or Command Bar row ID. Current live models
derive presentation and activation paths.

There are no SQL enum-list `CHECK` constraints. SQLite owns nullability, keys,
uniqueness, and indexes. Swift codecs own product vocabulary and cross-field
semantics.

There are no cross-database foreign keys into `core.sqlite`. Stale identities
are expected non-authoritative input and resolve through live state.

### Hard cut from recent workspace targets

This contract replaces `local_recent_workspace_target`,
`RecentWorkspaceTarget`, and `RecentWorkspaceTargetAtom`.

Existing rows are discarded rather than imported:

- they are non-authoritative local history;
- they are workspace-keyed despite application-global referents;
- they persist fallback presentation and paths instead of resolving live values;
- repository history was inferred rather than recorded;
- importing would manufacture semantics the old row did not prove.

No compatibility reader, dual-write path, or launcher-only legacy model remains.
The existing tabless launcher cuts over to the application recency atom and
retains its worktree/repository continuation behavior using live projection.
Legacy `cwdOnly` launcher cards are intentionally removed with the accepted
decision that CWD is not a recent entity.

This section supersedes only the recent-target row shape and ownership in the
2026-07-21 persistence hard-cut spec. Its one application `local.sqlite`,
non-authoritative local-state, fail-open, and Swift-validation contracts remain.

### Recording boundary

Successful action owners hand a narrow typed batch to recency ownership:

```text
worktreeOpened(
  worktreeStableKey,
  repositoryStableKey,
  completedAt
)

paneFocused(
  workspaceID,
  paneID,
  completedAt
)
```

The boundary accepts domain identity, not SQLite rows or `CommandBarItem`s.
Application and pane batches mutate their owning atom synchronously on
MainActor. Persistence captures bounded snapshots and writes each accepted batch
transactionally off MainActor.

This narrow boundary may be a small recorder object or direct typed owner API.
It must not become a general activity ledger, event store, or new global event
framework.

Pane activity captures `workspaceID` at acceptance. A late write cannot infer
ownership from whichever workspace is active later.

Command dispatch records typed command identity directly in Command Bar state.
It does not pass through the entity-recency recorder or persistence wrapper.

### Command Bar read projection

The root result session owns two views of one observation-consistent source:

```text
canonical root candidates ────────────────────────────┐
typed recency + current live entity resolution ──────┤
typed Command Bar command history ───────────────────┤
                                                     ▼
                                      root result projection
                                        │
                    ┌───────────────────┴───────────────────┐
                    │                                       │
            empty normalized query                 meaningful query
                    │                                       │
       recent groups + promoted rows          canonical fuzzy search
       canonical rows minus promotions        no Recent groups
```

Canonical candidates remain complete. Empty-versus-meaningful normalized root
query state is an explicit result-session cache/projection input. The cached
root snapshot rebuilds only when crossing that boundary, not for each meaningful
query character. Promotion does not destructively remove canonical rows from the
only source list.

The projection resolves current identity and presentation in bounded in-memory
passes. It builds repository/worktree stable-key lookup dictionaries once from
the current topology snapshot; this does not require another atom or persisted
index. Pane lookups use existing keyed atom reads. Worktree presence remains one
batched calculation. No synchronous I/O enters the projection.

Every displayed root row has a unique stable row ID. Entity deduplication uses
typed identity, not title or subtitle.

### Activation boundary

Recent rows re-resolve immediately before dispatch:

```text
repository
  resolve current live repository by stable key
  resolve its canonical default worktree

worktree
  resolve current live worktree and containing repository by stable key
  use current live worktree path

pane
  resolve current active-workspace ownership and command eligibility
  dispatch existing targeted focus command

command
  resolve current visible canonical command row by typed AppCommand identity
  reuse its canonical dispatch or drill-in action
```

Display text never selects an entity, directory, command, process, or shell
argument. Paths are not interpolated into shell commands.

Activation is bound to the presenting root-session and workspace generations.
Dismissal, scope/workspace change, or a superseding activation invalidates a
late completion.

Entity recency updates only after the repository/worktree or pane action owner
reports success. Command history updates when the Commands root accepts dispatch
initiation, as defined by R9; a later command-execution failure does not
retroactively remove that history entry.

### Stale and failure behavior

- Invalid persisted rows are skipped independently.
- A failure loading one recency lane defaults only that lane.
- Physical `local.sqlite` corruption may quarantine/reset all local lanes; valid
  `core.sqlite` still boots.
- Missing repo/worktree/pane identities are omitted after authoritative live
  hydration and pruned best-effort.
- A stale activation dispatches nothing, records no new recency, prunes
  best-effort, keeps the Command Bar open, and repairs selection.
- A recency write/prune failure does not roll back a successful user action or
  core topology/workspace deletion.
- Workspace deletion removes its pane-recency rows best-effort and can never
  remove application recency.

### Privacy and observability

New recency telemetry uses constant event names plus controlled categories,
booleans, and counts.

Raw paths, labels, prompts, UUIDs, row payloads, and raw errors do not enter OTLP
bodies, attributes, resources, logs, or metrics. Sentinel projection proof must
cover event bodies as well as attribute keys.

This spec does not claim that every pre-existing opt-in local OSLog or restore
diagnostic is scrubbed. New recency-specific local logs use reason codes rather
than adding raw recency values.

## Spec Boundary And Separability Map

```text
Application recency atom
  owns: application repository/worktree MRU
  exposes: bounded typed ordered values

Workspace recency atom
  owns: one workspace's pane MRU
  exposes: bounded typed ordered values

         typed snapshots
               │
               ▼
Entity recency persistence
  owns: two local tables, codecs, lifecycle-specific restore/save
  does not own: domain activity meaning or live execution authority
               │
               ▼
one application-root local.sqlite

live topology + workspace pane graph + recency atoms + command history
               │
               ▼
Command Bar root projection
  owns: empty-query grouping, promotion, canonical search reversal
  does not own: entity persistence or action success
               │
               ▼
validated action owners
  own: repository/worktree open and pane-focus success
  emit: typed post-success entity-recency facts

Command Bar
  owns: accepted command-dispatch initiation
  emits: typed command-history updates
```

Separable future changes:

- Adding another application-global recent entity changes the Swift vocabulary,
  live projector, and application interaction owner, not workspace lifecycle.
- A future Recent Tabs consumer adds `tab + selected` to the workspace Swift
  vocabulary and projector without changing the table shape.
- A clear-history or retention preference can remain lifecycle-specific without
  changing Command Bar search.
- A keyed atom family is justified only by a measured keyed hot-read consumer,
  not by the existence of entity IDs.

## Alternatives And Tradeoffs

### Extend `RecentWorkspaceTarget`

Gain: smallest immediate diff.

Cost: preserves workspace ownership for global facts, combines worktree identity
with an arbitrary stored launch path and fallback presentation, keeps recency
coupled to repo enrichment, and cannot represent panes without expanding a mixed
nullable model.

Decision: rejected.

### One nullable-scope polymorphic table

Gain: one table and one apparent codec family.

Cost: application/workspace lifecycle becomes a nullable convention; invalid
global-pane combinations remain representable; restore, cleanup, and retention
require filtered mixed operations.

Decision: rejected. Two small tables make lifecycle structural without SQL enum
checks.

### One table per entity kind

Gain: narrowest possible rows.

Cost: duplicates same-lifecycle storage/repository behavior and creates a schema
change for each new entity kind.

Decision: rejected. Repository/worktree share one application lifecycle;
workspace entities share another.

### General activity ledger or atom family

Gain: maximum generality and per-entity subscription potential.

Cost: event history, slot lifecycle, keyed hydration, pruning, and framework
surface without a current consumer.

Decision: rejected. Two bounded list atoms match current bulk-read patterns.

### Import legacy recent targets

Gain: preserves old launcher history.

Cost: invents global repository semantics from workspace rows whose fallback
path/presentation may be stale, and requires compatibility logic.

Decision: rejected. Reset non-authoritative history at hard cut.

## Security Context

This design touches local row parsing and live entity activation, but not
network, auth, secrets, plugins, MCP, or Git execution.

The relevant trust boundary is resilience against malformed/stale same-user
local state:

- local rows are hints;
- live atoms authorize entity-linked actions;
- persisted stable keys never directly supply a launch path;
- current live topology supplies repository/worktree activation paths;
- malformed history never blocks canonical startup;
- raw recency data is not exported through OTLP.

Protecting local history from a malicious same-user process and encryption are
explicit non-goals.

## Non-Goals

- Git CLI, Worktrunk, or worktree creation/removal/management.
- Recent CWD. Current terminal CWD remains pane-owned durable metadata.
- Recent Tabs or tab interaction persistence before a consumer exists.
- Arbitrary path entry or filesystem browsing.
- Pins, favorites, timestamps, clear-history settings, or recency preferences.
- A broad Command Bar visual redesign.
- Changing normal fuzzy matching or nested repository/worktree actions.
- Redesigning the tabless launcher.
- A compatibility layer for old recent-target rows.
- Remote sync or core persistence of recency.

## Proof Expectations

The implementation plan must map these requirements to permanent proof without
changing their meaning.

### Domain and atom proof

- All valid and invalid lifecycle/entity/interaction combinations.
- Stable-key, pane/workspace UUID, canonical key, and finite-time validation.
- Per-kind deduplication, 15-row retention, timestamp/identity order, and
  hydration equivalence.
- Coherent repository/worktree mutation from one completed worktree open.
- Captured workspace identity for pane facts.

### Persistence integration proof

- Both tables coexist in the one app-root `local.sqlite`.
- Application rows survive workspace switch/deletion.
- Pane rows isolate by workspace and clean up without affecting global rows.
- Malformed rows disappear independently.
- One lane can default without clearing the other or repo enrichment.
- A multi-fact application save is transactional.
- The old table/model/compatibility path is absent after cutover.
- Local corruption remains fail-open relative to core startup.
- Schema contains no product enum-list checks.

### Interaction proof

- Successful worktree/repository opens record the exact declared facts.
- Repository/worktree actions that do not report success and
  rejected/unavailable command dispatches record nothing.
- Pane focus proof covers a different-pane transition, same-pane reassertion,
  and a window-key/management `nil` round trip without re-recording.
- Direct and targeted Commands-root dispatches record typed command identity;
  drill-in and rejected commands record nothing.

### Command Bar state proof

- Exact group names/order for Main, `#`, `$`, and `>`.
- Group ordering is total and deterministic: each root group has a distinct
  priority and grouping has a deterministic defensive tie-break.
- Empty groups omitted; Main Recent Repositories caps at three and other recent
  groups cap at five.
- Promotion produces no duplicate typed entities or root row IDs.
- Whitespace-only, meaningful-query, and clear-query transitions.
- Root snapshot builds change only at empty/meaningful query boundaries, not on
  every meaningful-query character.
- Canonical search candidates remain complete and appear once.
- Nested levels remain unchanged.
- Selection identity/clamping remains safe during query and recency mutation.
- Stale entities omit and stale activation keeps the panel usable.

### Architecture and concurrency proof

- No SQLite, GRDB, filesystem, Git, process, auth, network, or secret access in
  Command Bar projection/MainActor hot paths.
- Late async activation cannot dispatch after panel, scope, or workspace
  generation changes.
- Repository/worktree activation uses current topology paths resolved from
  stable keys, not persisted history.

### Native UX and accessibility proof

- Real shortcuts open each scope with legible scope identity.
- Keyboard and click activation exercise every recent kind.
- Query/clear, scrolling, focus restoration, and stale failure work in the
  native app.
- Duplicate/long names remain distinguishable.
- VoiceOver reports scope, group header, complete row identity, selected row,
  action hint, and breadcrumb/back control.

Screenshots support group order and breadcrumb appearance only. They do not prove
activation, stale handling, focus semantics, deduplication, or query transition.

### Privacy proof

- Sentinel path, label, prompt, UUID, payload, and error values are absent from
  projected OTLP records and marker-scoped collector results.
- Entity and command recency row IDs/history contain no raw path.

## Approval Decisions

Approval of this draft accepts these product choices:

1. Main shows at most three Recent Repositories; `#` shows at most five Recent
   Repositories and five Recent Worktrees.
2. Recent Repository rows enter the existing live repository menu. Recent
   Worktree rows enter the existing live worktree action menu.
3. CWD is not a recent entity. Existing pane-owned current CWD tracking remains
   unchanged.
4. Recent Pane display is limited to canonical `$` main-pane inventory; drawer
   children are deferred and the currently focused pane is excluded.
5. `>` shows at most five Recent Commands from Command-Bar-owned typed command
   history; entity SQLite does not own command history.
6. Entity persistence retains 15 independently per kind/feed; Command Bar
   retains eight typed command identities.
7. Repository/worktree application identity uses stable keys derived from the
   symlink-resolved canonical path. Moving the physical target creates a new
   identity and leaves the old recent row stale.
8. Old recent-target history resets at the hard cut; legacy `cwdOnly` launcher
   cards are intentionally removed.

After product approval, `plan-creation-swarm` creates implementation sequencing
and exact proof commands.
