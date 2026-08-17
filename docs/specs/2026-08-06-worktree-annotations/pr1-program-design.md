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
  ├─ shared annotation client, thread-keyed presentation state, inline shell,
  │  and draft scheduler
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
         │ uses existing datastore boundary
         ├────────► AgentStudioCore
         │           WorkspaceSQLiteDatastore  local recovery provenance at boot
         │
         │ projects validated values
         ▼
BridgeWeb
  WorktreeAnnotationClient                typed calls/subscription
  WorktreeAnnotationInteractionController viewer-local decisions, output selection, and transient overlays
  WorktreeAnnotationDraftScheduler        debounce/max-wait/focus-loss intent
  Pierre annotation adapters              controlled selection, admission, and inline projection
  shared inline-comment components         shell/content/command-rail rendering and focus
  owned shadcn/Sonner toast primitive     Copy confirmation presentation
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
| Pending Pierre selection, active thread, thread-keyed disclosure, expanded composer, temporary output selection, bounded session/continuity choices, draft cadence, and unsent keystrokes after the last accepted command | active BridgeWeb annotation client/provider and `WorktreeAnnotationInteractionController` above Pierre portals | Store after semantic command admission; transient interaction state never enters the Store or projection Atom |

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
output, or recovering an attempt whose external result is unknown, changes each
included message from `editable` to `locked`. Known effect failure and successful
cancellation remove the prepared guard without changing `status`.

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
         └─ crash-unknown ──────────► LOCKED
                                         └─ new reply only
```

`editable | locked` is persisted on the message identity. There is no
`provisional` message status: an output attempt's prepared membership is the
short-lived transaction guard. Output admission requires saved content, no
draft, `editable` status, and no prepared membership. Successful or
crash-unknown output permanently changes the included message to `locked`.

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
       └─ no composer and no durable mutation

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
controlled selection feedback; `onGutterUtilityClick` is the sole composer
admission path. Selecting another range, clicking outside, or Escape clears a
pending empty selection. Durable located threads render through
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
resolvable threads at the same line therefore render as separate Bridge-owned
React wrappers inside one Pierre annotation row, not as two guaranteed Pierre
rows. Each wrapper and every active/disclosure/editor lookup is keyed by stable
`threadId`; portal-array position and source-row identity are never state keys.
Pierre owns the shared row height and source-range paint. BridgeWeb owns the
single `activeThreadId`, so selecting one wrapper never activates, expands, or
resolves its same-coordinate sibling.

```text
Pierre physical annotation row at file.ts:84
  ├─ threadId A wrapper ── summary or expanded A
  └─ threadId B wrapper ── summary or expanded B

source-row paint      → Pierre
active thread A       → BridgeWeb activeThreadId = A
disclosure for A / B  → BridgeWeb keyed state[A] / keyed state[B]
resolution for A / B  → durable Store commands by exact threadId
```

### Shared inline-comment component anatomy

The composer, collapsed durable draft, and saved thread use one BridgeWeb-owned
shell composed from the repository's shadcn primitives. Pierre owns placement,
range paint, and measurement; the shell owns comment content and actions.

```text
strongly rounded inline shell
  ├─ left timeline
  │    ├─ avatar as the timeline node
  │    └─ author/time/status in the avatar row
  └─ rounded body surface
       ├─ one-message Markdown body
       ├─ multi-message summary or flat expanded message sequence
       ├─ borderless composer while authoring
       └─ invisible bottom-right vertical icon rail
            ├─ context-appropriate secondary actions
            └─ primary Save icon while composing
```

The avatar is never placed on the right. Time is part of the left timeline row,
not a right-aligned field that consumes its own content row. The command rail
has no separate card, header/footer divider, or nested textarea card. Every
command is an icon-only shadcn `Button` with an accessible name and tooltip;
Save alone uses the primary treatment.
Draft uses visible `Draft` text plus a warning-semantic cue; it never relies on
yellow alone. Thread-active range tint uses only `comment-active`, while focus
uses the standard focus-visible ring. The component consumes the frozen
registered `comment-*` Tailwind utilities and owned shadcn primitives; it does
not edit `bridge-app.css`, add raw colors, or call `var(--comment-*)` where a
utility exists. If the token lane has not registered a warning-role utility,
the draft cue waits for that API rather than substituting raw yellow. Exact
radius, avatar overlap, spacing, and active/draft token derivations remain
visual-tuning decisions proved in the Vite loop and the packaged viewer rather
than hard-coded by this design.

The summary is a pure deterministic projection, not semantic or model-generated
content. It derives a bounded plain-text excerpt from the latest chronological
message plus author/time, total message count, resolution, and any hidden
Draft, placement, inclusion, or message-status facts required by the Specification. It
never receives a message identity, Markdown rendering, selection state, reply
target, Store command, or output membership.

### Viewer-level transient interaction owner

Each File or Review viewer constructs one
`WorktreeAnnotationInteractionController` in the shared annotation provider
above every Pierre portal. It owns only ephemeral interaction state; the Store
continues to own every decision, query, and durable mutation.

```text
WorktreeAnnotationInteractionController (one per viewer)
  ├─ pending inline admission
  │    ├─ several applicable sessions → anchored session-choice Popover
  │    └─ uncertain continuity → anchored decision Popover
  ├─ output selection
  │    ├─ { kind: explicit; messageIds }
  │    └─ { kind: allEligible; excludedMessageIds }
  ├─ Handoff DropdownMenu opened from an inline command rail
  │    └─ Select all · Clear · Copy selected · Export selected
  └─ output-history Dialog
       ├─ inspect successful events and unknown attempts
       └─ explicitly reproduce persisted exact bytes

