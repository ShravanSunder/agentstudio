# Worktree Annotations PR1 — Program Design

Requirements:
[`pr1-user-requirements.md`](./pr1-user-requirements.md)

Specification:
[`pr1-specification.md`](./pr1-specification.md)

## How the complete PR1 loop fits together

PR1 adds one Bridge-feature annotation Store shared by every File View and
Review View in the application. BridgeWeb owns interaction scheduling and
presentation. The Store owns feature commands, queries, demand, and publication;
the repository and `local.sqlite` own complete durable annotation records. A
bounded projection Atom exposes only the summaries and active-session detail
currently demanded by viewers. The App target supplies only composition and the
native clipboard and save-panel/file effects.

```text
App composition root
  │
  ├─ constructs one application-scoped WorktreeAnnotationStore
  │    ├─ commands + queries + demand admission
  │    ├─ datastore adapter → repository → local.sqlite authority
  │    ├─ source evaluator + output coordinator
  │    └─ committed results → WorktreeAnnotationProjectionAtom
  │
  ├─ injects the same Store facade into every BridgePaneController
  │    ├─ File annotation transport adapter  ──┐
  │    └─ Review annotation transport adapter ─┴─ same commands and state
  │
  └─ injects WorktreeAnnotationOutputEffects
       ├─ system clipboard
       └─ NSSavePanel + atomic file write

BridgeWeb
  ├─ shared annotation client, editor, thread, and draft scheduler
  ├─ File View → Pierre CodeView 1.2.10 annotation adapter
  └─ Review View → Pierre CodeView 1.2.10 annotation adapter
       └─ renders Store-published projections in the main CodeView
          no PR1 side panel
```

Pane state continues to describe what one pane displays. Annotation state
describes one worktree review round and therefore outlives any pane, any
workspace, and any viewer instance.

Current-source anchors for this structure are the existing Bridge transport in
`BridgeWeb/src/core/comm-worker/bridge-product-transport.ts`, Review CodeView
composition in
`BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel-frame.tsx` and
`bridge-code-view-panel.tsx`, File composition in
`BridgeWeb/src/file-viewer/bridge-file-viewer-code-panel.tsx`, workspace-local
persistence boundaries in `docs/architecture/atom_persistence_boundaries.md`,
and the Inbox Notification atom/store/adapter/repository chain under
`Sources/AgentStudio/Features/InboxNotification/State/MainActor`. Pierre claims
are pinned to tag `diffs-v1.2.10` (`fa35bdcf877678c717685ea285e11231cce69a94`),
not to a newer Pierre checkout.

## The structural choice and its cost

| Direction | Gain | Cost or failure | Decision |
| --- | --- | --- | --- |
| Put annotations in each pane/worker | locally simple UI wiring | duplicate truth, pane-loss risk, reconciliation between File and Review | rejected |
| Put annotations in Core workspace pane state | immediate access from App | widens transitional `BridgePaneState`, makes Core own a Bridge feature, couples review lifecycle to panes | rejected |
| One Bridge-feature Store backed by a repository, with a bounded projection Atom | durable truth stays in SQLite, commands remain transactional, UI observes only demanded state, File and Review converge | Store must explicitly manage projection demand and publish committed deltas; two thin surface adapters remain necessary | selected |

The paired adapters contain no lifecycle, storage, output, or source policy.
PR1 does not refactor the generic transport in anticipation; a repeated second
cross-surface use case is the revisit signal.

The existing Atom-observation → debounced snapshot-save pattern is deliberately
not reused. It fits bounded preferences and caches, but annotations retain
unbounded human history, immutable versions, and exact output bytes. Observing
the projection Atom would turn UI memory into a second database and could expose
uncommitted state. PR1 instead persists each semantic command first and projects
only its committed result.

## Owners and dependency direction

```text
AgentStudio App target
  owns native effect implementation and composition only
         │ injects
         ▼
AgentStudioBridge Feature
  WorktreeAnnotationStore                 command/query/demand coordinator
  WorktreeAnnotationProjectionAtom        bounded observable projection
  WorktreeAnnotationSQLiteDatastoreAdapter workspace datastore boundary
  WorktreeAnnotationSQLiteRepository      durable truth + transaction policy
  WorktreeAnnotationSourceEvaluator       continuity and placement evidence
  WorktreeAnnotationOutputCoordinator     prepare/effect/finalize sequencing
  WorktreeAnnotationBatchProjector        deterministic Markdown/JSON bytes
  WorktreeAnnotationTransportAdapters     pane protocol adaptation
         │ uses existing datastore boundary
         ├────────► AgentStudioCore
         │           WorkspaceSQLiteDatastore  local recovery provenance at boot
         │
         │ projects validated values
         ▼
BridgeWeb
  WorktreeAnnotationClient                typed calls/subscription
  WorktreeAnnotationDraftScheduler        debounce/max-wait/focus-loss intent
  Pierre annotation adapters              item/range projection and selection
  shared annotation components            editor/thread rendering and focus
  owned shadcn/Sonner toast primitive     Copy confirmation presentation
```

| Truth or side effect | Sole owner | Consumers |
| --- | --- | --- |
| Complete session, thread, message, version, origin, and output records | `WorktreeAnnotationSQLiteRepository` in `local.sqlite` | Store queries and transactions only |
| Command policy, query orchestration, projection demand, and committed publication | `WorktreeAnnotationStore` | transport adapters and output coordinator |
| Session discovery summaries and actively demanded session details | `WorktreeAnnotationProjectionAtom` | File/Review subscriptions only |
| Visible draft/save/lock, placement, resolution, loading, error, and revision facts | `WorktreeAnnotationProjectionAtom` | composers and thread presentation |
| Application-local datastore access | `WorktreeAnnotationSQLiteDatastoreAdapter` | store only |
| Immutable origin and accepted continuity evidence | `WorktreeAnnotationSQLiteRepository` | source evaluator through Store; batch projector |
| Rebuildable current placement projection | source evaluator result published by Store | active viewer projections and batch preparation |
| Exact output batch membership, bytes, and status | `WorktreeAnnotationSQLiteRepository` | output coordinator and on-demand history query |
| Clipboard replacement and save-panel/file write | App implementation of output-effects contract | output coordinator only |
| Application-local quarantine/replacement provenance | `WorkspaceSQLiteDatastore` boot recovery recorded through `WorkspaceLocalMigrations` schema | annotation repository hydration and App recovery reporting |
| DOM selection, draft cadence, and unsent keystrokes after the last accepted command | active BridgeWeb editor/scheduler | Store after command admission |

