# Worktree Annotation New And Pending — Program Design

This Program Design realizes
[`2026-08-24-requirements.md`](./2026-08-24-requirements.md) and
[`2026-08-24-specification.md`](./2026-08-24-specification.md). It extends the
existing
[`Worktree Annotations PR1 Program Design`](../2026-08-06-worktree-annotations/pr1-program-design.md)
in place. PR1 remains the authority for sessions, flat threads, drafts, source
placement, output history, Copy Markdown, Export JSON, exact command results,
compact invalidation, and finite projection convergence.

This design adds durable inbound-attention state for already-admitted agent
messages and separates that state from the existing human output-handled state.
It does not create an agent delivery, admission, identity, authorization,
provider, reply-mutation, acknowledgement, retry, reconciliation, or resolution
owner.

## How the existing system changes

The existing annotation path already has the right authority and transport
shape. `local.sqlite` owns durable messages and output handling;
`WorktreeAnnotationServiceActor` serializes annotation behavior; one typed
command route returns exact results; compact `snapshotRequired` facts trigger
finite projection replacement; and the BridgeWeb projection store presents the
same state in File and Review.

New and Pending extend those owners rather than introducing parallel state:

```text
BridgeWeb explicit interaction
  │
  ├─ human Save / Copy / Export ──────────────── existing PR1 path
  │
  └─ deliberate agent-message view ──────────── added typed operation
                    │
                    ▼
         WorktreeAnnotationTransportAdapter
                    │
                    ▼
         WorktreeAnnotationServiceActor
                    │
                    ▼
       WorktreeAnnotationSQLiteRepository
                    │
                    ▼
                local.sqlite
                    │
                    ├─ exact command result ──────────► initiating surface
                    └─ existing snapshotRequired ─────► all File/Review surfaces
```

The structural crux is exact revision identity. A message has one current saved
body and an integer `savedRevision`; it does not gain a saved-revision history.
Pending is derived from the current human revision's handled boundary. New is
derived from whether the current agent revision equals the last durably viewed
saved revision. Output never writes the viewed marker, and viewing never writes
handled.

## Current evidence and constraint degree

This is compatibility-bound extension work, not greenfield architecture.

| Current relationship | Evidence | Constraint on this design |
| --- | --- | --- |
| SQLite is the sole annotation authority | `WorktreeAnnotationSQLiteRepository`, `WorktreeAnnotationServiceActor` | viewed truth belongs on the existing durable message boundary, not in React, an Atom, or another store |
| `annotation_message.author_kind` already exists | `WorkspaceLocalMigrations` migration 006 | cut the existing human-only decoder over to a closed domain enum; do not add a second author column |
| the current domain and projection reject non-human authors | `WorktreeAnnotationDomainModels`, `WorktreeAnnotationSQLiteRepository+Loading`, `BridgeProductWorktreeAnnotationProjectionContracts`, BridgeWeb Zod contracts | every native and browser contract must cut over together |
| handled is exact-current-message state | `annotation_message.handled`, output-attempt membership by expected saved revision | Pending reuses the existing handled boundary; no second pending column exists |
| Share still transports `.new | .all` | `BridgeProductWorktreeAnnotationOutputSelectionContracts`, `worktree-annotation-share-mode.tsx` | hard rename to `pending | all`; no compatibility alias may preserve the overloaded meaning |
| output membership is re-derived natively under projection/session/source fences | `WorktreeAnnotationTransportAdapter+Output` | browser filtering is presentation; native remains the output authority |
| successful finalization marks every matching selected message handled | `WorktreeAnnotationSQLiteRepository+Output.markOutputMessagesHandled` | add the author guard so All never writes handled state for agent messages |
| output snapshots are one current v1 type | `WorktreeAnnotationBatchSnapshot`, `WorktreeAnnotationBatchProjector` | freeze v1 and add a version-dispatched v2 document; do not reinterpret stored v1 |
| command result and projection convergence are separate | typed command outcome plus `snapshotRequired` and finite query | viewed success can update the initiating surface immediately while SQLite and later projection remain authoritative |

