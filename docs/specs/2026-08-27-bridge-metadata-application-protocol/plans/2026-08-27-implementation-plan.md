# Bridge Metadata Application Protocol — Implementation Plan

Planning result: ready

Originating planner: `plan-implementation`

## Governing planning basis

Kind: reviewed three-artifact design

- Requirements:
  [`../2026-08-27-requirements.md`](../2026-08-27-requirements.md)
- Specification:
  [`../2026-08-27-specification.md`](../2026-08-27-specification.md)
- Program Design:
  [`../2026-08-27-program-design.md`](../2026-08-27-program-design.md)
- Independent review invocation:
  `bridge-metadata-application-protocol-three-artifact-review-20260827`
- Review result: `needs-revision` with six accepted findings
  `MAP-REV-C1` through `MAP-REV-C6`.
- Remediation result: one Specification → Program Design correction round;
  parent-verified current anchors cover complete registration, control-state
  preservation, annotation authority/generation, transfer precedence,
  catalog currentness, and bounded worker-to-main staging.
- Governing annotation behavior:
  [`../../2026-08-06-worktree-annotations/pr1-user-requirements.md`](../../2026-08-06-worktree-annotations/pr1-user-requirements.md),
  [`../../2026-08-06-worktree-annotations/pr1-specification.md`](../../2026-08-06-worktree-annotations/pr1-specification.md), and
  [`../../2026-08-06-worktree-annotations/pr1-program-design.md`](../../2026-08-06-worktree-annotations/pr1-program-design.md).
- Current transport architecture:
  [`../../../architecture/bridge/bridge_product_transport_architecture.md`](../../../architecture/bridge/bridge_product_transport_architecture.md),
  [`../../../architecture/bridge/bridge_web_runtime_architecture.md`](../../../architecture/bridge/bridge_web_runtime_architecture.md), and
  [`../../../architecture/bridge/bridge_native_runtime_architecture.md`](../../../architecture/bridge/bridge_native_runtime_architecture.md).

Current applicability anchors:

- planned at branch `bridge-review-design-2026-08-14`;
- planned at HEAD `458a057043c45ca388e5a59fa8281f352f300a69`;
- current Swift central application union:
  `BridgeProductSubscriptionData` in
  `BridgeProductSubscriptionContracts.swift`;
- current TypeScript central application union:
  `bridgeProductSubscriptionDataFrameSchema` in
  `bridge-product-session-contracts.ts`;
- current annotation notification is only `snapshot.required`;
- current repository projection loads all session summaries and rich details
  only for demanded session IDs;
- current browser annotation store replaces summaries and hydrated
  threads/messages as one snapshot.

The workspace contains concurrent user/agent changes, including uncommitted
Review UI/publication work and uncommitted annotation association repository
work. Those changes are not cleanup targets. Before each slice, re-read the
exact overlapping files and preserve or sequence with their owner.

## Delivery context

- Requested terminal: `plan-only`.
- Delivery grouping: `single:bridge-metadata-application-protocol`.
- PR topology: `not-applicable` for this plan-only result. If the owner later
  authorizes continued delivery, the smallest coherent implementation is one
  PR because Swift and TypeScript hard-cut one wire/application boundary and no
  mixed-version state is supported.
- Tracking: none selected.

## Goal

Make Bridge application metadata statically register behind one generic typed
transport boundary, add reusable bounded atomic catalog transfer, and use it to
keep Worktree Annotation IDs/relationships continuously available while rich
annotation details remain on existing session demand and finite content paths.

File and Review keep their current events, semantics, demand, source/publication
fences, and presentation. Exact annotation command results remain independent
from catalog and rich-content convergence.

## Scope and protected boundaries

In scope:

- static Swift and TypeScript metadata application registrations;
- generic raw-envelope → registered-schema → typed-event validation;
- registered surface/source lifecycle, initial-open conversion, empty/target
  interest state, delta construction/accounting, event generation, and native
  source binding;
