# Bridge Metadata Application Protocol — Requirements

## Purpose

Bridge already transports File and Review metadata separately from demanded
content. Adding another metadata-bearing Bridge capability still requires
editing central Swift and TypeScript transport unions that know every
application payload. Worktree Annotations currently compounds that coupling by
pushing only a generic stale-snapshot notification, then loading session
summaries and demanded thread/message details through one combined projection.

This work makes application metadata a registered typed use of the existing
pane-scoped transport and makes bounded atomic catalog replacement reusable.
Worktree Annotations is the first new catalog consumer: its lightweight
session, thread, message, and scope relationships remain continuously
available, while bodies, drafts, source origin, placement, history, and output
bytes remain demand-loaded.

## Authority and sources

- Decision owner: Agent Studio owner.
- Owner-confirmed direction: the 2026-08-27 conversation establishing a
  generic Bridge metadata application protocol, generic bounded catalog
  transfer, and Worktree Annotations as its first new consumer.
- Governing annotation needs:
  [`../2026-08-06-worktree-annotations/pr1-user-requirements.md`](../2026-08-06-worktree-annotations/pr1-user-requirements.md).
- Governing transport architecture:
  [`../../architecture/bridge/bridge_product_transport_architecture.md`](../../architecture/bridge/bridge_product_transport_architecture.md),
  [`../../architecture/bridge/bridge_web_runtime_architecture.md`](../../architecture/bridge/bridge_web_runtime_architecture.md), and
  [`../../architecture/bridge/bridge_native_runtime_architecture.md`](../../architecture/bridge/bridge_native_runtime_architecture.md).
- Current code and the annotation catalog research ledger are observational
  evidence. They do not authorize wider product behavior.

## Affected classes

### Bridge application developer

Adds or evolves a typed metadata-bearing Bridge capability. The developer needs
to define application schemas and handlers without modifying stream sequencing,
subscription lifecycle, queueing, acknowledgement, frame bounds, or
backpressure machinery.

### Human reviewer

Uses Worktree Annotations in File and Review. The reviewer needs annotation
identity and membership to remain truthful while rich content is not demanded,
refreshing, unavailable, or delayed, without making Save wait for read-model
convergence.

### Working agent

Consumes copied Markdown or exported JSON produced from complete current
annotation content. The working agent must never receive fabricated empty,
partial, or mixed-revision annotation membership.

## Authorized needs

### MAP-U1 — Add metadata applications without reopening transport mechanics

- Affected class: Bridge application developer.
- Need: A new Bridge metadata application defines and registers its own typed
  subscription options, interest updates, events, and source-generation
  relationship without adding application cases to generic stream,
  subscription, queue, acknowledgement, frame-bound, or backpressure owners.
- Why: The physical transport already owns delivery mechanics; central payload
  unions make those mechanics change for unrelated domain additions.
- Evidence: owner confirmation on 2026-08-27 and current central Swift and
  TypeScript application unions.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U2 — Preserve File and Review behavior through the cutover

- Affected classes: human reviewer and Bridge application developer.
- Need: File and Review retain their current metadata events, source and
  publication fences, incremental application, demand derivation, content
  loading, failure behavior, and presentation while becoming registered
  applications of the generic boundary.
- Why: Generic transport reuse is not permission to redesign the two working
  applications or their UI.
- Evidence: current Bridge architecture and owner confirmation on 2026-08-27.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U3 — Know annotation identity before loading annotation details

- Affected class: human reviewer.
- Need: An active Worktree Annotation surface can know which sessions, threads,
  and messages exist and how they belong together without loading message
  bodies, drafts, source origin, placement, history, or output bytes for every
  session.
- Why: Identity and membership drive discovery, continuity, selection, and
  truthful loading states; they should not require the expensive content they
  address.
- Evidence: owner confirmation on 2026-08-27; P1-U1, P1-U2, P1-U3, P1-U13, and
  P1-U14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U4 — Load rich annotation content only from current demand

- Affected classes: human reviewer and Bridge application developer.
- Need: Worktree Annotation bodies, drafts, source origin, placement, and other
  rich details load through the existing session-level demand and finite
  content path. An undemanded session remains identifiable but does not load its
  rich content.
- Why: File and Review already separate addressable metadata from demanded
  bytes; annotations need the same performance and ownership boundary.
- Evidence: owner confirmation on 2026-08-27; current annotation demand and
  projection contracts.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U5 — Make ordinary annotation edits cheap and truthful

- Affected class: human reviewer.
- Need: A body, draft, viewed, handled, or other content-state mutation that
  leaves the annotation identity relationships unchanged communicates the
  changed session identity and semantic revision without retransferring the
  complete annotation catalog. Only a currently demanded changed session
  triggers rich-content refresh.
- Why: Typing and saving are common; repeating the whole ID hierarchy for every
  edit wastes work and recreates the responsiveness problem this boundary is
  meant to solve.
- Evidence: owner confirmation on 2026-08-27; P1-U2, P1-U3, and P1-U14.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U6 — Replace large catalogs completely or not at all

- Affected classes: human reviewer and Bridge application developer.
- Need: A catalog larger than one metadata frame transfers in bounded pieces.
  Consumers continue using the last complete catalog until every piece of the
  replacement is accepted and the replacement commits. Reset, reconnect,
  cancellation, malformed input, missing pieces, or supersession cannot expose
  a partial catalog.