Never persisted or projected
  pending choice · open Popover/Dialog · active trigger · selected IDs
```

The default output selection is an empty `explicit` member. Include/Exclude on
an expanded message mutates that viewer-local set. `Select all` switches to
`allEligible`; exclusions then remain explicit without loading every cold
message into the Atom. The Store supplies eligible counts and resolves
`allEligible` against canonical repository state during preparation. A stale or
newly ineligible member causes typed preparation failure and a projection
refresh rather than silent omission. Known effect failure, file-panel
cancellation, or preparation failure preserves the selection; successful
Copy/Export clears it because every included message is then locked. Closing a
viewer may discard selection because it is navigation state, not human-authored
work.

The range endpoint or gutter `+` remains the admission trigger. When discovery
finds several applicable sessions, its anchored shadcn `Popover` lists only
those bounded choices; selecting one resumes the original create intent and
Escape/click-away cancels without mutation. When the selected session is
uncertain, the same transient owner presents `Continue`, `Leave Paused`, and
`Start Another`; only Continue persists the displayed continuity evidence,
Leave Paused cancels the intent, and Start Another records only the transient
admission choice. Its first non-whitespace edit atomically creates the new
session and root draft. No chooser remains after that blocked intent resolves.

Every visible inline thread exposes the same Handoff icon in its bottom-right
command rail when eligible messages or output history exist. It opens the
shared `DropdownMenu`; Copy success closes it and shows the required toast.
Locked messages additionally expose an Inspect Output message command. To keep
history reachable when every included thread is outdated or unavailable, one
icon-only `Output history` trigger appears in the existing File/Review rail
toolbar only while durable output history exists. It opens the same shadcn
`Dialog`, never lists or navigates comments, and is therefore neither a global
review panel nor persistent session-management chrome. An unknown recovered
attempt makes that trigger visibly announce `Output needs review`; the Dialog
offers inspection and explicit exact-byte repetition without an automatic
effect or recovery-choice modal.

```text
inline message Include/Exclude ──► viewer-local selection
                                        │
inline Handoff icon ──► DropdownMenu ────┼─► Store prepares canonical batch
                                        │        └─► App Copy/Export effect
                                        │
locked-message Inspect ────────────────►│
conditional toolbar History ───────────►└─► Store history query
                                                   └─► exact-byte repetition
