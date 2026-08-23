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

A hold also separates identities that are equal today. Native owns the newest
computed publication, while the main store owns the publication actually
displayed. Native keeps one lineage-monotonic acknowledgment of that displayed
identity for impact and annotation source resolution. Installation uses one
compare-and-set admission plus the existing publication-applied receipt; it is
not a general distributed transaction.

## Alternatives

### Selected — active and candidate banks in the existing main render store

- Native computation and worker projection remain unchanged in authority.
- Worker display events that cannot install directly apply to one candidate
  bank whose role is provisional or update-ready.
- The existing main render store atomically promotes the candidate bank when
  installation is admitted.
- Review viewer attention context reaches the store through an explicit
  feature-local admission interface.
- Display installation uses one native admission call and the existing
  publication-applied receipt on the existing command route.

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
    owns: nativeCurrent, acknowledgedDisplayed, optional admitted-publication
          lease, retained publication material, and publication ordering
    rule: classification settles before candidate display delivery and rides
          the first candidate display patch

existing product transport and comm worker
  owns: strict carriage, latest-generation application, projection
  carries: install admission and existing review.publication.applied receipt
  caches: newest complete active projection and its exact candidate-start and
          candidate-ready facts; emits an exact-identity candidate-failed event
          only after classified candidate work has started
  rule: no presentation-hold or final-class policy; after native acknowledges an
        installed predecessor, re-expose one newer worker-current projection

BridgeMainRenderSnapshotStore
  owns: visible Review bank, optional candidate bank, optional bounded promoted
        failure presentation, atomic bank promotion
  candidate role: provisional | updateReady | installing
  consumes: candidate class and affected file identities on the first display
            patch, later display patches, candidate-ready event,
            feature-local installation admission

BridgeReviewPresentationInstallationGate
  owns: final effective presentation class, ordinary/promoted installation
        decision, and install admission
  consumes: candidate affected-file set, Review attention-context snapshot,
            and Apply now

Worktree annotation Review source resolver
  owns: resolving projection, placement, new-root capture, and output against
        the explicitly requested installed Review publication
  consumes: installed package/generation identity and retained publication

WorktreeAnnotationEditSurfaceRegistry
  owns: an opaque ephemeral continuity lease keyed by edit token
  preserves: the existing editor owner across presentation replacement
  does not replace: SQLite durable draft/message authority

Bridge Review toolbar
  owns: pure rendering of promoted state and actions, including the existing
        comparison-retry action for a retryable promoted failure
```

Forbidden edges:

- native refresh owners do not read React interaction state;
- the comm worker does not decide whether Review attention holds installation;
- the toolbar does not own candidate or editor state;
- editor continuity does not become a second durable annotation store;
- ordinary and promoted modes do not fork comparison computation;
- native-current publication does not imply displayed or annotation-current;
- no annotation path falls back from an installed identity to native current;
- no wall-clock timestamp participates in publication ordering.

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

The publication coordinator supplies `acknowledgedDisplayed`, not
`nativeCurrent`, as the displayed input. The provider uses the existing bounded
Git scheduler and retained displayed Review material. Counts describe the
displayed-to-candidate delta. While those registers diverge for a successor, or
when timeout, unavailable material, or incomplete measurement prevents an exact
base, the result is `unknown`, which maps to promoted. Results from stale
lineages are ignored.
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
display event is delivered until that native classification is known. The first
candidate display patch carries one strict candidate-start disposition atomically
with the candidate identity:

```text
sameSource(class, affectedStableFileIdentities)
replacement
```

Initial load and explicit target replacement use `replacement`; same-source
updates carry their class and affected stable file identities. Later patches do
not repeat the disposition. The main
installation gate owns the final effective class and may make one monotonic
ordinary-to-promoted escalation with reason `activeAnchor` when the candidate
cannot preserve a locally active editor anchor. This orders presentation without
delaying Review computation or sending editor state to native.

Initial load and explicit target commands bypass same-source classification and
retain their current presentation contracts.

### Candidate start and candidate-ready event

Native settles classification before publishing the candidate metadata stream.
For a same-source delta, the single `review.delta` event carries the complete
classification group. For a same-source replacement that requires reset/window
delivery, the leading `review.reset` event carries the group before
`review.sourceAccepted` and window events. Initial load and explicit target
replacement omit the group because they retain their existing presentation
contracts. The TypeScript product contract admits the group only on those two
same-source leading events and rejects it on later windows.

The comm worker binds the leading event's facts to the first current-fenced
candidate `reviewDisplayPatch`. That strict internal patch carries
`sameSource(class, affectedStableFileIdentities)` when the leading event has the
classification group and `replacement` otherwise. Later patches for the same
identity omit the candidate-start disposition and are rejected if they attempt
to start or reclassify the candidate again. Main creates the candidate bank and
stores its immutable start disposition before
applying any geometry from that first patch. It uses the exact
package identity, generation, revision, pre-delivery presentation class, and
affected stable file identities before any candidate geometry is applied. A
promoted candidate can therefore render `Updating…` while the remainder of its
worker/main presentation is constructed, without guessing from a generic
provisional role.

The comm worker still observes the final Review metadata barrier. After it
applies the final current-fenced transaction, it emits one strict internal
candidate-ready event containing the matching package identity, generation, and
revision. Readiness does not repeat or replace the candidate-start classification
facts. Both messages use the existing worker RPC connection and add no physical
route.

The worker no longer sends or awaits `review.publication.applied` merely because
it committed metadata. It continues consuming newer metadata, while the main
installation gate returns that existing call only after atomic bank promotion.
The cutover removes the current sender and its application-failure recovery
branch from `BridgeCommWorkerProductController.#consumeReviewMetadataEvents`;
leaving either path active would incorrectly acknowledge worker-current as
displayed.

