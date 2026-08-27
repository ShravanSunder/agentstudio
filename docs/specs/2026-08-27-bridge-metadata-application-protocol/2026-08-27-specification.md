# Bridge Metadata Application Protocol — Specification

Requirements authority:
[`2026-08-27-requirements.md`](./2026-08-27-requirements.md)

Program Design:
[`2026-08-27-program-design.md`](./2026-08-27-program-design.md)

## Observable outcome

A Bridge application developer can add a typed metadata subscription by
defining and registering application contracts without adding application
payload cases to generic stream, subscription, queue, acknowledgement,
frame-bound, or backpressure logic. Existing File and Review metadata continues
to behave exactly as before.

Worktree Annotation consumers receive a lightweight, complete association
catalog independently of rich content. The catalog answers what annotation
identities exist and how they belong together. Existing session demand answers
which bodies, drafts, origin, placement, history, and output details must be
loaded now.

```text
generic metadata frame
  → registered application validation
  → typed application event
      ├─ bounded atomic catalog replacement
      └─ small application change event

Worktree Annotation catalog
  worktree → sessions → threads → messages

Worktree Annotation demand
  demanded session → rich details and placement
```

## Consumers and observable surfaces

```text
Bridge application developer
  ├─ application protocol definition
  ├─ static protocol registration
  ├─ typed subscription producer
  └─ typed subscription consumer

Human reviewer
  ├─ File Worktree Annotation surface
  ├─ Review Worktree Annotation surface
  └─ Share New/All output membership

Working agent
  ├─ copied Markdown
  └─ exported JSON

Outside this contract
  dynamic wire-provided protocol code · new transport route · UI redesign
```

## Terms

- **Generic metadata envelope**: stream and subscription delivery fields plus
  one application payload whose raw value has not yet been interpreted.
- **Metadata application protocol**: the registered application contract for
  subscription kind, options, interests, event validation, and event source
  generation.
- **Catalog transfer**: a bounded `begin`, ordered `window`, and `commit`
  sequence that replaces one application catalog atomically.
- **Catalog entry**: one application-defined typed member inside a catalog
  window.
- **Active catalog**: the last complete committed catalog visible to an
  application.
- **Candidate catalog**: one incomplete replacement hidden from application
  consumers until commit.
- **Rich annotation content**: bodies, drafts, immutable origin, current
  placement, output membership details, history, or output bytes.

## Normative requirements

### MAP-R1 — Generic envelope and registered typing boundary

Every application metadata data frame MUST expose generic stream identity,
stream sequence, subscription identity, subscription kind, subscription
sequence, source generation, optional operation correlation, and one raw
application payload. Before registered application validation, the raw payload
MUST be treated as unknown and MUST NOT be accessed through an asserted
application type.

After the generic envelope is accepted, the subscription kind MUST resolve one
registered metadata application protocol. That protocol MUST validate the
payload and MUST produce the typed event consumed by the application. An
unknown, unregistered, malformed, or application-mismatched payload MUST fail
closed and MUST NOT enter application state.

Basis: MAP-U1.

### MAP-R2 — One registration owns each application contract

Each registered metadata application protocol MUST define:

- one stable subscription-kind identity;
- the File or Review surface and worker/source authority required by that
  subscription;
- strict initial subscription options;
- strict initial-open conversion from those options;
- a canonical empty interest state and strict target-interest state;
- application interest-delta construction and accounting while generic
  batching and committed-interest barriers remain transport-owned;
- one closed event schema;
- how the event's source generation is read; and
- the application event type exposed to its producer and consumer; and
- the native application source binding that opens, updates, cancels, and
  closes the source behind the generic subscription lifecycle.

Two protocols MUST NOT register the same subscription-kind identity. Adding a
registered application MUST NOT require application cases in generic metadata
frame parsing, subscription sequencing, bounded event queues,
acknowledgement/backpressure, reset/end/error, or content transport.

Registration is static product composition. The wire MUST NOT register,
replace, or provide executable application protocols.

A registration MUST adapt an already-authorized native application owner. It
MUST NOT establish or widen pane, surface, worktree, provider, Review
publication, mutation, or content authority. Generic admission remains
mandatory, and the registered source MUST preserve its existing application
authority fences.