The existing three physical Bridge routes remain unchanged:

| Route | Responsibility retained |
| --- | --- |
| command | strict mutation/query request and exact result |
| stream | compact replaceable invalidation only |
| content | finite annotation projections and exact stored output bytes |

No new metadata event case is required. A successful viewed transition uses the
existing session change publication, represented on the current wire as
`snapshotRequired`.

## Structural choice

Three durable-view structures are credible:

| Alternative | Gain | Cost and failure shape | Decision |
| --- | --- | --- | --- |
| browser-local viewed set | no native schema or command | diverges across File/Review, resets on reload/restart, and can clear a newer revision | rejected |
| append-only view-receipt table | preserves every historical view receipt and could support several viewers | creates history, identity, retention, and query policy that no requirement needs | rejected |
| nullable viewed saved revision on the existing message row | exact current-revision CAS, one durable owner, simple restart and projection behavior | preserves only the boundary needed for the current revision | selected |

The selected design adds one nullable scalar to `annotation_message` and one
batched semantic repository operation. It intentionally does not add an Atom,
store, coordinator, event type, timer, queue, polling loop, or second
projection.

The accepted debt is that one scalar cannot answer historical questions such
as when or how often a superseded agent revision was viewed. The annotation
repository bears that limitation. Revisit only if a separately authorized
audit/history or multi-reviewer requirement needs those answers.

## Components, ownership, and dependency direction

```text
AgentStudioBridge
├─ WorktreeAnnotation domain model
│    owns: author vocabulary and derived New/Pending invariants
│    consumed by: repository, service, projections, output projectors
│
├─ WorktreeAnnotationSQLiteRepository
│    owns: author/viewed/handled persistence and exact transition transactions
│    consumed by: WorktreeAnnotationServiceActor
│
├─ WorktreeAnnotationServiceActor
│    owns: mutation admission, serialization, and existing change publication
│    consumed by: annotation transport adapters
│
├─ WorktreeAnnotationTransportAdapter
│    owns: strict operation translation and exact command-result projection
│    consumed by: command route and development HTTP adapter
│
├─ annotation projection contracts and finite content source
│    owns: closed author/attention projection and replacement snapshot
│    consumed by: comm worker and BridgeWeb projection store
│
├─ output scope assembler and output coordinator
│    owns: authoritative Pending/All membership and existing effect lifecycle
│    consumed by: Copy Markdown and Export JSON
│
└─ BridgeWeb worktree-annotations
     owns: local expansion/activation, command-confirmed viewed overlay,
           viewed-result output-readiness fence, New/Pending display,
           and Pending/All presentation
     consumed by: File and Review Pierre adapters
```

Allowed dependencies remain:

```text
File / Review adapters
        └─► shared BridgeWeb worktree-annotations
                    └─► typed worker/product transport
                                  └─► Swift transport adapter
                                                └─► service actor
                                                        └─► repository
                                                                └─► local.sqlite
```

Forbidden edges:

- File and Review must not own separate New, Pending, or viewed state.
- React and the comm worker must not write SQLite or infer durable success from
  a click, render, scroll, or viewport intersection.
- output handling must not call the viewed transition.
- viewed handling must not call the output coordinator or mutate handled.
- human draft/edit operations must not accept an agent-authored message.
- this design must not create an agent-ingress command or agent identity field.
- the annotation feature must not add a Core/MainActor Atom or a second SQLite
  store.

The existing module-import lint and strict transport schemas enforce the static
edges. Repository transactions, author guards, and exact revision comparisons
enforce the runtime edges.

## Domain and persisted state

The domain gains one closed author enum and one optional exact-revision marker:

```text
WorktreeAnnotationAuthorKind = human | agent

WorktreeAnnotationMessage
  id
  threadID
  ordinal
  authorKind
  savedBody
  savedRevision
  draft
  handled
  viewedSavedRevision
  status
  semanticRevision
```