### Installation admission

The main render store exposes a Review-local interface:

```text
setReviewAttentionContext(snapshot)
applyNow()
readRefreshPresentation()
```

The first worker display event for a publication creates the one candidate bank
and installs its immutable start disposition. A `replacement` candidate follows
the existing initial/target installation presentation and never renders the
promoted global bar. Every later display event for that publication targets the
same bank.
Without an active editor, an ordinary candidate proceeds immediately through
install admission with no global bar. With an active editor, the
bank remains provisional until the candidate-ready event proves exact
reattachment. Failure to prove exact reattachment escalates the same candidate
to promoted. Numerically promoted events use the same candidate bank with role
`updateReady`. The roles are mutually exclusive, and a newer candidate replaces
the one slot. The candidate-ready event allows the installation gate to install
immediately or hold it.

Affected stable file identities are the complete chrome-classification set.
Renames and deletions carry both displayed and candidate-side identities.
Selected items, threads, editors, ranges, reading position, and related commands
map to their owning stable file identity. The gate holds only when that file set
intersects the current semantic-attention file set.

An `unknown` promotion treats every current Review context as affected. Unknown
is represented symbolically by the promoted reason with an empty enumerated
affected-file list; it never materializes an unbounded wildcard list and is not
replaced by later exact facts for the same candidate.

If a promoted candidate fails after its classified first patch but before
installation, the store discards the candidate bank and retains one bounded
failure presentation containing only the failed candidate identity, affected
file identities or symbolic unknown, and retryability. It retains no candidate
geometry. The toolbar renders that failure only while affected semantic
attention remains and routes Retry through the existing comparison-retry owner
using the canonical active target. A new candidate start, attention leaving,
worker replacement, or close clears the failure presentation.

The comm worker reports that terminal through one strict internal
`reviewCandidateFailed` event on the existing worker connection. The event
carries the exact candidate publication identity and retryability; it does not
repeat classification or affectedness. Main accepts it only when that identity
exactly matches the current non-installing candidate bank, atomically discards
that candidate geometry, and, only for a promoted same-source disposition,
copies the bank's immutable facts into the failure presentation. Ordinary and
replacement candidates remain on their existing non-global failure paths. A
stale B failure arriving after C has replaced B is ignored
and cannot clear C or present B chrome. A failure before a classified candidate
bank exists remains on the existing non-global failure path.

### Two lineage registers and install admission

Native stores two independently monotonic publication identities:

```text
nativeCurrent          newest native-complete publication
acknowledgedDisplayed  newest publication main confirmed as displayed
```

Both use the existing accepted publication-lineage rule: generation orders first,
then revision; package, source, and publication identities are exact fences, and
an ambiguous identity never wins. They never use wall-clock LWW. Main remains
authoritative for the actual visible bank; the native displayed register is its
acknowledged mirror.

Bootstrap seeds both registers from the first publication main accepts as
displayed. Before that, `acknowledgedDisplayed` is absent and same-source
classification does not apply. Worker replacement preserves main's active bank
and re-establishes the mirror by replaying its exact applied receipt.