```

The controller restores focus to the exact invoking `+`, command-rail button,
or toolbar trigger when a transient surface closes. Session and continuity
choices, output selection, Copy/Export, history inspection, and unknown
repetition therefore have visible presentation-to-Store paths in both viewers
without restoring `WorktreeAnnotationSessionChrome`.

### shadcn/Base UI composition contract

The feature owns comment anatomy and composes the repository's owned shadcn
primitives. It does not recreate their interaction behavior with route-local
elements.

| Feature component | Owned shadcn/Base UI building blocks | Responsibility |
| --- | --- | --- |
| `InlineCommentSurface` | semantic container plus comment-role utilities | shared shell, left timeline/body layout, active/draft/resolved variants |
| `InlineCommentThread` | render-derived message-count branch | exact one-message versus multi-message presentation; Reply, Resolve/Reopen, and Expand/Collapse thread commands |
| `InlineCommentThreadSummary` | controlled `Collapsible`, dedicated `CollapsibleTrigger`, `Button` | generated summary, concise `Show N messages` disclosure, no nested commands |
| `InlineCommentMessage` | feature Markdown body, `Checkbox`, `Label`, `Button` | authored body, author/time, optional-draft and editable/locked facts, Edit and per-message Include/Exclude |
| `InlineCommentComposer` | `Textarea`, `Button` | borderless Markdown entry, Save/Revert, draft errors and focus |
| `InlineCommentCommandRail` | `Button`, `DropdownMenu`, `Tooltip` | context-filtered thread, message, and draft commands stacked as icon-only actions at the body's bottom-right without becoming a second card |
| `AnnotationSessionDecisionPopover` | owned `Popover`, `Button` | bounded several-session or uncertain-continuity choice anchored to the blocked inline intent |
| `AnnotationHandoffMenu` | owned `DropdownMenu`, `Checkbox`, `Button` | viewer-local Select all/Clear and Copy/Export invocation; never session management |
| `AnnotationOutputHistoryDialog` | owned shadcn `Dialog` added under `components/ui`, `Button` | inspect bounded event/attempt summaries and explicitly reproduce exact bytes; never a thread fallback panel |
| author identity | owned shadcn `Avatar` with `AvatarFallback` | compact human identity; no remote image source is invented |
| Copy confirmation | owned Sonner `Toaster` | concise status after the native clipboard effect succeeds |

`CollapsibleTrigger` contains only the disclosure label/icon. Reply,
Resolve/Reopen, Expand/Collapse, message links, and inclusion checkboxes remain sibling
controls. The closed panel is unmounted so M1 through Mn are not present behind
the summary. The panel uses normal document flow; no absolute thread stacking,
fixed/max-height clipping, inner scroll region, or height animation is allowed.
Pierre's ResizeObserver and normal annotation-height reconciliation remain the
only layout mechanism; BridgeWeb adds no resize or scroll API.

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
  ├─ always maps every message             ──► 1 message: M1; 2+: thread summary
  ├─ divided message cards                ──► expanded flat chronological flow
  └─ footer Reply                         ──► bottom-right icon-rail action

WorktreeAnnotationNewMessageComposer           InlineCommentComposer
  ├─ nested Textarea card                 ──X─► borderless Markdown canvas
  └─ Cancel/Save footer                   ──► bottom-right icon rail; Save is primary
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
    ├─ InlineCommentThread
    │    owns: message-count branch and thread-keyed disclosure
    │    ├─ exactly 1 ──► InlineCommentMessage(M1)
    │    └─ 2 or more
    │         ├─ collapsed ──► InlineCommentThreadSummary
    │         └─ expanded  ──► flat InlineCommentMessage(M1…Mn)
    ├─ InlineCommentComposer
    │    owns: active reply/edit and forced-expanded authoring state
    └─ InlineCommentCommandRail
         ├─ thread: Reply · Resolve/Reopen · Expand/Collapse
         ├─ message: Edit · Include/Exclude output
         └─ draft: Revert · Save, with Save as the only primary action

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

### One shell and message-count-dependent thread states

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
                         same shell · render M1 directly · no disclosure
                               │ Reply creates M2 draft
                               ▼
                         MULTI-MESSAGE AUTHORING
                         force expanded · render M1…Mn + active composer
                               │ Save/close editor; retain expansion
                               ▼
                         MULTI-MESSAGE EXPANDED
                         render M1…Mn exactly once in flat order

initial projection of an idle 2+ message thread
        │
        ▼
MULTI-MESSAGE COLLAPSED
  summary only · M1…Mn panel unmounted
        │ Show N messages
        ▼
MULTI-MESSAGE EXPANDED
  render M1…Mn exactly once in flat order

Resolve/Reopen changes whole-thread state without changing message membership.
```

`InlineCommentThread` derives the one-versus-many branch from the complete
ordinal-sorted projection. Its transient disclosure map is owned by the shared
annotation client/provider above Pierre portals and keyed by `threadId`, so
ordinary projection revisions, Copy success, and Pierre virtualization do not
reset an expanded thread. The map is presentation state: it is not persisted,
transported, or projected through the Atom. A new reply or edit sets the exact
thread expanded before mounting its composer and retains expansion until that
authoring session ends; no collapse path may unmount an active editor or unsent
text.

### Thread presentation path

```text
CURRENT
complete ordinal-sorted thread projection
  → WorktreeAnnotationThread maps every message
  → M1…Mn always mounted

PROPOSED
complete ordinal-sorted thread projection [UNCHANGED authority and transport]
  → InlineCommentThread reads message count [CHANGED presentation]
      ├─ count = 1 → InlineCommentMessage(M1) [ADDED branch]
      └─ count ≥ 2
           ├─ collapsed → derived InlineCommentThreadSummary only
           └─ expanded  → InlineCommentMessage(M1…Mn)
  → normal-flow portal height change → Pierre remeasurement [UNCHANGED]

No branch calls native code, writes SQLite, changes output membership, or
replaces the complete projection. Reply/Edit sets the exact thread expanded,
then follows the existing durable authoring path; Store errors return to that
editor without collapsing or discarding local text.
```

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
[ADDED] Pierre onLineSelectionEnd
   │ selectedLines feedback only; no durable effect
   ▼
