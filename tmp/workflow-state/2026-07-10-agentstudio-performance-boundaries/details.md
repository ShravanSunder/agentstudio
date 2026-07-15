# AgentStudio Performance Boundaries Goal Details

Goal id: `2026-07-10-agentstudio-performance-boundaries`

## Objective

Implement the accepted AgentStudio performance-boundary specs and reviewed plans so huge watched roots cannot starve terminal typing, cursor/caret, TUI mouse, focus/reveal, or MainActor availability; high-rate source samples contract before global delivery; Ghostty callback/lifetime/host boundaries remain correct; performance claims are proven baseline-to-candidate through Victoria; and the branch reaches a reviewed, PR-ready, non-merged state.

## Accepted source artifacts

- `docs/specs/2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md`
- `docs/specs/2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md`
- `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md`
- `docs/specs/2026-07-09-ghostty-terminal-interaction-fairness/ghostty-action-admission-manifest.md`
- accepted spec checkpoint: `c9f553e1`

## Reviewed implementation artifacts

- `docs/plans/2026-07-10-agentstudio-performance/implementation-plan.md`
- `docs/plans/2026-07-10-agentstudio-performance/watched-folder-and-shared-runtime-plan.md`
- `docs/plans/2026-07-10-agentstudio-performance/ghostty-terminal-interaction-plan.md`
- reviewed plan checkpoint: `a042d20fb57196a914417c8e3d70719321045baf`
- plan review synthesis: `tmp/plan-workflows/2026-07-10-agentstudio-performance/review/plan-review-synthesis.md`
- Claude Fable receipt: `tmp/plan-workflows/2026-07-10-agentstudio-performance/review/claude-fable-advisor-receipt.md`

## Review-cycle ledger

- D2c/D3 focused lifecycle reconvergence, 2026-07-13: implementation source
  proved three accepted assumptions incomplete. Source-kind changes have no
  implicit logical correlation key because kind is part of `FilesystemSourceID`;
  native commitment has no consumed create-or-abandon right; and `.starting`
  callback custody can enter the mailbox before accepting publication while
  whole-lease transfer lacks a publication-eligibility check. Direct cleanup
  context release also bypasses D3. Product edits are frozen while the focused
  contract is aligned. Focused review plus the local FSEvents SDK corrected the
  initial draft: callbacks begin only after successful native start, so every
  unpublished route proves zero callback/mailbox custody and no second consumer
  exists. The revised recommendation uses explicit exact-prior configuration
  intents, one fixed per-binding native owner with separate one-shot create and
  start rights, `createdNeverStartedClosed` withdrawal, atomic accepting
  publication with a complete retained close-obligation disposition, one
  bounded desired-record continuity requirement handed to the next accepting
  binding when prior continuity is absent, same-source exact replacement with
  cross-kind change represented as old-source removal plus new-source install
  through existing source-ID-keyed receipts, and one D3
  permit/acknowledgement union that keeps H2 semantically unchanged. Raw context
  release from cleanup or deinitialization is forbidden. Revised draft:
  `tmp/spec-workflows/2026-07-13-d2c-d3-lifecycle-reconvergence/focused-lifecycle-amendment.md`.
  Broad spec review `2/2` and broad plan review `1/1` remain closed.
  The user-approved smaller correction keeps UUIDv7 for native/lifecycle
  lineage but removes the proposed cross-source configuration-operation UUID:
  replacement is same-source only and cross-kind change is old-source removal
  plus new-source install. One final focused review cycle found and the parent
  validated two type-surface gaps: SourceGate handoff needed exact idempotent
  replay, and accepting-plus-repair needed an honest non-current configuration
  disposition. The one remediation adds fixed `pending | handoffInFlight`
  desired-record custody and `installedAwaitingContinuityRepair`; it adds no
  actor, task, map, EventBus route, MainActor work, or ownership boundary. The
  correction is folded into the maintained specs and D2c/D3 plan; implementation
  resumes at D2c. Review reduction:
  `tmp/spec-workflows/2026-07-13-d2c-d3-lifecycle-reconvergence/final-focused-review-reduction.md`.

- H2 exact transfer checkpoint, 2026-07-13: dormant whole-lease transfer now
  requires exact semantic acceptance, exact SourceGate acceptance when recovery
  exists, and one opaque combined authority before generic acknowledgement.
  Semantic and recovery replay clear require that exact authority and the exact
  post-acknowledgement receipt; stale same-binding acknowledgements cannot clear
  later custody. The registry retains the final retirement receipt and stops at
  `retiredAwaitingContextRelease`, leaving native release, acknowledgement,
  vacancy, and reuse solely to D3. Focused 16-test, combined 87-test, callback
  architecture 21-test, full `mise run test`, full `mise run lint`, and
  `git diff --check` gates exited 0. Independent adversarial reviews returned
  READY after authority, stale-acknowledgement, and recovery-retry repairs.
  Production remains legacy-only until W2b, so no product-performance claim is
  made. Receipt:
  `tmp/plan-workflows/2026-07-13-w1b-fixed-slot-lifecycle/h2-exact-transfer-proof-receipt.md`.