Full browser-document replacement has a different lifetime: native may still
retain `acknowledgedDisplayed` from the prior document while the fresh main
store has no active bank. The publication coordinator records which existing
worker instance last established display, using the existing
`BridgeProductControlCorrelation.workerInstanceId` carried by both the install
admission and applied calls. A current worker instance that has not established
display may admit exactly `nativeCurrent` with a null expected predecessor. The
coordinator does not clear
`acknowledgedDisplayed`; it retains that prior publication until the fresh main
atomically promotes the bootstrap candidate and sends the existing applied
receipt. That receipt establishes display for the current worker instance,
after which the ordinary exact-predecessor CAS rule applies. A worker replacement
whose main store still retains an active bank sends that exact active predecessor
and never uses fresh-session bootstrap.

Every visible replacement, ordinary or promoted, follows this bounded path:

```text
installation gate
  -> admitInstall(expectedDisplayed: A, candidate: B)
  <- accepted only when acknowledgedDisplayed == A
                     and nativeCurrent == B
  -> main render store atomically promotes candidate bank B
  -> review.publication.applied(B) on the existing command route
  <- acknowledgedDisplayed advances monotonically to B
```

The candidate publication identity is the admission identity; there is no
separate transition identifier. Admission is the linearization point and owns
one in-memory publication lease qualified by the admitting `workerInstanceId`.
Main marks B's existing candidate-bank role as `installing` before it requests
admission. Once admission succeeds, that one bank remains pinned until atomic
promotion; a successor C cannot overwrite admitted B. If native C completes
after B is admitted, C is a successor rather than a reason to invalidate B.
Until B's applied receipt arrives, native may retain displayed A, admitted B,
and current C; any other superseded unleased publication is released. The comm
worker may already have committed complete C while main keeps admitted B pinned.
It retains only its normal newest active projection plus the exact candidate-ready
facts for that projection. The first C display events are allowed to miss main's
one occupied candidate bank; they are not buffered.

The existing main-to-worker installed-B command continues to the native
`review.publication.applied(B)` call. Only after that call succeeds, the comm
worker compares installed B with its active projection. If worker-current C is
strictly newer, the applicator re-exposes C once as one full reset display patch
plus its candidate-ready event, reconstructed from the existing normalized C
projection. Re-exposure does not reapply or clone worker runtime state, request
native metadata replay, or change worker-current. One bounded in-memory fence
keyed by `(installed B, re-exposed C)` suppresses duplicate re-exposure on an
idempotent B receipt; a newer worker-current identity or replacement worker has
a different fence. This is one presentation delivery of the latest successor,
not a third presentation bank, raw-message buffer, metadata history, or new route.

The existing control mux serializes admitted product calls. A duplicate or stale
applied receipt is idempotent and cannot move `acknowledgedDisplayed` backward.
A valid duplicate receipt for already-acknowledged A still establishes A as the
current worker instance's display; invalid, stale, or unknown receipts establish
nothing.
A late or lost receipt leaves classification conservative and retention longer,
but never changes main's active bank. On reconnect, main resends the applied
receipt for its active bank. If the worker session ends before main installs an
admitted publication, successful retirement in the existing
`BridgePaneProductSessionOwner` invokes one coordinator operation with the
retiring `workerInstanceId`. That operation releases only the unmatched admission
owned by that worker and leaves `acknowledgedDisplayed` unchanged. App and
development-host composition install the same retirement callback. No abort
protocol or forced replacement is required.

The publication coordinator accepts an applied receipt for any exact retained
publication that is newer than `acknowledgedDisplayed`, even when
`nativeCurrent` has already advanced. A receipt for an unknown, ambiguous,
older, or already acknowledged publication is rejected or treated as an
idempotent duplicate; acceptance never depends on the publication still being
native-current.

If main displays B while B's receipt is still unacknowledged, admission of a
later C first retries B's receipt; it never guesses past the mismatched expected
displayed identity.

The existing `review.publication.applied` call moves from post-worker application
to post-main installation; no second acknowledgment kind is added. A prior
A-stamped annotation call enters the same serialized product-control mux before
B's applied receipt, and A retires only after that acknowledgment plus settlement
of every open A source lease. Commands created after installation carry B.

The Review annotation projection demand and every Review annotation command
carry the installed package/generation identity captured from the active main
bank. Native projection, source capture, placement, and output resolve that
explicit identity through the publication coordinator's retained displayed
publication instead of using `committedPublicationForReplay` as a synonym for
displayed. Existing annotation routes, immutable origins, placement states, and
SQLite authority remain unchanged.