- generic begin/window/commit catalog writer and assembler;
- bounded hidden worker-to-main catalog staging on the existing port/store;
- lightweight Worktree Annotation catalog SQL projection;
- service-owned application generation and content/control/catalog change
  classification;
- Worktree Annotation catalog, control, content, and exact-command overlay
  separation in the existing store;
- old/new worktree catalog replacement after reassociation;
- native, worker, Vite, SQLite, packaged, performance, and aggregate proof.

Protected:

- three physical Bridge routes and one pane worker;
- generic stream/subscription sequence, barriers, queueing, acknowledgement,
  backpressure, reset/end/error, and producer drain;
- File and Review wire events and behavior;
- Worktree Annotation SQLite identities and schema;
- session-level demand, projection paging, source/placement authority, output
  semantics, command receipts, and current UI design;
- unrelated dirty work.

Out of scope:

- new route, port, queue, scheduler, persistence owner, atom, coordinator, or
  UI surface;
- dynamic runtime protocol installation;
- File/Review behavioral rewrite;
- annotation catalog deltas/tombstones;
- thread/message-level annotation demand;
- database migration;
- new authentication or security behavior;
- broad refactors unrelated to eliminating the named central application
  switches or realizing the catalog/content split.

## Dependency graph

```text
Precondition P0: reconcile current HEAD and overlapping dirty ownership
  │
  ▼
S1 Generic application registry hard cutover
  │
  ├───────────────┐
  ▼               ▼
S2 Catalog        S3 Native annotation catalog/change source
transfer          (S3 also requires current association repository slice)
  │               │
  └───────┬───────┘
          ▼
S4 Worker/main annotation catalog-control-content integration
          │
          ▼
S5 Real backend, Vite, packaged, performance, and aggregate proof
```

Necessary edges:

- `S1 → S2`: catalog events must travel through registered application
  protocols rather than create another central-union exception.
- `P0 → S3`: association repository changes overlap native catalog owners and
  must be understood/landed before transport edits those files.
- `S2 + S3 → S4`: the worker requires both generic transfer semantics and the
  actual annotation producer contract.
- `S4 → S5`: broad proof must observe the completed production path, not
  fixtures standing in for missing wiring.

## Obligation and proof map

| Obligations | Owner/change | Proof that can distinguish pass from fail |
| --- | --- | --- |
| MAP-R1–R3 | generic Swift/TS registries and preserved transport mechanics | fixture application registers with empty interests without generic switches; malformed/unknown/generation-mismatched inputs fail before application state |
| MAP-R4–R5 | full-frame-measured writer, precedence-aware assembler, authority-bound active/candidate state | multi-window, zero-entry, oversized-entry, late superseded frame, current-candidate defect, replay, reset and reopen state-machine tests |
| MAP-R6 | File/Review registered adapters | existing contract, metadata applicator, interest, browser, and source/publication regression suites remain green with unchanged fixtures |
| MAP-R7–R8 | lightweight repository catalog plus existing control-summary/recovery read and store banks | real SQLite excludes rich columns; empty-rich-demand selects/gates session; recovery never appears ready-empty |
| MAP-R9–R10 | existing session demand plus session/control change events | demanded refreshes; undemanded body change fetches nothing; control/recovery change refreshes summaries without bodies; old/equal revisions suppress |
| MAP-R11 | topology classification and old/new catalog replacement | create/remove/reassociate races preserve IDs and reject stale rich installs; both worktrees converge after restart |
| MAP-R12 | existing exact command receipts/overlays | Save settles before delayed/failed catalog/content replacement; editor/message remains; Share stays non-authoritative until reconciliation |
| MAP-R13 | existing lifecycle owners plus authority-bound catalog bank | worker/source replacement, reset, inactive/reactivation, close/drain and post-terminal rejection |
| MAP-R14 | bounded native frames and worker-to-main hidden staging | large catalog shows bounded frame and port units, one active+candidate per boundary, no partial React membership, no main-thread long task |
| MAP-R15 | unchanged packaged and development carriers | real Vite production worker → Swift backend → file-backed SQLite journey, then packaged WKWebView File/Review proof |

