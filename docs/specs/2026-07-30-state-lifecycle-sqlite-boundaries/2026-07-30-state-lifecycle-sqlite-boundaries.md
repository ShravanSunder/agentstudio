# Live State and SQLite Lifecycle Boundaries

Date: 2026-07-30
Status: reviewed, ready for implementation planning
Source baseline: `36886e60bf4f3fcebeacc0804731be5b8c053897`

## Decision

SQLite remains a restart repository, never the live UI read model. Canonical
atoms and Feature-owned state remain the live owners after hydration.

The current storage split is mostly sound. This spec does not redesign the
schema. It makes each state field declare one lifecycle, prevents transient or
derived state from entering SQLite, and corrects the confirmed coupling where a
local-only continuation change can trigger a complete durable-core rewrite.

## What Is Actually Wrong

The problem is not “UI state exists in SQLite.” Restart continuation,
preferences, recency, inbox history, and rebuildable enrichment legitimately
survive process exit.

The confirmed problems are narrower:

- “UI state” conflates restart continuation, user history, preferences, cache,
  runtime presentation, and derived views;
- local-only cursor/window mutations are observed by the broad workspace save
  path and can cause a full `core.sqlite` snapshot replacement;
- a core-success/local-failure save can be reported too coarsely;
- application-window versus workspace scope is obscured by APIs that accept
  but ignore `workspaceId`;
- compatibility read models can perform live fleet reconstruction even though
  persistence itself is not queried by UI; and
- reset and corruption behavior differs by lifecycle lane but is not expressed
  as one enforceable classification contract.

## Result at a Glance

```text
                       LIVE PROCESS

runtime events ──► canonical atoms / Feature state ──► derived read models
                           │                                  │
                           │ immutable save capture           └── never stored
                           ▼
                    persistence stores
                           │
                 ┌─────────┴─────────┐
                 ▼                   ▼
            core.sqlite         local.sqlite
            durable truth       continuation / settings /
                                history / rebuildable cache

Restart:

SQLite rows ──► cold persistence DTO ──► validate/prepare
            ──► hydrate exact live owner ──► UI reads owner
```

## Product Intent

### User outcome

Restart restores durable workspace structure and intentional continuation, but
does not resurrect transient focus, zoom, pending panels, command surfaces, or
derived display caches.

Durable workspace truth must never be discarded because a local cache or UX
lane is damaged. Conversely, calling local state “non-authoritative” must not
hide loss of user-visible continuation or inbox history.

### Engineering outcome

- Every persisted field has one named lifecycle, scope, owner, reset rule, and
  recovery rule.
- UI, commands, validators, and IPC projections read live owners, not GRDB or
  repository rows.
- Local-only mutations do not cause durable-core rewrites.
- Save outcomes distinguish durable-core success from local-continuation
  failure.
- No migration is introduced without a concrete misclassified field.

The companion [DerivedValue Production Adoption](../2026-07-30-derived-value-production-adoption/2026-07-30-derived-value-production-adoption.md)
spec owns memoization mechanics. This spec owns lifecycle and persistence only.

## Current-State Inventory

### Durable canonical domain: `core.sqlite`

```text
workspace identity and selection
repository/worktree/watched-path topology
pane identity, content, durable facets, residency, drawers
tab shells, membership, arrangements, layouts
```

`WorkspaceStore` loads strict authoritative rows, prepares composition off-main,
and applies accepted owners on `MainActor`. Invalid authoritative core stops
boot; it is not silently quarantined and replaced.

### Persisted UX continuation: `local.sqlite`

```text
active tab / arrangement / pane / drawer cursors
main-window frame and sidebar continuation
sidebar expanded groups
application and workspace recency
```

These values may select among valid durable identities. They cannot create,
delete, or redefine durable workspace structure.

### User preferences: `local.sqlite`

```text
editor preference
Repo Explorer preferences
Inbox Notification preferences
```

They are explicit user intent, not transient presentation and not rebuildable
cache.

### Bounded Feature history: `local.sqlite`

Inbox notification rows include read/dismissal state, claim facts, and
event-time context snapshots. They are durable local product history, not
merely “UI state” and not a live derived model.