### Editor continuity

The existing edit-surface registry exposes one opaque continuity lease per active
edit token. The current editor owner transfers that lease across CodeView item
replacement and reclaims it on reattachment; the registry does not prescribe or
copy editor fields. Closing the editor releases the lease through its existing
flush/release contract.

SQLite remains the durable authority. The default continuity realization is the
stable editor owner plus edit token. A lease carries additional ephemeral state
only when that state cannot remain with the editor owner and is necessary to
preserve body or command settlement across replacement. The registry never
becomes history, a draft store, or a second command scheduler.

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
  -> leading same-source delta/reset classification group   changed event contract
  -> comm-worker projection                                 unchanged authority
  -> first candidate display patch + classification facts   changed internal event
  -> BridgeMainRenderSnapshotStore candidate bank           added state write
  -> remaining candidate display patches                    unchanged local route
  -> candidate-ready event                                  narrowed to readiness

classified candidate failure
  -> worker terminal classification                         unchanged failure owner
  -> reviewCandidateFailed(identity, retryable)             added internal event
  -> exact current-candidate identity guard                 added main guard
  -> discard candidate geometry + bounded failure facts     added atomic state write
  <- stale identity ignored                                 added failure result

candidate installation
  -> install admission CAS                                  added existing-route call
  -> BridgeReviewPublicationCoordinator admission lease      added retained authority
  <- admitted | rejected                                    added result edge
  -> atomic candidate-bank promotion                         added visible effect
  -> main-to-worker installed message                        added local command edge
  -> existing publication-applied product call               changed semantic point
  <- acknowledged | retry/reconnect                          changed result handling
  -> compare acknowledged installed identity with worker current
  -> re-expose newer normalized worker projection once       added local effect
  -> existing display patch + candidate-ready events         unchanged local route

installed Review annotation identity
  -> annotation projection demand/commands                   changed explicit input
  -> retained displayed publication source resolution       changed owner lookup
  <- projection | command result | output fence              unchanged result kinds

Review viewer attention-context snapshot
  -> BridgeReviewPresentationInstallationGate               added local edge
  <- candidate affected-file set                             added derived edge
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
    B exact/ordinary + install admitted ----------> installing(A, B)
    B anchor-unsafe ------------------------------> candidate(B, updateReady)

active(A)
  promoted B first classified patch --------------> receiving(A, B)+Updating
  B ready + no affected attention ----------------> installing(A, B)
  B ready + affected attention -------------------> candidate(B, updateReady)
  updateReady + affected attention leaves --------> installing(A, B)
  updateReady + Apply now ------------------------> installing(A, B)
  updateReady(A, B) + ordinary C ready -----------> installing(A, C)
  candidate/receiving + newer C ------------------> receiving(A, C)
  promoted B fails + affected attention ----------> active(A)+updateUnavailable(B)
  promoted B fails + no affected attention -------> active(A)

active(A)+updateUnavailable(B)
  Retry ------------------------------------------> existing comparison retry
  newer C starts ---------------------------------> receiving(A, C)
  affected attention leaves ----------------------> active(A)

installing(A, B)
  admission request pins B as installing
  admission accepted + atomic promotion ----------> active(B)+receiptPending(B)
  admission rejected -----------------------------> active(A)+superseded
  successor C arrives ----------------------------> installing(A, B)+nativeCurrent(C)

active(B)+receiptPending(B)
  applied receipt acknowledged -------------------> active(B)
  applied receipt + workerCurrent(C) --------------> active(B)+reExpose(C)
  receipt delayed/lost ---------------------------> active(B)+conservative

freshMain(empty)+nativeCurrent(B)
  worker instance has no established display
    + bootstrap admission(nil, B) accepted --------> active(B)+receiptPending(B)

