# Bridge Review Refresh Classification — Program Design

Date: 2026-08-21

Requirements:
[2026-08-21-requirements.md](./2026-08-21-requirements.md).

Specification:
[2026-08-21-specification.md](./2026-08-21-specification.md).

Current foundations:

- [Bridge latest-generation operations program design](../2026-08-18-bridge-latest-generation-operations/2026-08-18-program-design.md)
- [Worktree annotation PR1 program design](../2026-08-06-worktree-annotations/pr1-program-design.md)

## Structural crux

Review computation and Review presentation installation must remain separate.
Native owners continue producing one newest complete Review. The main-thread
Bridge presentation owner decides whether that complete result updates the
visible bank immediately or occupies one bounded candidate bank.

This placement is required because native and worker owners know source and
candidate identity, while the Review viewer owns semantic attention, the active
editor, and reading position. Holding work in native would make native depend
on UI attention. Holding only React components would be too late because worker
patches would already mutate the visible store.

A hold also separates three identities that are equal today: native/worker
current, main displayed, and annotation source. The main store remains the
authority for what is displayed. A bounded install handshake on the existing
command route lets native retain and resolve that displayed publication without
making presentation wait on computation or creating another data plane.

## Alternatives

### Selected — active and candidate banks in the existing main render store

- Native computation and worker projection remain unchanged in authority.
- Worker display events that cannot install directly apply to one candidate
  bank whose role is provisional or update-ready.
- The existing main render store atomically promotes the candidate bank when
  installation is admitted.
- Review viewer attention context reaches the store through an explicit
  feature-local admission interface.
- Display installation uses prepare and confirm messages on the existing
  command route so native source authority never advances merely because the
  worker committed a candidate.

Cost: memory for at most one additional normalized Review presentation.

### Rejected — stop refresh while the reviewer interacts

This would block freshness computation, make filesystem behavior depend on UI
state, and violate uninterrupted review.

### Rejected — disable comment creation

PR1 already owns immutable origin evidence and placement evaluation. Disabling
comments would trade away the primary product job instead of using that model.

### Rejected — hold publication in native

Native does not own edit tokens, scroll gestures, or main-thread display
installation. Sending that state upstream would invert ownership.

### Rejected — buffer arbitrary worker messages in React

Raw-message buffering duplicates protocol state, complicates bounds, and is
later than the existing render-store authority.

## Component and ownership model

```text
Bridge native Review refresh
  BridgePaneRefreshAdmissionCoordinator
    owns: current refresh generation and pre-delivery presentation class
    consumes: invalidation, impact result, acknowledged displayed publication

  BridgeReviewRefreshImpactProvider
    owns: bounded incoming-delta facts and affected file identities for one
          current generation
    uses: existing native Git/source and active/candidate Review identities

  BridgeReviewPublicationCoordinator
    owns: one complete native-current candidate, retained displayed publication,
          bounded display-install transition, and publication ordering
    rule: classification settles before candidate display delivery

existing product transport and comm worker
  owns: strict carriage, latest-generation application, projection
  carries: display-install prepare/confirm/abort commands on the existing route
  rule: no presentation-hold or final-class policy

BridgeMainRenderSnapshotStore
  owns: visible Review bank, optional candidate bank, atomic bank promotion
  candidate role: provisional | updateReady
  consumes: candidate class, affected item identities, display patches,
            candidate-ready event,
            feature-local installation admission

BridgeReviewPresentationInstallationGate
  owns: final effective presentation class, ordinary/promoted installation
        decision, and the display-install handshake
  consumes: candidate affected-item set, Review attention-context snapshot,
            and Apply now

Worktree annotation Review source resolver
  owns: resolving projection, placement, new-root capture, and output against
        the explicitly requested installed Review publication
  consumes: installed package/generation identity and retained publication

WorktreeAnnotationEditSurfaceRegistry
  owns: ephemeral editor continuity keyed by edit token
  preserves: editor body, origin, scheduler/in-flight persistence identity
  does not replace: SQLite durable draft/message authority

Bridge Review toolbar
  owns: pure rendering of promoted state and actions
```

