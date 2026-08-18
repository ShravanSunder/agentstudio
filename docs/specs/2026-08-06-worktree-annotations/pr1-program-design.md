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
  ├─ shared annotation client, complete-revision assembler, viewer-level
  │  thread interaction owner, inline shell, overlay, and draft scheduler
  ├─ File View → Pierre CodeView 1.2.10 annotation adapter
  └─ Review View → Pierre CodeView 1.2.10 annotation adapter
       └─ renders Store-published projections in the main CodeView
          no PR1 global panel, whole-file/session comment UI, or side panel
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
durable human work, flat thread history, and exact output bytes. Observing
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
  WorktreeAnnotationProjectionEventCursor incremental bounded event packing
  WorktreeAnnotationOutputSelectionAssembler
                                            product-session-scoped chunk assembly
  BridgeProductSession                    atomic capacity-wait admission lifecycle
  BridgeProductProducerRegistry           encoded frame/byte capacity truth
         │ uses existing datastore boundary
         ├────────► AgentStudioCore
         │           WorkspaceSQLiteDatastore  local recovery provenance at boot
         │
         │ projects validated values
         ▼
BridgeWeb
  WorktreeAnnotationClient                typed calls/subscription, assembly-failure resync emission
  WorktreeAnnotationInteractionController viewer-local decisions, output selection, and transient overlays
  WorktreeAnnotationDraftScheduler        debounce/max-wait/focus-loss intent
  AnnotationOutputSelectionSurface        on-demand bounded candidate selection
  Pierre annotation adapters              controlled selection, admission, and inline projection
  shared inline-comment components         shell/content/command-rail rendering and focus
  owned shadcn/Sonner toast primitive     Copy confirmation presentation
  BridgeCommWorkerProductController       annotation subscription cancel/reopen authority
```

| Truth or side effect | Sole owner | Consumers |
| --- | --- | --- |
| Complete session, thread, message, saved body, optional draft, origin, and output records | `WorktreeAnnotationSQLiteRepository` in `local.sqlite` | Store queries and transactions only |
| Command policy, query orchestration, projection demand, and committed publication | `WorktreeAnnotationStore` | transport adapters and output coordinator |
| Session discovery summaries and actively demanded session details | `WorktreeAnnotationProjectionAtom` | File/Review subscriptions only |
| Visible saved-body/draft/status, placement, resolution, loading, error, and revision facts | `WorktreeAnnotationProjectionAtom` | composers and thread presentation |
| Application-local datastore access | `WorktreeAnnotationSQLiteDatastoreAdapter` | store only |
| Immutable origin and accepted continuity evidence | `WorktreeAnnotationSQLiteRepository` | source evaluator through Store; batch projector |
| Rebuildable current placement projection | source evaluator result published by Store | active viewer projections and batch preparation |
| Exact output batch membership, bytes, and status | `WorktreeAnnotationSQLiteRepository` | output coordinator and on-demand history query |
| Clipboard replacement and save-panel/file write | App implementation of output-effects contract | output coordinator only |
| Application-local quarantine/replacement provenance | `WorkspaceSQLiteDatastore` boot recovery recorded through `WorkspaceLocalMigrations` schema | annotation repository hydration and App recovery reporting |
| Pending Pierre selection, active thread, open thread overlay, invoking-control focus return, active editor identity, temporary output selection, bounded session/continuity choices, draft cadence, and unsent keystrokes after the last accepted command | active BridgeWeb annotation client/provider and viewer-level `WorktreeAnnotationInteractionController` above Pierre portals | Store after semantic command admission; transient interaction state never enters the Store or projection Atom |
| Last complete browser projection and one assembling replacement revision | `WorktreeAnnotationProjectionStore` | File/Review projection subscribers; assembly state is transport synchronization, never durable annotation authority |
| One in-flight chunked output-selection transfer | transport-owned `WorktreeAnnotationOutputSelectionAssembler`, keyed by product session and transfer identity | transport adapter on commit; Store receives only one complete immutable selection |
| Eligible output-candidate query and inline-placement counts | `WorktreeAnnotationStore` over repository truth | bounded output-selection surface and conditional output-only rail trigger |
| Detection, retained-last-complete state, required browser-local `transportStatus`, and bounded resync request for annotation projection assembly failure | main-thread `WorktreeAnnotationProjectionStore` plus its `WorktreeAnnotationSurfaceClient` | File/Review subscribers and internal main-to-worker RPC |
| Exact active annotation subscription identity plus one request/generation-fenced cancel/reopen/first-state-barrier task | worker-owned `BridgeCommWorkerProductController` | strict `annotationProjectionResync` runtime handler only |
| Pending lossless ordinary metadata-frame admissions, FIFO order, cancellation, and producer/session replacement settlement | `BridgeProductSession` for the active metadata producer lease | pane presentation, pane surface-selection, and File/Review subscription-data callers through one internal async admission boundary |
| Encoded candidate size and the existing frame-count, byte-count, and terminal-reserve capacity predicate | `BridgeProductProducerRegistry` | `BridgeProductSession`; no feature or coordinator duplicates the calculation |
| Incremental `projection.state` then complete-message batch traversal for one consumed snapshot | `WorktreeAnnotationProjectionEventCursor` inside the annotation projection packer | annotation source; it retains cursor position plus at most one current encoded event, never a whole packed-event array |

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
- annotation assembly recovery invoking `source.refresh`, File display resync,
  Store/repository commands, or a new native product method;
- comm worker duplicating semantic projection assembly or accepting a resync
  request that does not name its exact active annotation subscription.
- an ordinary metadata-data source treating temporary queue saturation as
  `closeRequired`, resetting the shared stream, or silently retiring;
- the metadata coordinator, annotation Atom/source, or observation-pacing API
  owning another capacity queue or calculating producer capacity.

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
identity. New session, thread, message, output-attempt, and output-event
identities use the repository's
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
  ├─ session identity and created order
  ├─ open/resolved
  └─ immutable located origin reference
       └─ path, line/range, source role, excerpt, source/version evidence

annotation_message
  ├─ thread identity, flat chronological ordinal, human author kind
  ├─ one optional current saved body + monotonic saved revision
  ├─ one status: editable | locked
  └─ at most one durable working draft

annotation_output_attempt
  └─ exact prepared batch + message/saved-revision membership
       └─ prepared membership temporarily blocks message writes

annotation_output_event
  └─ successful copied/exported kind for the materialized exact bytes

local_recovery_provenance
  └─ recovery kind + recovered time + quarantined filenames
       └─ acknowledged time is nullable; acknowledgement never deletes witness
```

The message aggregate has no readiness enum and no saved-version collection.
Its content shape and durable status are sufficient:

```text
annotation_message
  id · thread_id · ordinal · author_kind
  saved_body? · saved_revision?
  status: editable | locked
  semantic_revision · created_at · updated_at

annotation_message_draft (zero or one per message)
  message_id · body · active_edit_token? · draft_revision · updated_at

saved_body   draft row   meaning
absent       absent      no durable message; rejected on hydration
absent       present     new unsaved message
present      absent      saved message; output-eligible when editable
present      present     saved message with unsaved edits
```

`saved_revision` is a monotonic compare token, not retained saved-body history.
It is absent exactly when `saved_body` is absent. First Save atomically writes
the body with revision `1`; every later Save atomically replaces the body and
increments that positive revision by one. Revision exhaustion fails Save
without changing the saved body or draft. Typed hydration rejects either
body/revision mismatch, and output admission requires the selected message's
positive expected revision to equal the current saved revision. These are
program-owned cross-field rules, never SQLite product-semantic `CHECK`s.

Save performs that replacement and deletes the draft in one transaction.
Revert deletes the draft; for a never-saved message it also removes the unsaved
message and its newly created thread when that thread has no other messages. A
never-saved draft must contain non-whitespace content. An existing saved message
may retain an empty draft so clearing the editor is durable; Save validation
rejects the empty body while Revert remains available. SQLite may structurally
bound a draft to `0...16384` UTF-8 bytes and a present saved body to
`1...16384` bytes. The typed repository owns the cross-field rule that an empty
draft is valid only when a saved body exists.

`status` is the only message-status enum. A prepared output membership is an
operation-owned write guard, not a third message status. Finalizing successful
output, or startup-recovering a prepared attempt whose external result cannot be
proven, changes each included message from `editable` to `locked`. Known
effect failure followed by successful cancel-attempt cleanup removes the
prepared guard without changing `status`.

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

The annotation portion of unshipped migration `005` is corrected in place. It
must not create `annotation_message_version`. Instead, `annotation_message`
owns nullable `saved_body` and `saved_revision` fields plus unconstrained-TEXT
`status`; `annotation_message_draft` remains the optional working row; and
`annotation_output_attempt_message` records the selected message ID and expected
saved revision. The attempt's canonical snapshot and exact bytes retain the
historical content. Because this schema has not shipped, adding a follow-up
migration to preserve the discarded version-table design is prohibited.

### SQLite schema evolution and program-owned enum validation

SQLite stores annotation product-enum values as ordinary `TEXT`, but it never
enforces their membership. `WorkspaceLocalMigrations` must not name annotation
enum literals in membership or equality `CHECK` constraints, triggers,
generated columns, or lookup-table foreign keys. This prohibition covers
session lifecycle and source relationship, thread scope and resolution,
message author kind and status, output kind and attempt state, output event kind,
recovery kind, and every future annotation product enum. The output-event kind
vocabulary is only `copied | exported`; uncertainty is represented exclusively
by output-attempt state `unknown` and never by a fabricated event.

Typed Swift codecs own product-enum membership and cross-field semantics. The
repository writes values only through those typed codecs and rejects an
unknown stored value during decoding according to the feature's fail-closed
load policy. SQLite retains structural integrity only: nullability, primary
and foreign keys, uniqueness, scalar and numeric bounds, byte limits, and
other constraints whose evolution does not enumerate product states.

```text
typed Swift enum ── encode ──► unconstrained SQLite TEXT
                                      │
                                      │ read
                                      ▼
typed Swift enum ◄─ validate/decode ─ stored string
       │
       └─ unknown value ──► typed repository failure; no fabricated state

SQLite may enforce                 SQLite must not enforce
  keys and relationships             product-enum membership
  uniqueness and nullability         product-enum equality
  numeric/scalar bounds              cross-field product semantics
  UTF-8 byte limits                  product-state transitions
```

SQLite cannot alter an existing table's `CHECK` expression in place. Encoding
product states into DDL would therefore turn every added or renamed enum case
into a replacement-table migration: create a new table, copy all rows, preserve
foreign-key ordering, drop and rename tables, and recreate indexes and
triggers. The cost, write-lock duration, and recovery exposure would grow with
stored review history. Program-owned validation keeps product evolution in
typed code and tests and prevents ordinary state additions from requiring a
destructive table rebuild.

The schema proof seam is behavioral: structurally valid future enum strings
must be insertable through raw SQLite for every annotation enum column, while
repository hydration of those same values must fail typed decoding. Schema
inspection additionally proves that annotation DDL contains no product-enum
membership mechanism. Existing structural-constraint tests remain required so
this rule cannot be misread as removing SQLite integrity.

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
  └─ undemanded thread/message history
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
   revalidate session writability, located-source identity, message mutability, Markdown,
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
awaits its committed draft revision, then requests the saved-body replacement
with that expected revision. Focus loss sends the latest body immediately but
does not replace the saved body. Equality with the last acknowledged draft
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
resolve/reopen, continuity decision, output preparation,
output-candidate paging, output-selection begin/chunk/commit/cancel,
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

Output selection is logically unbounded but every operation frame remains
bounded. The current direct selection operation admits at most 64 explicit IDs
or 64 `allEligible` exclusions, so neither representation alone can express
every finite subset. The transport adapter therefore owns an ephemeral
`WorktreeAnnotationOutputSelectionAssembler` scoped by product-session
identity plus caller-generated transfer identity:

```text
browser viewer-local selection
  → selection.begin(transferId, mode = explicit | allEligible)
  → selection.chunk(transferId, ordinal, ordered unique IDs ≤ wire cap)
  → zero or more further ordered chunks
  → selection.commit(transferId)
       └─ assembler produces one complete immutable selection
            └─ Store canonical preparation/revalidation [UNCHANGED]

selection.cancel / disconnect / decode error
  └─ discard ephemeral assembly; no Store, SQLite, or Atom mutation
```

`begin` rejects a duplicate live transfer identity in the same product
session. Chunks must have contiguous ordinals, contain IDs unique across the
whole transfer, and remain within the existing per-frame ID cap. `commit`
requires at least one explicit ID for `explicit`; `allEligible` may carry
zero or more exclusions and remains an optimization rather than a totality
requirement. The assembler never queries eligibility or silently drops an ID.
Commit passes the complete ordered selection to the Store, which atomically
rechecks eligibility and canonical ordering while preparing the immutable
batch. Success, typed Store failure, cancellation, connection loss, or product
session teardown removes the transfer. No assembled selection survives restart
or enters SQLite or the projection Atom.

#### Shared metadata admission for lossless ordinary data

The existing annotation source asks
`BridgeProductWorktreeAnnotationProjectionPacker.events` to construct the whole
event array for one consumed snapshot before it awaits the first emission. The
array contains one `projection.state` event followed by every complete
per-thread batch. The Atom's `AsyncStream.bufferingNewest(1)` coalesces only
snapshots that have not yet been consumed; it cannot shrink either the packed
array or event sequence for the snapshot already being emitted. The shared
metadata producer admits at most 64 queued frames or
4 MiB and reserves one frame for a terminal event. When an ordinary enqueue
finds that queue full while one frame receipt is in flight, the existing
overflow path returns `closeRequired`. Treating that temporary condition as a
subscription failure can retire the annotation producer after SQLite already
committed a command, leaving the browser without the correlated outcome.

PR1 therefore adds one internal generic async metadata-data admission boundary.
The `BridgeProductProducerRegistry` remains the sole owner of encoded frame size,
frame/byte capacity, sequence assignment, and terminal reserve.
`BridgeProductSession` owns a separate cancellable FIFO of capacity admissions
for the active metadata producer lease and atomically rechecks and enqueues each
head when acknowledgement frees capacity. Pane presentation, pane
surface-selection, and File/Review subscription-data events—including both
annotation kinds—use this one lossless boundary. Protocol lifecycle frames and
explicit subscription/stream reset remain outside the FIFO because they own
termination and replay rather than ordinary data delivery.

```text
CURRENT — one large already-consumed annotation snapshot

Projection Atom --newest-one--> annotation source
                                   │ state + batch 1 … batch N
                                   ▼
                           shared metadata producer
                                   │ queue saturated + receipt in flight
                                   ▼
                              closeRequired
                                   │
                                   └─ source task retires; command outcome is stranded

TARGET — same wire frames, admitted at the consumer's drain rate

Projection Atom --newest-one--> annotation source
                                   │ incremental cursor
                                   │ await event 1, then event 2 …
                                   ▼
                    BridgeProductSession capacity FIFO
                                   │ exact admission token
                 ┌─────────────────┴──────────────────┐
                 │ capacity now                      │ saturated
                 ▼                                   ▼
      registry encode + append             retain one current event
                 │                         until exact capacity wake
                 │                                   │
worker observes frame ──► acknowledgement frees frame/bytes
                                             │ same actor turn
                                             ▼
                                  revalidate + encode + append
                                             │
                                             └─ resume exact source callback
```

The boundary is atomic wait-and-enqueue, never `waitUntilCapacity` followed by
a caller retry: another metadata lane could steal the released slot between
those two operations. The registry reports an internal capacity-unavailable
disposition without mutating the queue, resetting the stream, advancing stream
or subscription sequence, or terminating a subscription. The session records
the exact admission token and resumes its caller only after that candidate is
actually appended or a terminal lifecycle result is known. Encoding and
sequence assignment occur during each atomic admission attempt, so a waiting
semantic event never retains a stale wire sequence.

Each annotation source awaits one event before emitting the next. It therefore
uses a `WorktreeAnnotationProjectionEventCursor`, not the eager array API. The
cursor performs one bounded prepass to derive `expectedThreadCount`, then yields
`projection.state` and advances through sorted threads/messages with indices,
one current dynamically sized batch, and terminal-batch state. It measures the
complete candidate frame before yield and starts the next batch before the
128-KiB limit; it never splits a message. Cursor construction does not copy the
snapshot's complete message set into another event collection. The source thus
retains the consumed snapshot, cursor position, and at most one current packed
event while waiting; after the current full snapshot finishes, the Atom
supplies only the newest pending full snapshot.
The capacity FIFO is distinct from producer-observation pacing: pacing permits
one superseding waiter per producer lease, while File and Review annotation
events are independent lossless callers that must not cancel one another.

| Capacity-admission transition | Owner and result |
| --- | --- |
| candidate fits current frame and byte budget | registry appends under the session actor turn; caller resumes `enqueued` |
| candidate is individually invalid, oversized, stale, or sequence-exhausted | registry returns the existing immediate typed rejection; no waiter is installed |
| candidate is valid but ordinary-frame capacity is unavailable, or an older metadata-data token already waits | session appends one exact FIFO token; queue, sequences, and subscription state remain unchanged; no newer ordinary data bypasses the head |
| worker acknowledgement removes an in-flight frame | session drains FIFO heads under the same actor turn, revalidating lease, subscription, product admission, and foreground admission before each append |
| waiting task is cancelled | session removes that exact token and settles it as cancellation; a late wake cannot enqueue it |
| subscription is cancelled or reset, producer is stopped/replaced, foreground admission closes, or session is revoked | session removes every affected token and settles it terminally; pending-admission residue cannot survive producer teardown |
| a protocol lifecycle or explicit reset transition terminates/replaces the stream | session settles every incompatible token before awaiting producer drainage; reset remains observable terminal recovery and canonical subscription sources replay after reopen; ordinary data never initiates this reset |

FIFO applies to every ordinary metadata-data candidate on one metadata lease.
If any token waits, every newer ordinary data candidate joins the tail even when
its smaller frame would fit; this prevents byte-capacity starvation of a larger
head. An acknowledgement drains as many consecutive FIFO heads as the exact
frame/byte predicate permits before yielding actor authority. The ordinary-data
path never invokes queue replacement, so a pane or File/Review metadata update
cannot discard an admitted annotation frame. Protocol lifecycle and explicit
reset retain priority as terminal transitions: they may replace the stream only
while atomically invalidating pending data and causing canonical sources to
replay after reopen. This preserves per-source order and global metadata/
subscription sequence ordering without adding a second queue limit, timer,
poller, wire member, durable pending store, or physical transport.

The current two-event projection wire cannot identify a complete replacement.
`projection.state` carries metadata and a revision but no global completion
fact; each `message.batch` can prove only that one thread is complete. An
unbounded identity manifest would consume the same 128 KiB frame budget as a
large demanded projection, while a browser-computed membership digest would
make the synchronous projection store asynchronous solely to distrust the
strict native producer. A third global-terminal event is also unnecessary:
every non-empty durable thread already ends with exactly one
`isLastBatchForThread` batch. PR1 therefore makes one fixed-size wire-contract
change: every `projection.state` carries required `expectedThreadCount`.

```text
native projection revision R
  projection.state(R, metadata, expectedThreadCount=2)
  message.batch(R, A, isLastBatchForThread = false)
  message.batch(R, A, isLastBatchForThread = true)
  message.batch(R, B, isLastBatchForThread = true)

browser WorktreeAnnotationProjectionStore
  publishedComplete = revision R-1
  assembling = { revision R, metadata, expectedCount=2,
                 partial batches, completedThreadIds }
       │
       ├─ until A and B are complete ──► keep publishing R-1 unchanged
       └─ after A and B are complete ──► atomically publish metadata + A + B
```

`expectedThreadCount = 0` is a complete zero-thread projection, so that state
event may atomically publish an empty thread set without waiting for a batch.
Otherwise the projection store stages metadata and per-thread entries without
notifying React. It validates that each batch revision matches the assembling
revision, every message belongs to its context thread, ordinals and identities
are unique, and no thread receives data after its one terminal batch. When the
number of distinct threads with a terminal batch equals the expected count, the
revision is complete. The atomic replacement publishes staged metadata and
complete sorted threads together; it never mixes new metadata with old threads.

Projection assembly is keyed by the existing product subscription/producer
identity and revision. Ordered delivery means a state event starts or resets
the batch epoch for that producer; batches observed before a same-revision state
replay are never merged with batches after it. A producer or subscription
replacement invalidates the prior private assembly even when the semantic
revision is equal.

| Incoming state | Projection-store transition |
| --- | --- |
| revision less than the published-complete revision or active-assembly revision | stale; settle no presentation state and ignore its batches |
| revision equal to active private assembly R | authoritative resync replay: discard only private R batches, rebuild R metadata/expected count from this state, and accept only subsequently ordered R batches; retain the published snapshot |
| revision equal to published-complete R with no incomplete assembly | idempotent replay: settle command outcomes, do not clear/publish/remount, and ignore its subsequently replayed R batches |
| revision newer than both | supersede only any private assembly, retain the published snapshot, and start the new revision |

```text
published complete R-1
  → projection.state R
  → partial R batches
  → resync projection.state R
       └─ discard private partial R only
  → complete replayed R batches
  → exactly one atomic complete-R publish

No old-R/new-R or old-producer/new-producer batch set is mergeable.
```

Excess unique thread IDs, duplicate terminal batches, post-terminal data, or a
message-identity violation is a semantic assembly failure. The projection store
discards only its private assembly, retains the last complete renderable
snapshot, and publishes browser-local transport availability as `unavailable`
without changing the native `recoveryStatus` domain fact. A missing batch
without another protocol failure keeps assembly pending; no wall-clock timeout
fabricates corruption or completion.

`WorktreeAnnotationProjectionSnapshot` adds one required browser-local
discriminated field owned by `WorktreeAnnotationProjectionStore`:

```text
transportStatus =
  { kind: available }
  | {
      kind: unavailable
      failedRevision: non-negative integer
      failureClass:
        excessThreadCount
        | duplicateTerminal
        | postTerminalBatch
        | messageIdentityViolation
      recovery:
        requested | awaitingReplay | blocked
    }
```

This field is never encoded on the product wire, persisted, or copied into
`WorktreeAnnotationProjectionAtom.recoveryStatus`. The initial empty browser
snapshot and every complete atomic publish use `available`. Semantic assembly
failure changes only `transportStatus` and private assembly: the previously
published metadata and complete `threads` remain byte-for-byte renderable.
Worker ready changes recovery from `requested` to `awaitingReplay`; degraded,
stale, repeated same-revision failure, or reopen failure changes it to
`blocked`. Only a complete accepted publish returns to `available`; receipt
of state, a ready RPC result, or partial replay cannot clear it.

File/Review consumers keep the last complete cards, overlay, editor DOM, focus,
and local unsent text visible with an annotation-unavailable status. They allow
read/inspection and local typing but disable new admission, Save, Reply,
Resolve/Reopen, output preparation, and other mutations that require a fresh
canonical projection. The draft scheduler retains pending intent without
releasing edit ownership and resumes its ordinary flush path only after
`transportStatus.available`; it does not invent a second persistence path.

The main thread currently has no annotation subscription lifecycle API, while
the comm worker's `BridgeCommWorkerProductController` privately owns the exact
File and Review annotation subscription objects and their cancel/reopen path.
PR1 adds one internal worker RPC command and no native product method:

```text
WorktreeAnnotationProjectionStore detects semantic assembly failure
  → retain published snapshot + transport unavailable
  → WorktreeAnnotationSurfaceClient sends once:
       annotationProjectionResync {
         surface,
         subscriptionId,
         revision,
         failureClass:
           excessThreadCount
           | duplicateTerminal
           | postTerminalBatch
           | messageIdentityViolation
       }
  → comm-worker strict command decoder / surface epoch admission
  → BridgeCommWorkerProductController validates exact active
       surface + subscriptionId
  → create controller-local resync task(requestId, generation, surface,
       exact old subscription object + ID)
  → retire old local slot before existing subscription.cancel()
  → cancel settles while task generation remains current
  → existing productTransport.subscribe(file.annotations | review.annotations)
       returns provisional replacement handle
  → replacement event consumer awaits first validated projection.state
  → promote exact replacement + forward state + resolve replay-start barrier
  → worker publishes ready for requestId
  → existing annotationProjection route continues replay batches
  → complete atomic browser publish clears transport unavailable
```

The command is main-to-comm-worker only. It does not invoke `source.refresh`,
`fileDisplayResync`, Store/repository/source evaluation, a new native scheme
method, or App IPC. The worker never validates or assembles semantic messages;
it only exercises the subscription lifecycle it already owns.

The surface client records at most one resync request for a failing semantic
revision. A second failure at that same revision stays unavailable and awaits
external subscription replacement or a newer revision; it cannot loop
cancel/reopen. A complete publish clears the gate, and observing a newer
semantic revision advances it so that revision may request recovery once. The
failed subscription identity is barred from further assembly immediately, so
queued old events cannot mix with the reopened producer.

The controller exposes one internal method that returns a task rather than an
unfenced promise:

```text
AnnotationProjectionResyncTask
  requestId
  controllerResyncGeneration
  surface
  oldSubscription object
  oldSubscriptionId
  completion: Promise<first validated replay state>
  invalidate(reason: timeout | concurrentReplacement | commandRejected)
```

`invalidate` is idempotent; when the task is still current it increments the
controller resync generation before settling the task as failed. That generation
change is the fence every outstanding continuation observes.

The worker validates the request against the exact currently installed
subscription object and ID. A stale ID, wrong surface, or second concurrent
request produces one request-correlated degraded result and performs no
cancellation. On admission the controller increments its resync generation,
creates the task, and retires the exact local slot before awaiting cancellation,
so its old consumer ignores queued events.

`subscription.cancel()` can wait indefinitely for native
`subscription.cancelled`. The runtime command handler therefore owns the
deadline and must call `task.invalidate(timeout)` before it returns degraded;
the generic promise timeout alone is insufficient because it does not abort the
underlying continuation. Cancellation rejection likewise invalidates the task
and returns exactly one degraded result. Cancellation timeout/failure never
starts a replacement. Late cancel resolution observes the invalid generation
and cannot subscribe, assign a slot, forward an event, or publish another
result.

After valid cancellation, `productTransport.subscribe` returns a handle
synchronously while native admission remains private and asynchronous. The
task treats that handle as provisional, not active. Its private consumer must
receive a decoded `projection.state` as the first replay event while request
ID, generation, surface, provisional object, and runtime's current controller
identity still match. Only then does it promote the replacement to the active
slot, forward that state through the existing annotation event callback, and
resolve its replay-start barrier. Stream rejection, terminal end, or a
non-state first event fails before the barrier, invalidates the task, ensures no
active slot is fabricated, and returns one degraded result.

Every continuation after cancel, subscribe, iterator read, state forwarding,
and barrier resolution checks task generation plus old/provisional object
identity. A newer exact-ID resync task or runtime controller replacement makes
the older task stale; the runtime handler invalidates it before reporting
degraded. There is no broad callable controller-disposal mechanism in current
production source and this design adds none. Hard worker termination ends the
execution context and every pending task. Main-client disposal rejects its own
pending RPC and ignores later worker messages; it does not attempt to dispose a
controller across the MessagePort.

The surface client correlates the worker's existing ready/degraded health result
by request ID. Worker ready means only that the exact replacement produced and
forwarded its first valid replay state. It changes `transportStatus.recovery`
from `requested` to `awaitingReplay` only if that same unavailable request is
still current. If the forwarded state already completed a zero-thread
projection and restored `available`, a later ready result is ignored and
cannot regress it. Only complete main-thread expected-count assembly restores
availability. Degraded/stale or a disposed main client retains the last complete
snapshot as unavailable and does not fall back to a domain command.

```text
READY(lastComplete)
  └─ semantic failure at R
       └─► UNAVAILABLE_REQUESTED(R, failedSubscriptionId)
              ├─ first validated replay state + worker ready
              │      └─► UNAVAILABLE_AWAITING_REPLAY(R)
              ├─ cancel/open/barrier timeout or failure
              │      └─► UNAVAILABLE_BLOCKED(R)
              ├─ worker degraded/stale ──► UNAVAILABLE_BLOCKED(R)
              ├─ repeated failure R ─────► UNAVAILABLE_BLOCKED(R)
              ├─ newer state R+1 ────────► UNAVAILABLE_AWAITING_REPLAY(R+1)
              └─ complete publish ≥ R ───► READY(newComplete)

main client disposed ──► pending RPC rejected; later messages ignored
hard worker termination ──► execution context and resync task cease
```

The native product subscription route, pane/session identity, request
correlation, strict decoding, wire frames, and sequence contract remain
unchanged. Native backpressure gains the generic session-owned atomic
capacity-wait admission described above for every ordinary metadata-data frame;
only protocol lifecycle and explicit reset retain the existing terminal/reset
path. The internal
main-to-worker command union and worker subscription-lifecycle handler also
grow for semantic-assembly recovery. There is no annotation App IPC operation.

### TypeScript contract discipline

BridgeWeb contracts use required fields by default. A field is nullable or
optional only when absence is a real domain value, and omission is distinct
from `null` only when the wire contract assigns those states different meaning.
The message contract therefore carries required `savedBody`, `draft`, and
`status` fields plus required `createdAt`: `savedBody` and `draft` admit explicit
absence, `status` is always `editable | locked`, and `createdAt` is the durable
message-creation time. BridgeWeb renders `createdAt` relatively in the timeline
and latest-message summary. It never substitutes session time or message
`updatedAt`; draft autosaves and later edits therefore cannot make an existing
message appear newly authored. The contract does not add a content-state
discriminator that recreates the rejected draft/saved/saved-with-draft enum.

Genuine variants use exhaustive discriminated unions, including File versus
Review source evidence, current-file versus diff-side anchors, output-effect
results, attempt states, and typed command outcomes. Variant-only fields live
on the matching union member rather than becoming optional properties on one
wide interface. Strict runtime schemas are the source of the corresponding
TypeScript types; handlers switch exhaustively on the discriminant and do not
recover precision with `any`, unchecked assertions, boolean bags, or
stringly-typed fallback states.

```text
good variant contract                    rejected convenience shape

{ kind: "succeeded" }                   { succeeded?: boolean
| { kind: "cancelled" }                   cancelled?: boolean
| { kind: "failed"; code }                 errorCode?: string }

message content is different:
  savedBody: string | null
  draft: Draft | null
  status: "editable" | "locked"

The valid content combinations are checked directly; no duplicate `kind`
turns those combinations into another lifecycle enum.
```

Contract tests prove every admitted union member, reject unknown discriminants
and invalid message-content combinations, and prove that a required field
cannot disappear merely because one caller does not use it.

Selection-transfer contracts are an exhaustive `begin | chunk | commit | cancel`
union with required transfer identity and contiguous chunk ordinal where
applicable. Candidate pages use a typed cursor/result union. Output-effect and
direct-command result unions contain no synchronous unknown member; durable
unknown remains only in projected recovered attempt/history state.

The internal `annotationProjectionResync` worker command is a separate strict
union member with required surface, active annotation subscription ID,
non-negative semantic revision, and the closed assembly-failure class above.
RPC surface admission, request-ID replay protection, and ready/degraded
correlation stay shared with existing worker commands. It is not projected into
the native product-control registry.

The runtime handler receives the controller task's `completion` and
`invalidate` interface. Its timeout branch calls `invalidate` before emitting
degraded; its success branch emits ready only after the first-state barrier;
its rejection branch emits degraded once. The generic unabortable action-timeout
helper is not used for this command. A command-specific
`runAnnotationProjectionResyncWithDeadline` owns the timer and invalidation
ordering.

Discovery returns every session for the current worktree lineage, including
applicable, uncertain, detached, and completed sessions, and never chooses by
recency. When no living applicable session and no relevant uncertain candidate
exists, the first non-whitespace draft command atomically rechecks discovery,
creates the session, and creates its root message draft in one repository
transaction; there is no separate session-create ceremony. When exactly one
living applicable session is eligible, presentation offers direct continuation.
When several are eligible, the reviewer must select one before the Store admits
a thread. Any relevant uncertain candidate routes through the reviewer decision
before the zero-session rule can run. Detached and completed sessions remain
distinguishable durable states, but PR1 exposes no persistent session
management, finish/reopen, or history chrome. Only the bounded choice blocking
the current inline intent appears.

```text
first annotation intent
  ├─ relevant uncertain candidate
  │    └─ Continue · Leave Paused · Start Another before admission
  ├─ zero living applicable sessions and no uncertain candidate
  │    └─ first non-whitespace edit: create session + root draft
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
confirmation, and filesystem errors. Destination choice returns selected or
cancelled before an output attempt is prepared. Once exact bytes are prepared,
the clipboard/file effect result is the closed union `succeeded | failed`.
Synchronous `unknown` is deleted from the App effect, output coordinator,
transport outcome, and browser direct-command result; a live caller cannot
declare uncertainty while the durable attempt remains merely prepared.

Only startup recovery may convert a durable attempt still found in `prepared`
into `unknown`, atomically lock its included messages, and retain exact bytes.
That path represents a crash or lost response whose effect cannot be proven.
It never automatically replays the effect. The App effect does not inspect or
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

No PR1 placement, output, resolve, pane, comparison, or visible command crosses
lifecycle. Every combination remains representable, including completed +
uncertain and completed + detached, without projecting session-management UI.
The follow-up session-management surface may own explicit living/completed
transitions.
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

Messages have structural content state plus one binary durable status:

```text
empty composer
  ├─ focus loss / Escape / abandoned selection ──► removed, no durable row
  └─ first non-whitespace edit ──► durable never-saved draft
                                ├─ focus loss ──► flush, remain visible
                                ├─ Escape/new range ──► flush, collapse
                                ├─ Revert ──► removed
                                └─ Save/Command+Enter
                                      └─► savedBody present + draft absent

savedBody present + draft absent + EDITABLE
  └─ edit ──► savedBody present + draft present + EDITABLE
                ├─ Revert ──► delete draft; show savedBody
                └─ Save ────► replace savedBody; delete draft

savedBody present + draft absent + EDITABLE
  └─ prepare output ──► writes blocked by prepared membership
         ├─ known failure + cancel ──► EDITABLE
         ├─ success ────────────────► LOCKED
         └─ startup recovers prepared as unknown ──► LOCKED
                                         └─ new reply only
```

`editable | locked` is persisted on the message identity. There is no
`provisional` message status: an output attempt's prepared membership is the
short-lived transaction guard. Output admission requires saved content, no
draft, `editable` status, and no prepared membership. Successful output or
startup recovery of a prepared attempt as unknown permanently changes the
included message to `locked`.

## Draft scheduling and convergence

Each active message edit has one scheduler owned by BridgeWeb and driven by an
injected monotonic clock. Native code persists every accepted command
immediately; it does not add a second debounce or max-wait timer.

```text
BridgeWeb edit scheduler
  ├─ new message: first non-whitespace edit ──► send immediately
  ├─ saved message: first changed edit, including empty ──► send immediately
  └─ later changed content
       ├─ restart 1-second debounce
       ├─ retain 5-second maximum-wait deadline
       └─ keep latest body in browser pending intent

whichever occurs first
  ├─ 1 second without another edit
  ├─ 5 seconds since the first unflushed edit
  ├─ focus loss
  ├─ Escape or admission of another range
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

