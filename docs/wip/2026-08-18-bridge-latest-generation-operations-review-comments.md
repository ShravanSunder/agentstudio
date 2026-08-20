# Bridge Latest-Generation Operations — Design Review Comments (validated)

- Date: 2026-08-18
- Review mode: three-artifact-design (independent fresh-context reviewer + parent code verification)
- Targets:
  - [2026-08-18-requirements.md](../specs/2026-08-18-bridge-latest-generation-operations/2026-08-18-requirements.md)
  - [2026-08-18-specification.md](../specs/2026-08-18-bridge-latest-generation-operations/2026-08-18-specification.md)
  - [2026-08-18-program-design.md](../specs/2026-08-18-bridge-latest-generation-operations/2026-08-18-program-design.md)
- Result: **needs-revision** — 2 blockers, 4 important accepted, 3 minor accepted, 4 rejected with evidence
- Remediation: **parent-verified complete on 2026-08-19** — accepted findings corrected in one `spec-design → program-design` pass; rejected findings excluded
- Every comment below was verified against current working-tree source by the review parent. Comments marked VALIDATED have code/doc anchors that were opened and reproduced. The reviewed Requirements, Specification, and Program Design targets were not edited by this review.

## Verdict on the actual question: does this solve the problem?

Mostly yes — and the spec is unusually well grounded (every "current system" claim checked against source is true). The supersession model (immediate logical authority transfer, drain-don't-block, late work can't publish), exact command receipts, supervised producers, and last-complete retention genuinely close: obsolete-work-overwrites, silent producer death, successor-blocked-behind-obsolete-pass, and stuck-"Saving".

**But the two blockers sit exactly in the stuck-loading lane that has been the recurring bane:**

1. F1: a Loading state the architecture itself says has **no operation and no terminal** (File descriptor-wait) is outside the whole operation contract — the contract that's supposed to guarantee "loading always clears".
2. F2: the most ordinary annotation race (notification arrives before the pane-presentation frame carrying the new source generation) is classified as a **failure**, burning the one automatic retry on a hopeless attempt and flashing the surface to unavailable during normal editing churn.

F1 and F4 settle the missing boundary between current operations and read-model publication; F2 separately classifies the ordinary stale-fence race. Ship the spec without F1/F2 and the stuck-placeholder class survives the correction.

---

## Blockers

### F1 — Descriptor-wait Loading has no operation behind it → outside the entire settlement contract  【VALIDATED · blocker · route: spec-design → program-design】

- Spec anchor: R-BLO-004 ("A loading indicator MUST be derivable from a current live operation and MUST clear on all terminal outcomes"); PD Operation-lifecycle Rule 4 ("Loading is derived **only** from a current operation in Queued/Preparing/CandidateReady").
- Code/doc anchors (verified verbatim):
  - `docs/architecture/bridge_web_runtime_architecture.md:105` — `Loading --> Loading: descriptor absent / pending`
  - `:121-125` — "`pending` is an internal fetch result… publishes **no terminal** content-availability patch, so the selected item remains `loading`"
  - `:158` — "a missing descriptor for current demand remains `loading`, with **no terminal publication**"
  - `:320` — the doc itself already calls "a permanent `loading` entry with no active demand or retry owner" a lifecycle bug.
- Problem: the Requirements name this architecture as the foundation to preserve, and the PD's only treatment of the File-content lane is "keeps its existing abort-controller plus preparation-generation pattern… exposes its operation terminal". But the descriptor-wait state has no operation to expose a terminal for. Either it is an operation stuck forever in `Preparing` (violates R-BLO-004 and R-BLO-014's "every stage-start has a terminal or bounded missing-terminal diagnostic"), or it is not an operation and Rule 4 forbids showing Loading at all. **This is the exact stuck-placeholder state that keeps recurring, and the design's answer to that lane is "preserve and instrument".**
- Smallest correction: Selecting a current File item admits a File-content operation immediately. Descriptor-wait is that operation's `Preparing` stage, and `file.descriptorReady` continues only the current selection epoch. The operation terminates `ready` after content/render fulfillment, `unavailable` when current metadata settles without a usable descriptor, `stale` when its source or selection is superseded, `cancelled` when selection clears, or `failed` on content/preparation failure. This preserves event-driven descriptor arrival without polling or an arbitrary timer while ensuring visible Loading always has a current owner and terminal.