`viewedSavedRevision` is not historical content. It records only which saved
revision of this message most recently crossed the durable deliberate-view
boundary.

The repository and strict decoders enforce:

| Invariant | Enforcement |
| --- | --- |
| human messages may have a draft; agent messages may not | domain validation plus repository mutation guards |
| every browser-authored root/reply is human | existing create-root/create-reply transactions continue writing `author_kind = human` |
| agent messages are read-only in this slice | edit-token, flush, Save, and Revert reject `author_kind = agent`; presentation exposes no Edit action |
| human `viewedSavedRevision` is null | repository decoding and writes reject a human viewed marker |
| agent `handled` remains false | output finalization and unhandle operations target human rows only; decoding rejects an agent handled value |
| an agent viewed marker is null or a positive saved revision no newer than the current saved revision | migration constraint for positivity plus domain validation for author/current-revision relationship |
| a current agent revision is New exactly when `viewedSavedRevision != savedRevision` | one pure domain predicate used by native projection; browser consumes projected attention state |
| a current human revision is Pending exactly when it has saved content, has no draft, and `handled == false` | existing handled truth plus shared native/browser scope predicate |

The SQLite schema changes in place:

```text
annotation_message
  existing author_kind TEXT NOT NULL
  existing handled INTEGER NOT NULL DEFAULT 0
  add viewed_saved_revision INTEGER NULL CHECK (viewed_saved_revision >= 1)
```

Existing rows remain `author_kind = human`, keep their current handled value,
and receive `viewed_saved_revision = NULL`. Therefore existing unhandled saved
messages become Pending, handled human messages remain neither Pending nor New,
and no existing row becomes New.

SQLite continues to avoid product-enum `CHECK` constraints. Swift owns the
closed `human | agent` vocabulary. The database retains scalar integrity while
the repository owns cross-column author/viewed/handled invariants.

## Projected state and browser derivation

Finite message projection replaces the human literal with the closed author
kind and adds an attention state derived by native:

```text
attentionState = not_applicable | new | viewed

human message  ──► not_applicable
agent message with viewedSavedRevision == savedRevision ──► viewed
agent message with no matching viewedSavedRevision ───────► new
```

The transport does not expose `viewed_saved_revision` as storage vocabulary.
It carries `authorKind`, current `savedRevision`, and the closed
`attentionState`. Strict Swift and Zod validation enforce the valid author and
attention combinations.

BridgeWeb derives display facts from the complete projected message plus a
surface-lifetime exact command-confirmed overlay:

```text
isNew(message)
  = agent
    + current saved revision exists
    + no matching command-confirmed viewed overlay
    + projected attentionState == new

isPending(message)
  = human
    + current saved body exists
    + draft absent
    + handled == false

isAllEligible(message)
  = current saved body exists
    + draft absent
    + author is human or agent
```

The viewed overlay is keyed by `(messageID, savedRevision, committed
sessionRevision)`. It is immediate presentation continuity, not a second
durable truth. A complete projection reconciles it as follows:

| Projection observation | Overlay action |
| --- | --- |
| same saved revision is projected viewed at the committed/newer session revision | remove overlay; durable projection now carries success |
| a newer saved revision is projected | remove old overlay; newer agent revision follows its own New state |
| message is no longer present in the authoritative projection | remove overlay |
| committed/newer projection still calls the same saved revision New | retain the exact committed overlay and mark convergence unavailable rather than resurrecting New silently |
| surface is disposed | clear overlay; reopening queries SQLite |

Pending and All membership never read the viewed overlay. New presentation
never reads `handled`.