Allowed dependencies point from App composition and BridgeWeb presentation
toward Bridge-feature interfaces, then from the feature toward the existing
Core datastore and `agentstudio-git` boundaries. Forbidden edges are:

- BridgeWeb directly reading or writing SQLite, Git, clipboard, or files;
- File and Review controllers owning independent annotation state or a comment side panel;
- persistence triggered by observing or snapshotting the projection Atom;
- exact output bytes or cold completed-session history retained in the Atom;
- the repository calling UI or native effects;
- `BridgePaneState` or pane publication becoming annotation authority;
- Infrastructure naming annotation models;
- PR1 types naming agents, providers, delivery, acknowledgement, or App IPC.

Package/module boundaries and exhaustive Swift/TypeScript protocol registries
provide static enforcement. Repository transaction guards and strict decoding
provide runtime enforcement.

## Durable and derived state

The application-local SQLite database carries application-global annotation
rows, following the existing global-row precedent (`local_entity_recency`).
The stable review identity is `(worktreeId, sessionId)`, where `worktreeId` is
the stable worktree lineage identity; workspaces, panes, and
viewer instances are not part of the key. The originating workspace may be
recorded as provenance metadata only and never partitions discovery or
identity. New session, thread, message,
saved-version, output-attempt, and output-event identities use the repository's
UUIDv7 generation APIs.

```text
local.sqlite authority

annotation_session
  ├─ session identity, stable repo/worktree lineage identity
  │    └─ originating workspace as provenance only, never a key
  ├─ living/completed
  ├─ applicable/uncertain/detached
  └─ accepted source fingerprint and reviewer continuity decision

annotation_thread
  ├─ session identity, scope, created order
  ├─ open/resolved
  └─ immutable origin reference
       └─ path, line/range, source role, excerpt, source/version evidence

annotation_message
  ├─ thread identity, flat chronological ordinal, human author kind
  ├─ saved versions ── immutable append-only records
  └─ at most one durable working draft

annotation_output_attempt
  └─ exact prepared batch + projection versions + provisional message locks

annotation_output_event
  └─ successful kind + exact immutable batch + materialized output bytes

local_recovery_provenance
  └─ recovery kind + recovered time + quarantined filenames
       └─ acknowledged time is nullable; acknowledgement never deletes witness
```

`WorkspaceLocalMigrations` remains the repository-facing owner of
`local.sqlite` schema migration. Under
`Sources/AgentStudio/Features/Bridge/State/MainActor`,
`WorktreeAnnotationStore` is the feature command/query/demand boundary;
`Persistence/` contains only its datastore adapter and SQLite repository. The
Store uses `WorktreeAnnotationSQLiteDatastoreAdapter` to reach
`WorktreeAnnotationSQLiteRepository`, whose transactions own durable invariants.
The `@MainActor @Observable WorktreeAnnotationProjectionAtom` is a view of
committed results, never a SQLite row model or persistence trigger. App boot
constructs the Store from the workspace datastore, source evaluator, output
coordinator, and projection Atom, then injects the Store facade into Bridge
controllers. `AtomRegistry` constructs and retains only the projection Atom;
neither the Store nor its repository becomes ambient. A migration creates the
tables in one hard cut; there is no legacy annotation data to import.

```text
WorktreeAnnotationProjectionAtom (bounded view)
  ├─ discovery summaries for the current worktree
  ├─ detail for sessions with active File/Review subscription demand
  ├─ visible output-attempt/event summaries
  └─ loading · unavailable · revision facts

Never projected merely because it exists in SQLite
  ├─ cold completed or detached session detail
  ├─ exact historical Markdown/JSON bytes
  ├─ normalized repository rows
  └─ undemanded message/version history
```

When the first viewer demands a session, the Store queries its complete visible
thread projection and publishes it. Multiple panes share that keyed projection.
When demand reaches zero, the projection may be evicted without a save because
SQLite already owns it. Discovery summaries remain bounded metadata; output
detail and exact bytes are fetched only when inspected or explicitly repeated.

Current placement is rebuildable derived state. It may be cached for display,
but immutable origin plus current source evidence remain authoritative; restart
publishes `unavailable` until evaluation completes.

The existing `PaneDomainState.review.threads` / `ReviewThread` test model is not
a predecessor authority. Its unused thread storage is removed or narrowed to
its remaining test-only viewed-file responsibility during cutover so it cannot
form a second annotation path.

## Behavioral interfaces

### Store command and projection boundary

Every mutation carries the session identity and expected committed semantic
revision. That revision is repository-backed and merely projected to the Atom;
it is not an Atom invalidation counter. Draft
edits also carry a message edit token and expected draft revision. The Store:

1. validates wire shape and resolves the command against the demanded projection;
2. asks one repository transaction to reload the authoritative affected rows,
   revalidate session writability, source scope, message mutability, Markdown,
   expected revision, and edit ownership, then commit the mutation;
3. converts the committed repository result into a compact projection delta;
4. applies that delta to `WorktreeAnnotationProjectionAtom`; and
5. publishes the committed revision through the existing product stream.

Failure leaves SQLite and the existing projection unchanged. Stale or duplicate
commands return a typed conflict/current revision and perform no write. A viewer
reloads the affected projection from the returned committed state without
overwriting its unsubmitted local text. No observer watches Atom changes for
autosave: a durable Atom revision means the repository commit already succeeded.