### F2 — Stale-fence rejection has no terminal classification → benign race degrades the surface  【VALIDATED · blocker · route: spec-design → program-design】

- Spec anchor: R-BLO-006 (retry-then-unavailable attaches to *failure*); Terms define stale/superseded as a distinct terminal but nothing classifies fence rejections.
- Code anchors (verified):
  - `Sources/AgentStudio/Features/Bridge/Transport/WorktreeAnnotations/BridgePaneProductWorktreeAnnotationProjectionSource.swift:111-113` and `:157-159` — query throws `staleSourceGeneration` when its fence doesn't match current (checked before capture and re-validated after).
  - `BridgeWeb/src/core/comm-worker/bridge-comm-worker-annotation-projection-query-controller.ts:217-225` — every thrown error routes to `#onFailure` when the attempt is still the newest.
- Problem: per R-BLO-013, `notificationRevision` may not serve as the query source fence, so the fence comes from demand fed by pane presentation on a *different stream*. Whenever an annotation notification lands before the presentation frame (the most ordinary interleaving under editing churn), the query is fenced out with `staleSourceGeneration` and — as failure — triggers one automatic retry of the *same stale generation* (guaranteed to fail again), then `unavailable` with a retry button, until the presentation frame arrives and recovers it. Classified as *stale/superseded* instead, the design must guarantee a successor for every stale rejection — true here (the presentation frame advances demand) but stated nowhere. Two implementers produce opposite user-visible behavior.
- Smallest correction: Specification — a rejection caused by losing a current fence is a `stale/superseded` terminal, never a failure, and a stale terminal MUST be paired with a named guaranteed successor trigger; absent such a trigger it is a failure. PD then names the annotation lane's successor trigger (pane-presentation source-generation advance).

---

## Important

### F4 — R-BLO-003 atomicity contradicts the PD's progressive File emissions  【VALIDATED · important · route: spec-design】

- Spec says partial replacements MUST NOT replace last complete state for "Each File… surface"; PD (correctly, to preserve BLO-U12 progressive browsing) has File metadata publish incrementally under a revalidated fence (`BridgePaneController+RefreshAdmission.swift:171-200` shows today's sequential changeset→status publication that can return `.stale` mid-sequence). An operation superseded after 3 of 5 emissions leaves a generation-9/10 mixture that the Spec's own words call a forbidden partial replacement, and "last complete state" is undefined for an incremental lane.
- Smallest correction: scope R-BLO-003 atomicity to logically finite results (Review publication, finite content, projection, render); give the File progressive lane its own completeness rule — which emission set constitutes `ready`, and that superseded partial emission sets MUST be re-covered by the successor's dirty aggregate (the PD's min-generation/max-batch union already implies this; say it).

### F6 — "Retryable" is load-bearing and never defined  【VALIDATED · important · route: spec-design】

- Code anchors: eight error cases with no retryability attribute (`BridgePaneProductWorktreeAnnotationProjectionSource.swift:4-13`); content error terminals *do* carry `retryable: boolean` (`bridge-product-content-contracts.ts:310-316`); `failReviewComparisonAttempt` takes caller-supplied `retryable: Bool` (`BridgePaneRefreshAdmissionCoordinator.swift:220-239`). The classification exists on some routes and not others, and neither artifact classifies a single failure family.
- Problem: R-BLO-006's whole retry-then-unavailable behavior branches on it. Misclassify capacity timeout → transient contention becomes permanent unavailable; misclassify digest mismatch → hopeless auto-retry. "Retry policy belongs in AppPolicies" locates a constant, not the semantics.
- Smallest correction: R-BLO-006 defines retryable by observable property (cause may resolve without new user/source input) and enumerates the current failure families on each side of the line (capacity timeout, stale fence [see F2], source unavailable, capture unavailable, descriptor mismatch, digest mismatch).

### F7 — The metadata overflow terminal named by the PD does not exist as a frame kind  【VALIDATED · important · route: program-design】