Each surface also retains the greatest command-confirmed viewed
`committedSessionRevision` per session as an output-readiness fence. The fence
does not change or re-derive Pending or All membership. While the last complete
projection for that session is older than the fence, the surface preserves the
last complete membership for inspection but classifies output membership as
unconfirmed and disables Copy and Export. A complete projection at the fenced
or a newer session revision clears the fence and restores output readiness.
Disposal clears the fence; reopening must obtain current SQLite-backed
projection truth before output is ready. A lost response installs neither an
overlay nor a fence, so the existing native revision fence remains the final
authority and safely rejects a stale output request.

## Deliberate-view operation

There is no current annotation viewed operation, so this is a proposed-only
call path with no predecessor.

The strict operation is feature-local product transport, not a new
`AppCommand`. It is a side effect of the existing Expand/activate local action
and adds no new visible command identity, shortcut, menu, toolbar entry, or IPC
method.

```text
message.viewed.mark
  sessionId
  items[1...256]
    messageId
    expectedSavedRevision
```

`256` is the shared Swift/Zod maximum for one viewed command. The strict body
rejects an empty list, more than 256 items, or a duplicate
`(messageId, expectedSavedRevision)` pair before service mutation. Request
order is semantic: the result contains exactly one item per request item in the
same order.

The closed command outcome adds one status variant. Viewed commands never use
the existing single-message receipt:

```text
command outcome
  requestId
  sessionId = requested session
  receipt = null
  status
    kind = viewed
    results[exactly request item count, same order]
      viewed
        messageId
        savedRevision
        committedSessionRevision
        disposition = changed | already_viewed

      not_viewed
        messageId
        expectedSavedRevision
        disposition = stale | not_agent | not_found
```

The result therefore returns one exact disposition per requested pair:

```text
viewed
  messageId
  savedRevision
  committedSessionRevision
  disposition = changed | already_viewed

not_viewed
  messageId
  expectedSavedRevision
  disposition = stale | not_agent | not_found
```

An Expand action with more than 256 currently New revisions partitions the
projection-ordered unique pairs into consecutive groups of at most 256. The
surface issues those groups sequentially with no retry and aggregates them as
one user action. Exact successes install overlays as their results arrive;
stale or rejected items remain New. A transport failure or unknown result for
one group installs no overlay for that group, does not prevent later groups
from being attempted, and produces one aggregate failure presentation after
the bounded sequence. This preserves partial progress without truncation or a
request larger than the product-command body budget.

The repository evaluates the bounded item set in one SQLite transaction:

1. verify every located row belongs to the named session;
2. compare `author_kind = agent` and current `saved_revision` against each
   requested pair;
3. update `viewed_saved_revision` only for exact agent pairs not already
   viewed;
4. increment each changed message semantic revision;
5. increment the session semantic revision once when at least one row changes;
6. return per-item exact dispositions from that transaction snapshot.

Stale or invalid items never change state. Valid exact items may commit in the
same batch even when another item is stale. This item-level partial result is
necessary because one newly revised agent reply must not prevent other exact
messages exposed by the same Expand action from becoming viewed. The UI clears
New only for `changed | already_viewed` items matching the same saved revision.

The service publishes one existing change notification when the transaction
changes at least one row. An all-idempotent or all-stale request returns its
exact result without a redundant invalidation.

### Entrypoint-to-effect path

```text
[ADDED] pointer/keyboard Expand on collapsed multi-message thread
   or deliberate activation of one agent message
    │ synchronous local interaction
    ▼
[CHANGED] BridgeWeb thread/message component collects exact current
          agent (messageID, savedRevision) pairs
    │ async typed command
    ▼
[UNCHANGED] WorktreeAnnotationSurfaceClient → comm worker → product command route
    │ exact request/result correlation
    ▼
[CHANGED] WorktreeAnnotationTransportAdapter decodes message.viewed.mark
    │ actor call
    ▼
[CHANGED] WorktreeAnnotationServiceActor serializes the semantic operation
    │ repository transaction
    ▼
[ADDED] WorktreeAnnotationSQLiteRepository.markViewed
    │ write viewed_saved_revision + semantic revisions
    ▼
[UNCHANGED] local.sqlite commit
    │
    ├─ exact per-item result
    │    ◄─ transport ◄─ worker ◄─ surface client
    │       └─ install matching command-confirmed viewed overlays
    │
    └─ existing snapshotRequired when changed
         └─ existing finite projection query/content path
              └─ reconcile overlay and converge every File/Review surface
```