A fixture application with empty interests MUST be addable through one
registration in each language without changing generic surface maps,
subscription open/update state, interest batching/barriers, producer source
switches, frame parsing, bounded queues, acknowledgements, or backpressure.

Basis: MAP-U1.

### MAP-R3 — Generic delivery invariants remain authoritative

For every registered application, the transport MUST continue to validate the
current pane session, metadata stream, worker instance, subscription identity,
subscription kind, committed interest revision/hash, source generation,
contiguous stream sequence, contiguous subscription sequence, worker
derivation epoch, and metadata-frame byte ceiling.

The transport MUST reject post-terminal data, sequence gaps, generation
disagreement, data outside the committed interest barrier, and application
events whose registered source generation differs from the generic frame's
source generation.

Application registration MUST NOT weaken, duplicate, or reinterpret these
generic delivery invariants.

Basis: MAP-U1, MAP-U2.

### MAP-R4 — Bounded atomic catalog transfer

The generic catalog-transfer contract MUST be parameterized by one strict
application catalog-entry schema and MUST provide exactly these phases:

```text
catalog.begin
  transfer identity
  catalog revision
  expected entry count

catalog.window
  same transfer identity and catalog revision
  zero-based contiguous window ordinal
  one or more complete application entries

catalog.commit
  same transfer identity and catalog revision
  expected window count
  expected entry count
```

Each physical frame MUST remain within the existing metadata-frame ceiling.
One catalog entry MUST remain a complete semantic entry and MUST NOT be split
across windows. A sender MAY pack several complete entries into one window.

A receiver MUST expose the candidate only when commit proves contiguous
windows and matching entry/window counts. Until then, the active catalog MUST
remain unchanged.

Basis: MAP-U6.

### MAP-R5 — Catalog replacement failure and recovery

If a catalog candidate is malformed, mismatched, incomplete, duplicated,
out-of-order, superseded, cancelled, reset, or terminated before valid commit,
the receiver MUST discard that candidate and retain the last complete active
catalog.

A newer catalog transfer MAY supersede an older incomplete candidate. A replay
of an already committed transfer identity and revision MUST either validate as
equivalent or be rejected; it MUST NOT mutate the active catalog differently.

Catalog revision ordering applies only within one lifecycle-admitted
subscription/source authority. After that authority retires, the retained
active catalog's numeric revision MUST NOT block the first complete replacement
for the expected new authority. A transfer from an authority that the generic
lifecycle has not admitted MUST be rejected.

After subscription reset, stream replacement, or reconnect disposition that
requires a snapshot, the application MUST receive a complete replacement
catalog before treating its catalog as current. An earlier catalog MAY remain
visibly retained as stale but MUST NOT be presented as current for the new
subscription/source authority.

Basis: MAP-U6.

### MAP-R6 — File and Review compatibility

File metadata MUST retain its current source-accepted, tree-window, tree-delta,
status-patch, descriptor-ready, and invalidation semantics. Review metadata
MUST retain its current source-accepted, snapshot, window, delta, invalidation,
reset, candidate/active publication, and final-barrier semantics.

Moving File and Review validation behind registered application protocols MUST
NOT change:

- their wire event shapes or subscription identities;
- source, generation, publication, revision, or interest fences;
- progressive File tree application;
- atomic Review publication application;
- content descriptor meaning or demand scheduling;
- failure, reset, resync, or presentation behavior; or
- native, Vite, and packaged route equivalence.

Basis: MAP-U2.

### MAP-R7 — Worktree Annotation catalog contract

The Worktree Annotation metadata application MUST use one catalog whose entries
form this normalized relationship:

```text
session entry
  session ID
  session semantic revision

thread entry
  thread ID
  parent session ID
  scope: located | whole_file | session
  created ordinal

message entry
  message ID
  parent thread ID
  message ordinal
```

The committed catalog MUST contain each identity at most once. Every thread
MUST reference a known session. Every message MUST reference a known thread.
Thread ordinals MUST be unique within a session and message ordinals MUST be
unique within a thread. Ordered indexes derived from those ordinals MUST be
deterministic.

The catalog MUST NOT contain message bodies, draft bodies, edit tokens, saved
bodies, source excerpts, immutable origin payloads, current placement,
output-history records, exact output bytes, raw filesystem paths, or Git
continuity evidence.