On Save, the BridgeWeb scheduler cancels pending timers, sends the latest body,
awaits its committed draft revision, then requests the version transition with
that expected revision. Focus loss sends the latest body immediately but does
not establish a saved version. Equality with the last acknowledged draft
suppresses a redundant send without suppressing Save.

```text
durable command
  BridgeWeb → Store → repository transaction → committed delta → projection Atom

projection-only change
  loading / error / rebuilt placement / demand eviction → projection Atom only

hydration or query
  repository → Store → projection Atom; never written back merely because read
```

### Surface transport boundary

Current product calls and subscriptions have one static surface. PR1 therefore
adds paired File and Review wire registrations for the same logical operations:

```text
File wire methods/subscription   ─┐
                                 ├─ WorktreeAnnotationTransportAdapter
Review wire methods/subscription ─┘
                                      │
                                      └─ one Store command/projection contract
```

The logical contract covers discovery, projection-demand acquire/release,
create/reply, draft flush, Save/Revert,
resolve/reopen, finish/reopen session, continuity decision, output preparation,
output-history inspection, and recovery-provenance acknowledgement. It defines
no delete operation: thread deletion
is PR2 scope with owner-decided semantics (open threads, whole thread only;
resolved threads never), and PR1 registers no delete wire method. The compact annotation subscription carries
session summaries and the complete messages needed by actively demanded
sessions. Complete messages are dynamically frame-packed under the existing
wire bound. Exact historical output bytes bypass the Atom and are consumed
directly by the native output coordinator; large source bodies continue to use
existing File/Review content descriptors. The annotation protocol does not
become another file transport.

The physical command and stream routes, pane/session admission, request
correlation, strict decoding, sequencing, resync, and backpressure remain
unchanged. There is no annotation App IPC operation.

Discovery returns every session for the current worktree lineage, including
applicable, uncertain, detached, and completed sessions, and never chooses by
recency. When no living applicable session exists, the first create-thread
command atomically rechecks discovery, creates the session, and creates its root
message draft in one repository transaction; there is no separate
session-create ceremony. When exactly one living applicable session is eligible, the
presentation offers direct continuation. When several are eligible, the
reviewer must select one before the Store admits a thread. Uncertain, detached,
and completed sessions remain explicit decide, inspect, or reopen paths. A
finish command carries the expected open-thread count and an explicit
unresolved-work confirmation when that count is nonzero; the Store/repository
transaction rejects a stale count or missing confirmation.

```text
first annotation intent
  ├─ zero living applicable sessions
  │    └─ one transaction: create session + root draft
  ├─ one living applicable session
  │    └─ continue that explicit projected session
  └─ several living applicable sessions
       └─ reject until reviewer selects one
```

### Source-evaluation boundary

The evaluator consumes immutable origin evidence, current worktree/repository
identity, surface-appropriate provenance, and bounded `agentstudio-git` reads.
File material requires the stable repository/worktree source identity already
published by the File surface. Review material additionally requires the PR0
comparison origin admitted with that Review source. The evaluator returns
evidence plus a classification; it never mutates session or thread state.

One Bridge-owned annotation-message Markdown policy is authoritative for editor
Save validation, rendered annotation messages, and output projection of authored
message bodies. It rejects raw HTML plus both ATX H1 (`# heading`) and setext H1
forms before Save, while admitting H2-H6 and the rest of the safe message
vocabulary. It does not govern File/Review document previews, whose source
documents may contain H1. The batch projector separately owns its one generated
packet H1.

Annotation rendering reuses the existing Markdown worker parser and Shiki code
rendering, then applies an annotation-specific sanitizer policy. That policy
preserves an authored link's `href` only when it parses as an absolute `http` or
`https` URL, removes every other link scheme and unrelated attribute, and keeps
raw HTML disabled. The existing `BridgeNavigationDecider` remains the navigation
authority: admitted web links open in the default browser and never navigate the
bundled Bridge pane; all other schemes remain blocked. File/Review document
preview sanitization remains unchanged, so PR1 does not silently widen the
existing document-preview trust contract merely to render annotation links.

Located-anchor admission has exactly one source in PR1: the Pierre adapter
maps the selected item, range, and diff side to repository-relative coordinates
plus the admitted content/source identity, and the native adapter cross-checks
identity and range before a Store/repository transaction admits an origin.
Rendered-Markdown preview selection is not an admission source: no
rendered-HTML-to-source-line mapping exists in the current
worker/sanitizer, and the source-map subsystem that capability requires is
deferred to a follow-up PR. Rendered DOM identity alone is never evidence.

```text
continuity
  same stable repository/worktree identity + compatible accepted provenance
      └─ proven same
  missing, conflicting, or insufficient identity/provenance
      └─ uncertain
  proven different repository/worktree lineage
      └─ detached

placement within an applicable session
  same source identity and range                       ── exact
  unique rename/context correspondence                 ── relocated
  applicable source but no unique trustworthy location ── outdated
  required source cannot be read                       ── unavailable
```

The durable accepted session fingerprint always contains the stable repository
ID and stable worktree ID. It also retains source-provenance observations by
surface: File observations use the stable File source identity, while Review
observations add the PR0 comparison-origin fields admitted for that Review
material: symbolic target, resolved target OID, reviewed HEAD OID, base role,
and base OID. PR0 comparison provenance is required only when evaluating Review
material; its absence on File material is not uncertainty. Paths, branch
labels, pane IDs, worker generations, and line placement are never lineage
evidence.

Continuity evaluation is ordered and stops at the first decisive row:

| Evidence | Result | Durable action |
| --- | --- | --- |
| Current stable repository ID or worktree lineage is proven different from the accepted fingerprint | `detached` | preserve accepted fingerprint and session history |
| Stable repository/worktree identity is missing or conflicting, or required provenance for the material being evaluated cannot be tied to that lineage | `uncertain` | preserve accepted fingerprint and pause annotation |
| Stable repository/worktree lineage matches and the surface-appropriate provenance is complete | `applicable` | accept the current File source observation or Review HEAD/target/base provenance |
| Evaluator/read failure prevents either conclusion | `uncertain` | preserve accepted fingerprint; never infer from path or branch label |

Within proven matching lineage, edits, commits, amend, rebase, reviewed-HEAD
movement, symbolic-target movement, resolved-target movement, and base movement
do not detach or complete the session. They update accepted provenance and
trigger placement reevaluation. An explicit reviewer Continue from `uncertain`
accepts the displayed current lineage/provenance; Leave Paused changes nothing,
and Start Another creates a separate session.

Placement evaluation runs only after continuity is applicable and uses this
precedence:

| Current-source evidence | Placement |
| --- | --- |
| Required source cannot be read or materialized | `unavailable` |
| Same repository-relative path and source role contain the exact selected source bytes at the original range, even if an unrelated part of the source changed | `exact` |
| One unique current range is proven by Git rename evidence or the stored selected excerpt plus context | `relocated` |
| Source remains applicable but there is no match, or two or more candidate ranges survive | `outdated` |

A comparison-target change therefore affects placement, not continuity: the
thread can remain exact, relocate, become outdated, or become unavailable in
the newly admitted material. Duplicate context never chooses a winner. A later
source read or the original proven lineage can move placement or relationship
back to a stronger state without changing lifecycle or resolution.

The evaluator never mutates state. The Store gives its evidence to a repository
transaction: durable continuity changes and accepted fingerprints commit there,
then the Store publishes the result. `Proven same` advances the accepted
fingerprint automatically. `Uncertain` pauses new annotation until a reviewer
decision. `Detached` preserves the session without completing it. If the
original proven source returns, the relationship becomes applicable again.
Rebuildable placement may be projected without persistence, but context matching
cannot prove continuity.

| Evidence or action | Relationship after evaluation | Lifecycle effect |
| --- | --- | --- |
| Same stable repository/worktree lineage and compatible surface provenance after edits, commits, amend, rebase, or target movement | applicable | none |
| Missing, conflicting, or insufficient identity evidence | uncertain until reviewer decision | none |
| Proven different repository/worktree lineage | detached | none |
| Original proven source returns | applicable again | none |
| Finish or reopen | relationship unchanged | completed or living respectively |

### Output-effects boundary

The Bridge feature declares an async, App-implemented effect contract:

- choose an export destination, where cancellation has no annotation effect;
- replace the system clipboard with exact UTF-8 Markdown bytes;
- atomically write exact JSON bytes to the selected file URL.

The App implementation owns `NSPasteboard`, `NSSavePanel`, overwrite
confirmation, and filesystem errors. It receives already validated bytes and
returns a typed success, cancellation, or failure. It does not inspect or
reconstruct annotation meaning.

## Session, thread, and message state

Session lifecycle and source relationship remain orthogonal:

```text
                    evaluator / reviewer source decision
              ┌──────────────────────────────────────────┐
              ▼                                          │
living + applicable ── uncertainty ──► living + uncertain
      │         ▲                         │
      │         └─ reviewer continues ────┘
      │
      ├─ different-lineage proof ──► living + detached
      │                                  │
      │       original source returns ───┘
      │
      └─ explicit finish ──► completed + current relationship
                                  │
                                  └─ explicit reopen ──► living

No placement, output, resolve, pane, or comparison event crosses lifecycle.
Every combination remains discoverable, including completed + uncertain and
completed + detached.
```

Threads use one whole-thread resolution state:

```text
OPEN thread
  root message
  reply 1
  reply 2
      │ explicit Resolve
      ▼
RESOLVED thread
  same immutable chronological messages
      │ explicit Reopen
      └──────────────────────────► OPEN thread
```

Messages have separate draft/readiness/immutability state:

```text
empty composer
  └─ first non-empty edit ──► durable never-saved draft
                                ├─ Revert ──► removed
                                └─ Save ────► saved message V1

saved message Vn
  └─ edit ──► durable draft based on Vn
                ├─ Revert ──► saved Vn
                └─ Save ────► append saved Vn+1

saved message Vn
  └─ successful or crash-unknown output includes it ──► output-locked message
                                                           └─ new reply only
```

An output lock applies to the message identity, not merely one version. Saved
versions remain append-only before output; successful or crash-unknown output
makes the included message permanently non-editable.

## Draft scheduling and convergence

Each active message edit has one scheduler owned by BridgeWeb and driven by an
injected monotonic clock. Native code persists every accepted command
immediately; it does not add a second debounce or max-wait timer.

```text
BridgeWeb edit scheduler
  ├─ first non-empty edit ──► send immediately
  └─ later changed content
       ├─ restart 1-second debounce
       ├─ retain 5-second maximum-wait deadline
       └─ keep latest body in browser pending intent

whichever occurs first
  ├─ 1 second without another edit
  ├─ 5 seconds since the first unflushed edit
  ├─ focus loss
  └─ explicit Save
        │
        ▼
one browser→native command
       │
       ▼
Store → repository transaction
       ├─ success ──► committed delta → projection Atom
       └─ failure ──► projection unchanged; browser keeps unsent text
```

Browser coalescing is keyed by message identity. Continuous typing produces at
most one command per five seconds, while focus loss and Save send immediately.
The Store serializes command admission and repository transactions serialize
durable rows. Every pane subscription observes the same committed revision.

Only one edit token may mutate a message at a time. Another view can read the
draft and thread, but a stale token cannot overwrite newer text. Pane closure
releases its token only after the browser requests the immediate focus-loss
flush. A hard crash recovers the latest completed native commit.

## Pierre 1.2.10 presentation in the main view