An exact command failure, response loss, or unknown outcome installs no
overlay. New remains until a later complete projection proves the durable
viewed state or another deliberate action returns exact success.

## Interaction boundaries

BridgeWeb distinguishes deliberate activation from passive presentation:

| Interaction | Viewed request |
| --- | --- |
| click/keyboard activation of Expand on a collapsed multi-message thread | one bounded request containing all currently New agent revisions exposed by that expansion |
| non-control body activation that expands a collapsed multi-message thread | same bounded request as explicit Expand |
| click, focused Enter, or activation of a one-message agent thread | request for that exact current agent revision |
| pointer or keyboard activation of a specific agent message that arrived after its thread was already expanded | request for that exact current revision |
| activation of a control inside that exact agent message | request for that exact current revision, idempotently coalesced while in flight |
| focus entering or moving within a thread or message without activating an action | no request and no selection/expansion transition |
| render, scroll, viewport intersection, source paint, projection refresh, page reload, Share entry, Copy, Export, History, collapse, placement change, or resolution change | no request |

One surface client coalesces an identical in-flight
`(messageID, savedRevision)` pair so pointer and keyboard activation callbacks
from the same user gesture do not issue duplicate transport calls. Repository
idempotency remains the authority if duplicates still arrive.

The command partitioner owns projection order, de-duplication across one user
action, the 256-item request bound, sequential dispatch, exact-result
aggregation, and the single aggregate failure presentation. It is a pure
feature-local helper consumed by the shared File/Review interaction owner; it
does not own durable state or another queue.

Human messages retain the existing edit/body behavior. Agent messages render
read-only, use `Agent` as the author label, and never enter the draft/edit-token
path. Reply remains a human-authored thread action and is not agent mutation.

## New and Pending presentation

One pure shared projection derives both thread-level counts and exact
message-level states for File and Review:

```text
thread summary
  [N new when N > 0]
  [M pending when M > 0]
  K messages
  latest …
  Open | Resolved

expanded or one-message row
  Agent · … · ● New
  You   · … · ● Pending
```

The order is New, Pending, message count, latest activity, resolution. Zero
counts and their adjacent separators are omitted. Existing Draft, placement,
lock, read-availability, and resolution facts retain their separate meanings.

The shared BridgeWeb annotation components remain the sole presentation owner.
File and Review supply only Pierre/source-range adapters. New uses the existing
primary attention role and text; Pending uses the existing warning role and
text. Neither status depends on color alone.

## Pending and All output scopes

The output scope union hard-cuts in every layer:

```text
old: new | all
new: pending | all
```

There is no `new` compatibility literal, alias, or dual decoder. The embedded
BridgeWeb bundle and Swift product contracts ship as one compatible cutover;
the Vite development backend must use the same contract version.

The browser projection and native scope assembler use the same domain rules:

| Scope | Complete membership |
| --- | --- |
| Pending | every current saved, draft-free, unhandled human revision |
| All | every current saved, draft-free human or agent revision |

Browser filtering decides what the reviewer sees. Native re-derives the same
scope from repository truth after validating displayed projection, session,
and source-generation fences. The output coordinator still receives one exact
ordered selection and uses the existing prepare/effect/finalize lifecycle.

Successful finalization applies two distinct effects in the same exact
transaction. Every matching included editable message becomes locked,
regardless of author. Only matching human messages become handled:

```text
UPDATE annotation_message
SET status = 'locked', ...
WHERE exact output membership matches current saved_revision
  AND status = 'editable'

UPDATE annotation_message
SET handled = 1, ...
WHERE exact output membership matches current saved_revision
  AND author_kind = 'human'
```