### Rebuildable cache: `local.sqlite`

```text
repository enrichment
worktree enrichment
pull-request counts
cache metadata
```

Loss may reduce freshness or display richness but cannot change durable
topology or prevent the core shell from opening.

### Runtime-only presentation: memory

```text
focus owner
sidebar focus
zoom / pane presentation override
command-bar and transient keyboard surfaces
pending arrangement presentation
editor chooser runtime state
health and pending UI requests
```

These values reset on process restart.

### Derived read models: memory

Rich panes, tabs, arrangements, display models, command snapshots, and IPC
projections are computed from live owners. Their construction cost never makes
them persistence owners.

## Lifecycle Classification Contract

The baseline is classified at the field-family level. Every new persisted
field, and every existing family changed by this work, must declare the same
dimensions before entering a migration or capture.

| Family | Meaning | Live owner | Restart authority | Scope | Explicit reset | Failure/recovery | Live read |
| --- | --- | --- | --- | --- | --- | --- | --- |
| workspace identity, panes, tabs, arrangements | durable domain | exact Core atoms | `core.sqlite` | workspace/entity | explicit domain mutation only | strict preserve; rejection stops boot | Core atoms |
| watched paths, repos, worktrees, availability | durable domain topology | `RepositoryTopologyAtom` | `core.sqlite` | application/entity | explicit domain mutation only | strict preserve; rejection stops boot | topology atom |
| tab/arrangement/pane/drawer cursors | UX continuation | cursor atoms | `local.sqlite` | workspace/entity | default/clamp | stale IDs clamp to core; physical local loss defaults | cursor atoms |
| frame, width, sidebar filter/surface/collapse/groups | main-window continuation | window/sidebar atoms | `local.sqlite` | main window | default | physical local loss defaults | window/sidebar atoms |
| editor, Repo Explorer, Inbox preferences | user preference | Feature preference atoms | `local.sqlite` | application | validated default | malformed slice defaults with recovery record | Feature atoms |
| entity recency | UX continuation | recency atoms | `local.sqlite` | application or workspace as declared | bounded clear | malformed/unavailable slice defaults | recency atoms |
| Inbox notifications and collapsed groups | bounded Feature history | Inbox atoms/state | `local.sqlite` | workspace/event | product retention/reset | malformed rows are repaired or removed within the Inbox lane | Inbox atoms/state |
| repo/worktree/PR enrichment | rebuildable cache | cache atoms | `local.sqlite` | application/entity | clear/rebuild | malformed or lost cache rebuilds | cache atoms |
| focus, zoom, transient surfaces, pending presentation | runtime presentation | runtime atoms | none | process/window/pane | discard | restart discards | runtime atoms |
| rich pane/tab/display/command/IPC projections | derived read model | no write owner | none | read lifetime | discard | recompute from live owners | explicit read model |

Current families outside the save-lane cut remain classified by this matrix but
do not require mechanical rewrites. New migrations must update the relevant
row or add a new one; there is no second executable schema registry.

## Boundary and Separability Map

```text
Core / Feature live owners
  own:
    observed process state
    named mutation methods
    runtime behavior
  expose:
    owner-local reads and explicit read models
           │
           │ immutable capture / validated hydration only
           ▼
Persistence stores and cold DTOs
  own:
    debounce/flush orchestration
    restart capture and hydration handoff
           │
           ▼
SQLite repositories
  own:
    row mapping, schema constraints, transactions, recovery

UI / commands / validators / IPC never cross into repository rows.
```

### Permitted dependencies

```text
Persistence store ──► live owner snapshot API
Persistence store ──► SQLite repository
SQLite repository  ──► cold row/record types
Boot workflow       ──► repository load + prepared owner hydration
UI / command        ──► live owners and explicit read models
```

### Forbidden dependencies

```text
UI / command / validator ─X─► GRDB, repositories, row records
SQLite repository        ─X─► atom(...), CoreAtomScope, Feature mutation
local.sqlite             ─X─► durable core identity/structure authority
cache or recency         ─X─► durable graph mutation
runtime presentation     ─X─► migration or persistence observer
derived read model       ─X─► persistence observer or stored row
cold persistence DTO     ─X─► render-time consumer
core recovery            ─X─► silent reset or quarantine replacement
```