- Code anchors (verified): `BridgeProductProducerContracts.swift:51-61` — the only terminal metadata frame is `.metadataStreamError`; metadata has no terminal *reset* kind (content does: `.end/.error/.reset`). Reserved terminal capacity and queue-replacement already exist (`BridgeProductProducerRegistry.swift:163-205`), and `BridgeProductProducerFrameValidator.swift:64-69` rejects any overflow frame that is not terminal. The defect the design targets is real and verified: both pane-metadata `overflowReset` builders emit **ordinary** frames (`BridgePaneProductMetadataCoordinator.swift:493`, `:591`), and the `.queueReset` outcome is recorded as `result: .success` — exactly what R-BLO-008 forbids.
- Problem: the PD's sequence says `terminal resync-required`, an identity that doesn't exist. One implementer adds a new terminal metadata frame kind (a wire-contract addition never enumerated in "Wire contract and time", which R-BLO-010's vectors must then cover); another reuses `.metadataStreamError(code: .resyncRequired)` (already how the session-level `metadataStreamOverflowReset` behaves — `BridgeProductSession+ProtocolLifecycle.swift:255-269`). Different observable stream health. Also be precise about which enum is meant: `resync_required` is a *request-error code*, `producer_overflow` is a *reset reason* (`bridge-product-contract-primitives.ts:106-125`).
- Smallest correction: PD names the exact terminal identity for metadata overflow (reusing `metadataStreamError(code: .resyncRequired, retryable: true)` is the smaller move — the fix is then just the two builder closures); if a new frame kind is chosen instead, list it in the wire-contract section for R-BLO-010 coverage.

### F8 — The wire-vocabulary exhaustiveness proof names a capability Swift doesn't have; enforcement owner undecided  【VALIDATED · important · route: program-design】

- Code anchors (verified): `BridgeProductStrictJSON.swift` — `productMemberVocabulary` is a hand-maintained flat allowlist with no structural link to contract `CodingKeys`; no test cross-checks it (5 existing tests cover duplicates/bounds only). Some `CodingKeys` are `CaseIterable`, many are not; compiler-synthesized key sets are not runtime-enumerable at all.
- Problem: the targeted defect is real (add a field → forget the allowlist → native rejects its own valid response after commit — BLO-U8's exact scenario). But the PD's "compares every reachable `CodingKeys` raw value **and synthesized key**" is not implementable by runtime reflection, and its "contract registry **or** generated checked mirror" leaves the enforcement owner and class (compile/lint/test failure) undecided. A third option — a SwiftSyntax pass in the existing `Tools/AgentStudioArchitectureLint` — is repo-native and never mentioned, but must re-derive synthesized keys from stored properties, which breaks for the many types with hand-written `encode(to:)`.
- Smallest correction: PD selects one enforcement owner, states its enforcement class, and replaces "synthesized key" with the derivation rule that owner can actually apply.

---

## Minor (accepted)

### F9 — Two generation concepts share nearly the same name; commit fence ambiguous  【VALIDATED · minor · route: program-design】
`desiredGeneration` (latest-intent supersession fence) vs the dirty generation ("earliest unapplied invalidation interval… not a Lamport latest-generation value"; merge keeps earliest at `BridgePaneRefreshAdmissionCoordinator.swift:329-335`, restore uses `min` at `:371-387`). Using the earliest-unapplied value as the commit fence would let obsolete work pass its own fence check — silently reintroducing the R-BLO-001 defect. One name per quantity; state that the commit fence is the desired-generation captured at admission.

### F13 — Only the annotation producer gets a worked supervision machine  【VALIDATED · minor · route: program-design】
R-BLO-007 covers "a metadata or annotation notification producer" but the PD draws the supervision state machine for the annotation producer only. "Silent subscription death" is one of the three named recurring failures and File/Review metadata + content producers are the higher-volume instances. Correction: state that the same supervision machine governs every protocol producer and name those in scope.

### F11 — `BridgeOperationFence` is a shared type the design immediately disowns  【VALIDATED · minor · route: program-design】
Declared in the shared vocabulary, then "No shared component owns current-generation policy… Each feature owner defines its fence", followed by seven structurally different tuples. Deletion test passes: telemetry needs safe generations, not a shared fence type; no proof seam names it. The PD's own fifth falsifier anticipates this. Correction: delete it from the shared vocabulary; the per-owner fence table carries the meaning.

---

## Rejected (with evidence — do not act on)

### F3 — "Bounded wait" requires a new operation-level deadline — REJECTED

The source evidence is real but the proposed correction expands policy. `BridgeGitReadScheduler` owns bounded logical waiters and excludes same-worktree `.running` or `.draining` work from successor admission; its existing per-request deadline supplies the capacity terminal. The settled design direction is to reuse that capacity owner's bounded wait, not introduce a pane/refresh-operation watchdog. An operation-level wall-clock ceiling would be a new behavioral policy and contradict the rejected timeout/watchdog alternative. Clarification only: a Git capacity timeout terminates the current lane `unavailable`; no second pane-level timer is added.

### F5 — Correlation cleanup clears live command waiters without settlement — REJECTED

The cited source demonstrates the opposite on the inspected lifecycle path. `worktree-annotation-surface-client.ts:325-345` rejects every pending command, inspection, candidate query, and snapshot waiter with the disposal error before clearing its maps. R-BLO-004 already requires exactly one terminal for every admitted command. A reset/replacement proof case should verify that this invariant remains true, but no separate Specification correction is established by the cited evidence.

### F12 — `refreshing` may exist without a live current operation — REJECTED

The proposed correction contradicts R-BLO-004 and Program Design Rule 4, which make visible loading derivable only from a current live operation. Visible retained dirty work must admit a current queued operation before presenting `refreshing(lastComplete)`. If current admission cannot be established, the surface is `unavailable(lastComplete, admission failure)`; an inactive/hidden surface does not make a visible loading claim. Do not create a second loading authority from retained dirty state.

### F10 — "`semanticRevision` has no consumer" — REJECTED
The reviewer's deletion test missed the PR1 lineage. `semanticRevision` originates in the PR1 program design (`docs/specs/2026-08-06-worktree-annotations/pr1-program-design.md:257`, `:281`) and **is consumed**: "the aggregate retains the newest semantic revision per applicable session" (`pr1-program-design.md:270-273`) — it drives per-session newest-wins coalescing in the observer aggregate, mirrored by the new PD's "Per-observer aggregation retains the newest demanded session revision". Optional (observation only): R-BLO-013 could name that role explicitly.

---

## Validated positives — the design targets real bugs (verified in source)

These survived adversarial checking; do **not** re-litigate them during revision:

1. **All "current system" claims checked are true**: combined File+Review pass with single `activeReviewRefreshTask` gate (`BridgePaneController.swift:70`, `+RefreshAdmission.swift:133-135`); failed pass skips immediate retry (`:158-160`); worker does not abort in-flight query on newer invalidation (`bridge-comm-worker-annotation-projection-query-controller.ts:164-183`); native single mutable `logicalReservation` wiped per fresh query (`BridgePaneProductWorktreeAnnotationProjectionSource.swift:78`, `:176-189`).
2. **Timestamp defect is real and worse than the spec implies**: Swift encodes annotation `Date`s via default `JSONDecoder`/`JSONEncoder` (`BridgeProductStrictJSON.swift:438`, no `dateDecodingStrategy` anywhere in Bridge) = seconds since 2001; TS validates bare `z.number().finite()` (`bridge-product-worktree-annotation-contracts.ts:10`) and constructs `new Date(n)` = ms since 1970. R-BLO-011's `…UnixMilliseconds` cutover is well aimed; the RFC 3339 carve-out for exported batch JSON is accurate (`WorktreeAnnotationBatchProjector.swift:152`).
3. **Three-page rejection is real**: `expectedPage ??= descriptor.page` freezes the contract at page 0 and `expectedOrdinal = expectedPage.pageOrdinal + 1` then permanently expects ordinal 1 (`bridge-comm-worker-annotation-projection-query-controller.ts:253-261`, `:365`); a genuine 3-page snapshot fails today. R-BLO-009's "including three or more pages" clause targets this exactly.
4. **Overflow defect is real**: ordinary frames passed as overflow builders + `.queueReset` recorded as success (`BridgePaneProductMetadataCoordinator.swift:493-517`, `:591-599`); reserved terminal capacity already exists, so R-BLO-008 is cheaper than it reads (see F7).
5. **Content-terminal asymmetry is real**: only `annotation.output`'s complete terminal lacks `observedByteLength` (`bridge-product-content-contracts.ts:326-333` vs the other four).
6. **Scanner allowlist drift is real**: hand-maintained `productMemberVocabulary` with zero cross-checks (see F8).
7. **Requirements coverage is complete**: BLO-U1..U12 all reach normative requirements; all 15 R-BLO realized in the PD table; no scope expansion; no requirement subtraction.
8. **Bounded-wait capacity owner exists** (`BridgeGitReadScheduler` with slots, deadlines, coalescing) — the design correctly treats it as existing. F3's proposed second operation-level deadline is rejected.
9. **Two-reservation snapshot bound is properly specified** (owner, AppPolicies bound of 2, third-replacement revocation, unclaimed-descriptor settlement).
10. **Alternatives/cutover sections are sound**: three directions each with falsifier; hard cutover, no shim, rollback = source rollback — matches repo convention.

## Coverage gaps (honest limits of this review)

- PR1 Specification was not opened (PR1 program design was opened only for the `semanticRevision` check). R-BLO-013's four-variant vocabulary matches PR1's design (`pr1-program-design.md:278-284`) on face.
- Review render-fulfillment coordinator inspected by grep only; the PD's render-lane claims (stale receipt cannot clear current loading) are plausible but unverified against source.
- `bridge_native_runtime_architecture.md` not read in depth (F1 rests on the transport + web-runtime docs, which agree with each other and with code).

## Parent-verified remediation closure

Current target identities:

- Requirements: `5e28be872703074d1205f3ebb891eb547052114d9843eb1ad7c4dd571607e466` (unchanged)
- Specification: `1c707d08c26a72f48809598320c8795f8be87ba6d2412ecd105852cc305f79b7`
- Program Design: `942bcbde881e36a975cdb5fddd4ea614bf473326be9af25514fc398b8474a3d7`

| Finding | Corrected owner and anchor | Parent verification |
| --- | --- | --- |
| F1 | Specification R-BLO-004; Program Design `File selected-content operation` | selection admits the operation before descriptor arrival; descriptor wait is preparing; producer/source/selection/content/render paths settle it; no polling or descriptor watchdog |
| F2 | Specification R-BLO-006/R-BLO-013; Program Design `Cancel-and-replace query controller` | fence mismatch is stale, not failure; convergence operation remains live; pane-presentation generation owns the successor; retry is not consumed |
| F4 | Specification R-BLO-003; Program Design `Private prepare and atomic commit` | finite results remain atomic; progressive File metadata uses current-fenced coverage and successor re-coverage |
| F6 | Specification R-BLO-006; Program Design `Failed current work with retained dirty state` | retryable is defined; current failure families map to retryable failure, non-retryable failure, stale, preparing, or unavailable surface behavior |
| F7 | Program Design `Metadata overload and replay` | overflow reuses existing `metadataStreamError(.resyncRequired, retryable: true)`; no new metadata-reset frame kind |
| F8 | Program Design `Exhaustive strict vocabulary` | one explicit contract-vocabulary registry owns scanner members; explicit `CaseIterable CodingKeys`, exhaustive roots, and production round-trip vectors replace reflection/unchecked flat vocabulary |
| F9 | Program Design `Native File and Review refresh ownership` | `authorityGeneration` is the admission/commit fence; `earliestUnappliedGeneration` is dirty coverage and never a commit fence |
| F11 | Program Design `Common lifecycle vocabulary` | shared fence type removed; owner-specific fence inventory remains |
| F13 | Program Design `Protocol producer supervision` | pane-presentation, File/Review metadata, annotation notification, and finite content producers have explicit supervisors and terminal behavior |

Rejected findings remain excluded:

- F3: no new operation-level or pane watchdog; existing capacity-owner deadlines remain authoritative.
- F5: no duplicate cleanup obligation was added; existing exactly-one-terminal contract remains.
- F10: `semanticRevision` remains in the scoped invalidation contract.
- F12: retained dirty state does not become an independent Loading authority; visible refreshing remains derived from a live current operation.

Parent integration checks:

- exactly four semantic terminals remain: succeeded, failed, cancelled, stale;
- `unavailable` remains a retained surface state, not an operation terminal;
- Requirements/Specification/Program Design identities remain separate;
- Requirements and accepted BLO-U1…U12 boundary remain unchanged;
- no Atom, new route, polling loop, operation-level watchdog, durable task state, compatibility shim, or capacity increase entered the design;
- eight Mermaid source diagrams plus plain prose/table normative homes were inspected for state/flow agreement; Node rendering remains unverified because Mermaid 11.16.1 fails before render on its DOMPurify hook in this environment;
- Program Design remains below the repository's 900-line refactoring prompt.

## Recommended next step

The original independent review plus this parent-verified bounded remediation closes the design review; do not dispatch another reviewer automatically. Route the current three-artifact design to `plan-implementation`.