Only one active edit token may mutate a message at a time. The Store keeps an
in-memory map from each active token to the admitting product-session
generation; the optional token persisted beside the draft is a compare fence,
not a time lease. Another view can read the draft and thread, but a stale token
cannot overwrite newer text.

Normal pane closure first requests the immediate focus-loss flush and then uses
one matching-token transaction to clear `active_edit_token`. Product-session
disconnect invalidates that generation in the Store even when browser teardown
never sent release. On acquire, one repository transaction reloads the draft:
it returns the caller's still-active token, rejects a token owned by another
live product session, or replaces a token whose owner generation is absent or
invalidated while preserving the last committed body and advancing
`draft_revision`. Store boot begins with no live product-session generations,
so every persisted token is reclaimable; no wall-clock timeout or cleanup poll
is involved. A delayed command must match both the replacement token and the
advanced revision, so an orphaned writer cannot resume after reclamation. A
hard crash therefore recovers the latest completed native commit and the first
new editor can use it.

## Pierre 1.2.10 selection and inline presentation

PR1 stays pinned to `@pierre/diffs` 1.2.10. Pierre owns source selection,
gutter triggers, diff side, annotation slots, range highlighting, layout, and
scrolling. It does not own threads, messages, drafts, persistence, resolution,
continuity, placement meaning, or output history.

`@pierre/diffs` 1.3.5 is a stable follow-up upgrade, not PR1 scope. Pierre
1.2.10 already requires controlled selection to be fed back through the React
`selectedLines` and `onSelectedLinesChange` props; `controlledSelection` in
`CodeViewOptions` selects the interaction mode but does not own React feedback
or paint. PR1 therefore wires those existing 1.2.10 props now. The later
dependency upgrade must preserve this ownership rather than introducing it.

```text
Pierre CodeView 1.2.10
  onLineSelectionEnd
       │ range + side
       ▼
BridgeWeb controlled selectedLines state
       │ React CodeView selectedLines feedback
       ├─ pending range/new composer selection
       └─ one active saved thread's complete stored range
          no selection presentation performs a durable mutation

Pierre endpoint/gutter utility click
  onGutterUtilityClick
       │ selected line/range + side
       ▼
BridgeWeb Pierre annotation adapter
  maps repository-relative evidence and admitted source identity
       │ typed create/continue-draft intent after first non-whitespace edit
       ▼
native Store → repository commit → projection Atom
       │
       ▼
adapter builds LineAnnotation / DiffLineAnnotation values
       │ renderAnnotation portal
       ▼
shared inline thread shell in the main CodeView
  left avatar timeline │ rounded body surface │ bottom-right icon rail
```

File mode uses `LineAnnotation<T>`; diff mode uses
`DiffLineAnnotation<T>` with its additions/deletions side. The adapter enables
line selection and gutter utility callbacks. `onLineSelectionEnd` updates only
pending controlled-selection feedback; saved-thread focus and overlay activity
reuse the same controlled `selectedLines` owner. `onGutterUtilityClick` is the
sole composer admission path. Selecting another range, clicking outside, or
Escape clears a pending empty selection. Durable located threads render through
`renderAnnotation`; Pierre's `setSelectedLines`/`scrollTo` handle operations
remain available where navigation requires them.

Pierre line slots are used only when a trustworthy current location exists.
`exact` and `relocated` located threads render through those slots. `outdated`
and `unavailable` state remains durable and output-visible, but PR1 creates no
global degraded-thread region and never fabricates a line slot. A later sidebar
or navigation slice may expose durable threads that have no trustworthy inline
placement.

```text
main File / Review surface
  Pierre source slots
    ├─ exact located thread
    └─ relocated located thread

  no global review panel · no file/session comments · no degraded-thread panel
```

Review worker/materialization updates must merge the current annotation
projection into each item. They may update content or syntax state, but must
not overwrite `item.annotations`; `CodeViewHandle.updateItem` receives the
merged item. Shared thread/editor components remain Bridge-owned React views
rendered through Pierre's portal slots.

Pierre groups annotations by physical source position. Two independently
resolvable threads at the same coordinate therefore render as separate
Bridge-owned compact wrappers inside one Pierre annotation row. Neither thread
can turn that row into a chronology container. Wrapper lookup, active state,
overlay state, invoker return, editor identity, and resolution commands are all
keyed by stable `threadId` and `messageId`; portal-array position and
source-row identity are never state keys.

```text
Pierre physical annotation row at file.ts:84
  ├─ threadId A compact wrapper ── M1 or M-summary + M-last
  └─ threadId B compact wrapper ── M1 or M-summary + M-last

Pierre code canvas
  ├─ inactive A/B ──► no saved-range paint; endpoint cards remain
  └─ BridgeWeb activeThreadId ──► exactly that stored range in selectedLines

viewer overlay portal (outside Pierre row measurement)
  └─ at most one open thread per viewer, keyed by threadId
       └─ keeps that thread active and its selectedLines paint present

resolution for A / B
  └─ durable Store command by exact threadId
```

Pierre remains the only code-canvas range-paint owner. The viewer interaction
controller holds at most one saved-comment `activeThreadId`; the File/Review
adapter maps that thread's complete stored range into Pierre's existing
controlled `selectedLines` value. Focusing the compact surface or one of its
controls activates it without opening the overlay. An open overlay retains that
same active identity while focus moves inside it. Activating another comment
replaces `selectedLines` with the new stored range. Clearing comment-system
focus/activity clears saved-comment `selectedLines`. Inactive threads retain
their endpoint-anchored cards and no range paint. Pending drag/new-composer
selection keeps its existing selection owner and is never conflated with saved
comment activation. The MapPin/Show-source-range action is removed, and
BridgeWeb paints no competing absolute overlay over code.

```text
saved-comment activation path

compact surface/control focus
  → InteractionController.activateSavedThread(threadId)
  → resolve exact/relocated stored item + range from complete projection
  → pierreRangePresentation = savedThread(threadId, itemId, range)
  → File/Review adapter derives controlled selectedLines
  → Pierre paints exactly that complete range

open overlay descendants
  → overlay threadId retains savedThread presentation

focus another compact comment
  → replace savedThread presentation and selectedLines

leave comment system with no overlay
  → pierreRangePresentation = none
  → selectedLines = null
```

### Compact inline surface and floating chronology

New-root authoring remains inline at the admitted range. A saved thread always
uses one compact BridgeWeb-owned surface composed from owned shadcn primitives.
Its visible boundary owns the background, border, radius, focus treatment, and
body/rail grid; the Textarea introduces no second card or radius.

```text
InlineCommentSurface (inside Pierre normal flow)
  ├─ Avatar timeline node + metadata row
  │    └─ author/time/status · Include/Exclude · Expand · More
  └─ one rounded content surface
       ├─ top-aligned content-sized body
       │    ├─ one message  ──► M1
       │    └─ two or more ──► M-summary + M-last
       └─ independent bottom-right command column
            └─ exact icon-only core commands

WorktreeAnnotationThreadOverlay (portal above code)
  ├─ anchored to the exact compact inline invoker
  ├─ flat M1…Mn chronology in bounded ScrollArea
  ├─ message-level Edit/Reply controls
  └─ integrated reply/edit composer

Opening the overlay changes neither InlineCommentSurface content nor Pierre row
height. The normal-flow compact anchor remains mounted underneath.
```

The body grid uses top alignment and content-driven height. The command column
is independently positioned within the same surface and cannot establish the
body's minimum height. The avatar stays on the left; message time belongs in
its metadata/timeline row. There is no header card, footer card, nested
Textarea card, square field inside an oval shell, or command-rail background.

Draft uses visible `Draft` text plus a warning-semantic cue and never relies on
color alone. Active range tint uses only `comment-active`; keyboard focus uses
the standard focus-visible ring. Components consume registered `comment-*`
Tailwind utilities and owned shadcn primitives. They do not edit
`bridge-app.css`, add raw colors, or call `var(--comment-*)` where a utility
exists. Exact radius, spacing, avatar overlap, and token derivations remain
visual tuning constrained by this anatomy.

M-summary is a pure deterministic projection, not stored or model-generated
content. It derives message count, latest activity, resolution, and any hidden
Draft, placement, inclusion, or lock fact needed to avoid a false compact
representation. M-last is a bounded projection of the latest actual message.
The summary has no message identity, Markdown source, reply target, Store
command, selection membership, or output eligibility.

### Viewer-level transient interaction owner

Each File or Review viewer constructs one
`WorktreeAnnotationInteractionController` in the shared annotation provider
above every Pierre portal. It owns only viewer-local interaction state. The
Store owns durable decisions and mutations; the projection store owns only
complete-revision assembly.

```text
WorktreeAnnotationInteractionController (one per viewer)
  ├─ pierreRangePresentation
  │    ├─ { kind: none }
  │    ├─ { kind: pending, itemId, range, editToken? }
  │    └─ { kind: savedThread, threadId, itemId, range }
  ├─ activeThreadId derived from savedThread presentation or open overlay
  ├─ threadOverlay
  │    ├─ closed
  │    └─ open {
  │         threadId,
  │         anchor/invoker identity,
  │         editor:
  │           none
  │           | { kind: reply, editToken }
  │           | { kind: message, messageId, editToken }
  │       }
  ├─ pending inline admission
  │    ├─ several applicable sessions → anchored session-choice Popover
  │    └─ uncertain continuity → anchored decision Popover
  ├─ output selection
  │    ├─ { kind: explicit; messageIds }
  │    └─ { kind: allEligible; excludedMessageIds }
  ├─ AnnotationOutputSelectionSurface
  │    ├─ entered from compact timeline More
  │    ├─ or conditional output-only File/Review rail Handoff trigger
  │    ├─ on-demand bounded eligible-candidate summaries
  │    └─ Select all · Clear · Copy selected · Export selected
  └─ output-history surface
       ├─ inspect successful events and unknown attempts
       └─ explicitly reproduce persisted exact bytes

Never persisted or projected
  open overlay/Popover/menu · anchor DOM reference · active editor identity
  Pierre range presentation · pending choice · selected output IDs
```

The Pierre adapter derives its single controlled `selectedLines` value from
`pierreRangePresentation`. Starting a pending drag/new-composer selection
replaces saved-thread presentation; focusing a compact saved thread replaces
pending presentation; clearing either becomes `none`. This discriminated
union prevents pending admission feedback and saved-comment activity from
becoming competing selection writers.

Expand, Edit, and Reply are the only inline actions that open the chronology
overlay. Focus entering a compact surface or its controls instead sets that
thread active and projects its complete stored range through `selectedLines`;
it never opens the overlay. The open overlay keeps its thread active while focus
moves among its descendants. Focus/activity moving to another compact thread
changes the single active identity and painted range; leaving the comment system
with no overlay open clears both. The controller records the exact overlay
invoker so closing can return focus to it. Ordinary projection revisions and
Pierre portal rerenders preserve open/editor state by stable thread/message
identity. If the replacement projection removes that durable identity, the
controller flushes any active draft through its current edit token, closes the
overlay, clears saved-range paint, and returns focus to the nearest surviving
compact-thread control; it does not retarget the editor to another message.

The default output selection is an empty `explicit` member. Include/Exclude in
the compact timeline or overlay message row mutates that viewer-local set.
`Select all` switches to `allEligible`; exclusions remain explicit without
loading every cold message into the Atom. Either browser representation may
contain an arbitrary finite number of IDs because invocation transfers it
through the chunk assembler rather than one capped operation frame.

The Store publishes only eligible counts, including
`eligibleWithoutInlinePlacementCount`, and owns an on-demand cursor query
scoped to the active session and expected committed revision for bounded
eligible-candidate summaries. Each summary exposes only message/thread
identity, flat message ordinal, path/original-or-current location label,
placement, saved authored time, selection/lock facts, and a bounded derived
plain-text excerpt needed to distinguish multiple eligible messages at the same
path or thread. It never carries the full Markdown body, navigation identity, or
edit/reply controls and is not a general comment reader. The output surface
pages that query while open and keeps its viewer-local selection across page
eviction. `allEligible` remains an
optimization; the Store resolves it and any exclusions against canonical
repository state during preparation. A stale or newly ineligible member causes
typed preparation failure and a projection refresh rather than silent omission.
Known effect failure, file-panel cancellation, transfer cancellation, or
preparation failure preserves the browser selection; successful Copy/Export
clears it because every included message is then locked. Closing a viewer may
discard selection because it is navigation state, not human-authored work.