Forbidden edges:

- native refresh owners do not read React interaction state;
- the comm worker does not decide whether Review attention holds installation;
- the toolbar does not own candidate or editor state;
- editor continuity does not become a second durable annotation store;
- ordinary and promoted modes do not fork comparison computation;
- native-current publication does not imply displayed or annotation-current;
- no annotation path falls back from an installed identity to native current.

## Behavioral interfaces

### Refresh impact

`BridgeReviewRefreshImpactProvider` accepts the displayed source identity,
candidate source identity, and current generation. It asynchronously returns:

```text
newlyImportedCommitCount
affectedFileCount
addedLineCount
deletedLineCount
affectedStableFileIdentities
```

The publication coordinator supplies the last confirmed installed publication,
not its native-current publication, as the displayed input. The provider uses
the existing bounded Git scheduler and retained displayed Review material.
Counts describe the displayed-to-candidate delta. A pending display transition,
timeout, unavailable material, or incomplete measurement returns `unknown`,
which the coordinator maps to promoted. Results from stale generations are ignored.
The result also carries the affected stable file identities needed to decide
whether promoted computation concerns the current Review attention context.

### Presentation classification

The native coordinator owns the pre-delivery class:

```text
ordinary
promoted(reason: commits | files | lines | unknown)
```

Native classification begins ordinary only as an internal provisional state.
It may promote monotonically from numeric or unknown impact. No candidate
display event is delivered until that native classification is known. The main
installation gate owns the final effective class and may make one monotonic
ordinary-to-promoted escalation with reason `activeAnchor` when the candidate
cannot preserve a locally active editor anchor. This orders presentation without
delaying Review computation or sending editor state to native.

Initial load and explicit target commands bypass same-source classification and
retain their current presentation contracts.

### Candidate-ready event

The comm worker already observes the final Review metadata barrier. After it
applies the final current-fenced transaction, it emits one strict internal
candidate-ready event containing the package identity, generation, revision,
pre-delivery presentation class, and affected item identities. This uses the
existing worker RPC connection and adds no physical route.

### Installation admission

The main render store exposes a Review-local interface:

```text
setReviewAttentionContext(snapshot)
applyNow()
readRefreshPresentation()
```

Every complete worker display event first targets the one candidate bank.
Without an active editor, an ordinary candidate proceeds immediately through
the display-install handshake with no global bar. With an active editor, the
bank remains provisional until the candidate-ready event proves exact
reattachment. Failure to prove exact reattachment escalates the same candidate
to promoted. Numerically promoted events use the same candidate bank with role
`updateReady`. The roles are mutually exclusive, and a newer candidate replaces
the one slot. The candidate-ready event allows the installation gate to install
immediately or hold it.

During known-impact computation, the impact result's affected stable file
identities allow the gate to render `Updating…` only for relevant Review
attention. At candidate readiness, the candidate bank derives the precise
affected item set by comparing the active and candidate Review catalogs and
identities. Added, removed, and changed Review items, including threads whose
trustworthy placement changes, are affected. The gate holds only when that set
intersects the current semantic-attention item set.

An `unknown` promotion treats every current Review context as affected until the
candidate-ready event replaces that conservative set with precise affected item
identities.

### Displayed-source install handshake

Every visible replacement, ordinary or promoted, uses one bounded handshake:

```text
installation gate
  -> prepareDisplayInstall(expected displayed A, candidate B, transition id)
  <- prepared: native retains A and B; displayed authority remains A
  -> confirmDisplayInstall(transition id, B) enqueued on the existing command route
  -> main render store atomically promotes candidate bank B in the same
     non-yielding main-thread turn
  <- native displayed mirror becomes B; A may retire when no lease remains
```