receiving/candidate + worker replacement ----------> active(A)
close --------------------------------------------> disposed
```

Illegal transitions fail closed:

- a candidate-ready event without matching candidate identity is rejected;
- a first candidate patch without one complete start disposition is rejected;
- later patches that attempt to change the candidate start disposition are rejected;
- a candidate-failed event without an exact current non-installing candidate is ignored;
- stale or duplicate candidate-ready events do not install twice;
- an older generation cannot replace a newer candidate;
- provisional, update-ready, and installing roles cannot coexist;
- partial candidate state is never readable through active-store selectors;
- install admission compares expected displayed and native-current identities;
- a publication completing after admission is a successor.

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

The installation gate maps semantic-attention items to owning stable file
identities and intersects those with the candidate affected-file set.
Same-context DOM blur, Save or Share clicks,
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
installation gate -> edit registry: transfer continuity leases
installation gate -> native: admit expected displayed A and candidate B
installation gate -> main render store: promote newest candidate bank atomically
installation gate -> native: send existing publication-applied receipt for B
main render store -> Review viewer: one new active snapshot
Review viewer -> composers: reattach by edit token
annotation projection -> source evaluator: refresh placement
source evaluator -> UI: exact | relocated | outdated | unavailable
```

If continuity reattachment fails, the gate leaves the active bank visible,
retains the continuity lease, and exposes preservation failure. There is no
partial bank promotion.

## Ordinary installation with an active editor

Ordinary mode does not hold a complete candidate after the continuity and
install-admission decisions. The one candidate bank uses its provisional role
while the gate validates editor reattachment and requests exact install
admission. Exact reattachment installs immediately and silently. If
reattachment is not trustworthy, the same bank changes role to `updateReady`
and the effective class escalates to promoted. This is a correctness escalation,
not a third presentation class or a second bank.

## Supersession and concurrency

- Native classification, publication, worker projection, candidate banking, and
  ready events carry the same Review generation and source identity.
- The active bank and one candidate bank are main-thread serialized.
- Newer work replaces the candidate bank; cleanup of the old candidate bank
  cannot mutate the active bank unless that candidate is already install-admitted.
- An admission request changes the existing candidate role to `installing`.
  Once native admits it, successor delivery cannot replace that bank before
  promotion. After native acknowledges the applied receipt, the comm worker
  re-exposes only a strictly newer complete active projection. Exact
  `(installed, worker-current)` pair fencing makes duplicate receipts
  presentation-idempotent without retaining a successor history.
- Apply now records install intent. At commit the gate uses the newest complete
  candidate present at that moment and runs the same continuity and install-admission
  checks. If no complete candidate remains, presentation returns to `Updating…`.
- Accepted admission is the newest-native-complete linearization point. A later
  native publication is a successor even if it completes before main paints B.
- Admission, candidate replacement, and active-bank promotion are serialized by
  their existing native and main owners; no cross-process lock is introduced.
- No timer forces installation while affected semantic attention remains.

## Failure and recovery

- Impact timeout, unavailable facts, or divergent current/displayed registers:
  promote conservatively and treat every Review context as affected for that
  candidate until supersession, installation, failure, worker replacement, or
  close; computation continues.
- Candidate build or validation failure: discard candidate; active bank remains;
  use existing retry classification. Render `Update unavailable` only while the
  classified failed promoted candidate affects the current attention context;
  retain only its bounded failure presentation and route Retry through the
  existing canonical comparison-retry owner. A failure before candidate-start
  classification keeps the global bar absent and uses the existing non-global
  refresh outcome.
- Worker reset: the pane runtime that already observes replacement calls the
  main store's worker-replacement preparation, discards the candidate bank and
  promoted chrome immediately, then resends the publication-applied receipt for
  the retained active bank after worker bootstrap.
- Successful worker retirement passes the retiring `workerInstanceId` from the
  existing session owner to the publication coordinator. It releases only an
  unmatched admission owned by that worker; an acknowledged display and other
  workers' authority remain unchanged.
- Full document replacement: the new main store has no active bank. Its current
  worker instance uses the bounded null-predecessor bootstrap rule to install
  only `nativeCurrent`; the prior acknowledged publication remains retained
  until the existing applied receipt establishes the new session's display.
- Main continuity failure: do not promote the bank; preserve editor and active
  Review; expose failure.
- Install-admission rejection: retain the active bank and annotation authority,
  discard the stale candidate, and admit only the newest replacement.
- Applied receipt delay or failure: retain newly active B and its annotation
  identity, retry idempotently, and classify successors conservatively until
  acknowledgment; do not re-expose worker-current C before native acknowledges
  B, and never roll back to A. A retry that succeeds runs the same bounded
  newer-projection comparison.
- Successor re-exposure failure: retain active B and worker-current C; do not
  fabricate a main candidate. A later idempotent installed-B retry or replacement
  worker re-evaluates the exact pair from current normalized state.