The range endpoint or gutter `+` remains the admission trigger. When discovery
finds several applicable sessions, its anchored shadcn `Popover` lists only
those bounded choices; selecting one resumes the original create intent and
Escape/click-away cancels without mutation. When the selected session is
uncertain, the same transient owner presents `Continue`, `Leave Paused`, and
`Start Another`; only Continue persists the displayed continuity evidence,
Leave Paused cancels the intent, and Start Another records only the transient
admission choice. Its first non-whitespace edit atomically creates the new
session and root draft. No chooser remains after that blocked intent resolves.

The compact timeline's one `More` entry opens the shared output-selection
surface; no Handoff or history glyph is added to the core right column. When
`eligibleWithoutInlinePlacementCount > 0`, one conditional icon-only
`Handoff` trigger appears in the existing File/Review rail. It opens that same
bounded output-only surface and on-demand candidate query, making a first
Copy/Export reachable even when every eligible thread is outdated or
unavailable and therefore has no Pierre slot. It does not navigate, edit,
reply, resolve, manage sessions, or render general comments. Closing returns
focus to the exact timeline or rail invoker. Candidate-query loading keeps the
surface and current selection visible; failure shows a retryable output-query
error and never substitutes an empty eligible set.

Locked overlay messages may expose Inspect Output through their message-level
More actions. Separately, a conditional icon-only `Output history` trigger may
appear in the existing File/Review rail while history exists. Its bounded
history surface inspects output records only and never lists or navigates
comments. An unknown attempt created by startup recovery makes that trigger
announce `Output needs review` and offers explicit exact-byte repetition
without an automatic effect or recovery-choice modal.

```text
inline timeline More ───────────────┐
conditional rail Handoff ──────────┤
                                   ▼
bounded output-selection surface
  ├─ on-demand Store candidate pages
  └─ viewer-local arbitrary finite selection
          │ begin + bounded chunks + commit
          ▼
transport selection assembler
          │ one complete immutable selection
          ▼
Store prepares canonical batch ──► App Copy/Export effect

message More / conditional toolbar History
  └─► Store history query ──► exact-byte repetition
```

The controller restores focus to the exact invoking `+`, command-rail button,
timeline action, or toolbar trigger when a transient surface closes. Session
and continuity choices, output selection, Copy/Export, history inspection, and unknown
repetition therefore have visible presentation-to-Store paths in both viewers
without restoring `WorktreeAnnotationSessionChrome`.

### shadcn/Base UI composition and command contract

The feature owns comment anatomy and composes the repository's owned shadcn
primitives. It does not recreate their interaction behavior with route-local
elements.

| Feature component | Owned shadcn/Base UI building blocks | Responsibility |
| --- | --- | --- |
| `InlineCommentSurface` | semantic container plus comment-role utilities | one rounded shell, left timeline/body layout, active/draft/resolved variants |
| `InlineCommentCompactThread` | render-derived message-count branch | exact M1 versus M-summary + M-last normal-flow projection |
| `InlineCommentTimeline` | `Checkbox`, `Button`, `DropdownMenu`, `Tooltip` | status, Include/Exclude, Expand immediately before More; never Edit/Reply/Resolve |
| `InlineCommentMessage` | feature Markdown body, `Button`, `Tooltip` | authored body, author/time, optional-draft and editable/locked facts |
| `InlineCommentComposer` | `Textarea`, `Button`, `Tooltip` | transparent Markdown entry in the owning shell, Revert/Save, draft errors and focus |
| `InlineCommentCommandRail` | `Button`, `Tooltip` | exact context-specific core commands, icon-only, stacked bottom-right without becoming a second card |
| `WorktreeAnnotationThreadOverlay` | owned `Popover`, `PopoverTrigger`, `PopoverContent`, `ScrollArea`, `Separator` | non-modal anchored portal, bounded chronology, message controls, one thread Resolve/Reopen, and integrated authoring |
| `AnnotationSessionDecisionPopover` | owned `Popover`, `Button` | bounded several-session or uncertain-continuity choice anchored to the blocked inline intent |
| `AnnotationOutputSelectionSurface` | owned `Dialog`, `ScrollArea`, `Checkbox`, `Button` | bounded on-demand candidate pages, arbitrary finite viewer selection, Select all/Clear, and Copy/Export; never comment navigation or session management |
| conditional rail `Handoff` | `Button`, `Tooltip` | output-only entrance when eligible messages lack inline placement; opens the same selection surface |
| `AnnotationOutputHistoryDialog` | owned shadcn `Dialog` added under `components/ui`, `Button` | inspect bounded event/attempt summaries and explicitly reproduce exact bytes; never a thread fallback panel |
| author identity | owned shadcn `Avatar` with `AvatarFallback` | compact human identity; no remote image source is invented |
| Copy confirmation | owned Sonner `Toaster` | concise status after the native clipboard effect succeeds |

The repository's existing owned Popover is backed by Base UI and already owns
portal positioning, outside-press/Escape dismissal, and focus restoration.
The thread overlay uses it as a controlled non-modal surface. Base UI 1.6.0 has
no ScrollArea primitive, so the owned shadcn-style `ScrollArea` under
`components/ui` is a feature-neutral semantic container using native bounded
overflow; it owns no overlay state or comment policy. Closed Popover content is
unmounted and absent from Tab/accessibility traversal. The overlay portal is
outside Pierre normal flow, so its bounded height and inner scrolling never
invoke Pierre measurement or a CodeView scroll API.

| Surface | Exact core controls | Presentation |
| --- | --- | --- |
| M1 compact right column | Edit when editable; Reply; Resolve/Reopen | `Pencil`; `Reply`; `Check`/stateful `RotateCcw` |
| multi compact right column | Edit M-last when editable; Reply; Resolve/Reopen | same canonical identities as M1 |
| composer right column | Revert; Save | `Undo2` quiet; `Save` primary |
| timeline row | status; Include/Exclude; Expand; More | Expand immediately before `Ellipsis`; never Edit/Reply/Resolve |
| overlay message right column | Edit when editable; Reply | canonical `Pencil` and `Reply` |
| overlay thread level | Resolve/Reopen once | same stateful thread command as compact surface |

Every core control is an owned shadcn `Button` with one canonical Lucide
identity, the compact component scale, one optical-size rule, tooltip, and
accessible name. It has no visible text label. Save alone uses primary
treatment. Visible timeline status and Draft text carry state meaning without
depending on tooltips. The inline location/MapPin command does not exist.

### Current components become one comment system

The current source has the wrong presentation boundary: session chrome owns a
general Comments popover and the thread is assembled as header, divided message
cards, nested textarea, and footer. The target keeps the durable client/store
seams but replaces that visible anatomy.

```text
CURRENT UI                                      TARGET PR1 UI

WorktreeAnnotationSessionChrome                removed from rendered composition
  ├─ Comments popover                    ──X─► no global Comments panel
  ├─ session chooser                     ──X─► no persistent session chrome
  ├─ Finish/Reopen + warning card        ──X─► no PR1 session-management UI
  └─ output controls                      ──► comment-scoped handoff affordance

WorktreeAnnotationConversationFrame            InlineCommentSurface
  └─ bordered standalone card            ──► one strongly rounded shared shell

WorktreeAnnotationThread                       InlineCommentThread
  ├─ header + location + Resolve          ──► left timeline + rounded body
  ├─ always maps every message             ──► 1: M1; 2+: M-summary + M-last
  ├─ divided message cards                ──X─► no inline chronology
  └─ footer Reply                         ──► bottom-right core command

WorktreeAnnotationNewMessageComposer           InlineCommentComposer
  ├─ nested Textarea card                 ──X─► borderless Markdown canvas
  └─ Cancel/Save footer                   ──► bottom-right icon rail; Save is primary

controlled Collapsible                          WorktreeAnnotationThreadOverlay
  ├─ M1…Mn in Pierre row                  ──X─► portal above code
  └─ height remeasurement                 ──X─► bounded ScrollArea; row unchanged
```

The names on the target side express responsibilities, not a mandate to create
one file per box. Reuse or rename the existing components when their ownership
matches; delete presentation structure rather than wrapping it in another
layer.

```text
InlineCommentSurface
  owns: shared rounded shell, active/draft/resolved visual variants
  consumes: comment tokens and shadcn primitives
  contains
    ├─ InlineCommentCompactThread
    │    owns: message-count branch only
    │    ├─ exactly 1 ──► InlineCommentMessage(M1)
    │    └─ 2 or more ──► InlineCommentThreadSummary + M-last projection
    ├─ InlineCommentTimeline
    │    owns: status · Include/Exclude · Expand · More
    └─ InlineCommentCommandRail
         ├─ M1/multi: Edit · Reply · Resolve/Reopen
         └─ draft: Revert · Save, with Save as the only primary action

WorktreeAnnotationThreadOverlay
  owns: anchored open/close boundary and bounded chronology presentation
  contains
    ├─ ScrollArea
    │    └─ InlineCommentMessage(M1…Mn), flat and ordinal-sorted
    ├─ overlay message rails: Edit when editable · Reply
    ├─ one thread-level Resolve/Reopen
    └─ active InlineCommentComposer for reply or edit

InlineCommentTimeline
  owns: left avatar node plus author/time/status row for each visible message or
        synthetic summary

message time flow
  annotation_message.created_at
    ──► WorktreeAnnotationMessage.createdAt
    ──► complete-message wire `createdAt`
    ──► BridgeWeb relative-time presentation

  annotation_message.updated_at ──X─► never displayed as authored time

Pierre adapter
  owns: selected range, endpoint/gutter +, inline portal placement
  never owns: message state, comment shell, commands, or persistence
```

### Inline and overlay interaction states

```text
PENDING RANGE
  Pierre highlight + endpoint +
  no InlineCommentSurface yet
        │ click +
        ▼
EMPTY COMPOSER
  full shell · left avatar timeline · rounded body · borderless empty canvas
        ├─ focus loss / Escape ──► removed
        └─ first non-whitespace edit
                    ▼
DURABLE DRAFT
  same shell · Draft text + warning cue · Save primary
        ├─ focus loss ──► remains expanded
        ├─ Escape/new range ──► collapsed draft, same shell
        └─ Save ──► SAVED ONE-MESSAGE THREAD
                         same shell · render M1 directly

SAVED THREAD IN PIERRE NORMAL FLOW
  one message  ──► M1
  two or more ──► M-summary + M-last
        │
        ├─ focus surface/control
        │     └─► activeThreadId = this thread
        │          selectedLines = complete stored range
        │          overlay stays closed
        └─ Expand / Edit / Reply
                    ▼
OVERLAY OPEN, NO ACTIVE EDITOR
  compact inline anchor remains unchanged
  bounded M1…Mn chronology floats above code
  activeThreadId and selectedLines stay on this thread
        ├─ Edit message ──► OVERLAY EDITING(messageId, editToken)
        ├─ Reply ─────────► OVERLAY EDITING(reply, editToken)
        └─ Escape / outside / Expand toggle
                    └─► close overlay; return focus to exact invoker

OVERLAY EDITING
  stable editor identity = threadId + messageId/reply edit token
        ├─ Save / Revert ──► OVERLAY OPEN, NO ACTIVE EDITOR
        ├─ Escape ─────────► flush; exit edit; keep overlay open
        └─ outside click ──► flush; close; return focus

Resolve/Reopen changes whole-thread state without changing message membership.

comment focus/activity moves to another thread
  └─► activeThreadId and selectedLines move to that thread

comment system loses focus/activity with no overlay open
  └─► clear activeThreadId and saved-comment selectedLines
```