## P0 — Re-anchor and secure the existing checkpoints

Purpose: prevent this transport work from overwriting concurrent UI,
publication, or association work.

Read before any edit:

- `git status --short`, current HEAD/log, and the complete scoped diff;
- `docs/wip/communications/2026-08-20-share-comments-backend-ui-coordination-log.md`;
- current Worktree Annotation repository access/loading/lifecycle files and
  their association tests;
- current Review main-publication/store files changed by the UI/publication
  agent;
- current render-disposition admission and fulfillment clock/replacement paths
  in `bridge-main-render-disposition-admission.ts`,
  `bridge-main-render-fulfillment-coordinator.ts`,
  `bridge-worker-render-fulfillment.ts`, and
  `bridge-worker-render-fulfillment-registry.ts`;
- this complete plan and all three governing artifacts.

Required state:

- the uncommitted association repository slice has a named owner and passing
  focused proof or is committed as its existing green checkpoint;
- transport implementation does not begin in a second worktree copy of those
  same uncommitted files;
- later concurrent commits are re-anchored before every slice;
- a separately accepted transport correction eliminates the existing
  cross-realm receipt-lease clock comparison and includes an offset-clock
  worker-replacement proof;
- the existing render-disposition `stalled` state has an implemented recovery
  owner and proof that delivery resumes;
- those transport-remediation checkpoints land before S1; this plan consumes
  them and does not redesign receipt delivery as metadata-application work.

Proof:

- current repository/association focused tests remain 15/15 or better;
- offset-clock worker-replacement regression proves the receipt lease cannot
  compare unrelated Main/worker clock origins;
- stalled-disposition recovery regression proves queued receipts resume under
  the separately accepted recovery owner;
- format/lint/diff checks reported by that slice remain reproducible;
- no unrelated file appears in the transport slice diff.

Stop/replan:

- association semantics, session control summaries, or UI/store ownership have
  changed from the reviewed design;
- the current owner cannot provide a stable overlapping checkpoint;
- proceeding would require discarding or rewriting concurrent work.

## S1 — Generic application registry hard cutover

Type: vertical contract/cutover slice.

Obligations: MAP-R1, MAP-R2, MAP-R3, MAP-R6, and the registration part of
MAP-R15.

Primary write surfaces:

Swift:

- `BridgeProductSubscriptionContracts.swift`;
- `BridgeProductSubscriptionInterestContracts.swift`;
- `BridgeProductSubscriptionInterestStateCodec.swift`;
- `BridgeProductSubscriptionRuntimeFactories.swift`;
- `BridgeProductSubscriptionState.swift`;
- `BridgeProductSubscriptionInterestMutation.swift`;
- `BridgePaneProductMetadataCoordinator+SubscriptionProducers.swift` and
  the narrow coordinator registration/composition surface.

TypeScript:

- `bridge-product-session-contracts.ts`;
- `bridge-product-subscription-contracts.ts`;
- `bridge-product-subscription-state.ts`;
- `bridge-product-transport.ts`;
- new narrowly named metadata application protocol/registry modules under
  `BridgeWeb/src/core/comm-worker/`;
- existing File/Review protocol schema modules as registrations, not rewrites.

RED first:

- a fixture protocol with empty interests cannot currently register without
  editing central kind/surface/options/interest/event/source switches;
- duplicate and unknown registrations are not centrally rejected because no
  registry exists;
- raw application `data` is currently validated by the central payload union.

Implementation behavior:

1. Introduce typed protocol definition and one static registry per language.
2. Move surface/source binding, initial-open conversion, empty/target interest
   state, application delta construction/accounting, event schema, and
   generation reader into registrations.