Prepare, confirm, and abort are idempotent for the same transition identity.
Prepare rejects a mismatched displayed predecessor or candidate. While prepared
but unconfirmed, native impact classification is `unknown`, annotation
resolution remains valid for A, and both retained publications remain available.
The gate enqueues confirm and promotes the bank without yielding, so later Review
annotation commands on the same worker route cannot overtake confirm. If confirm
cannot be enqueued, the store does not publish B as active.

Worker replacement or restart reconciles the prepared transition against the
main store's active bank: matching A aborts the transition, matching B confirms
it, and any mismatch retains the last complete bank and reports installation
failure. Pane close aborts the transition and releases both candidate and
display leases. These are bounded lifecycle states, not durable history.

The Review annotation projection demand and every Review annotation command
carry the installed package/generation identity captured from the active main
bank. Native projection, source capture, placement, and output resolve that
explicit identity through the publication coordinator's retained displayed
publication instead of using `committedPublicationForReplay` as a synonym for
displayed. Existing annotation routes, immutable origins, placement states, and
SQLite authority remain unchanged.

### Editor continuity

The existing edit-surface registry expands each active edit-token record from a
count to one ephemeral continuity record. The record retains the current editor
body, immutable origin, editor kind, draft scheduler, and in-flight persistence
handle across CodeView item replacement. A re-mounted composer reattaches by
edit token. Closing the editor releases the record after its existing flush/
release contract.

SQLite remains the durable authority. Continuity records are never history and
are cleared on editor close, pane close, or settled command handoff.

## Current and proposed call-path delta

```text
CURRENT — intentionally preserved computation

filesystem/Git invalidation
  -> BridgePaneWorktreeRefreshDriver                         unchanged
  -> BridgePaneRefreshAdmissionCoordinator                  unchanged authority
  -> Review source/provider + package construction          unchanged
  -> BridgeReviewPublicationCoordinator                     unchanged candidate owner
  -> metadata stream -> comm worker                         unchanged route
  -> reviewDisplayPatch -> BridgeMainRenderSnapshotStore    changed apply policy
  -> Review viewer                                          visible result

PROPOSED — added/changed edges

refresh generation
  -> BridgeReviewRefreshImpactProvider                      added async fact edge
  <- ordinary/promoted result or unknown                    added result edge
  -> BridgePaneRefreshAdmissionCoordinator                  changed state write
  -> pane/Review presentation contract                      changed strict value

complete publication + classification
  -> existing metadata stream                               unchanged route
  -> comm-worker projection                                 unchanged authority
  -> candidate-ready event                                  added internal event
  -> BridgeMainRenderSnapshotStore candidate bank           added state write

candidate installation
  -> display-install prepare command                        added existing-route call
  -> BridgeReviewPublicationCoordinator display lease       added retained authority
  <- prepared | rejected                                    added result edge
  -> display-install confirm + atomic bank promotion         added serialized effects
  <- installed | failed                                     added result state
  -> display-install abort on supersession/teardown          added cleanup edge

installed Review annotation identity
  -> annotation projection demand/commands                   changed explicit input
  -> retained displayed publication source resolution       changed owner lookup
  <- projection | command result | output fence              unchanged result kinds

Review viewer attention-context snapshot
  -> BridgeReviewPresentationInstallationGate               added local edge
  <- candidate affected-item set                             added derived edge
  -> BridgeMainRenderSnapshotStore                          added admission edge
  -> atomic candidate-bank promotion                        added visible effect
  <- installed | held | preservation failure                added result state
```

Preservation-critical unchanged edges are native latest-generation fencing,
metadata ordering, worker application validation, main-thread presentation
ownership, SQLite annotation durability, and source evaluator placement.

## State model

The main render store owns the Review presentation state:

```text
active(A)
  candidate(B, provisional)
    B exact/ordinary + install prepared ----------> installing(A, B)
    B anchor-unsafe ------------------------------> candidate(B, updateReady)

active(A)
  promoted B starts ------------------------------> receiving(A, B)
  B ready + no affected attention ----------------> installing(A, B)
  B ready + affected attention -------------------> candidate(B, updateReady)
  updateReady + affected attention leaves --------> installing(A, B)
  updateReady + Apply now ------------------------> installing(A, B)
  updateReady(A, B) + ordinary C ready -----------> installing(A, C)
  candidate/receiving + newer C ------------------> receiving(A, C)

installing(A, B)
  confirm enqueued + atomic promotion ------------> active(B)
  prepare/enqueue failure ------------------------> active(A)+unavailable
  confirm lost after promotion -------------------> active(B)+reconciling

receiving/candidate/installing + worker replacement
  ------------------------------------------------> active(A)+reconciling
close --------------------------------------------> disposed
```

Illegal transitions fail closed:

- a candidate-ready event without matching candidate identity is rejected;
- stale or duplicate candidate-ready events do not install twice;
- an older generation cannot replace a newer candidate;
- provisional and update-ready roles cannot coexist;
- partial candidate state is never readable through active-store selectors.

## Review attention context

The Review viewer publishes one feature-local snapshot, without ambient/global
state:

```text
ReviewAttentionContext
  surface mode and pane/tab/closed identity
  selected Review item
  Review item owning the reading position
  Review item or range owning the active editor
  Review item owning an active range gesture or related command
```

The Review CodeView integration extends its existing Pierre-owned visible-item
callback to publish the item at the specification's leading-edge reading line.
The attention adapter consumes that identity. It does not own scroll position,
write `scrollTop`, install a parallel observer, or poll; Pierre remains the
scroll and visibility owner.

The installation gate intersects those semantic-attention item identities with
the candidate affected-item set. Same-context DOM blur, Save or Share clicks,
and temporary app/window deactivation do not clear attention. Selecting an
unaffected item, switching File/Review mode, switching pane or tab, or closing
Review removes the affected attention and automatically installs the newest
update-ready candidate bank. Partially visible unrelated files, expanded
inactive threads, hover, and unrelated chrome focus are not attention inputs.
Equality suppression prevents redundant store updates.

The toolbar renders promoted state only while the candidate affects the current
attention context. An ordinary update never renders the bar. No timer changes
attention or forces installation.

The active-editor origin remains only in the local admission snapshot. The main
store compares that origin with the complete candidate before any active-bank
mutation and escalates to promoted when direct reattachment would be
untrustworthy. No comment body, selected text, edit token, or origin crosses
telemetry or native boundaries.

## Apply now sequence

```text
reviewer -> toolbar: Apply now
toolbar -> installation gate: record install intent
installation gate -> candidate bank: read newest complete candidate at commit
installation gate -> edit registry: retain continuity records
installation gate -> native: prepare displayed-source transition
installation gate -> native: enqueue confirm on existing command route
installation gate -> main render store: promote newest candidate bank atomically
main render store -> Review viewer: one new active snapshot
Review viewer -> composers: reattach by edit token
annotation projection -> source evaluator: refresh placement
source evaluator -> UI: exact | relocated | outdated | unavailable
```

If continuity reattachment fails, the gate leaves the active bank visible,
retains the continuity record, and exposes preservation failure. There is no
partial bank promotion.

## Ordinary installation with an active editor

Ordinary mode does not hold a complete candidate after the continuity and
display-install decisions. The one candidate bank uses its provisional role
while the gate validates editor reattachment and prepares the displayed-source
transition. Exact reattachment installs immediately and silently. If
reattachment is not trustworthy, the same bank changes role to `updateReady`
and the effective class escalates to promoted. This is a correctness escalation,
not a third presentation class or a second bank.

## Supersession and concurrency

- Native classification, publication, worker projection, candidate banking, and
  ready events carry the same Review generation and source identity.
- The active bank and one candidate bank are main-thread serialized.
- Newer work replaces the candidate bank; cleanup of the old candidate bank
  cannot mutate the active bank.