`InlineCommentCompactThread` derives only the one-versus-many branch from the
complete ordinal-sorted projection. Overlay and editor state live in the viewer
controller, not in the compact component, Store, wire, or Atom. Save/Revert end
editing but do not close the overlay. Copy success does not close an overlay or
resolve a thread.

### Thread presentation path

```text
CURRENT
complete ordinal-sorted thread projection
  → WorktreeAnnotationThread maps every message
  → controlled Collapsible mounts M1…Mn in Pierre normal flow
  → projection.state clears thread maps and publishes threads=[]

PROPOSED
projection.state expected count + same-revision batches [CHANGED wire completeness]
  → projection store assembles full replacement offscreen
  → one atomic complete snapshot publish [CHANGED presentation boundary]
  → InlineCommentCompactThread reads message count
      ├─ count = 1 → InlineCommentMessage(M1)
      └─ count ≥ 2 → M-summary + M-last
  → Expand/Edit/Reply opens viewer-owned Popover portal [ADDED]
      └─ ScrollArea renders InlineCommentMessage(M1…Mn)
  → Pierre normal-flow row height stays unchanged [PRESERVED]
```

No presentation branch writes SQLite or changes output membership. Durable
Reply/Edit commands still use the Store/repository path. Store errors return to
the stable overlay editor without closing it or discarding local text.

## Current-to-proposed call paths

The current branch already contains the durable PR1 Store/repository/transport
path. That path remains authoritative. This correction changes projection
replacement completeness and comment presentation; it does not replace SQLite,
the Store, command admission, edit-token authority, or Pierre slot ownership.

| Behavior | Current source-anchored path | Proposed delta |
| --- | --- | --- |
| File/Review intent to native | annotation component → `WorktreeAnnotationSurfaceClient.execute` → existing product session → surface adapter → Store → repository | intentionally unchanged physical route, command correlation, durable owner, and typed result/error |
| Native state to viewer | projection packer emits `projection.state`, then per-thread `message.batch`; `WorktreeAnnotationProjectionStore` clears maps/publishes empty state, then publishes each completed thread; File/Review `renderAnnotation` returns null when lookup fails | add state expected-thread count; assemble until that many distinct per-thread terminal batches arrive; publish metadata + threads once atomically; retain last complete projection during gaps |
| Ordinary metadata delivery under queue pressure | eager annotation `events(snapshot:)` materializes the full packed-event array; annotation and File/Review metadata use reset-capable `enqueueSubscriptionData`, while pane presentation/selection can bypass a waiting annotation; frame/byte saturation may reset/discard or return `closeRequired`, and the annotation source retires | replace eager annotation production with `WorktreeAnnotationProjectionEventCursor`; route pane presentation, pane selection, and every File/Review subscription-data event through one session FIFO and non-resetting registry admission; an older byte-blocked head prevents smaller ordinary-data bypass; acknowledgement performs atomic admission; lifecycle/reset is the only terminal replacement path and forces canonical replay |
| Annotation assembly failure recovery | main surface client has no annotation resync command; `fileDisplayResync` owns only File display; exact annotation subscription refs/cancel/reopen live privately in `BridgeCommWorkerProductController`; cancel may hang and subscribe handle precedes admission | add strict internal `annotationProjectionResync` RPC; main detects once per revision; generation-fenced worker task retires exact slot, command-specific timeout invalidates before degraded, cancel must settle before provisional reopen, and first valid replay state is the ready barrier; complete main assembly alone restores available; no domain/native call |
| Thread presentation | Pierre portal → `WorktreeAnnotationThread` → controlled Collapsible maps M1…Mn inline; MapPin and shared command rail own mixed actions | compact M1 or M-summary + M-last only; remove Collapsible/MapPin; viewer-level Popover owns M1…Mn and authoring; exact command matrix |
| Durable feature rows | App boot → `WorkspaceSQLiteDatastore` → annotation SQLite adapter/repository → `local.sqlite` | intentionally unchanged; no schema or persistence-authority change for presentation/assembly |
| Source evidence and range presentation | pane controller → `agentstudio-git` provider → immutable File/Review products → evaluator; current adapter already owns one controlled `selectedLines` range for pending/active feedback | retain Git/evaluator authority; make the viewer's pending-or-saved discriminated selection the sole `selectedLines` writer; compact focus activates without opening, overlay retains activity, inactive cards have no range paint, and no location control exists |
| Output selection transfer | one `output.prepare` operation carries at most 64 explicit IDs or exclusions directly to the Store | add product-session-scoped begin/chunk/commit/cancel assembler; Store still receives one complete immutable selection; no persistence/Atom authority |
| Output selection reachability | inline controls require a Pierre slot; history rail appears only after output exists | add Store-owned bounded candidate query/count and conditional output-only rail Handoff for eligible messages without inline placement; same selection surface in File/Review |
| Clipboard/file output | interaction controller → output coordinator → App-owned effect with succeeded, failed, or unknown → durable/browser outcome | retain prepare/effect/finalize owners but delete synchronous `unknown`; destination cancel remains pre-prepare, effect returns succeeded/failed, and only startup recovery converts prepared attempts to durable unknown |

### Authoring path

```text
[UNCHANGED] Pierre onLineSelectionEnd
   │ selectedLines feedback only; no durable effect
   ▼
[UNCHANGED] controlled React selection
   │ endpoint/gutter onGutterUtilityClick
   ▼
[UNCHANGED] React inline composer
   │ async typed File/Review annotation call
   ▼
[UNCHANGED] surface transport adapter
   │ typed logical command
   ▼
[UNCHANGED] WorktreeAnnotationStore
   │ validate + async repository transaction
   ▼
[UNCHANGED] datastore adapter → repository → local.sqlite authority
   │ committed result | typed error
   ▲
Store applies committed delta to WorktreeAnnotationProjectionAtom
   │ event through existing pane stream [UNCHANGED]
   ▼
projection.state expected count + complete message batches
   │ assemble without changing the published snapshot
   ▼
atomic complete snapshot publish
   └─ all subscribed File/Review viewers render the same revision
```

### Reply first-character path and state/batch interleaving

The current implementation breaks after the durable commit, not during typing
or SQLite persistence:

```text
CURRENT — observed failure

Reply control
  → viewer-local reply editor mounts with editToken T
  → first input h remains in the Textarea
  → reply.create(T, body = h)
  → Store/repository commits message M with draft h
  → projection.state(R) arrives
  → WorktreeAnnotationProjectionStore clears thread/message maps
  → publishes threads=[]                                      [REMOVED]
  → File/Review renderAnnotation cannot resolve thread
  → Pierre SlotPortals unmount compact thread + editor
  → focus, DOM identity, local h, and token registration are lost
  → later message.batch(R, thread) cannot restore that editor identity
```

The target keeps the existing durable command path and changes only projection
completeness and presentation ownership:

```text
TARGET — same reply with separately delivered state and batches

Reply control
  → WorktreeAnnotationInteractionController opens overlay(threadId, invoker)
  → reply editor mounts once with stable identity (threadId, T)
  → first input h remains in the Textarea
  → reply.create(T, body = h)
  → Store/repository commits message M with draft h
  → projection.state(R, expectedThreadCount=1)
       └─ projection store begins assembly; published R-1 remains unchanged
  → zero or more message.batch(R, threadId, terminal=false)
       └─ merge into private assembly; no React notification
  → message.batch(R, threadId, terminal=true)
       └─ validate distinct terminal-thread count and complete message set
  → atomically publish snapshot R
  → existing compact thread reconciles by threadId
  → existing overlay editor reconciles by threadId + editToken
  → same Textarea node remains connected, focused, and valued h

observable result
  one thread · one reply message · one edit token · no release or duplicate
```

If state R is followed by state R+1 before R completes, R+1 replaces only the
private assembly; the published complete snapshot stays unchanged. Batches for
R are then stale and ignored. If R+1 expects zero threads, that state is complete
and atomically publishes the empty replacement. Invalid or incomplete assembly
never calls File/Review render subscribers with a partial thread set.

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

### Arbitrary output-selection and reachability path

```text
Store projection summary
  → eligible count + eligible-without-inline-placement count
  → inline timeline More and/or conditional rail Handoff
  → AnnotationOutputSelectionSurface
       → paged Store candidate-summary query
       ← page | typed loading/failure
       → viewer selects any finite subset
       → begin(mode, transferId)
       → ordered unique ID chunks under frame cap
       → commit(transferId)
  → transport assembler returns one complete immutable selection
  → Store prepare revalidates canonical eligibility and order
       ├─ failure ──► preserve browser selection; discard transfer
       └─ success ──► existing prepare/effect/finalize path
```

The candidate query and conditional rail trigger are output-only reachability
mechanisms. They never hydrate comment bodies into a global panel, navigate to
threads, or create another mutation entrance.

## One batch, two output effects

The output coordinator prevents the Markdown and JSON paths from selecting or
snapshotting independently.

```text
selected message IDs + expected saved revisions
                 │
                 ▼
prepare operation: validate + capture exact batch + project exact bytes
                 │
Store → repository transaction: revalidate + persist batch/bytes
                                + persist exact membership
                                + block writes through prepared membership
                 ▼
App-owned clipboard or file effect
        ├─ known failure ──► idempotent cancel-attempt transaction
        │                    ├─ commit ──► remove prepared write guard;
        │                    │             message status remains editable
        │                    └─ failure ─► retain prepared row/write guard; report
        │                                  effect failure and cleanup failure
        │                                  separately; retry cleanup only
        └─ known success
                 │
                 ▼
Store → repository transaction: finalize event + set included status = locked
        ├─ success ──► publish event/history
        └─ failure ──► fallback transaction records finalization_failed
                       + sets included status = locked
                       ├─ commit ──► report partial success
                       └─ failure ──► prepared write guards remain
                       never repeat the external effect automatically

live App effect result has no unknown member

process exits or response is lost while durable attempt remains prepared
        │ no synchronous browser/coordinator outcome
        ▼
next startup recovery transaction
        └─► attempt unknown + included messages locked + exact bytes retained
```

The prepared transaction is the immutability boundary: no external effect may
begin until the exact bytes, exact membership, and prepared write guards commit.
Known effect failure asks one idempotent repository transition to cancel that
attempt and removes its write guard only when no other prepared attempt includes
the message. If that cancellation transaction fails,
the coordinator retains the in-memory proof that the external effect failed,
reports both the effect failure and the cleanup-persistence failure, leaves the
durable prepared row and write guards unchanged, and may retry only the idempotent
cancel transition while that proof remains available. It never repeats the
external effect automatically. If the process terminates before cancellation
commits, restart can no longer prove the external outcome from durable state;
the still-prepared attempt therefore recovers as `unknown` rather than
fabricating the lost in-memory failure result. A returned effect success followed
by finalization failure is known partial success: the fallback transaction marks
the attempt `finalization_failed` and the included messages `locked`. If that
fallback cannot commit, the prepared membership continues to block writes until
restart converts it to `unknown`. Only a crash or lost response that leaves
durable state unable to prove whether the effect occurred becomes `unknown`;
startup recovery atomically changes every included message to `locked`.

For Export, destination selection occurs before the store prepares an attempt,
so panel cancellation creates neither a file nor annotation state. The pure
projector builds bytes from the captured snapshot; the store transaction then
revalidates each selected message's saved revision, editable status, absent
draft, and lack of another prepared membership before atomically persisting
canonical semantics, the projection contract version, the exact materialized
bytes, and membership. History can therefore inspect and reproduce the
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
fence in the excerpt. The projector orders located threads by
repository-relative path, trustworthy current/original line, and stable
thread/message identity. The JSON projector emits the same membership and order
as the exact closed `WorktreeAnnotationBatchV1` contract in R-P1-012. Its schema
literal is `agentstudio.worktree-annotations.batch`, its only emitted format
version is `1`, every field is required, semantic absence is explicit `null`,
and File/diff source plus placement variants use their specified
discriminants. The Swift encoder/validator and strict TypeScript fixture schema
share canonical golden documents; neither may infer fields from the Markdown
projection or admit unknown properties.