[ADDED] controlled React selection
   │ endpoint/gutter onGutterUtilityClick
   ▼
[ADDED] React inline composer
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
restart converts it to `unknown`. Only a crash or lost response
that leaves durable state unable to prove whether the effect occurred becomes
`unknown`; recovery atomically changes every included message to `locked`.

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
       └─ durable attempt becomes unknown; included status becomes locked
          and exact batch/bytes remain
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
| Pane closes during pending debounce | controller requests immediate flush, then clears the matching token; product-session disconnect invalidates ownership if teardown cannot complete |
| Browser/pane/app terminates with a persisted edit token | Store boot or product-session invalidation makes the orphan reclaimable; acquire preserves the committed body, replaces the token, advances draft revision, and rejects delayed old-token commands |
| Known external effect failure, then cancel-attempt transaction fails | output coordinator reports the known effect failure and cleanup-persistence failure separately, retains the prepared row/write guards, and retries only the idempotent cancel transition while the known result remains in memory; it never repeats the external effect |
| App restarts with an unfinished attempt | recovery marks the attempt `unknown`, changes included messages to `locked`, and retains exact bytes; no recovery modal and no automatic replay |
| Reviewer explicitly retries an unknown attempt | output coordinator reuses the persisted exact bytes and batch; a new explicit effect result is recorded without rebuilding current content |
| Finalization request repeats | attempt identity makes finalization idempotent; existing event returns success without a duplicate event |
| Placement evaluation races a newer source epoch | evaluator result carries input fingerprint/epoch; store rejects stale result and schedules current evidence |
| Subscription reconnects | Store reloads the demanded committed projection; deltas older than its accepted revision are ignored |

Successful Copy uses a BridgeWeb-owned shadcn/Sonner toast primitive to show
`Copied N comments`, dismisses the copy interaction, and leaves every inline
thread open and visible. The annotation surface consumes the owned `Toaster`
wrapper and never invents route-local toast markup. Copy and Export never
resolve a thread, change its disclosure state, or claim an agent addressed it.

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

Thread disclosure is local derived presentation state and produces no Store,
repository, Atom, or wire traffic. The client consumes only complete
ordinal-sorted thread projections, so it never summarizes a partial message
batch. A projection transition from one to two messages while Reply/Edit is
active retains forced expansion; unrelated projection revisions and Copy
outcomes preserve the existing `threadId` entry.

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
- A one-message thread has no disclosure semantics. A multi-message thread uses
  a dedicated `CollapsibleTrigger` with an explicit `Show N messages` accessible
  name; Enter/Space expand it and focus remains on the trigger. No interactive
  command is nested inside that trigger, and the unmounted closed panel leaves
  no hidden message control in Tab or accessibility traversal.
- Summary text is generated plain text rather than rendered authored Markdown.
  Draft, resolution, placement, inclusion, and message-status facts use visible text and
  never rely on color, an icon, or a tooltip alone. Icon-only affordances retain
  accessible names and tooltips are visual enhancement only.