Every annotation catalog and small annotation change event MUST carry one
common application authority containing the worktree identity and annotation
application source generation. That generation MUST equal the generic frame's
source generation. A catalog transfer's catalog revision MUST be the same
service-owned application generation captured with its entries.

Basis: MAP-U3, MAP-U4.

### MAP-R8 — Catalog presence is independent of content readiness

An active annotation catalog MUST make sessions, threads, messages, parent
relationships, scope, ordering, and session semantic revision addressable even
when no rich session content is demanded.

For every catalog session, rich content MUST expose one of these distinct
states:

```text
not demanded
loading(required semantic revision)
ready(semantic revision, complete content)
stale(required semantic revision, retained last complete content)
unavailable(required semantic revision, optional retained content)
```

`not demanded`, `loading`, `stale`, and `unavailable` MUST NOT be interpreted as
a confirmed empty session. A confirmed session with zero threads or messages
requires complete ready content at the catalog's applicable semantic revision.

The existing demand-independent annotation control read MUST remain separate
from both the catalog and rich session content. For every active annotation
surface it MUST provide current recovery status and session control summaries
needed to choose or gate demand, including session identity, semantic revision,
lifecycle, source relationship, and applicable foreign-candidate disposition.
It MUST NOT hydrate undemanded message bodies, drafts, origin, placement,
history, or output bytes.

An active surface MUST use that control read to distinguish no applicable
session, one applicable living session, several applicable sessions, uncertain
continuity, detached/completed sessions, and recovered-degraded or unavailable
storage before acquiring rich session demand. Catalog presence alone MUST NOT
authorize mutation or be treated as recovery health.

Basis: MAP-U3, MAP-U4.

### MAP-R9 — Existing session demand owns rich annotation loading

The existing Worktree Annotation demand acquire/release contract MUST remain
session-granular. While a session is demanded, the worker MAY request its rich
content through the existing typed projection query and finite content route.
When a session is not demanded, its catalog entry remains addressable but its
rich content MUST NOT be fetched merely because the catalog exists.

Native MUST continue to validate pane, worker, surface, source generation,
Review publication when applicable, worktree association, and demanded session
identity before issuing or serving rich annotation content.

Thread/message-level demand, catalog-driven prefetch of every session, and a
new content transport are outside this contract.

The finite annotation projection MAY return the demand-independent control
snapshot on an empty demanded-session list. Adding demanded session identities
to that request adds only those sessions' rich content. Control-summary and
recovery refresh therefore reuse the existing projection query/content route
without making undemanded content eager.

Basis: MAP-U4.

### MAP-R10 — Content-state mutation uses a small session-change event

When a durable annotation mutation changes content state without changing the
session/thread/message association catalog, the annotation application MUST
publish the affected worktree, session identity, and newest committed session
semantic revision as one small typed change event. It MUST NOT publish a
replacement catalog solely because a body, draft, viewed state, handled state,
resolution, placement-input revision, or other non-topology session content
changed.

On receiving a newer session-change revision:

- a currently demanded session MUST become stale and request one current rich
  replacement under existing coalescing/currentness policy;
- an undemanded session MUST record the newer required revision without
  fetching rich content; and
- an equal or older revision MUST NOT schedule duplicate work.

Intermediate session-change revisions MAY coalesce to the newest revision.
SQLite remains the durable truth.

Lifecycle, source-relationship, foreign-candidate, or recovery changes that may
alter relevant-session choice or mutation admission MUST additionally mark the
demand-independent control snapshot stale. An active surface MUST refresh that
control snapshot even when no rich session is demanded. A body-only change to
an undemanded session MUST NOT do so.

Basis: MAP-U5.

### MAP-R11 — Topology and association changes replace the catalog

Creating or removing a session, thread, or message; changing a thread's parent
or catalog scope; moving a session association between worktrees; bootstrap;
recovery replacement; and subscription reset/reconnect MUST converge through a
complete bounded catalog replacement for each affected worktree.

When a session moves from worktree A to worktree B, both A and B MUST receive
new catalog revisions. Until each replacement commits, that worktree retains
its previous complete catalog as stale. The same durable session, thread,
message, draft, and output identities MUST be preserved by reassociation.

Catalog commit MUST reconcile current session demand. Rich content for a
removed or foreign-associated session MUST no longer install into the current
worktree. A retained demanded session whose catalog semantic revision advanced
MUST refresh under MAP-R10 and MAP-R9.