Annotation mutation frames carry only compact repository/worktree identity,
repository-relative path, source role, admitted source identity, and selected
line/range coordinates. They do not carry an arbitrary source excerpt. The
native source owner validates those coordinates against the admitted File or
Review material and captures the selected excerpt for immutable origin and
batch construction. Exact excerpt and final Markdown/JSON bytes remain in the
repository/output path outside the compact projection Atom and message-frame
packing contract.

Each root, reply, optional draft, and current saved body is admitted only when
its UTF-8 body is at most 16 KiB. The complete-message wire entry is deliberately
smaller than the durable model: it carries session/thread/message identities,
flat ordinal, durable message `createdAt`, semantic and saved revisions, fixed
human-author kind, current saved body, optional draft body, `editable | locked`
status, and resolution/placement summary. Immutable excerpts, `updatedAt`, exact
output bytes, and duplicated source bodies are excluded. One bounded
thread-context record carries the repository-relative path, source role and
coordinates; it references the admitted source identity and never embeds the
source excerpt.

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
  ├─ projection.state arrives before complete same-revision batches
  │    └─ stage replacement; keep last complete snapshot visible
  │       publish once only after expected distinct terminal-thread count arrives
  ├─ semantic projection assembly failure
  │    └─ discard private assembly; retain last complete as unavailable
  │       request exact worker subscription reopen once for that revision
  ├─ annotation frame meets temporary shared metadata-queue saturation
  │    └─ session retains exact FIFO admission; source awaits real capacity;
  │       acknowledgement admits without reset, sequence advance, or retirement
  ├─ selection chunk/query failure
  │    └─ discard transport transfer or retain retryable surface respectively;
  │       preserve browser selection; no Store/SQLite/Atom selection write
  ├─ source read/evaluation failure
  │    └─ placement unavailable or continuity uncertain; never guess
  ├─ clipboard/file effect failure
  │    ├─ cancel transaction commits
  │    │    └─ no output event; remove prepared write guards
  │    └─ cancel transaction fails
  │         └─ report known effect failure + cleanup failure; retain prepared
  │            row/write guards; retry idempotent cleanup only while proof is live
  ├─ known effect success followed by finalization failure
  │    ├─ fallback commits ──► finalization_failed + status locked
  │    └─ fallback fails ────► report partial success; prepared guard remains
  └─ crash or lost result where effect outcome cannot be proven
       └─ no live unknown outcome; next startup atomically converts the durable
          prepared attempt to unknown, locks included messages, and retains bytes
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
| Annotation projection expands beyond the 63 ordinary queued-frame slots or 4 MiB budget | the session parks the exact next annotation event in its capacity FIFO; acknowledgement atomically rechecks and appends it; source continues sequentially until every packed event is admitted, without `closeRequired`, stream reset, or subscription retirement |
| A large annotation head waits while smaller pane/File/Review metadata candidates arrive | every ordinary metadata-data candidate joins the same FIFO behind the existing head; smaller frames cannot steal byte capacity; acknowledgement drains consecutive heads atomically, so the large head eventually fits as queued bytes leave |
| Ordinary metadata arrives while admitted annotation frames fill the queue and no receipt is in flight | ordinary data receives capacity-unavailable and joins the FIFO; it cannot invoke queue replacement or discard admitted frames |
| Protocol lifecycle or explicit reset becomes authoritative while data is queued/waiting | reset atomically terminates the old data epoch, settles incompatible waiters before producer drainage, and exposes the terminal transition to the worker; reopened canonical subscription sources replay rather than treating discarded old-epoch frames as delivered |
| One waiting annotation source is cancelled while another remains | session removes and settles only the matching admission token; the other waiter retains its order and can be admitted; late wake of the cancelled token cannot enqueue |
| Producer/session replacement or revocation occurs with capacity waiters | session settles every affected waiter terminally before teardown completes; pending-admission count is lifecycle residue and must reach zero |
| `projection.state(R)` arrives before one or more expected thread batches | projection store stages R privately and keeps the last complete snapshot renderable; no File/Review subscriber sees empty or partial threads |
| state R → partial R → resync state R | equal-revision state is authoritative replay: reset only private R assembly, keep published state/editor mounted, accept only subsequently ordered R batches from the same producer identity, and publish complete R exactly once |
| state R replays after complete R is already published and no assembly exists | settle current command outcomes but perform no clear/publish/remount; ignore its replayed R batches |
| same revision arrives from a replacement producer/subscription | invalidate old private assembly and key the replay to the new producer identity; never merge old/new producer batches |
| `projection.state(R+1)` arrives while R is incomplete | discard only R's private assembly; retain the last complete published snapshot; accept only R+1 batches and ignore later R batches |
| Completed unique-thread count exceeds expectation, terminal repeats, data arrives after terminal, or message/thread identity is invalid | projection store rejects private assembly, retains last complete snapshot as transport-unavailable, bars failed subscription ID, and emits one `annotationProjectionResync` request for that semantic revision |
| Resync request names stale subscription ID, wrong surface, or a controller no longer current in runtime registration | worker returns one request-correlated degraded/stale without cancellation; main remains unavailable and sends no domain fallback |
| Concurrent second resync names the already retired exact subscription | exact active-object validation rejects it; only the first task owns that request generation and no second cancel/reopen begins |
| Exact subscription cancel hangs until command timeout, then resolves late | runtime invalidates task generation before one degraded result; retired slot stays non-authoritative; late cancel continuation cannot subscribe, assign, forward, or publish |
| Exact subscription cancel rejects | task invalidates and returns one degraded; no replacement subscription is started |
| Replacement admission, event iterator, or stream fails/ends before first valid state | provisional handle is never promoted; task invalidates, returns one degraded, and leaves no fabricated active slot |
| Replacement emits first valid `projection.state` | current task promotes exact handle, forwards state, resolves replay-start barrier, and only then returns worker ready; main remains unavailable until complete expected-count assembly |
| Reopened subscription fails assembly again at the same semantic revision | main remains unavailable and does not emit another resync request; complete/newer publication is required to reset the gate |
| Main surface client disposes during resync | pending RPC is rejected and later worker messages are ignored; no cross-port controller disposal is invented |
| Hard worker termination during resync | execution context ends, so pending task and continuations cannot install or publish; replacement worker establishes fresh controller authority |
| Runtime installs a replacement controller while old task is pending | current-controller identity check invalidates old task before assignment/result; late continuation cannot mutate the replacement controller |
| Expected thread count is zero | state is a complete zero-thread revision and atomically replaces metadata and threads without waiting for a batch |
| Output-selection chunk is out of order, duplicated, oversized, or repeats an ID | transport assembler discards that transfer and reports typed failure; browser keeps its viewer-local selection and may begin a fresh transfer |
| Product session disconnects or caller cancels selection transfer | assembler discards the ephemeral transfer; Store, SQLite, and Atom never observed it |
| Candidate-summary query fails | output surface remains open with current selection and retryable failure; it never treats failure as zero eligible messages |
| Two viewers edit one message | one edit token and expected draft revision accept one ordered writer; stale writes fail without replacing text |
| Pane closes during pending debounce | controller requests immediate flush, then clears the matching token; product-session disconnect invalidates ownership if teardown cannot complete |
| Browser/pane/app terminates with a persisted edit token | Store boot or product-session invalidation makes the orphan reclaimable; acquire preserves the committed body, replaces the token, advances draft revision, and rejects delayed old-token commands |
| Known external effect failure, then cancel-attempt transaction fails | output coordinator reports the known effect failure and cleanup-persistence failure separately, retains the prepared row/write guards, and retries only the idempotent cancel transition while the known result remains in memory; it never repeats the external effect |
| App effect returns | only succeeded or failed is legal; no coordinator/browser direct unknown branch exists |
| App restarts with an unfinished prepared attempt | startup recovery atomically marks the attempt `unknown`, changes included messages to `locked`, and retains exact bytes; no recovery modal and no automatic replay |
| Reviewer explicitly retries an unknown attempt | output coordinator reuses the persisted exact bytes and batch; a new explicit effect result is recorded without rebuilding current content |
| Finalization request repeats | attempt identity makes finalization idempotent; existing event returns success without a duplicate event |
| Placement evaluation races a newer source epoch | evaluator result carries input fingerprint/epoch; store rejects stale result and schedules current evidence |
| Subscription reconnects | Store reloads the demanded committed projection; browser assembly accepts only the newest expected-count-complete revision and ignores older states/batches |

Successful Copy uses a BridgeWeb-owned shadcn/Sonner toast primitive to show
`Copied N comments`, dismisses the copy interaction, and leaves every inline
thread open and visible. The annotation surface consumes the owned `Toaster`
wrapper and never invents route-local toast markup. Copy and Export never
resolve a thread, close its overlay, or claim an agent addressed it.

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

Selection transfer is explicit user-driven traffic with at most one live
assembler per product session. Each chunk is frame-bounded; ephemeral memory is
linear in the finite selected/excluded ID set and is released on
commit/cancel/error/disconnect. This accepted cost preserves arbitrary subset
totality without durable selection state. Candidate summaries are paged on
demand, never bulk-published through the Atom, and only one page plus the
viewer-local ID set needs to remain rendered.

The transport publishes only demanded session projections and never duplicates
source bodies. Projection eviction is not deletion; no silent retention cap
deletes human review history from SQLite.

Ordinary metadata publication is one capacity-managed FIFO on the existing
metadata producer. The registry owns the unchanged 64-frame/4-MiB limits and
one-frame terminal reserve; the session owns only pending admission lifecycle.
Pane presentation, pane selection, File/Review metadata, and File/Review
annotation candidates cannot bypass an older head. Annotation sources emit
sequentially and may each retain one current event while waiting.
Acknowledgement is the only capacity wake for ordinary data: there
is no timer, polling, wall-clock sleep, capacity increase, or observation-pacing
reuse. Each source advances an incremental projection-event cursor whose bounded
prepass derives expected thread count and whose current batch stays below one
encoded frame; it never materializes the full packed-event array. Newer Atom
snapshots coalesce to one while a current full snapshot is still being emitted,
so incremental packing overhead is bounded by cursor/current-event state per
annotation source plus one newest pending snapshot. A slow worker applies backpressure to those source
tasks—the correct payer for preserving every complete message—and never to
SQLite command durability.

Protocol lifecycle and explicit reset are not ordinary-data FIFO entries. They
retain terminal priority and the existing worker-visible reset contract. A
reset invalidates the old epoch and all pending data before any producer-drain
await, then canonical sources replay after reopen. Thus reset recovery may
discard obsolete old-epoch frames, but no ordinary metadata caller can silently
discard a committed annotation outcome or starve it with smaller frames.

Overlay open/editor state is local derived presentation state and produces no
Store, repository, Atom, or wire traffic. Projection assembly is also
browser-local but is a synchronization boundary, not presentation truth: it
notifies React only for an expected-count-complete revision. A one-to-two-message
transition changes the compact branch from M1 to M-summary + M-last while the
open overlay and editor survive by `threadId`, `messageId`, and edit token.
Copy outcomes preserve that interaction state. Equal-revision resync resets
only producer-keyed private assembly; idempotent replay of a published revision
never produces a second presentation revision.

Assembly recovery is serialized at two owners: the main surface client admits
one resync request per failing semantic revision, and the worker controller
admits it only for the exact active subscription object/ID. Local slot
retirement precedes asynchronous cancel. Runtime timeout invalidates the task
generation before reporting degraded; every cancel/open/iterator continuation
checks that generation plus old/provisional object and current-controller
identity. Replacement is provisional until its first-state barrier. Recovery
work is therefore one RPC, at most one cancel, and—only after valid cancel
completion—at most one provisional reopen per revision. Repeated corruption or
late settlement remains fail-closed rather than creating a recovery loop.

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
- Expand is a real timeline `Button` with an explicit accessible name. Enter
  or Space opens the non-modal overlay. Focus alone activates the compact
  thread's stored range through `selectedLines` but never opens the overlay.
  Edit/Reply open the same overlay and move focus to the intended editor. The
  overlay retains range activity as focus traverses its descendants. Closed
  Popover content is unmounted, so chronology and controls leave Tab and
  accessibility traversal. Closing returns focus to the exact surviving inline
  invoker; leaving the comment system with no overlay clears saved-range paint.