PR1 stays pinned to `@pierre/diffs` 1.2.10. Pierre owns source selection,
gutter triggers, diff side, annotation slots, range highlighting, layout, and
scrolling. It does not own threads, messages, drafts, persistence, resolution,
continuity, placement meaning, or output history.

```text
Pierre CodeView 1.2.10
  onGutterUtilityClick / onLineSelectionEnd
               │ item + selected range + diff side
               ▼
BridgeWeb Pierre annotation adapter
  maps to repository-relative evidence and admitted source identity
               │ typed create-thread intent
               ▼
native Store → repository commit → projection Atom
               │
               ▼
adapter builds LineAnnotation / DiffLineAnnotation values
               │ renderAnnotation portal
               ▼
shared thread component, inline inside the main CodeView
  root → flat replies → Reply / Resolve or Reopen
```

File mode uses `LineAnnotation<T>`; diff mode uses
`DiffLineAnnotation<T>` with its additions/deletions side. The adapter enables
line selection and gutter utility callbacks, renders durable located threads
through `renderAnnotation`, and uses Pierre's `setSelectedLines`/`scrollTo`
handle operations where navigation requires them. Whole-file and session
threads render in the main File/Review surface outside a source slot, not in a
side panel.

Pierre line slots are used only when a trustworthy current location exists.
`exact` and `relocated` located threads render through those slots. `outdated`
and `unavailable` located threads render in a clearly labeled degraded-thread
region in the same main File/Review surface beside the file/session chrome.
That region shows immutable origin, placement status, and the reason current
placement is not trustworthy; it never fabricates a line slot and is not a
sidebar.

```text
main File / Review surface
  ├─ Pierre source slots
  │    ├─ exact located thread
  │    └─ relocated located thread
  ├─ file/session chrome
  │    ├─ whole-file thread
  │    └─ session thread
  └─ degraded-thread region
       ├─ outdated + immutable origin + warning
       └─ unavailable + immutable origin + warning
```

Review worker/materialization updates must merge the current annotation
projection into each item. They may update content or syntax state, but must
not overwrite `item.annotations`; `CodeViewHandle.updateItem` receives the
merged item. Shared thread/editor components remain Bridge-owned React views
rendered through Pierre's portal slots.

## Current-to-proposed call paths

There is no current durable annotation call path. Existing paths provide the
transport, source, persistence, and effect boundaries that PR1 composes.

| Behavior | Current source-anchored path | Proposed delta |
| --- | --- | --- |
| File/Review intent to native | BridgeWeb `BridgeProductTransport.call` → product session → `BridgePaneProductSchemeProvider.response` → controller callback/result | unchanged physical route and correlation; add paired annotation call registries and adapter target |
| Native state to viewer | pane metadata source → product stream → comm worker → React store | unchanged stream mechanics; add paired annotation subscriptions sourced from Store-published projection Atom state |
| Durable feature rows | App boot → `WorkspaceSQLiteDatastore` → feature SQLite adapter/repository → `local.sqlite` | add Bridge annotation repository and one App-composed store; do not route through pane persistence |
| Source evidence | pane controller → shared construction / `agentstudio-git` provider → immutable File/Review products | retain Git authority; add evaluator consuming admitted provenance and bounded reads |
| Clipboard/file output | no Bridge annotation predecessor; AppKit clipboard examples exist, no annotation save-panel flow | add injected output-effects implementation; no browser or Infrastructure ownership |

### Authoring path

```text
[ADDED] React composer
   │ async typed File/Review annotation call
   ▼
[ADDED] surface transport adapter
   │ typed logical command
   ▼
[ADDED] WorktreeAnnotationStore
   │ validate + async repository transaction
   ▼
[ADDED] datastore adapter → repository → local.sqlite authority
   │ committed result | typed error
   ▲
Store applies committed delta to WorktreeAnnotationProjectionAtom
   │ event through existing pane stream [UNCHANGED]
   ▼
all subscribed File/Review viewers render the same revision
```

### Source-change path

```text
existing worktree epoch / Review publication change [UNCHANGED]
   │ compact immutable evidence
   ▼
[ADDED] source evaluator actor
   │ classification + evidence | unavailable error
   ▼
[ADDED] Store → repository transaction
   ├─ proven same ──► persist fingerprint; project placements
   ├─ uncertain   ──► persist pause; project warning
   └─ detached    ──► persist detached; preserve history
   │ revisioned delta through existing stream [UNCHANGED]
   ▼
File and Review presentation
```

## One batch, two output effects

The output coordinator prevents the Markdown and JSON paths from selecting or
snapshotting independently.

```text
selected message IDs + expected saved-version IDs
                 │
                 ▼
prepare operation: validate + capture exact batch + project exact bytes
                 │
Store → repository transaction: revalidate + persist batch/bytes
                                + provisionally lock every included message
                 ▼
App-owned clipboard or file effect
        ├─ known failure ──► idempotent cancel-attempt transaction
        │                    ├─ commit ──► release only its otherwise-unlocked
        │                    │             provisional locks
        │                    └─ failure ─► retain prepared row + locks; report
        │                                  effect failure and cleanup failure
        │                                  separately; retry cleanup only
        └─ known success
                 │
                 ▼
Store → repository transaction: finalize event + exact batch + permanent locks
        ├─ success ──► publish event/history
        └─ failure ──► keep durable attempt and locks; report partial success
                       never repeat the external effect automatically
```

The prepared transaction is the immutability boundary: no external effect may
begin until the exact bytes, exact membership, and provisional locks commit.
Known effect failure asks one idempotent repository transition to cancel that
attempt and releases a message only when no successful event, unknown attempt,
or other prepared attempt also locks it. If that cancellation transaction fails,
the coordinator retains the in-memory proof that the external effect failed,
reports both the effect failure and the cleanup-persistence failure, leaves the
durable prepared row and locks unchanged, and may retry only the idempotent
cancel transition while that proof remains available. It never repeats the
external effect automatically. If the process terminates before cancellation
commits, restart can no longer prove the external outcome from durable state;
the still-prepared attempt therefore recovers as `unknown` rather than
fabricating the lost in-memory failure result. A returned effect success followed
by finalization failure is known partial success. Only a crash or lost response
that leaves durable state unable to prove whether the effect occurred becomes
`unknown`; it retains the prepared attempt and locks.