- Apply now records install intent. At commit the gate uses the newest complete
  candidate then present and runs the same continuity and display-install
  checks. If no complete candidate remains, presentation returns to `Updating…`.
- A candidate that supersedes an in-flight prepare aborts that transition before
  its own prepare; a stale confirm cannot promote either bank.
- Display-install transitions and candidate replacement are serialized by the
  main-thread gate and native transition identity.
- No timer forces installation while affected semantic attention remains.

## Failure and recovery

- Impact timeout, unavailable facts, or a pending display transition: promote
  conservatively and treat every Review context as affected until precise
  candidate identities arrive; computation continues.
- Candidate build or validation failure: discard candidate; active bank remains;
  use existing retry classification. Render `Update unavailable` only while the
  failed promoted candidate affects the current attention context; otherwise
  keep the global bar absent and use the existing non-global refresh outcome.
- Worker reset: the pane runtime that already observes replacement calls the
  main store's worker-replacement preparation, discards the candidate bank and
  promoted chrome immediately, and reconciles or aborts the native display
  transition before replaying the retained active bank.
- Main continuity failure: do not promote the bank; preserve editor and active
  Review; expose failure.
- Display-install prepare rejection or confirm-enqueue failure: retain the active
  bank and annotation authority; expose installation failure; retry only through
  a new transition identity.
- Confirm application lost after enqueue: retain newly active B, force worker
  replacement/bootstrap reconciliation, and never fall back to A for B-relative
  annotation work.
- Pane close: cancel impact work, release candidate bank, display leases, and
  continuity records through current editor teardown; no later event may install.
- Memory pressure: the candidate bank is bounded to one normalized Review and
  may not displace the active bank; inability to retain it becomes an explicit
  retained-Review failure.

## Cross-cutting realization

- Reliability: active and candidate banks are disjoint, generation-fenced, and
  atomically promoted after a bounded displayed-source prepare. Existing last-
  complete and retry owners remain.
- Performance: impact work uses existing bounded Git scheduling; candidate
  state holds at most one extra normalized Review. No polling or duplicated
  comparison build is introduced.
- Accessibility: the existing Review header hosts one live status and actions;
  it never steals focus or inserts content rows.
- Privacy: telemetry includes class, reason, safe counts/buckets, generation,
  hold/install terminal, and duration only. Paths, source, selections, comments,
  and edit tokens are prohibited.
- Compatibility: pre-release internal Swift/worker contracts cut over together;
  the three physical Bridge routes and Review package schema remain singular.
- Security: no new trust boundary, authentication, authorization, or external
  input surface is introduced.

## Requirement realization and proof seams

- R-RRC-001/R-RRC-002: coordinator classification, acknowledged displayed
  publication, and shared publication path; prove displayed-to-candidate facts,
  conservative transition fallback, one production path, and no ordinary chrome.
- R-RRC-003/R-RRC-004: main active/candidate banks and installation gate; prove
  state transitions and real browser geometry.
- R-RRC-005/R-RRC-006/R-RRC-007: Pierre-owned leading-edge attention signal,
  edit continuity registry, displayed-publication resolver, and existing
  immutable origin/source evaluator; prove real draft persistence, Apply now,
  displayed-generation comment/output fencing, and placement results.
- R-RRC-008/R-RRC-009: one generation-fenced candidate bank, display-install
  transition, and atomic bank promotion; prove ordinary successor replacement,
  prepare/confirm failure, supersession, reset, and no partial visibility.
- R-RRC-010/R-RRC-011: pure header presentation; prove accessible text,
  keyboard actions, focus, reduced motion, and no loading row.
- R-RRC-012: bounded state and lifecycle telemetry; prove cleanup snapshots and
  marker-scoped source-scrubbed terminals.

Production-real proof must cross native invalidation, the existing Swift
backend/metadata route, comm worker, main render store, Review viewer, and
annotation persistence/source evaluation. Fakes may control interleavings but
cannot replace the final cross-boundary observation.