- Escape while editing flushes and exits editor mode but leaves the overlay
  open; the later Escape closes it. Outside press flushes an active draft before
  close. Because the surface is non-modal, it does not trap keyboard users in a
  page-sized review; Tab can continue through the viewer while the overlay is
  open.
- Summary text is generated plain text rather than rendered authored Markdown.
  Draft, resolution, placement, inclusion, and message-status facts use visible text and
  never rely on color, an icon, or a tooltip alone. Icon-only affordances retain
  accessible names and tooltips are visual enhancement only.
- The comment system admits at least 24-by-24 CSS-pixel pointer targets or
  equivalent target spacing, remains operable at 200% text and narrow viewer
  widths, and disables Popover transition motion under reduced-motion settings.
  Bounded chronology scrolling remains independent of the Pierre canvas.
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
browser interaction in File or Review
   │ React through Vite HMR
   ▼
real typed product transport
   │
   ▼
real Swift bridge development server (tracked PID + isolated data root)
   │
surface adapter ──► Store ──► real SQLite repository
                       │
                       ├─► projection Atom
                       │      └─► state expected count + message batches
                       │             └─► session capacity FIFO + producer registry
                       │                    └─► shared metadata stream
                       │                           ├─ acknowledgement ──► capacity FIFO
                       │                           └─► browser complete-revision assembler
                       │                                  ├─► Pierre compact row + overlay
                       │                                  └─ assembly failure
                       │                                       └─► internal worker resync RPC
                       │                                            └─► exact cancel/reopen
                       │                                                 through same product transport
                       ├─► source evaluator ──► controlled real Git fixture
                       ├─► output-candidate query ──► bounded selection surface
                       │      └─► chunk assembler ──► complete selection
                       └─► output coordinator
                                  ├─ fake effect for narrow failure/order proof
                                  └─ real App effect for clipboard/file proof

Observation points
  committed repository revision · SQLite rows · rendered viewer state
  projection event order · Textarea DOM/focus/value · Pierre row/scroll geometry
  range paint · exact clipboard/file bytes · output event/batch history
```

Assembly-recovery proof uses the real `WorktreeAnnotationSurfaceClient`, strict
worker RPC codec/router, and `BridgeCommWorkerProductController`. Only the
locally substitutable product transport supplies deterministic annotation
subscription objects so the harness can observe exact subscription ID
validation, hanging/rejected/late cancel, provisional subscribe, pre-state
stream failure, first-state barrier, queued-old-event rejection, concurrent
controller replacement, and hard worker termination. Main-client disposal is
proved at the real MessagePort/RPC seam. No Store/source/repository fake
participates because that path must remain absent.

The browser interaction proof is not a static JSX or mock-only design review.
It drives real Pierre threads in both File and Review against the real Swift
development backend and isolated `local.sqlite`, while Vite supplies React
HMR and browser screenshot/interaction iteration. JS/TS/CSS edits use Vite HMR
without restarting that backend; its exact PID and data root remain recorded so
a reset cannot masquerade as state continuity. A Swift/backend edit permits one
deliberate backend restart. Restart/recovery proof deliberately reuses the same
isolated data root and records the before/after backend identity. The packaged
app is the final WebKit/native-effects boundary after the fast loop passes, not
the first component-design loop.

| Requirements | Realization owner and seam | Required proof boundary |
| --- | --- | --- |
| P1-U1, P1-U8, P1-U13, P1-U14 / R-P1-001, R-P1-009, R-P1-014, R-P1-016 | repository identities, Store discovery/commands, atomic zero-session first annotation, paired demand projections, flat whole-thread transactions | zero/one/several applicable-session admission without persistent session chrome; multi-pane File/Review integration; commit-before-publication retry; demand eviction/reload without a save; restart hydration; resolve/reopen journeys |
| P1-U2, P1-U3 / R-P1-003, R-P1-004, R-P1-006 | edit scheduler, saved-body/draft/status transactions, edit-token ownership, producer-keyed complete-revision assembler, session-owned lossless ordinary-metadata capacity admission, required browser-local `transportStatus`, surface-client resync gate, generation-fenced worker resync task, first-state replay barrier, and stable editor identity | first-character and equal-R continuity; a projection larger than physical queue capacity completes amid smaller competing pane/File/Review metadata and simultaneous File/Review annotation sources; no ordinary-data bypass/reset/discard, byte-head starvation, cancellation/revocation/FIFO/zero-residue cases; explicit lifecycle reset settles old epoch and canonical replay converges; cancel hangs → timeout → late resolve yields one degraded/no install; cancel rejection and pre-state admission/stream failure yield degraded/no slot; first valid state alone yields worker ready while complete main assembly alone restores available; stale/duplicate/concurrent replacement, main disposal, and hard worker termination cannot loop, mix events, install late, issue domain calls, or lose editor state |
| P1-U4 / R-P1-005 | Markdown validator, annotation-specific sanitizer, existing Markdown parser/code renderer and `BridgeNavigationDecider`, packet projector | schema/unit cases for H1/raw HTML and safe/unsafe link destinations, native navigation-policy proof, and real visual rendering/accessibility of an admitted link |
| P1-U5, P1-U6 / R-P1-002, R-P1-007 | viewer-owned pending-or-saved range-presentation union, one controlled Pierre `selectedLines` writer, endpoint-anchored cards, immutable origin, and source evaluator | real Git fixtures plus File/Review pending drag/endpoint/gutter `+`; focus each compact thread/control without opening the overlay; retain one painted stored range while its overlay is open; move paint to another active thread; clear paint on comment-system inactivity; prove inactive cards have no range paint and no location command exists |
| P1-U7, P1-U8 / R-P1-008, R-P1-009, R-P1-014 | Store/repository session transitions, continuity matrix, and anchored transient decision Popover | transition unit tests and bounded ambiguity/continue/detach behavior without persistent session-management chrome |
| P1-U9, P1-U10, P1-U12, P1-U13 / R-P1-001, R-P1-010, R-P1-011, R-P1-013 | viewer selection, bounded candidate query, conditional rail Handoff, transport selection assembler, output coordinator, history Dialog, and Markdown projector | 130 eligible with the middle 65 explicit and complementary 65 excluded through multi-frame transfers; same-path/thread candidates distinguishable by ordinal/excerpt; ordering/duplicate/disconnect failures; all-outdated/unavailable first Copy and first Export from File and Review; loading/failure/focus return; deterministic bytes and actual clipboard inspection; no general comments/session panel |
| P1-U11 / R-P1-012 | exact `WorktreeAnnotationBatchV1` contract, JSON projector, Swift validator, and strict TypeScript fixture schema | canonical complete-document conformance; every source/placement union member; missing/unknown-field and discriminant rejection; duplicate/mismatched-thread and order rejection; actual selected-file inspection |
| P1-U12 / R-P1-013 | prepared membership guards, succeeded/failed-only App effect, idempotent cancel/finalize transactions, and startup unknown recovery | compile/schema proof that direct effect/coordinator/browser outcomes contain no unknown; known failure/cancel and success/finalization failure; process termination with prepared attempt followed by startup atomic unknown/lock/byte-retention; real Copy/Export history inspection |
| P1-U14 / R-P1-014, R-P1-016 | flat message ordinal, durable `createdAt`, compact message-count projection, viewer-owned non-modal Popover, bounded ScrollArea, thread/message-keyed editor state, exact command owners, and overlay-retained active range | M1-only or M-summary + M-last in Pierre normal flow; focus activates range without opening; M1…Mn only in overlay; open overlay retains the one painted range; unchanged Pierre row height/scroll anchor; exact controls; Save/Revert/Escape/outside-click/focus return; independent same-coordinate threads; closed-overlay traversal exclusion; reduced-motion, 200% text, narrow-width, browser screenshot/interaction, and packaged VoiceOver proof |
| all message-bearing requirements / R-P1-017 | 16 KiB body admission, bounded 64 KiB complete-message DTO, bounded thread context, incremental projection-event cursor with dynamic complete-message frame packing, and sequential capacity-managed annotation emission | maximum-legal singleton encoding and multi-message boundary packing at 16/64/128 KiB without rejection or message splitting; block first admission for a many-thread projection and inspect cursor/current-event state to exclude a whole packed-event array; then drain a projection exceeding physical queue capacity amid smaller ordinary metadata without bypass, ordinary-data reset, discard, or retirement |
| reliability obligation | boot-owned durable recovery provenance plus annotation hydration/acknowledgement policy | corrupt local-database integration proving quarantined filenames persist, pre-ack mutation fails closed, acknowledgement retains the witness, and subsequent restart distinguishes recovery from never-created state |
| system persistence-evolution standard | structural-only annotation DDL plus typed Swift enum codecs | raw SQLite accepts structurally valid future enum strings for every annotation enum column; repository decoding rejects unknown values; schema inspection finds no product-enum membership enforcement; adding a product state requires no table rebuild |
| TypeScript contract standard | strict schema-derived types, required-by-default fields, direct nullable message content, and exhaustive discriminated unions for genuine variants | type tests and runtime-schema tests admit every intended variant, reject unknown discriminants and invalid message-content combinations, and fail missing required fields |
| all / R-P1-015 | dependency and protocol boundaries | module/protocol/source inspection proving no PR2 machinery or App IPC |

Real SQLite, the real product transport, the safe Markdown renderer, real
Pierre, and real Git fixtures are required for their integration claims.
Controlled clocks and fake output effects replace only time and fallible App
effects in narrow unit proof. The Vite/Swift loop proves live component behavior
and visual structure; packaged UI proof then proves WKWebView, clipboard, and
save-panel/file effects. A mocked browser test cannot substitute for either
real-runtime layer.

Structural enforcement uses typed Swift codecs and exhaustive registries for
product variants and wire calls; SQLite constraints only for storage integrity
plus transactions for durable atomicity; revision, edit-token, and source-epoch
runtime guards for concurrency; strict Markdown/JSON/path validation;
module/architecture lint boundaries; and automated plus packaged-effect proof.
SQLite does not enforce product-enum membership or cross-field product
semantics.

Projection/output proof must also establish these negative rules: mutating
loading/display state does not persist; zero-demand eviction does not delete or
save domain records; exact historical bytes never become Atom state;
`projection.state` alone never clears complete live projection; partial batches
never notify React; equal published replay never republishes; batches never mix
across producer/replay epochs; temporary metadata-data capacity absence never
returns `closeRequired`, advances a sequence, resets the stream, permits a newer
smaller ordinary-data candidate to bypass the FIFO head, or retires another
subscription; ordinary data never queue-replaces already admitted annotation
frames; explicit lifecycle/reset settles pending tokens before producer drain
and requires canonical replay; a cancelled capacity token never enqueues on a
late wake; the annotation source never materializes a complete packed-event
array; capacity admission never calls producer-observation pacing; selection
chunks never become SQLite/Atom truth;
candidate-query failure never means zero candidates; the output-only rail
surface never becomes comment navigation; synchronous effect/coordinator/browser
unknown does not exist; and chronology never changes Pierre row height or
CodeView scroll position. Assembly recovery proof additionally establishes that
`source.refresh`, `fileDisplayResync`, Store/repository calls, native product
methods, and App IPC are never invoked; the comm worker never performs semantic
assembly; one failing revision cannot trigger more than one reopen request;
native `recoveryStatus` is unchanged; unavailable transport never hides the
last complete threads; and ready/partial replay never clears unavailable before
one complete atomic publish. The worker cannot publish ready before the first
validated replay state, a timed-out task cannot install after late settlement,
and no callable controller-disposal contract is invented.

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