## Technical Contract

### 1. Live-owner rule

After hydration, canonical atoms and Feature-owned state are the sole live
read/write owners. Repositories do not participate in Swift Observation and do
not answer render-time or command-time queries.

No direct repository UI reads were found at the source baseline. This spec
ratchets that good property rather than replacing an existing SQL-backed UI.

### 2. Cold persistence DTO

The existing `WorkspaceSQLiteSnapshot`/bridge shape is classified as a cold
persistence composition DTO:

- allowed only in persistence, hydration, diagnostics, and fixtures;
- never observable;
- never a UI, command, validator, or IPC contract;
- never enriched with display cache or runtime presentation; and
- never treated as canonical merely because it contains `Pane`/`Tab` product
  values.

Replacing it with row-native DTOs is deferred until a concrete leak or coupling
requires that cost.

### 3. Save-lane separation

The persistence trigger must distinguish:

```text
workspace composition core dirty
  └──► save workspace/pane/tab core generation

application topology core dirty
  └──► existing RepositoryTopologyStore path
       (never a workspace/local replacement)

local continuation dirty
  └──► save only affected local continuation

both dirty
  └──► core first, then local, with lane-specific result
```

An active-tab, active-pane, active-arrangement, drawer-expansion, sidebar-width,
or window-frame change must not replace durable core rows unless a durable
domain owner also changed.

This requirement separates dirty tracking and capture. It does not prescribe
incremental SQL writes inside an affected lane.

Each lane carries a monotonically increasing dirty generation. A save
acknowledges only the generation it captured. A mutation arriving after capture
keeps the newer generation dirty and schedules another save, even if the older
save succeeds.

### 4. Save outcomes

Core and local commits remain non-atomic across databases, with core
authoritative. A combined result contains an independent status for every
requested lane:

```text
notRequested
persisted(capturedGeneration)
failed(capturedGeneration)
```

This represents core-only, local-only, full success, and partial success
without inventing an aggregate “everything saved” state.

A local failure cannot roll back or invalidate committed core truth. It also
cannot be silently described as complete persistence.

On the next load, stale local IDs are validated against core and deterministically
clamped/defaulted without mutating core.

### 5. Hydration cohorts

The app intentionally presents accepted core before all local/cache slices are
hydrated. This spec does not require one global atomic boot transaction.

Atomicity and readiness apply per declared lane:

- accepted core composition installs as one non-suspending cohort;
- each local settings/history/cache slice installs into its exact owner;
- late cache enrichment is allowed to update display after core readiness; and
- persistence observation arms only after that owner’s restore/replay phase.

Consumers must not interpret a default from an unready lane as a durable
authoritative answer.

### 6. Recovery by classification

#### Core

- supported-schema migrations run before strict semantic acceptance;
- current-schema rejection performs no writes and preserves the current
  database/sidecar bytes;
- an older supported schema may receive only required migration writes, after
  which semantic rejection performs no additional writes;
- neither rejection path quarantines or replaces core as rebuildable state;
- no local recovery path may touch `core.sqlite`.

#### UX continuation, preferences, and Feature history

- failure behavior is explicit per logical slice;
- stale identity references are clamped against core;
- recovery diagnostics report loss of user-visible continuation/history
  distinctly from cache rebuild; and
- one malformed logical slice must not silently redefine another slice.

#### Rebuildable cache

- malformed or missing rows may default and rebuild;
- cache loss cannot block core shell readiness; and
- cache restore never mutates durable topology authority.

#### Runtime and derived state

- no restore path exists;
- process restart discards it.

### 7. Local quarantine

Destructive local replacement is authorized only for:

- SQLite `SQLITE_CORRUPT`;
- SQLite `SQLITE_NOTADB`; or
- an incomplete local file set where the main database is absent but WAL/SHM
  remains.

Those cases may quarantine the exact database, WAL, and SHM set before creating
a fresh local database. Permission, disk, unsupported-schema/migration, and
all other unclassified failures preserve the existing file set, leave local
state unavailable for that launch, and cannot be retried independently by
consumers.