- F2 retirement-fence checkpoint, 2026-07-13: dormant fixed-slot lifecycle
  now converts an exact native-generation lease-drain receipt into bounded
  predecessor and pending-fence custody, installs the fence as the final
  generic gather contribution, and retries only after valid acknowledgement or
  cleanup progress. An adversarial RED reproduced an empty-queue precondition
  crash during ordinary progress; the repair and permanent regression proof are
  green. Shared `A, B, fence` finality and identity, idempotence, one-head
  acknowledgement rotation, and exactly-one post-lock wake are permanent.
  Focused 11-test and combined 56-test lanes, full `mise run test`, fresh
  `mise run lint`, and `git diff --check` exited 0. H2 still solely owns exact
  semantic replay plus SourceGate transfer authorization and final retirement
  receipt. Production remains legacy-only until W2b, so no performance claim
  is made. Receipt:
  `tmp/plan-workflows/2026-07-13-w1b-fixed-slot-lifecycle/f2-retirement-fence-proof-receipt.md`.

- H1 fixed per-slot semantic replay checkpoint, 2026-07-13: dormant replay
  retains an exact binding plus ordered contribution vector, rotates UUIDv7
  attempt authority across retry/rebind, preserves a dense accepted prefix,
  and bounds identity retention to `Q` per slot and `P × Q` per fleet. The
  permanent three-slot proof resumes distinct partial prefixes in rotated
  order and applies all 12 contributions exactly once. Focused H1 and mailbox
  integration, full `mise run test`, and fresh `mise run lint` exited 0. The
  scoped checkpoint is commit `b7634ee9`. Production remains legacy-only until
  W2b; F2/H2 are the next implementation boundaries.

- Atomic W1b E/F1/G1 callback-admission checkpoint, 2026-07-13: dormant
  fixed-slot callback admission is exact-binding credentialed and one-shot;
  mailbox coordination has one lexical mutable owner; raw producer and
  callback-only authority surfaces are removed; lazy control-block drain
  waiters add no retained task/stream per source; and 1/100/300/301 proof keeps
  fleet work out of the callback. Focused repair recheck is READY, `mise run
  lint` and `mise run test` exited 0, and the scoped checkpoint is commit
  `92f9bd1f`. Production remains legacy-only until W2b; H1 semantic replay is
  the current implementation slice.

- Focused opaque-recovery representation correction, 2026-07-13: the fixed
  recovery shell retains the complete opaque generic recovery revision rather
  than exposing its private stamp. Binding plus UUIDv7 domain custody remain the
  only domain authority. This is a type/encapsulation correction, not an
  architecture, boundary, requirement, or product-behavior change. The atomic
  gate also owns the minimal SourceGate value-signature migration needed for a
  compile-complete hard cut; H2 retains all semantic transfer and retirement
  ownership. Checkpoint: `7d873929`.

- User-approved performance-first sequencing correction, 2026-07-12:
  product behavior and focused runtime proof now precede S1h/S1i completion,
  S5, W11, and final lint expansion. The accepted product/spec contracts and
  atomic hard-cut gates are unchanged. Source:
  `docs/plans/2026-07-10-agentstudio-performance/performance-first-sequencing-amendment.md`.

- Spec review cycles: `2/2` complete.
- Plan review cycles: `1/1` complete.
- Do not rerun a broad spec or plan review merely to regain confidence. If implementation evidence breaks the accepted model, stop code edits, record the contradiction, and route the smallest affected contract back to its owning phase after reconvergence.
- Implementation review remains open and is required before PR wrap-up.
- Focused S1 implementation re-review is `not_ready`. Five accepted roots are
  being corrected without reopening the completed broad spec/plan review cycles:
  bind/doorbell liveness, capacity-accounted cleanup custody, negative journal
  sizes, bounded replay/diagnostic/invalidation lock work, and independent
  operation-shape proof.
- Focused correction source: `docs/plans/2026-07-10-agentstudio-performance/s1-admission-correction-plan.md`.
- Focused correction result: contract-coherence and plan/proof-fit rechecks are
  READY; `git diff --check` and `mise run lint` passed. Official workflow has
  returned to `implementation-execute-plan`; earlier S1 green receipts are stale.
- Focused gather-age correction: exact dynamic global age conflicted with
  strict O(1) protected work. The accepted amendment introduces typed
  `AdmissionAgeMeasurement` precision, explicit custody sets, mailbox-timestamp
  read-time aging, bulk-transfer precision inheritance, and a literal
  non-understatement oracle. Focused spec and plan rechecks are READY; broad
  review-cycle counts remain unchanged. Implementation is again the current
  workflow.
- Focused gather-age ledger:
  `tmp/spec-workflows/2026-07-11-s1-gather-age-amendment/swarm-ledger.md`.