3. Keep generic batching, barriers, queueing, sequence, acknowledgement,
   backpressure, reset/end/error, task replacement, and drain in current owners.
4. Register `file.annotations`, `file.metadata`, `review.annotations`, and
   `review.metadata` using unchanged wire/event contracts. The two annotation
   registrations share their existing event schema/source helper while
   retaining distinct kind, surface, and source authority.
5. Decode the generic raw envelope before registry validation; no application
   consumer accepts `unknown`.
6. Remove central application payload/control/source switches in the same
   hard-cut slice.

Focused proof:

- Swift subscription/session/coordinator unit and integration tests;
- TypeScript session-contract, subscription-contract/state, transport, and
  comm-worker entry tests;
- fixture application proof in both languages;
- File and Review metadata applicator/source/publication regression tests;
- File and Review annotation `snapshot.required` subscription parity tests;
- exact raw/typed fixtures and interest hash/delta parity.

Integration gate G1:

Run the complete BridgeWeb unit/integration lanes plus focused Swift product
session/metadata coordinator tests. File and Review must open, update interests,
receive typed events, reset, and close through registrations with unchanged
observable fixtures.

Safe checkpoint:

Commit only when Swift and TypeScript both use the registry, all central
application switches named by the design are gone, and G1 is green. Do not
checkpoint a mixed old/new wire path as working.

Stop/replan:

- preserving File/Review requires changing their application semantics;
- the registration must own generic sequencing/backpressure policy rather than
  only application transformation/source binding;
- a future fixture still requires edits to generic transport mechanics.

## S2 — Generic bounded catalog transfer across both process boundaries

Type: reusable vertical contract slice; first consumed by S4.

Obligations: MAP-R4, MAP-R5, and MAP-R14.

Primary write surfaces:

- new Swift metadata catalog transfer contracts and writer beside current
  metadata frame/producer contracts;
- new TypeScript catalog transfer schema, assembler, and bounded staging helper
  under `BridgeWeb/src/core/comm-worker/`;
- worker-to-main contracts in `bridge-worker-annotation-contracts.ts`,
  `bridge-worker-contracts.ts`, and RPC client/server routing;
- candidate-bank behavior in the existing annotation projection store test
  surface; application-specific production wiring waits for S4.

RED first:

- multi-frame catalogs have no generic begin/window/commit contract;
- late B frames can damage an unmodeled newer C candidate;
- one native multi-window result can only become one whole worker-to-main
  annotation convergence publication today;
- reset during main staging has no hidden candidate to discard.

Implementation behavior:

1. Define strict begin/window/commit transfer schemas with complete entries,
   zero-entry behavior, revision/identity/ordinal/count rules.
2. Swift writer packs by measuring the prospective full encoded metadata frame,
   never estimates payload-only size and never splits one entry.
3. Worker assembler implements the reviewed precedence rules: newer begin may
   supersede; noncurrent frames have no state effect; current-candidate defects
   discard only that candidate; committed replay is rejected.
4. Reuse the same semantics for bounded worker-to-main normalized staging on
   the existing port.
5. Main candidate bank remains hidden until a lightweight final commit; reset
   discards candidate and preserves active state as stale.
6. Scope revision precedence to one lifecycle-admitted authority. Replacement
   clears the worker and main numeric comparison baselines; the first begin for
   the expected new authority is admitted even when its revision is equal to or
   lower than the retained stale catalog, while unexpected authorities remain
   rejected.

Focused proof:

- deterministic writer packing at/over the frame ceiling and an entry that
  cannot fit alone;
- assembler table/state-machine tests covering A/B/C supersession and replay;
- authority replacement tests covering a high retained revision followed by an
  equal or lower revision under the expected new authority, plus rejection of
  equal/older same-authority and unexpected-authority begins;
- bounded worker port units, hidden main candidate, one final presentation
  revision, and reset during staging;