One successful physical `local.sqlite` replacement emits exactly one
application-scoped source-scrubbed recovery record. Logical store loads from the
fresh database do not duplicate that physical incident. Store-owned malformed
slice recovery remains a separate logical record.

Quarantine must never touch core and must not export row contents, paths,
notifications, notes, or payloads through diagnostics.

Retention/cleanup policy and stronger sidecar move atomicity are security and
recovery follow-ups unless implementation of this spec must modify quarantine.
The lifecycle work must not weaken the current preservation behavior.

### 8. Scope honesty

APIs and documentation must state whether continuation is application,
main-window, or workspace scoped.

At baseline, main-window repository calls accept but ignore `workspaceId`.
This spec preserves that behavior: window frame, sidebar width, filter text,
selected sidebar surface, collapsed state, and expanded groups follow the main
window across workspace switches.

APIs and architecture documentation must stop implying workspace isolation for
these values. No schema migration occurs. A future request for per-workspace
sidebar continuation is a separate product change with its own migration and
proof.

### 9. Feature history is not transient UI

Inbox notification rows are classified as bounded Feature history. Any reset,
retention, corruption repair, or migration must preserve its claim/read/dismiss
semantics or explicitly document the loss behavior. It must not be casually
cleared under a generic “UI cache” rule.

The existing retention contract remains: at most 1,000 notifications per
workspace, evicting the oldest entry when the cap is exceeded. This spec does
not redesign Inbox retention.

### 10. Rich compatibility APIs

Expensive rich pane/tab projections remain read models, not storage owners.
Foundational canonical accessors must not hide topology enrichment, fleet
composition, or SQLite reads.

The DerivedValue production mechanism is specified separately. This spec owns
the lifecycle classification, not cache mechanics.

## Requirements

| ID | Requirement |
| --- | --- |
| SL-01 | Every new persisted field and every changed field family declares meaning, live owner, restart authority, scope, explicit reset, failure/recovery, and live read path. |
| SL-02 | SQLite repositories and cold DTOs are never live UI/command/validator/IPC read models. |
| SL-03 | Runtime presentation and derived read models have no SQLite rows or persistence observers. |
| SL-04 | Local continuation may select only valid durable identities and cannot mutate core during hydration. |
| SL-05 | Local-only mutations do not trigger durable-core replacement. |
| SL-06 | Save results and recovery reporting distinguish core success from local failure. |
| SL-07 | Core rejection preserves core authority and never uses local quarantine/reset behavior. |
| SL-08 | Rebuildable cache loss does not block core readiness or change canonical topology. |
| SL-09 | Inbox rows are treated as Feature history with explicit retention/reset semantics, not transient UI. |
| SL-10 | Hydration readiness and persistence observation are lane-specific rather than globally atomic. |
| SL-11 | Application/window/workspace scope is explicit; ignored scope parameters cannot imply false isolation. |
| SL-12 | Existing schemas remain unchanged unless a concrete field is proven misclassified. |

## Proof Expectations

### Static and architecture proof

- Targeted SwiftSyntax/structural rules prevent forbidden repository/cold-DTO
  references from UI, commands, validators, and IPC while allowlisting real
  persistence coordinators.
- Targeted structural rules prevent runtime/presentation and derived types from
  entering migration declarations or persistence observers.
- A focused migration/classification gate requires every new persisted field
  and changed family to update the lifecycle matrix.
- Behavioral tests, not vocabulary lint, prove recovery, hydration, revision,
  dirty-generation, and save-result semantics.

### Data and repository proof

- Durable core round-trips exactly across two generations.
- Each declared local continuation, preference, Feature-history, and cache lane
  round-trips at its intended scope.
- Runtime presentation and derived values are absent after restart.
- Foreign keys, checks, triggers, and semantic composition validation remain
  enforced.
- Core rejection preserves the authoritative database and blocks startup.
- Current-schema rejection preserves bytes; supported older schemas may receive
  only required migration writes before rejection.
- Classified local corruption quarantines only local sidecars, leaves core
  unchanged, and defaults/rebuilds the declared lanes.