For Export, destination selection occurs before the store prepares an attempt,
so panel cancellation creates neither a file nor annotation state. The pure
projector builds bytes from the captured snapshot; the store transaction then
revalidates the selected saved versions before atomically persisting canonical
semantics, the projection contract version, the exact materialized bytes, and
the provisional message locks. History can therefore inspect and reproduce the
original output without running current projection code.

The store supplies the batch identity and captured creation time through
injectable UUID and wall-clock sources. The monotonic draft clock and wall-clock
output timestamp are separate dependencies, so controlled-time proof never
depends on sleeps or the machine clock.

Output-history discovery publishes only bounded event summaries. Inspect asks
the Store for the selected event's immutable membership and context. Reproduce
passes the repository's already materialized exact bytes directly to the output
coordinator; exact Markdown/JSON bytes never enter the projection Atom or get
rebuilt from current messages.

The Markdown projector emits exactly one generated H1. Every other generated
context element is a plain field label followed by text, with `---` between
entries; it generates no H2–H6 wrapper headings. The authored message body is
then inserted byte-for-byte after the `Request:` label, so authored H2–H6 remain
subordinate to the packet H1 without escaping a generated file/request heading.
Source excerpts use visible line numbers and a fence longer than any colliding
fence in the excerpt. The projector orders session threads first, then
repository-relative paths, whole-file before located threads, trustworthy
current/original line, and stable thread/message identity. The JSON projector
emits the same membership and order under one strict format version.

Annotation mutation frames carry only compact repository/worktree identity,
repository-relative path, source role, admitted source identity, and selected
line/range coordinates. They do not carry an arbitrary source excerpt. The
native source owner validates those coordinates against the admitted File or
Review material and captures the selected excerpt for immutable origin and
batch construction. Exact excerpt and final Markdown/JSON bytes remain in the
repository/output path outside the compact projection Atom and message-frame
packing contract.

Each root, reply, draft, and saved version is admitted only when its UTF-8 body
is at most 16 KiB. The complete-message wire entry is deliberately smaller than
the durable model: it carries the session/thread/message/version identities,
flat ordinal and semantic revisions, fixed human-author kind, latest saved body,
optional current draft body, readiness/lock facts, and resolution/placement
summary. Immutable excerpts, exact output bytes, cold saved-version history, and
duplicated source bodies are excluded. One bounded thread-context record carries
the scope, repository-relative path, source role and coordinates; it references
the admitted source identity and never embeds the source excerpt.

All strings and identifiers in those records use the existing product-wire
ceilings, each body uses the 16 KiB limit, and a complete encoded message entry
has a 64 KiB ceiling. The codec contract MUST prove that a singleton frame
containing the maximum legal thread context and maximum legal message entry fits
inside the existing 128 KiB encoded-frame ceiling. Runtime packing measures the
entire encoded frame, including its envelope and repeated thread context, and
starts a new frame before appending an entry that would exceed the ceiling. It
never splits a message and never rejects a Specification-valid message merely
because other messages filled the current frame. Failure of a maximum-legal
singleton to fit is an implementation invariant violation that makes the
projection unavailable; it is not a second user-facing message-admission rule.
Thread size is otherwise the sum of its independently admitted messages.

```text
ordered complete messages
   │ measure encoded message + envelope overhead
   ▼
current frame fits? ── yes ──► append complete message
        │ no
        ▼
seal frame (≤ 128 KiB) → start next frame → append complete message

singleton proof:
  maximum legal thread context + maximum legal message entry + envelope
      ≤ 128 KiB encoded

No byte range from one message appears in two frames.
```

## Failure, partial success, and recovery

```text
mutation or output failure
  ├─ validation/revision conflict
  │    └─ no write; return committed repository revision
  ├─ draft persistence failure
  │    └─ keep last durable draft; retain local unsent text; allow retry
  ├─ commit succeeds, response/publication is interrupted
  │    └─ reconnect reloads committed state; a stale retry conflicts
  │       Store republishes projection without a second mutation
  ├─ source read/evaluation failure
  │    └─ placement unavailable or continuity uncertain; never guess
  ├─ clipboard/file effect failure
  │    ├─ cancel transaction commits
  │    │    └─ no output event; release only otherwise-unlocked locks
  │    └─ cancel transaction fails
  │         └─ report known effect failure + cleanup failure; retain prepared
  │            row/locks; retry idempotent cleanup only while proof is live
  ├─ known effect success followed by finalization failure
  │    └─ report partial success; durable attempt and locks remain
  └─ crash or lost result where effect outcome cannot be proven
       └─ durable attempt becomes unknown; exact batch/bytes and locks remain
            └─ reviewer may explicitly copy/export exact bytes again
               or leave unknown; never replay automatically
```