- resource inspection: one active plus at most one candidate per boundary.

Integration gate G2:

A fixture catalog much larger than one metadata frame traverses native writer,
generic stream, worker assembler, bounded existing worker port, hidden main
bank, and final commit without exposing partial state or creating a main-thread
long task.

Safe checkpoint:

Commit generic transfer only after G2 is green and no annotation, File, or
Review domain fields appear in generic helpers.

Stop/replan:

- the existing worker port cannot stage bounded units without another queue or
  route;
- atomic visibility requires an additional presentation store;
- a total-size policy or transfer lifecycle remains undefined.

## S3 — Native Worktree Annotation catalog and classified changes

Type: annotation native vertical/contract slice; consumed by S4.

Obligations: MAP-R7, MAP-R10, MAP-R11, MAP-R13, and native portions of R8/R9.

Primary write surfaces:

- `WorktreeAnnotationRepositoryAccess.swift` and datastore adapter;
- one focused repository catalog-loading extension rather than enlarging
  `WorktreeAnnotationSQLiteRepository+Loading.swift` past its current size;
- `WorktreeAnnotationServiceActor.swift` and narrow runtime models;
- Worktree Annotation transport event contracts;
- `BridgePaneProductWorktreeAnnotationNotificationSource.swift`;
- development host/adapters only where generic registration requires wiring.

RED first:

- repository has no body-free normalized catalog capture;
- service currently publishes only `snapshot.required`;
- repository/service mutation results do not classify content, control, and
  catalog effects;
- current annotation event authority cannot express reviewed worktree plus
  service-owned application generation across every event;
- reassociation does not publish catalog replacement for both associations.

Implementation behavior:

1. Read session/thread/message IDs, parent IDs, scope, ordinals, and session
   semantic revision in one SQLite read transaction; do not decode rich columns.
2. Keep application source generation in `WorktreeAnnotationServiceActor`:
   capture/recheck around repository read and wrap immutable rows.
3. Return compact committed-change classification from mutation transactions:
   content, control, or catalog plus affected IDs/worktrees/revisions.
4. Aggregate one catalog-required flag, one control-changed flag/reason, and
   newest session revision per changed session.
5. Register observer before bootstrap capture and publish authority-bound
   catalog transfers, `annotation.sessionChanged`, or
   `annotation.controlChanged` through S1/S2.
6. Reassociation emits catalog replacement for previous and current worktrees
   while preserving descendant IDs.

Focused proof:

- repository ordering, uniqueness, body/origin/draft/history exclusion, empty
  catalog, and existing identity preservation;
- mutation classification matrix;
- observer-before-capture race, coalescing, multi-observer delivery, cleanup;
- envelope/event generation mismatch and worktree mismatch rejection;
- old/new reassociation, restart, and recovery replacement.

Integration gate G3:

Swift notification-source tests consume real repository captures through the
registered annotation protocol and generic writer. A content-only mutation
emits no catalog; topology emits a complete replacement; recovery/control emits
no rich bodies.

Safe checkpoint:

Commit after native repository/service/transport tests, scoped format/lint,
architecture lint, and `git diff --check` pass. Preserve the prior association
checkpoint and do not combine unrelated UI changes.

Stop/replan:

- current association owner changes transaction result/identity semantics;
- topology cannot be classified at the committing repository boundary;
- a new database field or migration appears necessary.

## S4 — Annotation worker, control read, catalog/content store, and UI continuity

Type: production integration slice.

Obligations: MAP-R7 through MAP-R14 and preserved PR1 session selection,
recovery, Save, viewed, Share, File, and Review semantics.

Primary write surfaces:

- `bridge-product-worktree-annotation-contracts.ts`;
- annotation protocol registration;
- `bridge-comm-worker-annotation-projection-query-controller.ts`;
- `bridge-comm-worker-product-controller.ts`;
- new narrow annotation catalog applicator/projection module;
- worker annotation/main contracts and runtime protocol integration;
- existing `worktree-annotation-projection-store.ts` and surface client;
- `worktree-annotation-surface-provider.tsx`, File/Review annotation adapters,
  viewed/Share selectors only where the catalog/control/content split requires
  consumer changes; no visual redesign.