Agent messages included under All retain `handled = false` and keep their
read-only author semantics while participating in the same durable lock
boundary as every other included message. Unknown-outcome recovery and
finalization-failed containment likewise lock every matching included editable
message while leaving agent `handled = false`. Output does not write
`viewed_saved_revision` and does not alter New. `output.handled.clear` targets
matching current human revisions only and never unlocks any message.

The existing failure behavior remains:

- validation conflict produces no external effect and leaves Share open;
- cancellation or known effect failure releases the prepared fence and changes
  neither Pending nor New;
- known effect success plus finalization failure closes Share, preserves the
  write fence/lock behavior, leaves affected human revisions Pending, and does
  not alter agent New;
- recovered unknown attempts remain exact-byte inspectable/repeatable without
  changing viewed state.

## Versioned output documents

The current single batch type becomes a version-aware boundary:

```text
WorktreeAnnotationStoredBatchDocument
├─ v1: frozen WorktreeAnnotationBatchSnapshotV1
│      author.kind = human only
└─ v2: current WorktreeAnnotationBatchSnapshotV2
       author.kind = human | agent
```

The JSON document does not gain an outer wrapper. Repository decoding first
uses the attempt's persisted `format_version` to select the strict versioned
decoder, then verifies that the document's own `formatVersion` matches. Each
version keeps its own closed member vocabulary and validation.

New output preparation always creates v2. Pending and All share the same v2
projector; membership determines whether an agent author appears. Unknown
author kinds fail before the external effect or successful history
finalization.

Historical v1 rows retain their exact `snapshot_json`, `exact_bytes`, format
version, and membership. Inspect and explicit Repeat dispatch through the v1
decoder and reuse stored exact bytes. They never pass through the v2 projector
and are never rewritten.

The output content/inspection contracts accept supported stored versions 1 and
2, while the new-output preparation boundary accepts only version 2. This
separates compatibility reads from current writes.

Markdown uses the same v2 snapshot and labels every entry without hidden UI
context:

```text
Author: Human | Agent

Message:

<authored Markdown unchanged>
```

The remaining path, location, source excerpt, placement, thread resolution,
ordering, escaping, and Markdown-safety behavior remains unchanged.

## Failure, recovery, and concurrency

| Failure or interleaving | Containment and recovery owner |
| --- | --- |
| viewed request arrives for an older saved revision | repository returns stale for that item; no write; newer revision remains New |
| two panes mark the same exact revision viewed | service/repository serialization makes one change and one idempotent already-viewed result; both converge |
| agent revision changes while viewed batch is in flight | exact saved-revision comparison prevents the old request from clearing the new revision |
| one viewed batch contains current and stale items | current items commit; stale items remain New; exact per-item result controls the initiating overlay |
| command commit succeeds but response is lost | no optimistic overlay; existing invalidation/projection eventually reveals durable viewed state |
| command result succeeds but projection is delayed | exact viewed overlay hides only the matching saved revision; last complete projection remains otherwise intact |
| viewed success advances the session beyond the last complete output projection | command-confirmed session fence makes Pending/All membership unconfirmed and disables Copy/Export until projection convergence; membership is not re-derived from the overlay |
| successor projection contains a newer agent revision | old overlay is discarded; the successor's projected attention state controls New |
| successor projection contradicts a committed same-revision view | retain committed overlay and expose convergence unavailable; do not silently resurrect New |
| passive render produces repeated React effects | no view operation is owned by render/effect lifecycle; only explicit callbacks can call the command |
| Pending/All browser and native predicates drift | strict cross-language membership matrices and real effect inspection detect disagreement; native fence rejects stale displayed scope |
| All output includes agent entries | projector preserves agent author; finalization's human guard prevents handled mutation on agent rows |
| v1 history is inspected after v2 cutover | persisted version selects frozen v1 decoder and exact bytes; no migration or rewrite |
| unsupported output version or author kind | fail closed before external effect or successful history claim |
| local SQLite recovery replaces annotation data | existing recovery witness and acknowledgement gate remain authoritative; no client-local viewed fallback is fabricated |