| Failure/interleaving | Containment and recovery owner |
| --- | --- |
| Store query/hydration fails | Store publishes unavailable for the affected projection; no empty replacement is published; repository remains recovery truth |
| local.sqlite was quarantined and recreated before this launch | boot recovery persists a recovery-provenance row in the fresh database before feature hydration; annotation state becomes recovered-degraded and rejects annotation mutations, the reviewer is notified through `PersistenceRecoveryReporter`, and quarantined sidecars stay on disk; acknowledgement records `acknowledgedAt`, accepts beginning from the fresh database, and clears the warning without deleting the witness |
| One malformed persisted row breaks invariants | repository quarantines/fails the affected load according to existing datastore recovery policy; it never silently fabricates an annotation |
| Duplicate or out-of-order wire command | product session sequencing rejects it before the Store; the transaction's expected committed revision is the durable second fence |
| Repository commit succeeds before crash or projection publication | durable result remains authoritative; reconnect reloads it, and a retry carrying the old expected revision conflicts rather than mutating twice |
| Two viewers edit one message | one edit token and expected draft revision accept one ordered writer; stale writes fail without replacing text |
| Pane closes during pending debounce | controller requests immediate flush, then releases edit token; durable store survives pane teardown |
| Known external effect failure, then cancel-attempt transaction fails | output coordinator reports the known effect failure and cleanup-persistence failure separately, retains the prepared row/locks, and retries only the idempotent cancel transition while the known result remains in memory; it never repeats the external effect |
| App restarts with an unfinished attempt | attempt is inspectable as `unknown`; exact bytes and included message locks survive; no recovery modal and no automatic replay |
| Reviewer explicitly retries an unknown attempt | output coordinator reuses the persisted exact bytes and batch; a new explicit effect result is recorded without rebuilding current content |
| Finalization request repeats | attempt identity makes finalization idempotent; existing event returns success without a duplicate event |
| Placement evaluation races a newer source epoch | evaluator result carries input fingerprint/epoch; store rejects stale result and schedules current evidence |
| Subscription reconnects | Store reloads the demanded committed projection; deltas older than its accepted revision are ignored |

Successful Copy uses a BridgeWeb-owned shadcn/Sonner toast primitive to show
`Copied N comments`, dismisses the copy interaction, and leaves every inline
thread open and visible. No toast primitive exists in the current owned UI
layer, so PR1 adds that primitive rather than inventing route-local toast
markup. Copy and Export never resolve a thread and never claim an agent
addressed it.

No automatic retry repeats Copy or Export. Repository retries may repeat only
idempotent reads or transaction attempts whose attempt/command identity prevents
duplicate semantic commits.

## Consistency and performance

The Store serializes semantic command admission. Repository transactions own
durable ordering, and the projection Atom applies only committed compact deltas
on MainActor. SQLite and Git work remain behind their existing async owners.
Batch formatting uses an immutable Sendable repository snapshot and runs off
MainActor before returning exact bytes to the output coordinator.

Draft traffic is an `often` lane. Its browser-side admission policy is
per-message coalescence with one-second debounce, five-second maximum wait, and
immediate first-edit/focus-loss/Save send. Equality suppression happens before
the repository transaction and projection publication. Source evaluation is
admitted by existing worktree epoch changes rather than a new poller. Output is
explicit user-driven work and has one in-flight attempt per session.

The transport publishes only demanded session projections and never duplicates
source bodies. Projection eviction is not deletion; no silent retention cap
deletes human review history from SQLite.

## Trust, privacy, accessibility, and observability

```text
untrusted Markdown / strict JSON wire input
       │ one WorktreeAnnotationMarkdownPolicy (Bridge feature)
       ▼
canonical repository snapshot
       │ projector scrubs generated fields; authored Markdown stays verbatim
       ▼
exact bytes
       │ App effect boundary
       ├─ system clipboard
       └─ reviewer-selected file

No network, agent principal, provider credential, or App IPC boundary exists.
```

- Authored Markdown is preserved verbatim and rendered through the existing
  Markdown parser/code-highlighting path plus the annotation-specific sanitizer;
  raw HTML and H1 fail before Save while H2–H6 and all other allowed Markdown
  remain valid. Only absolute HTTP(S) link destinations survive sanitization,
  and `BridgeNavigationDecider` opens them outside the Bridge pane. Only
  generated context fields are path-scrubbed.
- Wire and JSON contracts are strict discriminated/versioned schemas. Unknown
  fields and versions fail closed.
- Generated output fields contain repository-relative paths and source evidence
  only. An absolute path written by a human inside authored Markdown is content,
  not silently rewritten. Message bodies, excerpts, and exported JSON never
  enter OTLP.
- Telemetry may record safe counts, durations, outcome classes, and hashed
  repository/worktree identities under existing Bridge telemetry gates.
- File and Review compose the same shared editor/thread controls, keyboard
  behavior, focus semantics, status labels, and accessible actions. The Store
  owns behavior; presentation remains reusable and surface-neutral.
- The loop remains offline. Clipboard and local file access are the only
  external effects.

## Cutover and compatibility

PR1 is a hard additive cutover: the migration creates annotation tables, App
boot constructs the shared Store, repository, and projection Atom, and paired
File/Review adapters make the Store the only annotation command entrance. The
minimal pane-local thread test model cannot
accept annotation mutations afterward.

The local schema migration is atomic under the existing migrator. Failure keeps
the prior database authoritative and prevents annotation boot from claiming a
usable session. No legacy or deprecated review-comment schema is imported.

The JSON export version is an external strict output contract. PR1 emits one
version; unsupported-version rejection applies to internal validators and
tests, not to a PR1 import feature. Existing File/Review Git construction,
presentation state, physical transport routes, pane resync, and PR0 comparison
provenance remain authoritative.

SQLite migration or hydration failure fails the annotation feature closed while
preserving the database as recovery truth; it never publishes an empty
replacement. Annotation history opts out of the default-and-continue posture
that UX/cache lanes keep. The existing
local-database quarantine mechanism still isolates corrupt sidecars, but a
quarantine-and-replace launch must not let annotations silently hydrate as
"never existed". `WorkspaceLocalMigrations` owns a small application-local
recovery-provenance table. After successful quarantine and fresh migration,
`WorkspaceSQLiteDatastore` writes one row containing the recovery kind,
recovery time, and the quarantine helper's returned filenames before reporting
the local database available. Annotation hydration reads that provenance;
while an unacknowledged row exists, the Store publishes annotation state as
recovered-degraded rather than empty and emits the existing
`PersistenceRecoveryReporter` event consumed by App notification UI; PR1 adds
the worktree-annotation store discriminant to that existing event vocabulary.
An
explicit reviewer acknowledgement sets the row's `acknowledgedAt` and clears
the warning, allowing annotation commands to begin from the fresh database; it
never deletes the recovery witness, and quarantined sidecars remain on disk for
recovery. Before acknowledgement, annotation commands fail closed. A malformed
annotation
row that cannot satisfy schema and model invariants makes annotation hydration
unavailable and visible; PR1 does not silently drop the row, fabricate a
thread, or weaken durability.