The post-commit active catalog MUST be bound to the subscription, worker epoch,
worktree, and application source generation that admitted it. Reset, source or
worker replacement, and reconnect MUST discard any candidate and mark the
retained active catalog stale against the expected new authority. A stale
catalog MAY remain visible, but MUST NOT establish current empty state, current
output membership, current mutation admission, or install authority for a rich
result. Only a complete replacement commit binds the catalog to the new
authority and makes it current.

Basis: MAP-U3, MAP-U6 and Worktree Annotation continuity authority.

### MAP-R12 — Exact commands remain independent

An annotation mutation's exact typed response MUST remain its initiating
caller's success, failure, conflict, or admission result. A committed canonical
message receipt MUST be presented before the command resolves. Catalog
replacement, session-change notification, rich-content query, or projection
failure MUST NOT keep a committed Save busy, remove its command-confirmed
message, or reinterpret commit as failure.

Command-confirmed overlays MUST remain excluded from authoritative New/All
output membership until complete current rich content reconciles the exact
message revision and output fences.

Basis: MAP-U7; P1-U2 and P1-U3.

### MAP-R13 — Application and transfer lifecycle follows pane authority

Application metadata subscriptions MUST retain the existing pane/product
session authority, worker-replacement, active/hidden, reset, cancellation, and
close behavior. This protocol does not create an independent lifecycle or
promote browser visibility into native authority.

Catalog candidates and rich-content attempts MUST be cancelled or made stale
when their subscription, worker, source generation, Review publication, pane
admission, or product session is replaced or closed. Returning authority MUST
reopen through current subscription/bootstrap behavior rather than continuing
an obsolete candidate.

Basis: MAP-U2, MAP-U4.

### MAP-R14 — Capacity and performance boundaries

The metadata route MUST remain body-free for Worktree Annotations. Each catalog
window MUST fit the existing metadata-frame ceiling, and the receiver MUST own
at most one active and one candidate catalog per annotation subscription.

Normal content-state mutations MUST transfer one bounded session-change event,
not the complete catalog. Catalog replacement cost is admitted only for
bootstrap/reset/recovery or topology/association change. Existing metadata
acknowledgement and producer backpressure MUST apply to every catalog window.

If measurement later proves topology replacement cost unacceptable, a typed
catalog-delta extension MAY be designed separately. This specification does not
define delta/tombstone semantics.

Basis: MAP-U5, MAP-U6.

### MAP-R15 — Equivalent development and packaged contracts

The Swift development backend MUST expose the same subscription registration,
raw-to-typed validation, catalog phases, source generation, session-change,
reset, and finite rich-content semantics as the packaged URL-scheme transport.
Vite and HTTP adapters MUST remain carriers, not alternate application owners.

A new application protocol MUST behave equivalently through native URL-scheme
and development HTTP adapters without application-specific behavior in the
proxy.

Basis: MAP-U8.

## Observable application contract

| Contract slot | Required behavior |
| --- | --- |
| Consumer | registered native producer and communication-worker consumer |
| Input | registered subscription kind plus strict options/interests/events |
| Success | generic envelope accepted, application schema accepted, typed event delivered once in sequence |
| Unknown kind | reject without application state change |
| Malformed event | terminate or reset according to existing subscription failure behavior; do not partially apply |
| Generation mismatch | reject before application state change |
| Sequence gap | existing subscription failure/reset behavior; no application reordering |
| Cancellation/close | no post-terminal application events |
| Compatibility | File and Review current contracts remain byte/behavior compatible within this hard cutover |

## Worktree Annotation sequences

### Bootstrap and first demand

```text
open annotation subscription
  → subscription accepted
  → catalog begin
  → bounded catalog windows
  → catalog commit
  → install complete ID/association catalog
  → query current recovery and session-control summaries with empty rich demand
  → choose or gate the relevant session
  → acquire demand for relevant session
  → existing projection query returns descriptor
  → existing content route returns complete rich session replacement
  → install rich content at exact semantic/source revision
```

### Save or other content-only mutation

```text
ordered annotation command
  → SQLite transaction commits
  → exact canonical command response settles initiating UI
  → session changed(session ID, semantic revision)
      → demanded: mark stale and query current rich session
      → undemanded: record required revision only
  → complete rich replacement reconciles exact receipt
```