The service actor remains the semantic serialization owner and
`WorkspaceSQLiteDatastoreActor` remains the physical database owner. The new
batch viewed transaction advances a session revision once, not once per
message. One existing replaceable invalidation is sufficient regardless of the
number of messages in the batch.

## Cutover

This is one hard product-contract cutover with four coordinated parts:

| Phase | Authority and permitted behavior |
| --- | --- |
| schema migration | add nullable `viewed_saved_revision`; preserve every existing row and handled/output record |
| native domain/transport cutover | decode closed human/agent author kind, project attention state, admit exact viewed operation, use Pending/All scope, produce v2, retain versioned v1 reads |
| worker/BridgeWeb cutover | accept the same closed contracts, render New/Pending, send viewed operations only from explicit actions, use Pending/All scope |
| packaged/dev proof | Swift backend and embedded/Vite BridgeWeb must use the same contract; no mixed old/new wire operation is supported |

The application ships Swift and embedded BridgeWeb together, so there is no
runtime negotiation or compatibility shim. The additive column preserves data
through forward migration, but product rollback across the hard
New/Pending/v2 cutover is unsupported even while every stored message remains
human: an older binary would restore the retired New meaning and create new v1
output. Historical output compatibility is different and belongs only to the
new binary's read path: stored v1 documents remain deliberately supported for
inspection and exact-byte Repeat.

## Trust, privacy, performance, and accessibility

| Obligation | Structural realization | Degraded behavior and proof seam |
| --- | --- | --- |
| trust | existing pane/product-session gates admit the command; Web UI cannot create an agent author; strict enums reject unknown author/attention values | unauthorized or malformed requests fail before repository mutation; contract/admission proof observes no write |
| privacy | viewed state stores one integer revision; telemetry records only bounded operation/result/count/revision facts | no body, excerpt, raw path, agent credential, or exact output bytes enter attention telemetry |
| reliability | SQLite marker plus exact CAS and projection convergence; overlay is disposable | response loss retains New until durable projection proof; restart reloads SQLite truth |
| performance | one bounded viewed batch transaction, one session revision increment, one existing invalidation; passive render performs no writes | batch-size policy rejects oversized input; marker-scoped latency can separate command, SQLite, projection, and paint |
| accessibility | shared semantic text plus color, author text, existing keyboard order and two-stage Escape | browser and packaged assistive proof inspects exact message and thread names at normal/narrow/200% text |
| File/Review parity | both surfaces consume one shared projection/store/component path | cross-surface proof observes one view action converge in the other surface |

No new secret, privilege, external process, or network boundary is introduced.

## Proof architecture

The proof path follows production ownership rather than replacing the command,
repository, or projection boundaries:

```text
browser driver
  └─ real shared File/Review annotation components
       └─ real surface client and production comm worker
            └─ real Swift product command adapter
                 └─ WorktreeAnnotationServiceActor
                      └─ WorktreeAnnotationSQLiteRepository
                           └─ isolated local.sqlite

observations
  ├─ exact command result and initiating New marker
  ├─ SQLite author/handled/viewed revision state
  ├─ compact invalidation and finite replacement projection
  ├─ cross-surface New/Pending counts and exact message markers
  ├─ actual clipboard/file bytes and immutable history
  └─ v1 inspection/repeat and new v2 author document
```

Pure domain and contract tests may substitute the database or transport only at
their owned seam. Repository transition/concurrency proof uses real SQLite.
Browser interaction proof may fake native only for deterministic UI states, but
the composed development journey must use the real comm worker, Swift adapter,
service, repository, and SQLite. Packaged proof remains required for WKWebView,
clipboard, save panel, focus, and accessibility behavior.