- Focused S1 completion review: `not_ready`. The source-backed review accepted
  physical-custody, cleanup-accounting, latest delivery-quantum, journal
  snapshot-pressure/diagnostics, gather invalidated-metadata, architecture-rule,
  typed-age, lifecycle-conformance, raw-state-authority, and mutation-proof
  findings. Code edits are frozen while only the missing Admission contract
  returns to `spec-creation-swarm`; broad spec/plan review counts remain closed.
- Focused completion review synthesis:
  `tmp/plan-workflows/2026-07-10-agentstudio-performance/review/s1-admission-completion/review-synthesis.md`.
- Focused latest-overload correction: the accepted `D/R/C` contract closes
  auxiliary and physical custody, cleanup-free replacement-wave scope,
  cleanup-finalization delivery reservation and final-batch wake, per-value
  latest retry, incumbent-lease preservation, and atomic authoritative-resample
  debt clearing. Native whole-contract, proof, and adversarial rechecks plus the
  persistent Fable advisor are `READY`. Focused planning is the current route;
  implementation remains frozen until that translation and review are ready.
- Focused latest-overload review synthesis:
  `tmp/spec-workflows/2026-07-11-s1-physical-custody-reconvergence/review-synthesis.md`.
- Focused physical-custody plan translation: READY. The corrected S1a–S1i
  plan now owns slice-local RED/GREEN, exact family wrapper/token and journal
  raw-state boundaries, `Int.max` capacity versus `UInt64.max` authority proof,
  transactional dirty-worktree rollback, lane-A/S5 serialization, executable
  privacy canaries, and final plan/matrix freshness. Three native recheck lanes
  plus the same persistent Fable Advisor returned READY.
- Focused plan review synthesis:
  `tmp/plan-workflows/2026-07-10-agentstudio-performance/s1-physical-custody-plan/review/review-synthesis.md`.
- Focused accepted spec/plan checkpoint commit: `8a2f3975` (`docs: finalize S1
  physical custody plan`), containing only the maintained performance spec,
  parent implementation plan, and focused S1 correction plan.
- Official current workflow after event
  `2026-07-11T13:32:59Z-s1-physical-custody-plan-ready`:
  `shravan-dev-workflow:implementation-execute-plan`. The first unproven gate is
  S1a; implementation must populate the pending physical-custody correction
  receipt and may not reuse earlier GREEN counts.

## External advisor continuity