- Why: Metadata frames are bounded and annotation identity must not disappear or
  become partially related while replacement is in flight.
- Evidence: owner confirmation on 2026-08-27; current 128 KiB metadata-frame
  ceiling and Review final-barrier precedent.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U7 — Keep command completion independent from background convergence

- Affected class: human reviewer.
- Need: Exact annotation command success or failure remains the initiating
  interaction's terminal result. Catalog transfer and rich-content refresh
  reconcile shared state afterward and cannot keep a committed Save busy, hide
  its exact result, or convert it into failure.
- Why: Mutation authority and read-model convergence are separate boundaries.
- Evidence: P1-U2 and P1-U3 plus owner confirmation on 2026-08-27.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U8 — Keep native, Vite, and packaged behavior equivalent

- Affected classes: human reviewer and Bridge application developer.
- Need: The Swift development backend, Vite proxy, production communication
  worker, and packaged WKWebView use the same application protocol, catalog
  transfer, sequence, reset, and content-demand semantics.
- Why: Direct repository or HTTP success does not prove the browser-to-native
  system that developers and reviewers actually use.
- Evidence: PR1 acceptable proof boundary and owner confirmation on 2026-08-27.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

### MAP-U9 — Make first selected File and Review content usable promptly

- Affected classes: human reviewer and Bridge application developer.
- Need: With the development backend already ready, File and Review metadata,
  initial selection, and the first selected preview become usable within one
  second on the repository-owned real-worktree startup journey. Remaining
  progressive metadata may continue streaming afterward and must not delay
  content whose source authority and metadata member are already admitted.
- Why: Early metadata is not useful when the selected content remains blocked
  behind unrelated enumeration of the rest of a large worktree.
- Evidence: owner confirmation and real-worktree measurements on 2026-08-30;
  File metadata and selection completed within one second while File preview
  required 1.44–1.82 seconds. Review completed within 0.43–0.51 seconds.
- Authority: authorized.
- Priority: must, assigned by the Agent Studio owner.
- Hypothesis state: none.

## Goal boundary

- Primary goal: make typed Bridge metadata applications register behind one
  generic transport boundary and use that boundary to separate Worktree
  Annotation identity catalogs from demanded rich content.
- Existing foundation to preserve: one pane metadata stream, generic stream and
  subscription sequencing, acknowledgements and backpressure, three physical
  routes, one communication worker per pane, existing File and Review metadata
  protocols, existing Worktree Annotation commands, session demand, finite
  projection/content, SQLite authority, exact command receipts, and Vite/native
  adapters.
- Missing capabilities: application-owned schema registration outside central
  transport unions; reusable bounded atomic catalog transfer; a lightweight
  Worktree Annotation association catalog; catalog/content-separated browser
  state; content-only session-change notification.
- Allowed surface: existing Bridge Swift transport and metadata owners,
  BridgeWeb communication-worker transport and subscription owners, Worktree
  Annotation repository/service/transport/store owners, and existing proof
  harnesses.
- Protected surface: File and Review observable behavior except the authorized
  first-selected-content latency correction in MAP-U9; annotation durable
  identities and persistence semantics, command behavior, output semantics,
  source placement, native pane authority, demand scheduling, render
  backpressure, and the three physical routes.
- Non-goals: File or Review behavioral redesign beyond MAP-U9; UI redesign; a
  new physical route, port, queue, scheduler, atom, coordinator, or persistence
  boundary;
  dynamic runtime plugin discovery; application-defined executable code from
  the wire; thread/message-level annotation demand; delta-first annotation
  catalog replication; annotation database migration; a new authentication or
  security system.
- Complexity limit: use a static typed protocol registry, one reusable catalog
  transfer contract, one reusable writer/assembler pair, and existing
  application owners. Any additional physical transport, durable transfer log,
  independent scheduler, or alternate compatibility path requires renewed
  owner approval.
- Acceptable outcome evidence: schema and state-machine behavior; File/Review
  compatibility evidence; repository and Swift transport integration; real
  Vite/production-worker/Swift-backend/SQLite annotation journeys; reset,
  restart, delayed-content, and malformed-transfer cases; packaged File and
  Review annotation interaction; ready-backend real-worktree startup timing
  for metadata and first selected content; current-head lint and aggregate
  tests.

## Confirmed decisions

```text
raw transport payload
  enters as unknown
  becomes typed only through the registered application schema

application registration
  static and typed
  unknown or unregistered kinds fail closed

catalog transfer
  generic begin → bounded windows → commit
  last complete catalog remains active until commit

Worktree Annotation metadata
  session/thread/message IDs, parent relationships, scope, ordering,
  session semantic revision

Worktree Annotation rich content
  bodies, drafts, origin, placement, history, output bytes
  loaded only through existing demand/query/content owners

ordinary content-state mutation
  session changed + semantic revision
  refresh rich content only when that session is demanded

topology, association, bootstrap, and reset
  bounded complete catalog replacement

File and Review
  register current protocols without changing their behavior except that
  admitted File demand need not wait for unrelated remaining tree enumeration
```