### Reply/root creation or removal

```text
ordered annotation command
  → SQLite topology transaction commits
  → exact canonical receipt/tombstone settles initiating UI
  → bounded catalog replacement
  → commit changes session/thread/message relationship maps atomically
  → currently demanded affected session refreshes rich content
```

### Session reassociation

```text
fenced Continue command
  → one SQLite transaction moves the existing session association
  → exact command result
  → old worktree catalog replacement
  → new worktree catalog replacement
  → each worker reconciles demand only after its own catalog commit
```

### Reset, reconnect, and malformed replacement

```text
active catalog A
  → candidate B begins
  → reset/error/current-candidate defect/supersession
  → discard B
  → retain A as stale
  → reopen/bootstrap
  → complete candidate C commits
  → atomically replace A with C
```

## Reliability and quality obligations

- Strict application schemas MUST reject unknown members and invalid
  discriminants before application state changes.
- Generic transport telemetry MAY identify application kind, transfer phase,
  revision, window ordinal/count, entry count, byte count, result, and latency.
  It MUST NOT export application catalog entries or annotation content.
- Worktree Annotation telemetry MUST NOT export bodies, drafts, paths, origins,
  session/thread/message IDs, edit tokens, output bytes, or SQL errors.
- Catalog assembly MUST not block the main React thread; only a complete bounded
  catalog projection may become active. A catalog that required multiple native
  metadata windows MUST reach the main presentation owner through bounded
  worker-to-main staging units on the existing port and a hidden candidate
  bank. React MUST continue reading the prior active bank until one lightweight
  final commit swaps the candidate active.
- This change introduces no external network dependency and no new security or
  authorization behavior.

## Explicit negative space

This specification does not define:

- a fourth physical transport route;
- dynamic protocol installation or wire-supplied executable behavior;
- a replacement for File/Review metadata event semantics;
- a second Worktree Annotation presentation store;
- eager hydration of every catalog entry;
- thread/message-granularity annotation demand;
- catalog delta or tombstone events;
- a durable catalog-transfer log;
- new annotation persistence fields or migration;
- new user interface, output membership, placement, or continuity semantics;
- weaker validation, sequence, generation, acknowledgement, or backpressure
  rules.

## Requirement-to-proof coverage

| Requirements | Required evidence class |
| --- | --- |
| MAP-R1, MAP-R2, MAP-R3 | schema/type behavior and Swift/TypeScript transport integration proving unknown-to-typed validation, duplicate/unknown registration rejection, sequence/generation mismatch rejection, and no generic transport edit for a fixture application |
| MAP-R4, MAP-R5 | automated transfer state-machine behavior for packing, multi-window commit, replay, supersession, reset, malformed/missing/duplicate/out-of-order windows, frame ceiling, and last-complete retention |
| MAP-R6 | existing File and Review unit/integration/browser behavior plus wire fixture parity across the registry cutover |
| MAP-R7, MAP-R8 | repository/catalog projection and worker/store behavior proving normalized relationships, deterministic order, catalog-only state, and no false empty content |
| MAP-R9, MAP-R10 | session-demand and coalescing behavior proving demanded refresh, undemanded no-fetch, equal/older suppression, and body-free metadata |
| MAP-R11 | repository/Swift/worker integration for create/remove/reassociate, old/new worktree catalog replacement, stale rich-result rejection, and identity preservation |
| MAP-R12 | browser behavior proving exact Save settlement and overlay retention while catalog/content replacement is delayed or fails |
| MAP-R13 | worker replacement, reset/reconnect, inactive/reactivation, close/drain, and post-terminal rejection evidence |
| MAP-R14 | frame/entry packing, active/candidate capacity inspection, message-edit transfer measurement, and metadata backpressure evidence |
| MAP-R15 | real Vite + production comm worker + Swift development backend + SQLite journey and packaged WKWebView compatibility evidence |

## Traceability

```text
MAP-U1 → MAP-R1, R2, R3
MAP-U2 → MAP-R3, R6, R13
MAP-U3 → MAP-R7, R8, R11
MAP-U4 → MAP-R8, R9, R13
MAP-U5 → MAP-R10, R14
MAP-U6 → MAP-R4, R5, R11, R14
MAP-U7 → MAP-R12
MAP-U8 → MAP-R15
```