- Unclassified local open/migration failures preserve the exact file set and
  remain unavailable without consumer retry.
- Cache deletion permits shell startup and later enrichment rebuilding.

### Save-lane proof

- A local-only cursor/window mutation produces no durable-core generation
  replacement.
- A durable-only mutation persists core without requiring unrelated local
  rewrites.
- Injected failure after core commit reports partial success and restart
  sanitizes stale local identity references.
- A local-only failure is represented without pretending core was requested.
- A mutation arriving after capture remains dirty after the older generation
  completes.
- A topology-only mutation stays on `RepositoryTopologyStore` and does not
  replace workspace or local rows.
- Persistence observation does not fire from restore-time mutation.

### Manual product proof

Using a disposable debug data root:

- mutate durable panes/tabs/topology and intentional local continuation;
- restart and verify each declared persisted lane;
- activate zoom, focus, transient command surfaces, and pending presentation
  before exit, then verify they do not return;
- damage/delete only rebuildable cache and verify core UI opens and repopulates;
  and
- switch workspaces to demonstrate the accepted window/sidebar scoping
  behavior.

## Tradeoffs

### What we gain

- SQLite has a clear restart role without becoming live UI state.
- Legitimate continuation and history are not mislabeled as disposable.
- Local interaction no longer rewrites durable core.
- Recovery and save outcomes match actual authority.
- New state has one lifecycle decision before code lands.

### What we pay

- Dirty tracking becomes lane-aware.
- Partial core/local success becomes explicit in result and tests.
- Existing ambiguous window/workspace naming must be resolved.
- Physical `local.sqlite` still couples several logical lanes during corruption.

### Why not split the database now?

No evidence shows that a new physical database per logical lane is required.
It would add migrations, recovery coordination, and more failure combinations
without fixing live ownership or save-trigger coupling.

### Why not remove persisted UX state?

Active cursors, window/sidebar continuation, preferences, recency, and inbox
history provide intentional restart behavior. Removing them would trade a
classification problem for product regressions.

### Why not make SQLite the read model?

The app’s live behavior is push-driven through observed owners. Query-backed UI
would introduce a second source of truth, I/O in interaction paths, and new
coherence rules.

## Non-Goals

- SQLite normalization or one table per atom.
- New databases or migration-history rewrite.
- General repository, dependency-injection, or state framework.
- Cache removal.
- Inbox product redesign.
- Global atomicity across all boot lanes.
- Incremental row-level writes unless measurement later requires them.
- Auth, encryption, cloud sync, or multi-user account design.
- DerivedValue mechanics, which have their own spec.

## Security Context and Threat Model

SQLite databases, WAL/SHM sidecars, and quarantined copies contain local paths,
notes, notification data, and payloads. This spec preserves strict core
handling, local-only quarantine, content-scrubbed diagnostics, and local
filesystem ownership.

```text
Assets
  core truth; local continuation/preferences/history/cache;
  DB/WAL/SHM and quarantined copies

Trusted actors
  app-owned persistence and boot code operating inside the resolved app data
  root

Entry points
  database open/migration, save capture, hydration, corruption classifier,
  sidecar quarantine

Threats in scope
  accidental corruption, malformed rows, partial sidecar sets, permission/disk
  failures, path/sensitive-content disclosure through diagnostics, and
  destructive misclassification of an open failure

Required controls
  exact recovery allowlist; core never uses local reset; resolved file set
  stays inside the app-owned data root; source-scrubbed diagnostics; one
  physical-recovery record; unclassified failures preserve files
```

An adversarial local user with access to the same account, encryption at rest,
cloud sync, and multi-user isolation are non-goals. The implementation must not
add network export, include row contents in telemetry, or broaden filesystem
scope.

File-mode hardening, quarantine retention, and rollback-capable sidecar moves
are separate security/recovery work because this spec preserves the current
quarantine implementation rather than modifying it.

## Planning Inputs

- Local continuation failures and successful physical local replacement remain
  diagnostic-only in this focused change; no new user-visible recovery UI.
- Main-window sidebar continuation and the existing Inbox retention policy are
  preserved.
- Exact task ordering, write scopes, and commands belong to the implementation
  plan.