- Agent: Claude Fable through ACPX.
- ACPX relationship/session id: `9e3e7cee-a26b-4ce8-93c3-f3355af5e740`.
- Provider-native session id: `c17a833a-acc7-4061-a6b5-7796fc1a3ada`.
- Session cwd/context: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.ghostty-performance`.
- Exact custom model: `claude-fable-5[1m]`; requested reasoning: `xhigh`.
- Permission boundary: read-only (`--approve-reads --no-terminal`); no repository or home writes.
- Latest assignment result:
  `w1b-sealed-callback-lifecycle-advice-20260712` resumed the same relationship,
  provider session, exact model, and `xhigh` reasoning, but the provider rejected
  the assignment because its usage limit resets July 16 at 11:00 America/Toronto.
  No advisor claim was used and no replacement session was created.

## Allowed write scope

- Tracked AgentStudio source, tests, scripts, docs, `AGENTS.md`, `.mise.toml`, and vendored Ghostty pointer/artifacts only where the reviewed task packets authorize them.
- `tmp/workflow-state/2026-07-10-agentstudio-performance-boundaries/**` and plan/task evidence under repo-local `tmp/`.
- Disposable build/source worktrees and isolated debug app/data/zmx identities created by the reviewed harness.
- For real-root qualification only, a canonical run-token-owned `.agentstudio-performance-soak/<run-token>` directory beneath each explicitly authorized root.

Existing repositories beneath `/Users/shravansunder/Documents/dev/open-source` and `/Users/shravansunder/Documents/dev/project-dev` are read-only. No old sentinel is deleted automatically. The vendor submodule cutover occurs only at T12 after isolated candidate acceptance.

## Non-goals

- Deep Bridge/React render redesign beyond the bounded refresh/currentness containment in W10.
- Screen capture or broadcast of terminal screen contents.
- A permanent dual-version Ghostty runtime, compatibility shim, or runtime vendor selector.
- A second product EventBus or actor-per-pane rewrite.
- Mutation of existing repositories in the real watched roots.
- Weakening/deleting proof to obtain green results.
- Merging the PR; merge requires separate authorization.

## Requirements/proof matrix

### R1 — High-rate admission contracts before expansion

Proof source: RED/GREEN unit and bounded-flood integration tests for
`LatestValueMailbox`, value-only `BoundedGatherMailbox`, `OrderedFactJournal`,
source gates, zero UI-sample global posts, zero critical drops, exact gap/debt
recovery, retained-custody limits, one-key retry fairness, bind/rebind authority,
and orthogonal contraction/recovery counters.

Evidence source: parent-run focused commands plus task receipts from `implementation-execute-plan`.

Freshness guard: current HEAD, exact task spec hashes, current source inventory, and no legacy/new dual publication.

### R2 — MainActor remains available and attributable

Proof source: `performance.mainactor.work`, `performance.mainactor.heartbeat`, and `performance.pipeline.contraction` Victoria evidence; queue age and synchronous service remain separate; injected-clock heartbeat tests; fixed-change 10/100/300 scaling; no acceptance span crosses `await`.

Evidence source: focused unit/integration tests, marker-scoped VictoriaMetrics/VictoriaLogs queries, and independent MainActor heartbeat records.

Freshness guard: exact PID, run marker, build identity, calibration digest, operation manifest, and non-evictable summary receipt agree.

### R3 — Terminal interaction remains direct under pressure

Proof source: causal AppKit dispatch-to-handler, Ghostty host-call service, `inputToFrameLayerPublished`, typing echo, cursor/caret, TUI mouse, focus, reveal, and loaded-output distributions under idle, watched, terminal, and combined pressure.

Evidence source: authenticated IPC control/status/snapshot/wait, Victoria, and PID-targeted Peekaboo against the exact debug process. Use Computer Use for native interactions that the authenticated IPC and Peekaboo control surfaces cannot express; record the exact PID and interaction receipt so UI driving cannot be confused with a different app instance.

Freshness guard: current PID/run/vendor/host/corpus/display capability manifest; pre-marker, stale-generation, wrong-size, or missing-watermark frames are rejected.

### R4 — Ghostty callback and lifetime boundary is safe

Proof source: pinned/candidate callback lease, tick-gate, clipboard/close token, surface/app teardown, post-free sentinel, resource/action manifest, and native quiescence tests.

Evidence source: focused unit tests, real vendor integration harness, `verify-ghostty-vendor-manifest`, `verify-ghostty-terminal-native`, and T11/T12 receipts.

Freshness guard: exact Ghostty commit/header/library/resource/executable/adaptation/probe digests and current app generation.

### R5 — Vendor and host improvements are independently attributable

Proof source: immutable P0/N0/P1/N1 factorial report, conditional A0 adaptation-control identity for a pure-vendor claim, eight probe-perturbation prerequisites, absolute/control-relative deltas, and adequacy checks.

Evidence source: shared comparison scripts plus VictoriaMetrics distributions, VictoriaLogs stage validity, and the out-of-band run summary.

Freshness guard: alternating build order, human-approved immutable CG1 digest, identical scenario manifests, and no candidate-selected window/retry/trimming/threshold.

### R6 — Watched folders never authorize false removal or false currentness

Proof source: loss/overflow/replacement/unavailable cases, complete-authoritative removal rule, repair acknowledgement ledger, `WatchedFolderCurrentnessAtom`, visible Repo Explorer non-current states, and independent final topology/SQLite/content oracles.

Evidence source: deterministic filesystem/Git integration tests, W12 generated workloads, DQ1, and PID-targeted native visibility proof.

Freshness guard: source/registration/repair generation, current root manifest, current canonical revision, and quiescent repair debt.

### R7 — Persistence has one revision owner and one writer

Proof source: fixed-revision leases/pages, contiguous update journal, stale-checkpoint rejection, persistence chaos/recovery, one outer transaction revision, and structural sole-writer inventory before/after W7d.

Evidence source: unit/integration tests plus fresh SQLite reload through independent repository/datastore read APIs.

Freshness guard: current process generation, accepted canonical revision, datastore receipt, and no intermediate dual-writer commit.

### R8 — Agent state/notifications use authenticated semantic IPC

Proof source: authenticated Unix-socket agent report and notification methods, pane identity derived from principal, session/sequence idempotency, lease/revocation/rate/payload rules, terminal snapshot/wait behavior, and no screen capture.

Evidence source: focused IPC tests and a real authenticated IPC smoke/control run against the exact debug app.

Freshness guard: current socket, principal, runtime/app generation, pane identity, PID, and run marker. Unsafe-no-auth mode cannot satisfy acceptance.

### R9 — Real development roots remain usable and stable

Proof source: DQ1 baseline/candidate runs for `open_source`, `project_dev`, and both together; read-only initial/cold/settled observation; controlled sentinel churn; root pre/post manifests; MainActor/interaction/currentness/memory gates; clean shutdown.

Evidence source: `verify-agentstudio-real-root-qualification`, VictoriaMetrics/VictoriaLogs, authenticated IPC, and PID-targeted Peekaboo, with Computer Use only for remaining native controls that those deterministic surfaces cannot drive.

Freshness guard: aliases only in exported evidence, canonical sentinel containment, unique run token, exact current root/build/calibration manifests, alternating order, and unrelated churn invalidates attribution.

### R10 — Compiler/static architecture boundaries prevent regression

Proof source: type separation (`RuntimeDomainFact`, local samples, compact synchronous mutation appliers), `MainActorBlockingWorkRule`, `RuntimeSignalPlaneRule`, rule inventory/parity/good-bad fixtures, and architectural source inventories.

Evidence source: focused architecture-lint tests and `mise run lint`.

Freshness guard: current source tree and zero permanent broad allowlists; runtime proof remains mandatory.

### R11 — Operator and future-agent guidance stays current

Proof source: `docs/guides/performance_proof_runbook.md`, `AGENTS.md` routing/proof obligations, and component-ownership updates in each hard-cut integration commit.

Evidence source: docs link checks, architecture inventory, and parent review of the final tracked diff.

Freshness guard: current task names, Victoria endpoints/query contract, current owner paths, and `CLAUDE.md` symlink preserved.

### R12 — Product behavior feels responsive to the user

Proof source: after all objective interaction and stability gates pass, ask the user to type, move the cursor/caret, use a TUI mouse interaction, switch focus, and reveal a loaded terminal under the qualified watch configuration.

Evidence source: explicit user assertion in this chat, recorded alongside the exact candidate run/build/root context. IPC and Peekaboo prepare and corroborate the scenario but do not replace human feel.

Freshness guard: same candidate build and watched-root configuration that passed DQ1; ask again only after a materially changed interaction boundary.

### R13 — Implementation and PR are review-ready

Proof source: focused RED/GREEN receipts, required test pyramid, full lint/tests, current implementation-review disposition, draft PR, fresh checks/comments/thread/mergeability state, and no merge.

Evidence source: parent verification, `implementation-review-swarm`, and `implementation-pr-wrapup`.

Freshness guard: current HEAD/diff, current PR review/check state, and no unresolved accepted finding.

## Current implementation checkpoint — S1e complete pending S1h

Execution remains in `shravan-dev-workflow:implementation-execute-plan` at HEAD
`8a2f39754e8e0b9bcda06c8509826c5003b87c40` with the intentional dirty S1
worktree preserved.

```text
S1-P0  GREEN_REVIEWED
S1-L1  GREEN_REVIEWED
S1-L2  GREEN_REVIEWED
S1-L3  GREEN_REVIEWED
S1-L4  GREEN_REVIEWED
S1-G1  GREEN_PENDING_S1H
```

S1e's corrected gather behavior and runtime proof are exact-hash READY:
configuration admission semantics, rollover-before-node-publication,
terminal/incumbent drain precedence, sole token-factory root, payload-bearing
physical-custody mutation, exact inverse restoration, 27/27 gather tests,
139/139 Admission tests across 15 suites, strict Swift 6, repo lint, and diff
hygiene pass. The counter-neutral mutation is preserved as a reconstructable
patch and produces exactly 2,378 weak/deinit failures with zero counter/turn
failures before restoring to 3 tests / 7 cases GREEN.

S1-G1 intentionally cannot promote to `GREEN_REVIEWED` until S1h proves the
private recovery-metadata weak-edge/no-extra-alias contract structurally. The
next serial implementation frontier is S1f, which must first make the journal
the sole lexical raw-state owner and settle its helper graph. S1h follows S1f
and S1g; it must not be implemented early against moving journal syntax.

S1f's permanent compiler/static RED exposed one plan-only contradiction: moving
every journal raw transition into the sole lexical owner cannot satisfy the old
generic `<900` craft threshold. The focused correction preserves the accepted
spec boundary and replaces only that plan gate with a shared S1f/S1g 1,250-line
ceiling, an S1f structural baseline, and a post-S1g downward-only ratchet. It
also separates dynamic discovery of every Admission Swift source from journal-
qualified syntax-aware ownership classification and compiler privacy proof.
Arbitrary-new-file and renamed/type-alias mutations prevent filename or generic-
substring false greens. The first recheck's classifier and ratchet findings were
accepted; the exact-hash correction recheck is `READY`. Official workflow has
returned to `shravan-dev-workflow:implementation-execute-plan` at event
`2026-07-11T20:41:49Z-s1f-owner-line-budget-plan-ready`.

Evidence:

- `tmp/plan-workflows/2026-07-10-agentstudio-performance/implementation/s1e/correction-rereview-receipt.md`
- `tmp/plan-workflows/2026-07-10-agentstudio-performance/implementation/s1e/mutation-receipt.md`
- `tmp/plan-workflows/2026-07-10-agentstudio-performance/implementation/s1e/green-receipt.md`
- `tmp/plan-workflows/2026-07-10-agentstudio-performance/implementation/s1-proof-matrix.md`

## Current implementation checkpoint — W2a mailbox mechanics complete

W2a's fixed-registration filesystem observation mailbox is `GREEN_REVIEWED` at
commit `59af980d`. Callback admission retains opaque observations with exact
count/byte footprints, installs recovery evidence before wake visibility, and
does no path/flag/semantic reduction under callback custody. Capability ports
hold only private operation closures. Recovery transfer requires an exact
`FilesystemSourceGateRecoveryAcceptance`, and lifecycle is the closed
`open -> sealed -> invalidated -> finished` state machine with sealed
drainability and typed outstanding-custody rejection.

Parent proof is 28 focused tests across 3 suites, scoped lint exit 0, and an
adversarial correction re-review of `READY`. Evidence is recorded in
`tmp/plan-workflows/2026-07-10-agentstudio-performance/implementation/w2a/mailbox-proof-receipt.md`.
This is dormant mechanics, not a product performance claim: the real Darwin
adapter, actor reduction, canonical gate storage, and production ingress remain
owned by W1b/W2b and later watched-folder tasks.

## Current focused contract checkpoint — W1b fixed-slot lifecycle

The initial sealed-callback correction exposed a fleet-grouping contradiction:
one source cannot seal a mailbox shared by hundreds of registrations. The
accepted correction uses one fixed fleet mailbox with predeclared physical
slots, exact UUIDv7 bindings, paired credentialed callback ports, FIFO
retirement fences, and shutdown-only global seal.

Implementation then exposed a reservation/binding ownership contradiction. The
confirmed correction keeps selected state reservation-only. One lock-linearized
native-lifetime commitment consumes the exact reservation, mints the complete
binding/control-block identities, and commits unpublished-native-generation
custody before any native create call. D3 remains the only post-binding recycler.

The corrected focused implementation plan is accepted after current-hash
whole-plan cohesion, testability/spec-compliance, and
architecture/execution/security review. Current workflow is
`shravan-dev-workflow:implementation-execute-plan`; broad completed spec/plan
review cycles remain closed. Task A has a captured compile RED and is the first
unproven gate.

The accepted contract additionally fixes repeatable custody-local generic
recovery stamps, fleet-wide recovery-authority exhaustion with one minimal typed
generic contraction cause, fixed per-slot semantic retry shells, deterministic
desired FIFO/withdrawal, strict retained-current versus non-current replacement
results, cleanup-gated retirement, native release-once acknowledgement, bounded
completion tombstones, and typed in-memory shutdown debt.

Evidence:

- parent spec SHA-256
  `77e7c671513ee0aa8ccdf039379fe2eef734a639a9652df40b740c478dcc3f88`
- child spec SHA-256
  `f546f63a6a7608950f8f2ebf4f780d98e3fef7b5282e36393aa089f7ebf19f23`
- `tmp/spec-workflows/2026-07-12-w1b-sealed-callback-reconvergence/swarm-ledger.md`
- native whole-spec, requirements/proof, and adversarial lanes: READY
- focused plan SHA-256
  `0b6e486e75aa59491c9762965af84d911a758f3ae158162e1a35f1c075165d59`
- watched parent plan SHA-256
  `5aa84d25d40c448dc5474ebd342d8a5ebddedc4097095642f7ea58433598ab3d`
- exact-delta whole-plan cohesion, testability/spec-compliance, and
  architecture/execution/security lanes: READY
- `git diff --check`: passed
- Claude Fable advisor session remained provider-limited; no claim was used and
  no replacement session was created.

## Required proof ladder

1. Revalidate plan/spec hashes and live high-conflict source before the first edit.
2. For each behavior slice: focused RED for the intended seam, then GREEN, lint/type/architecture proof, and the task receipt required by the plans.
3. Run integration and persistence/filesystem/vendor/IPC boundaries with exact event/state waits; no wall-clock sleeps as proof.
4. Run the standard observability stack and debug identity. Control the app through authenticated IPC; query Victoria with fresh markers.
5. Run generated fixture baseline/candidate matrices and obtain CG1 approval before candidate acceptance.
6. Run DQ1 on the two authorized roots, using only the controlled sentinel for writes.
7. Run PID-targeted Peekaboo native proof with fresh snapshots against the exact app process. Use Computer Use for any required native interaction that IPC and Peekaboo cannot express, while retaining the same exact-PID/run/build freshness contract.
8. After objective gates pass, request the user's subjective typing/cursor/TUI/focus/reveal assessment.
9. Run full required repo test/lint gates, implementation review, and PR-ready non-merge wrap-up.

## Checkpoint rhythm

- Re-anchor before each meaningful task or hard cut.
- Commit only scoped, verified lifecycle/task checkpoints; never stage unrelated work and never use a commit as proof.
- Append one orchestrator-written transition event only after parent verification of the phase receipt.
- Report brief progress at task boundaries and whenever reality contradicts the accepted model.
- Ask the user for help only when a material permission/hardware/user-feel gate cannot be completed autonomously or when the design must change.

## Stop and blocked conditions

Stop code edits and reconverge when live source materially contradicts the accepted ownership/dataflow contract, a hard cut cannot remain atomic, a required proof is too large/flaky for its task, a real-root operation cannot stay inside the authorized sentinel, or a scope-external infrastructure failure would require edits.

The goal is complete only when every material matrix row is `done` or explicitly `not-applicable`, the implementation review is disposed, the PR is created/updated and freshly proven ready, and no merge has been performed. Missing user-feel, CG1 approval, permission, hardware, stack, or PR authority is an open gate; treat the goal as host-blocked only after the same blocker repeats under the host blocked-state rule.

## 2026-07-14 D3 native-retirement checkpoint

D3 is frozen and committed at `7777953ff58f5578ce8a2a37d39641c4369915c0`.
The persistent native owner now retains the exact fence-backed or unpublished
retirement permit, finalizes callback context exactly once, replays one UUIDv7
acknowledgement, and lets the registry atomically install the completion
tombstone before vacancy and fresh UUIDv7 rebinding. Strict discriminated
unions replace optional correlated lifecycle fields. SwiftSyntax rules enforce
the canonical issuers and registry/native-retirement ownership seams.

Fresh parent proof:

- focused context-release/native-retirement: 20 tests, 4 suites, exit 0;
- ownership architecture regression: 26 tests, 1 suite, exit 0;
- `mise run test`: 5,040 tests, 614 main suites, all serialized WebKit lanes,
  exit 0; configured E2E and Zmx E2E lanes skipped;
- `mise run lint`: swift-format OK, SwiftLint 0/1,529, architecture lint OK,
  31 mutation rows restored exactly, release scripts passed, exit 0;
- `git diff --check`: exit 0.

Two signed commit attempts failed after hooks with the 1Password signer error
`failed to fill whole buffer`; the checkpoint was committed unsigned without
changing the verified index. The official workflow remains
`shravan-dev-workflow:implementation-execute-plan`; F3 fleet shutdown debt and
deterministic resume is the next implementation slice, with G2 real Darwin
lifecycle proof still open.

## 2026-07-14 F3 authorized-completion checkpoint

F3 is frozen and committed at `80b7c396`. The fleet lifecycle now performs a
fresh joined actor and mailbox quiescence capture, presents one lifecycle-owned
completion authority to the mailbox, synchronously seals and invalidates the
generic gather mailbox, marks the filesystem mailbox finished, finishes the
doorbell, then mints and retains one UUIDv7 completion receipt without another
suspension point. Begin, resume, and debt capture replay that exact receipt.
Raw filesystem `seal`, `invalidate`, and `finish` surfaces are removed; the
generic gather and doorbell lifecycle operations remain private composition
primitives. UUID values are never used for ordering.

Fresh parent proof:

- `swift test --disable-sandbox --filter FilesystemObservation`: 179 tests,
  28 suites, exit 0;
- `swift test --disable-sandbox --filter FilesystemSourceGate`: 23 tests,
  2 suites, exit 0;
- cancelled/lost-response final completion replays the exact retained UUIDv7
  receipt and finished mailbox/doorbell state;
- bounded read-only completion review found no implementation defect and one
  proof-only gap, remediated in the focused suite;
- `mise run lint`: swift-format OK, SwiftLint 0/1,548, architecture lint OK,
  31 mutation rows restored exactly, release scripts passed, exit 0;
- `git diff --check`: exit 0.

The 1Password signer hung after staged hooks, so the attempt was cancelled and
the checkpoint was committed with the allowed unsigned local fallback. The
official workflow remains `shravan-dev-workflow:implementation-execute-plan`.
G2 real Darwin lifecycle proof is next, followed by WF-C/W2a repair participant
mechanics and the W2b atomic production cut. Product-performance claims remain
open until the Victoria, authenticated exact-PID IPC, large-root, native UI,
and explicit human interaction-feel proof gates pass.

## 2026-07-14 G2 real-Darwin lifecycle checkpoint

The dormant fixed-slot lifecycle now has one real CoreServices integration
proof. A UUIDv7-named temporary root is installed through the production Darwin
driver and callback adapter; a real post-start filesystem mutation enters the
bounded callback path and deliberately contracts to exact recovery evidence.
The test then proves stop, invalidate, callback-queue barrier, zero callback
leases, exact close-receipt replay, exact recovery-revision retirement, the
fence-backed retirement permit, release-once unmanaged callback context,
acknowledgement replay/application, and final physical-slot vacancy. Transparent
test wrappers retain the actual native operation order:
`create -> start -> stop -> invalidate -> barrier -> release`.

Fresh parent proof:

- expected RED before the suite existed: the focused filter discovered zero
  tests;
- `mise run test-large -- --filter DarwinFSEventObservationLifecycleIntegrationTests`:
  1 test, 1 suite, exit 0, 0.018 seconds;
- repeated focused runs and the surrounding `DarwinFSEventObservation` filter:
  27 tests, 3 suites, exit 0;
- one bounded review found two proof defects; one remediation requires the exact
  `.quiescentAfterRecovery(recoverySnapshot.revision)` receipt and closes the
  real generation before rethrowing callback/write failure;
- `mise run lint`: swift-format OK, SwiftLint 0/1,549, architecture lint OK,
  31 mutation rows restored exactly, release scripts passed, exit 0;
- `git diff --check`: exit 0.

AgentStudio-owned test identities use UUIDv7; native FSEvent handles retain
their platform identity; lifecycle order remains revision/fence based and never
uses UUID ordering. The official workflow remains
`shravan-dev-workflow:implementation-execute-plan`. W1b dormant readiness and
F3 shutdown mechanics are complete; continue at WF-C/W2a repair participant
mechanics. Production remains wholly legacy until the later W2b atomic cut, so
no product-performance claim is made from this checkpoint.

## 2026-07-14 WF-C C1 content-repair registry checkpoint

WF-C C1 is frozen and committed at `5e4da5c0`. The off-main
`WorktreeContentRepairConsumerRegistry` now owns a bounded active generation
plus newest pending successor per registered-worktree source, exact captured
consumer generations, current/non-current/retry transfer, acknowledgement
custody through exact SourceGate confirmation, bounded terminal replay, and
debt-safe source retirement. AgentStudio-owned consumer, capture, and retry
identities are UUIDv7; numeric generations and ordinals remain the only
ordering authorities.

The C2 boundary check tightened two type contracts before the checkpoint:
every delivery request carries its exact content-invalidation generation, and
only a registry-issued `ContentRepairActivatedGeneration` can enter the future
projector. Pending generations and completed replay cannot regain activation
authority.

Fresh parent proof:

- expected RED: missing active/pending/completed binding cases and missing
  delivery invalidation generation failed compilation;
- focused registry: 19 tests, 1 suite, exit 0;
- surrounding SourceGate: 20 tests, 1 suite, exit 0;
- scoped SwiftLint: 0 violations across the five C1 files;
- `mise run lint`: swift-format OK, SwiftLint 0/1,554, architecture lint OK,
  31 mutation rows restored exactly, release scripts passed, exit 0;
- `git diff --check`: exit 0;
- all five production/test files remain below 900 lines.

One bounded implementation review and one remediation are complete. A later
parent C2 inventory found no design contradiction; continue
`shravan-dev-workflow:implementation-execute-plan` at
`FilesystemContentRepairProjector`, then isolated SourceGate integration and
the W2b atomic production cut. Product-performance claims remain open until
that cut and the final Victoria, authenticated exact-PID IPC, large-root,
native UI, and human interaction-feel proof loop.

## 2026-07-14 WF-C C1 temporal eligibility correction checkpoint

Implementation exposed that a registry-issued, copyable
`ContentRepairActivatedGeneration` proves origin but cannot permanently prove
temporal eligibility after the projector's bounded replay evicts an old
completion. The user approved preserving the two-actor responsibility split:
C1 remains the lifecycle authority and C2 remains the bounded effect executor.

C1 now validates the complete activation before C2 may perform consumer work.
Only the exact current active generation or an exact capture-ledger
`.completed` entry is eligible; pending, superseded, mismatched, retired, and
older/evicted generations reject. The completed exception preserves valid
zero-consumer and final-consumer projector acknowledgement. C1 also returns an
owner-minted, non-forgeable retirement receipt carrying the exact final
`FSEventRegistrationToken`; C2 will match that registration against its
SourceGate acceptance/binding before clearing bounded state.

Fresh parent proof before checkpoint commit:

- expected RED: missing eligibility API and exhaustive result types failed
  focused compilation;
- focused registry: 22 tests, 1 suite, exit 0;
- scoped swift-format: exit 0;
- scoped SwiftLint: 0 violations across five C1 files, exit 0;
- `git diff --check`: exit 0;
- actor mutation/state remains in the 892-line registry owner; pure immutable
  lifecycle classification lives in the 579-line registry-state owner;
- the maintained spec and WF-C plans record the approved separation and causal
  exact-registration retirement contract.

Continue `shravan-dev-workflow:implementation-execute-plan` by integrating C2's
reserved admission, eligibility/forwarding ports, and debt-safe retirement.
Production remains wholly legacy until W2b, and all product-performance and
real-app proof gates remain open.

## 2026-07-15 WF-C C2 bounded content-repair projector checkpoint

WF-C C2 is frozen and committed at `7cb48618`. The off-main projector owns
bounded serial delivery, exact resumable acknowledgement forwarding, causal
source retirement, and per-source bounded completion replay. C1 remains the
sole lifecycle and currentness authority; C2 revalidates the exact activation
immediately before every consumer effect and discards a superseded journal so
the successor can progress.

Fresh parent proof:

- focused projector: 24 tests, 1 suite, exit 0;
- focused registry: 25 tests, 1 suite, exit 0;
- `mise run lint`: swift-format OK, SwiftLint 0/1,560, architecture lint OK,
  31 mutation rows restored exactly, release scripts passed, exit 0;
- strict scoped swift-format and SwiftLint: exit 0, 0 violations;
- `git diff --cached --check`: exit 0 before commit;
- C2 rejects brand-new forwarding while draining, distinguishes same-token
  acknowledgement conflicts during processing, and preserves exact newer
  replay after stale retirement attempts;
- all C2 source and test files remain below 600 lines;
- identity is UUIDv7 and ordering uses checked integer ordinals only.

Continue `shravan-dev-workflow:implementation-execute-plan` at the isolated
registered-worktree repair integration against the frozen SourceGate API, then
the atomic W2b production cut. No product-performance claim is made before W2b
and the final Victoria, authenticated exact-PID IPC, large-root, native UI, and
human interaction-feel proof loop.