- Pane close: cancel impact work, release candidate bank, admission lease, and
  continuity leases through current editor teardown; no later event may install.
- Memory pressure: the candidate bank is bounded to one normalized Review and
  may not displace the active bank; inability to retain it becomes an explicit
  retained-Review failure.

## Cross-cutting realization

- Reliability: active and candidate banks are lineage-fenced and atomically
  promoted after exact install admission. Existing last-complete and retry owners
  remain.
- Performance: impact work uses existing bounded Git scheduling. Candidate
  representation is implementation-owned, bounded by the memory cost of one
  additional normalized Review, and must support atomic promotion. No clone,
  polling, or duplicated comparison build is prescribed.
- Accessibility: the existing Review header hosts one live status and actions;
  it never steals focus or inserts content rows.
- Privacy: telemetry includes class, reason, safe counts/buckets, generation,
  hold/install terminal, and duration only. Paths, source, selections, comments,
  and edit tokens are prohibited.
- Compatibility: pre-release internal Swift/worker contracts cut over together;
  the app and `BridgeDevelopmentProductHost` compose the same install-admission,
  applied-receipt, and retained-publication owners; the three physical Bridge
  routes and Review package schema remain singular.
- Security: no new trust boundary, authentication, authorization, or external
  input surface is introduced.

## Requirement realization and proof seams

- R-RRC-001/R-RRC-002: coordinator classification, acknowledged displayed
  publication, and shared publication path; prove displayed-to-candidate facts,
  exact install admission, conservative divergence fallback, one production
  path, and no ordinary chrome.
- R-RRC-003/R-RRC-004: main active/candidate banks and installation gate; prove
  classified first-patch ordering, state transitions, and real browser geometry.
- R-RRC-005/R-RRC-006/R-RRC-007: Pierre-owned leading-edge attention signal,
  edit continuity registry, displayed-publication resolver, and existing
  immutable origin/source evaluator; prove real draft persistence, Apply now,
  displayed-generation comment/output fencing, and placement results.
- R-RRC-008/R-RRC-009: one generation-fenced candidate bank, admission lease,
  and atomic bank promotion; prove immediately-before/after admission completion,
  delayed receipt, ordinary successor replacement, supersession, reset, and no
  partial visibility.
- R-RRC-010/R-RRC-011: pure header presentation; prove accessible text,
  keyboard actions, focus, reduced motion, and no loading row.
- R-RRC-012: bounded state and lifecycle telemetry; prove cleanup snapshots and
  marker-scoped source-scrubbed terminals.

Production-real proof must cross native invalidation, the existing Swift
backend/metadata route, comm worker, main render store, Review viewer, and
annotation persistence/source evaluation. Fakes may control interleavings but
cannot replace the final cross-boundary observation.

## Proof pyramid and development-server system

The proof pyramid climbs from deterministic policy to the real runnable surface:

```text
many unit proofs
  classification thresholds; lineage comparison; install-admission CAS;
  register monotonicity; one-candidate state transitions; attention/file mapping

fewer integration proofs
  worker final-barrier -> candidate bank; main-installed message -> existing
  publication-applied call; retained-publication annotation/output resolution;
  delayed receipt, admitted-B/successor-C replay, worker retirement and
  replacement, and continuity interleavings

real development-server smoke and E2E
  seeded disposable Git worktree -> Darwin/native invalidation -> Swift
  development backend -> production metadata/content/control routes -> comm
  worker -> Vite Review UI -> visible active/candidate behavior

packaged boundary proof
  packaged BridgeWeb in WKWebView plus native lifecycle/chrome, real comment
  persistence/output, accessibility/focus, reduced motion, and atomic geometry
```

Unit tests own pure decisions and illegal transitions. Integration tests use
fakes only to control ordering; the real production owners on each side of the
boundary remain in the test. The Swift development backend plus Vite is the
primary fast cross-boundary proof system because it exercises real worktrees,
native Git/source computation, production Bridge routes, and browser workers
without rebuilding the app for every iteration. It must prove at least ordinary
silent installation, promoted hold and Apply now, automatic install after
leaving an affected file, A-relative annotations and output while B waits,
successor admission around the linearization point, and delayed applied-receipt
recovery.

The development server cannot prove WKWebView packaging, App/native chrome,
LaunchServices lifecycle, or final accessibility and focus behavior. Those stay
in the small packaged proof cap. No mocked/unit lane may be reported as smoke,
and neither development-server nor packaged proof replaces the cheaper
deterministic layers.