RED first:

- catalog with no rich demand cannot expose normalized relationships;
- current session selection depends on combined projection summaries;
- catalog-only absence can look empty-ready;
- recovered-degraded gating exists only in the combined projection;
- delayed catalog/content can clear editor/viewed/Share state incorrectly;
- obsolete rich response is not fenced by authority-bound catalog currentness.

Implementation behavior:

1. Validate typed annotation authority and event union behind the registry.
2. Assemble/validate worker catalog, then send bounded normalized staging units
   to the existing main store candidate bank.
3. Split existing store into authority-bound catalog, demand-independent
   control, per-session rich content, command overlays, read/recovery, and
   output history banks.
4. Query control snapshot with empty rich demand; derive relevant-session
   selection from lifecycle/source relationship/candidate/recovery facts.
5. Acquire existing session demand only after control selection; load rich
   content only for demanded IDs.
6. `sessionChanged` refreshes demanded content or records undemanded revision;
   `controlChanged` refreshes control without bodies; catalog commit reconciles
   removed/new/retained demand and content.
7. Reset/source/worker replacement marks retained catalog/control/content stale
   under new expected authority; only complete replacements become current.
8. Preserve exact command receipt/editor continuity and keep Share/output
   membership unavailable until complete current content/fences reconcile.

Focused proof:

- protocol/assembler/applicator/store/query-controller unit tests;
- catalog-only, control-only, empty/current, stale/unavailable, reset and late
  content cases;
- selection with zero/one/several/uncertain sessions and recovered-degraded
  mutation rejection;
- demanded/undemanded session changes and no-body metadata assertions;
- editor first-character/Save overlay, viewed overlay, and Share unknown/current
  membership continuity;
- File and Review Browser Mode journeys with existing visuals/interactions.

Integration gate G4:

Production comm-worker tests drive registered annotation metadata and finite
content together: catalog commits first, control selects a session, demand loads
only that session, Save settles immediately, topology stages bounded replacement,
and reset retains last-complete state without false currentness.

Safe checkpoint:

Commit only after focused worker/store/browser proof plus complete
`mise run test:bridge-web` pass. Coordinate before touching concurrent UI or
Review publication files; keep styling changes out of this checkpoint.

Stop/replan:

- the existing store cannot hold hidden candidate/currentness without a second
  authority;
- current UI/data-model changes invalidate the reviewed catalog/control/content
  consumer boundary;
- a new scheduler, port, or demand granularity is required.

## S5 — Real system stability and final proof

Type: integration/proof slice.

Obligations: MAP-R6 and MAP-R12 through MAP-R15 plus all proof obligations not
observable below the process/browser boundary.

Permanent journey:

```text
file-backed SQLite with at least two sessions
  → start Swift development backend and Vite production composition
  → open File and Review registered annotation subscriptions
  → observe worker and bounded main-bank catalog commit before rich content
  → receive control snapshot and select/gate the relevant session
  → demand one session while proving the other remains unfetched
  → create/flush/Save two different messages without unrelated conflict
  → observe exact receipt before background reconciliation
  → create reply/root and observe bounded atomic catalog replacement
  → reassociate one session and observe old/new catalogs with stable IDs
  → reset during staging and retain stale prior catalog/control/content
  → reopen and commit current authority-bound state
  → restart backend against the same SQLite root
  → restore exact IDs, bodies, placement, recovery state, and Share membership
```

Required proof layers:

1. Focused Swift integration through repository/service/notification/content.
2. Complete BridgeWeb unit/integration/browser/E2E gates.
3. Real Vite + production communication worker + Swift backend + SQLite journey.
4. Marker-scoped telemetry proving edit traffic uses bounded session events,
   undemanded sessions cause no rich fetch, catalog units remain bounded, and no
   main-thread long task appears for the large fixture.