Because this slice intentionally adds no product agent-ingress operation, real
agent-message proof begins from a proof-only pre-boot seed. A test-target
fixture creates an isolated data root, runs the production migrations, and
inserts a constraint-valid session, thread, and already-admitted agent message
directly into that isolated `local.sqlite` before the backend starts. The
unmodified production backend then owns every query, viewed transition,
invalidation, output, reload, and restart step. The fixture is unavailable to
product targets and adds no debug route, repository API, transport operation,
or production authoring capability. Proof inspects SQLite before launch and
after each material transition, and source/contract scans verify that no agent
ingress exists in the production command surface.

## Requirement realization

| Requirements | Specification obligations | Structural realization | Proof seam |
| --- | --- | --- | --- |
| ANP-U1 | R-ANP-001, R-ANP-010 | closed author enum; separate handled and viewed fields/predicates; no cross-write | domain/state matrix, repository row inspection, strict contract proof |
| ANP-U2 | R-ANP-003, R-ANP-006, R-ANP-007 | projected attention state; shared thread/message projection and semantic author/status labels | collapsed/expanded/one-message File and Review browser plus visual/accessibility proof |
| ANP-U3 | R-ANP-004, R-ANP-005 | explicit interaction callbacks; bounded viewed command; no render/scroll effects; exact overlay | explicit-action versus passive-action matrix and command-count observation |
| ANP-U4 | R-ANP-003, R-ANP-005, R-ANP-009 | SQLite viewed revision; CAS; service invalidation; finite cross-view projection; overlay reconciliation | stale revision, two-pane convergence, reload, restart, response-loss proof |
| ANP-U5 | R-ANP-002, R-ANP-006, R-ANP-007, R-ANP-009 | existing handled field renamed semantically to Pending presentation; human-only predicate | human saved/draft/handled/locked matrix plus output/unhandle state inspection |
| ANP-U6 | R-ANP-002, R-ANP-008, R-ANP-010, R-ANP-011 | hard Pending/All scope; browser/native matching predicates; human-only finalization; complete v2 projector | complete-scope Copy/Export with human/agent mixtures and no checklist |
| ANP-U7 | R-ANP-006, R-ANP-007, R-ANP-011 | shared semantic tokens/text; explicit Human/Agent output labels | visual, keyboard, screen-reader, Markdown and JSON author inspection |
| ANP-U8 | R-ANP-004, R-ANP-005, R-ANP-008, R-ANP-009 | no optimistic clear without exact result; per-item stale results; preserved PR1 output failure state | failure, cancellation, unknown, partial success, stale response, restart inspection |

Load-bearing enforcement classes are:

| Invariant | Enforcement class |
| --- | --- |
| author and attention vocabulary is closed | Swift enum, Zod discriminated contract, strict JSON |
| stale viewing cannot clear a newer revision | SQLite transaction guard plus saved-revision CAS |
| viewing cannot change Pending | repository interface separation and mutation tests |
| output cannot clear New | human-only handled SQL guard and output-state tests |
| passive presentation cannot write viewed state | explicit callback-only interface plus browser command-count tests |
| File/Review share one truth | shared projection store/components plus cross-surface integration proof |
| new JSON is v2 and stored v1 remains v1 | version-dispatched schema validation and immutable exact-byte history proof |

## Deliberate limits and revisit signals

- No view-receipt history exists. Revisit only for an authorized audit or
  multi-reviewer requirement.
- No agent identity exists beyond `kind = agent`. A later identity contract
  requires a new Requirements/Specification and likely another output version.
- No agent admission or mutation operation is added. This design consumes an
  agent row only after separate authority admits it.
- No global New count, inbox, notification center, sound, badge, or operating-
  system notification exists.
- No viewport, dwell-time, hover, or scroll heuristic marks viewed.
- No delta projection or annotation-specific push payload is introduced.
- No Atom or native SwiftUI annotation read model is introduced.
- No output-scope compatibility shim retains `new` after the hard cut.
- A separate viewed table becomes credible only if history, several viewer
  identities, retention policy, or audit queries become required.