```text
corrupt local.sqlite detected
          │
          ▼
quarantine DB / WAL / SHM ── failure ──► local unavailable; no replacement
          │ success + returned filenames
          ▼
migrate fresh local.sqlite
          │
          ▼
persist recovery provenance before availability
          │
          ├─ unacknowledged ──► recovered-degraded + mutations rejected
          │
          └─ reviewer acknowledges
                    └─► warning clears + fresh annotation writes allowed
                         witness and quarantined files remain
```

## How each requirement is realized and proved

```text
BridgeWeb interaction
   │ real typed product transport
   ▼
surface adapter ──► Store ──► real SQLite repository
                       │
                       ├─► projection Atom ──► rendered viewer state
                       ├─► source evaluator ──► controlled real Git fixture
                       └─► output coordinator
                                  ├─ fake effect for failure/order proof
                                  └─ real App effect for clipboard/file proof

Observation points
  committed repository revision · SQLite rows · rendered viewer state
  exact clipboard bytes · exact exported bytes · output event/batch history
```

| Requirements | Realization owner and seam | Required proof boundary |
| --- | --- | --- |
| P1-U1, P1-U8, P1-U13, P1-U14 / R-P1-001, R-P1-009, R-P1-014, R-P1-016 | repository identities, Store discovery/commands, atomic zero-session first annotation, paired demand projections, flat whole-thread transactions | zero/one/several applicable-session admission; multi-pane File/Review integration; commit-before-publication retry; demand eviction/reload without a save; restart hydration; finish/reopen/resolve journeys |
| P1-U2, P1-U3 / R-P1-003, R-P1-004, R-P1-006 | edit scheduler, draft/version transactions | injected-clock unit behavior, SQLite recovery, Save/Revert UI integration |
| P1-U4 / R-P1-005 | Markdown validator, annotation-specific sanitizer, existing Markdown parser/code renderer and `BridgeNavigationDecider`, packet projector | schema/unit cases for H1/raw HTML and safe/unsafe link destinations, native navigation-policy proof, and real visual rendering/accessibility of an admitted link |
| P1-U5, P1-U6 / R-P1-002, R-P1-007 | immutable origin plus source evaluator and same-surface degraded-thread region | real Git fixtures for exact/relocated/outdated/unavailable placement plus rendered main-view accessibility without fabricated line slots |
| P1-U7, P1-U8 / R-P1-008, R-P1-009, R-P1-014 | Store/repository session transitions and continuity matrix | transition unit tests and manual warning/continue/detach/finish/reopen journey |
| P1-U9, P1-U10 / R-P1-010, R-P1-011 | output coordinator and Markdown projector | deterministic permutation tests and actual system clipboard inspection |
| P1-U11 / R-P1-012 | JSON projector and strict schema | round-trip, malformed/unknown-version rejection, actual selected-file inspection |
| P1-U12 / R-P1-013 | prepared attempt with provisional message locks plus idempotent cancel-attempt and event/batch finalization transactions | injected known-failure, cancel-transaction failure/retry, known-success/finalization-failure, and crash-unknown effects plus restart and real Copy/Export history inspection |
| P1-U14 / R-P1-014, R-P1-016 | full session discovery, flat message ordinal, and thread-owned resolution | mutation/store tests and cross-view reply/resolve/reopen interaction |
| all message-bearing requirements / R-P1-017 | 16 KiB body admission, bounded 64 KiB complete-message DTO, bounded thread context, and dynamic complete-message frame packer | maximum-legal singleton encoding and multi-message boundary packing at 16/64/128 KiB without rejection or message splitting |
| reliability obligation | boot-owned durable recovery provenance plus annotation hydration/acknowledgement policy | corrupt local-database integration proving quarantined filenames persist, pre-ack mutation fails closed, acknowledgement retains the witness, and subsequent restart distinguishes recovery from never-created state |
| all / R-P1-015 | dependency and protocol boundaries | module/protocol/source inspection proving no PR2 machinery or App IPC |

Real SQLite, the real product transport, the safe Markdown renderer, and real
Git fixtures are required for their integration claims. Controlled clocks and
fake output effects replace only time and fallible App effects in narrow unit
proof. Packaged UI proof uses the real clipboard and save panel/file path; a
mocked browser test cannot substitute for those effects.

Structural enforcement uses types and exhaustive registries for variants and
wire calls; SQLite constraints and transactions for durable invariants;
revision, edit-token, and source-epoch runtime guards for concurrency; strict
Markdown/JSON/path validation; module/architecture lint boundaries; and
automated plus packaged-effect proof.

Projection proof must also establish three negative rules: mutating loading or
display state does not invoke persistence, evicting a zero-demand projection
does not delete or save domain records, and exact historical output bytes never
become Atom state.

## Deliberate limits and revisit signals

Each selected component exists because removing it breaks a named durability,
cross-view, placement, deterministic-output, partial-success, or platform
obligation. PR1 adds no agent identity/delivery machinery, provider, App IPC,
new service/authentication system, second physical transport, or exactly-once
external delivery.

Revisit this structure only if evidence shows one of these falsifiers:

- a second cross-surface Bridge feature makes paired static-surface adapters a
  repeated source of protocol drift;
- measured annotation projections exceed compact stream bounds and require a
  content-descriptor query path;
- source evaluation cannot produce trustworthy relocation using File source
  identity or Review PR0 provenance plus `agentstudio-git` reads;
- product requirements later authorize collaboration, retention/deletion
  policy, or automated delivery that changes the owner or trust boundary.