5. Packaged WKWebView File and Review journey with current UI, focus/editor,
   Share, source refresh, reset/restart, and output behavior.
6. `mise run lint`, `git diff --check`, then complete `mise run test` on the
   exact final HEAD.

False-green protections:

- mocked browser fixtures do not prove Swift/SQLite or the real worker;
- direct HTTP tests do not prove subscription consumption or main-store apply;
- worker catalog success does not prove bounded main-thread staging;
- a successful Save does not prove cross-view/catalog convergence;
- an empty fresh database does not prove identity/recovery migration behavior;
- individual E2E success does not replace the aggregate gate;
- feel-fast is not performance proof without marker-correlated boundaries.

Safe checkpoint:

Commit proof/harness changes only when they observe production owners and do
not add test-only production hooks. Final readiness requires every applicable
gate above on one exact HEAD; partial lower-layer success is reported separately.

Stop/replan:

- File/Review behavior regresses rather than exposing adapter wiring defects;
- the real path differs from the reviewed ownership/call sequence;
- aggregate failures reveal an out-of-scope runner/environment layer;
- performance evidence requires catalog deltas, new capacity policy, or another
  transport mechanism.

## Exact quality commands

Use repository tasks from the monorepo root. Start narrow, then climb:

```bash
mise run test:bridge-web:unit
mise run test:bridge-web:integration
mise run test:bridge-web:browser
mise run test:bridge-web:e2e
mise run test:bridge-web

mise run test:swift -- --filter BridgeProductSessionSubscriptionTests
mise run test:swift -- --filter BridgeProductSubscriptionReconciliationTests
mise run test:swift -- --filter BridgePaneProductMetadataCoordinator
mise run test:swift -- --filter WorktreeAnnotationNotificationSourceTests
mise run test:swift -- --filter WorktreeAnnotationSQLiteRepositoryTests
mise run test:swift -- --filter WorktreeAnnotationProjectionSourceTests
mise run test:swift -- --filter WorktreeAnnotationTransportContractTests
mise run test:swift

mise run format
mise run lint
mise run test
git diff --check
```

The implementation plan may refine filters after inspecting current suite
names, but it may not replace `mise run` tasks with raw SwiftPM commands or
weaken the final aggregate gate.

## Checkpoint policy

Create scoped commits only after the corresponding slice's focused proof and
quality gates pass:

```text
checkpoint 1  S1 registry hard cutover + File/Review parity
checkpoint 2  S2 generic bounded transfer end to end
checkpoint 3  S3 native annotation catalog/classification
checkpoint 4  S4 worker/store/control/content integration
checkpoint 5  S5 real-system proof and final gates
```

Never commit unrelated dirty files. Re-read `git status`, scoped diff, diff
stat, and `git diff --check` before every checkpoint. If 1Password signing fails
twice while the user is AFK, use the repository-approved unsigned fallback;
never bypass hooks or use `--no-verify`.

## Global stop and replan conditions

Stop implementation and return to the design owner if:

- a new physical route, queue, scheduler, store, persistence field, migration,
  security mechanism, or UI surface becomes necessary;
- File or Review must change observable semantics;
- application registration cannot eliminate central generic switches without
  moving delivery policy into application code;
- the annotation catalog cannot remain body/origin/placement/history-free;
- session-level demand cannot preserve current behavior;
- exact command completion must wait for catalog/content convergence;
- bounded worker-to-main atomic staging cannot use the existing port/store;
- catalog delta/tombstone semantics become necessary before measured evidence;
- concurrent owner changes contradict the reviewed design;
- required proof can pass only through mocks or weakened gates.

Environment or unrelated runner failures do not authorize product-code changes.
Report scoped green/red evidence separately and ask before expanding into an
unowned layer.