- The comment system admits at least 24-by-24 CSS-pixel pointer targets or
  equivalent target spacing, remains operable at 200% text and narrow viewer
  widths, and disables disclosure/height motion under reduced-motion settings.
  Escape remains owned by pending-range and draft behavior, not disclosure.
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
| P1-U1, P1-U8, P1-U13, P1-U14 / R-P1-001, R-P1-009, R-P1-014, R-P1-016 | repository identities, Store discovery/commands, atomic zero-session first annotation, paired demand projections, flat whole-thread transactions | zero/one/several applicable-session admission without persistent session chrome; multi-pane File/Review integration; commit-before-publication retry; demand eviction/reload without a save; restart hydration; resolve/reopen journeys |
| P1-U2, P1-U3 / R-P1-003, R-P1-004, R-P1-006 | edit scheduler, saved-body/draft/status transactions, saved-body/revision invariant, edit-token ownership/reclamation, shared shell state | injected-clock unit behavior; absent/absent, mismatched body/revision, first/later Save, stale expected revision, and revision-exhaustion cases; SQLite recovery; empty dismissal; durable empty edit of a saved message; non-empty flush/collapse; normal token release; disconnect/restart orphan reclamation with delayed-token rejection; Command+Enter Save, Revert, newline behavior; and Vite/packaged visual interaction proof |
| P1-U4 / R-P1-005 | Markdown validator, annotation-specific sanitizer, existing Markdown parser/code renderer and `BridgeNavigationDecider`, packet projector | schema/unit cases for H1/raw HTML and safe/unsafe link destinations, native navigation-policy proof, and real visual rendering/accessibility of an admitted link |
| P1-U5, P1-U6 / R-P1-002, R-P1-007 | controlled Pierre selection, gutter-only composer admission, immutable origin, and source evaluator | real Git fixtures for exact/relocated/outdated/unavailable placement plus File/Review drag highlight, endpoint/gutter `+`, inline rendering, and absence of fabricated/global fallback UI |
| P1-U7, P1-U8 / R-P1-008, R-P1-009, R-P1-014 | Store/repository session transitions, continuity matrix, and anchored transient decision Popover | transition unit tests and bounded ambiguity/continue/detach behavior without persistent session-management chrome |
| P1-U9, P1-U10, P1-U12, P1-U13 / R-P1-001, R-P1-010, R-P1-011, R-P1-013 | viewer-level interaction controller, temporary discriminated output selection, Handoff menu, output-history Dialog, output coordinator, and Markdown projector | zero/one/several-session journeys; explicit/all-minus-exclusions selection; unavailable-thread history reachability; focus restoration; deterministic permutation tests; actual system clipboard inspection; no persistent session/general-comment panel |
| P1-U11 / R-P1-012 | exact `WorktreeAnnotationBatchV1` contract, JSON projector, Swift validator, and strict TypeScript fixture schema | canonical complete-document conformance; every source/placement union member; missing/unknown-field and discriminant rejection; duplicate/mismatched-thread and order rejection; actual selected-file inspection |
| P1-U12 / R-P1-013 | prepared membership write guards plus idempotent cancel-attempt and event/status-finalization transactions | injected known-failure, cancel-transaction failure/retry, known-success/finalization-failure, and crash-unknown effects plus restart and real Copy/Export history inspection |
| P1-U14 / R-P1-014, R-P1-016 | full session discovery, flat message ordinal, durable message `createdAt` projection, thread-owned resolution, thread-keyed presentation state, count branch, and controlled shadcn Collapsible | controlled-clock projection proves message `createdAt` survives unchanged across draft autosave/edit while relative timeline/summary time derives from it; one-message/no-disclosure; two-or-more summary with M1 absent; expand to M1…Mn exactly once; authoring-forced expansion; independent same-coordinate threads; sibling-command, Tab, Enter/Space, focus, reduced-motion, 200% text, and packaged VoiceOver proof |
| all message-bearing requirements / R-P1-017 | 16 KiB body admission, bounded 64 KiB complete-message DTO, bounded thread context, and dynamic complete-message frame packer | maximum-legal singleton encoding and multi-message boundary packing at 16/64/128 KiB without rejection or message splitting |
| reliability obligation | boot-owned durable recovery provenance plus annotation hydration/acknowledgement policy | corrupt local-database integration proving quarantined filenames persist, pre-ack mutation fails closed, acknowledgement retains the witness, and subsequent restart distinguishes recovery from never-created state |
| system persistence-evolution standard | structural-only annotation DDL plus typed Swift enum codecs | raw SQLite accepts structurally valid future enum strings for every annotation enum column; repository decoding rejects unknown values; schema inspection finds no product-enum membership enforcement; adding a product state requires no table rebuild |
| TypeScript contract standard | strict schema-derived types, required-by-default fields, direct nullable message content, and exhaustive discriminated unions for genuine variants | type tests and runtime-schema tests admit every intended variant, reject unknown discriminants and invalid message-content combinations, and fail missing required fields |
| all / R-P1-015 | dependency and protocol boundaries | module/protocol/source inspection proving no PR2 machinery or App IPC |

Real SQLite, the real product transport, the safe Markdown renderer, and real
Git fixtures are required for their integration claims. Controlled clocks and
fake output effects replace only time and fallible App effects in narrow unit
proof. Packaged UI proof uses the real clipboard and save panel/file path; a
mocked browser test cannot substitute for those effects.

Structural enforcement uses typed Swift codecs and exhaustive registries for
product variants and wire calls; SQLite constraints only for storage integrity
plus transactions for durable atomicity; revision, edit-token, and source-epoch
runtime guards for concurrency; strict Markdown/JSON/path validation;
module/architecture lint boundaries; and automated plus packaged-effect proof.
SQLite does not enforce product-enum membership or cross-field product
semantics.

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
