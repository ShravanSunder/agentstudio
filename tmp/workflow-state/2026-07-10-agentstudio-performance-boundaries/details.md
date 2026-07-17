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
  `shravan-dev-workflow:implementation-execute-plan`. That historical event made
  S1a the first unproven gate at the time. It is superseded for current execution
  order by the active strict-startup/W4.5p pointer below.

## Current blocking correction — strict startup and pure atom persistence boundary

- The existing repository contract is authoritative: canonical atoms own in-memory state and synchronous local invariants; persistence wrappers live under `State/MainActor/Persistence`; coordinators own cross-atom sequencing.
- Commit `5f8bf99d` violated that boundary by embedding persistence DTO projection, snapshot participants, membership limits, byte estimates, fixed-revision preparation, and transaction registration in atom files. Dirty W4.5 composition work extended the same violation with `prepareCompositionParticipant` methods.
- Strict composition startup and terminal identity are now hard-cut in commits
  `0d3ec070`, `c7e6bb17`, `cb62c43f`, and `350ed632`. Representative
  real-process failure proof and the non-serial startup readiness DAG remain
  blocking before event/performance work resumes. W4.5p writer/pager proof is
  still open in parallel with that cleanup.
- Blocking remediation: move all persistence/revision/pager/lease responsibilities for identity, window memory, topology, pane graph, drawer cursor, tab shell, tab cursor, tab graph, and arrangement cursor into long-lived persistence adapters shared by the participant factory and mutation/applier paths. Atoms retain only canonical state, local invariants, and narrow domain-native reads/mutations.
- Direct persistence-affecting mutation paths must be inventoried. Once participants are installed, no production setter may bypass first-post-base capture.
- Independent review verified that the current participant factory is test-only and current focused tests are false-green for live first-post-base semantics because production writers still use direct atom mutations. Runtime construction plus writer routing is required before W4.5p can close.
- Independent review also verified that topology snapshot storage duplicates canonical/read authority inside the topology atom; W4.5p moves persistence custody out, while W5 remains the exclusive owner of off-main identity reconciliation.
- Required order: remove persistence mechanics from atoms; integrate exactly one adapter bundle into production composition; hard-cut every installed persistence-affecting live writer through adapters/coordinators; prove a real production pager lease observes literal pre-mutation state through real product front doors; then run build/tests/lint and the focused review/remediation cycle. Adapter-only tests do not advance this gate.
- Startup authority is domain-scoped inside one runtime: composition and topology share one revision owner/bundle but use distinct non-copyable preinstall tokens and strict enum-backed lifecycles. A token cannot authorize the other domain, and neither initial apply nor any post-open startup mutation remains callable after its domain installs.
- Safe per-domain transition: off-main prepare/validate -> atomic initial apply with the domain token -> cut every same-domain steady-state writer through the bound adapters/coordinator -> install that domain participant inventory -> expose that domain mutation gateway. Installation before writer cutover is forbidden because it makes fixed-revision custody false.
- Composition may finish that transition and unlock window/terminal readiness while topology remains suspended. Topology cannot gate or mutate composition. The complete pager is assembled only after both domains install; optional participant arrays/`nil` are not lifecycle authority.
- Startup has no zmx reconciliation, repair, adoption, derivation, or identity
  mutation. Exact stored `ZmxSessionID` values flow from strict composition into
  terminal activation. Startup diagnostics use installed semantic gateways when
  they execute after normal boot.
- Representative live routes include sidebar/window memory, topology coordination, pane/drawer compatibility facades, tab/arrangement compatibility facades, and terminal pane creation with caller-minted UUIDv7 identity. The inventory must discover and cover any additional installed writer rather than treating this list as exhaustive.
- Proof: structural zero-persistence-vocabulary scan over atom files; atom invariant suites; adapter mutation/lease/page suites; complete heterogeneous participant inventory; one adapter-bundle/revision-owner object identity across production composition; RED/GREEN real-front-door preimage/insertion/tombstone integration proof; direct-mutation inventory; build/lint/diff check.
- Independent review lane: native Sol xhigh `/root/sol_xhigh_atom_boundary_review`, source-backed and risk-triggered over `5f8bf99d`, supporting commits, current dirty state, tests, docs, and the proposed adapter correction. Parent verification owns accepted findings.
- Controller brief: `tmp/plan-workflows/2026-07-15-agentstudio-ghostty-performance-pure-atoms/implementation-execute-plan-brief.md`.
- No broad spec or plan review cycle is reopened; this is implementation remediation against existing authoritative docs and one focused review/remediation cycle.

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

## 2026-07-15 WF-C registered-worktree integration checkpoint

The isolated WF-C composition proof is frozen and committed at `499adefa`.
Two deterministic integration tests compose the real mutable
`FilesystemSourceGate`, real `WorktreeContentRepairConsumerRegistry`, and real
`FilesystemContentRepairProjector`. The participant oracle is derived
independently from registered consumer tokens and then cross-checks C1's
captured participant set.

Fresh parent proof:

- expected RED: the exact integration filter discovered zero tests and zero
  suites before the files existed;
- focused integration: 2 tests, 1 suite, exit 0;
- focused projector: 24 tests, 1 suite, exit 0;
- focused registry: 25 tests, 1 suite, exit 0;
- `mise run lint`: swift-format OK, SwiftLint 0/1,562, architecture lint OK,
  31 mutation rows restored exactly, release scripts passed, exit 0;
- the positive path mixes `rebuiltCurrent`, exact retained retry, and
  `notApplicableNoRetainedState`; C2 delivery is serial and exact;
- SourceGate remains awaiting Git plus pane projection after content repair,
  remains awaiting pane projection after Git, and becomes healthy only after
  the pane acknowledgement;
- the negative path routes consumer rejection through C2 into the real
  SourceGate and retains the exact repair generation as dirty debt;
- both new files remain below 600 lines and use UUIDv7 identities with checked
  numeric ordering only.

Continue `shravan-dev-workflow:implementation-execute-plan` at the combined
pre-W2b mechanics gate, then the W2b atomic production cut. Production remains
wholly legacy and no product-performance claim is made until W2b plus the final
Victoria, authenticated exact-PID IPC, large-root, native UI, and human-feel
proof loop.

## 2026-07-15 Pre-W2b proof-manifest checkpoint

The combined pre-W2b proof surface is frozen at `47d4833b`. The manifest-driven
runner rejects zero-test selectors, dispatches ordinary and large Swift test
tasks explicitly, and proves the production path remains wholly legacy while
the dormant fixed ingress has exactly one consumer/waiter owner.

Fresh parent proof:

- `bash scripts/verify-filesystem-observation-proof-suites.sh --gate pre-w2b`:
  12/12 nonzero selectors, exit 0;
- the deliberately nonexistent selector produced 0 tests/0 suites and was
  rejected with the exact expected status 65;
- the real Darwin lifecycle selector passed 1 test/1 suite through
  `test-large`;
- the consolidated ingress ownership selector passed 2 tests/1 suite;
- `mise run lint`: SwiftLint 0/1,562, architecture lint passed, 31 type-state
  mutation rows restored exactly, release scripts passed, exit 0;
- `mise run test-fast`: 4,888 tests/584 suites plus 19 IPC socket tests/1 suite,
  exit 0;
- the local checkpoint is unsigned because two identical 1Password signing
  attempts failed after hooks with `failed to fill whole buffer`; no commit
  content or proof was bypassed.

W2b remains correctly gated by W4.5/W5, W9, and W10. Implementation continues
at the focused W3/W4a ownership correction and the first exhaustive scanner
RED; production-performance claims remain open.

## 2026-07-15 W3 scanner/scheduler/projector boundary correction

Live implementation evidence showed that the earlier monolithic scan-result
shape crossed three owners: `RepoScanner` had no prior topology from which to
derive removals, scheduler metrics did not belong in scanner output, and
`RegisteredRootDescriptor` was not available until the later W4 task. The
focused correction is frozen at `c3ee892d` after one bounded review and one
remediation pass.

The corrected ownership is:

- W4a constructs `RegisteredRootDescriptor` from host-authorized input and
  carries one exact `FSEventRegistrationToken` as sole authority;
- `RepoScannerResult` is a strict associated-value union containing only
  exhaustive traversal/validation evidence and counts;
- `WatchedFolderScanScheduler` owns single-flight/fairness, exhaustive causes,
  non-empty repair obligations, checked scan-run generations, and scheduler
  metrics;
- W5 constructs `TopologyProjectionRequest` by binding an accepted scheduled
  result to its canonical mirror base revision, and only W5 derives canonical
  removals from complete-current evidence;
- the W3 transitional `FilesystemActor` comparison is explicitly gated against
  partial/stale removal and is hard-cut when W5 becomes the final owner.

UUIDv7 remains opaque source/lifecycle authority. Checked numeric generations
remain ordering/currentness only. Scanner paths and Git metadata remain
evidence and cannot select watcher/root authority. Implementation resumes at
the W4a construction RED and exhaustive RepoScanner RED.

## 2026-07-15 W3 bounded-quantum alignment

The user explicitly aligned on bounded watched-folder scan quanta. W3 schedules
one bounded quantum per root turn rather than one complete recursive scan per
turn. A suspended scan retains its logical run generation and exposes no
inventory. Final results retain a scheduler credit through pending/leased
custody until exact transfer acknowledgement, so consumer pressure throttles
new scans instead of growing an unbounded result queue. The focused W3 plan now
also names repair-preserving trigger merge, cancellation-safe waiting/shutdown,
private completion ingestion, scanner-owned service duration, and deterministic
10/100/300-root fairness/custody proof.

## 2026-07-15 topology identity atomicity prerequisite

The historical duplicate-worktree-UUID crash path is closed at the current
canonical mutation boundary before W3 integration. Scanned ingress is ID-free;
`RepositoryTopologyAtom` is the sole UUIDv7 minting and identity-consumption
owner; one existing identity can be consumed only once; UUID and stable-key
uniqueness are validated globally before mutation. Reassociation prepares and
validates repository metadata, availability, and worktrees before one commit.
Typed rejection propagates through the mutation and cache coordinators with no
topology, pane-residency, cache, persistence, trace, or index-generation effect.
The guarded regression produces `[X, Y]`, never `[X, X]`. Focused parent proof
passed 37 tests across the topology atom and both cache-coordinator suites;
strict scoped lint/format and diff checks passed. Checkpoint commit `b39a0f23`.

## 2026-07-15 W3 traversal and Git validation separation

Implementation evidence proved that the first resumable scanner draft still
awaited synchronous libgit2 inside an eight-millisecond traversal quantum. Swift
cancellation cannot interrupt that native call, so the task-group timeout could
retain traversal credit until physical exit. The focused correction is frozen
in spec/plan commit `cac5c6d9`.

`RepoScannerTraversalSession` now has the required strict shape
`suspended | validationRequired | finished`; Git validation never owns a
traversal credit. One `RepoScannerValidationExecutor` actor owns a root-fair
bounded queue and two physical native-task slots. A logical timeout creates
partial/dirty evidence immediately, but a non-cooperative native task keeps its
physical slot in `draining` until actual exit. No replacement task is created,
and unrelated-root traversal continues when validation saturates.

Discovery receives a narrow read-only capability, never writer, remote, or
mutation authority. Production W3 integration is dependency-gated on an
immutable `agentstudio-git` revision that opens only the exact candidate with
`GIT_REPOSITORY_OPEN_NO_SEARCH`. Discovery may read identity, registration,
lock state, and HEAD but cannot create/remove/hold Git locks or mutate a repo,
worktree, or common directory. Discovery, status, network, lifecycle/checkout,
and mutation budgets/executors remain distinct. The two physical slots and one
outstanding candidate per logical scan are fixed; logical deadline and global
queue capacity remain typed and test-injectable pending workload calibration.

## 2026-07-15 W3 scanner and scheduler mechanics checkpoint

Checkpoint `9db6809f` freezes the standalone W3 mechanics without changing the
legacy production `FilesystemActor` callback path. The scanner returns exhaustive
typed evidence, traversal advances through bounded resumable quanta, validation
uses independent bounded logical and physical custody, and the scheduler owns
root-fair ready selection, running-plus-newest-dirty collapse, exact registration
and scan-run currentness, and lossless leased terminal-result custody.

The implementation review findings were remediated once: candidate containment
is checked before Git access and positive evidence is rechecked after the read;
both draining physical slots reject new logical custody; stale pending and leased
results cannot transfer after replacement; ready selection performs constant
work independent of fleet size; and recent validation completions use a bounded
256-entry diagnostic history without granting authority. Traversal service and
physical-slot validation service are separate metrics; executor queue wait,
scheduler queue wait, and late native drain remain separately owned.

Fresh parent proof passed 75 tests across 9 suites with deterministic 10/100/300
root fairness, exact result-custody tests, candidate authority tests, draining
slot tests, and injected-clock validation timing tests. Scoped strict SwiftLint
reported zero violations across 17 files, strict formatting passed, and the
cached diff check passed. Production integration remains the next W3 slice: it
must preserve `WatchedPath.id`, return an exact submission receipt for awaited
manual demand, route every scan cause through the scheduler, and ensure partial,
cancelled, unavailable, failed, or stale evidence never removes prior inventory.

## 2026-07-15 S3 MainActor diagnostics checkpoint

Checkpoint `821e63af` adds the measurement primitives needed by later workload
proof: UUIDv7 one-use work tickets separate MainActor queue age from synchronous
service, the responsiveness heartbeat exposes gaps and overdue pulses, and one
bounded synchronous probe sink feeds scrubbed Victoria distributions, counters,
and gauges. A run evidence ledger tracks exact stage coverage, loss, sequence
gaps, and drain completion without exporting raw identities.

The final concurrency review was remediated before commit. Sink calls execute
outside the ledger lock under typed in-flight custody; drain admission closes
the sink atomically; an exact UUIDv7 drain-operation token rejects stale or
foreign receipts; mixed non-run probe records do not corrupt run accounting;
and every sink-recorded run sequence must be observed exactly once before the
strict lifecycle can enter `finished`. The lifecycle is one discriminated union,
not correlated optional sink/state fields.

Fresh parent proof passed 42 tests across 7 suites. Strict scoped swift-format,
strict SwiftLint, working-tree and cached diff checks passed, and the final
read-only remediation review returned READY. These primitives are diagnostic
substrate only; runtime workload wiring and Victoria acceptance remain open.

## 2026-07-15 W3 production integration checkpoint

Checkpoint `6557bf87` routes every watched-folder scan cause through the bounded
W3 scheduler while deliberately retaining the complete legacy `FSEventBatch`
transport until the atomic W2b cut. `WatchedPath.id` remains the stable source
identity, each legacy callback registration receives a fresh UUIDv7 routing
identity, and retired callbacks cannot attribute work to a replacement source.

The actor owns strict manual-refresh and result-drain lifecycle unions. Binding
the sole scheduler result consumer and draining its leased results are one
awaitable task custody chain, so shutdown cannot strand a pending result during
consumer binding. Exact current complete evidence may replace inventory;
complete older evidence, partial evidence, and cancelled evidence are additive;
unavailable and failed evidence preserve the last-known inventory. One atomic
EventBus batch admits the authoritative positive and removal effects after the
final synchronous currentness check.

Fresh parent proof passed 73 tests across 12 suites. `mise run build`, strict
swift-format over all 23 changed Swift files, strict SwiftLint with zero
violations, and working/cached diff checks passed. The checkpoint used the
repo-authorized unsigned local fallback after the configured 1Password account
was unavailable; `.agents/` was not staged. Continue
`implementation-execute-plan` at W4.5 canonical revision ownership and
fixed-revision page leases before W5.

## 2026-07-15 W4.5 Packet E snapshot substrate checkpoint

Packet E now has a closed, finite fourteen-participant factory over the exact
canonical owners; a bounded contiguous revision journal; a pure off-main
snapshot assembler/finalizer; pure aggregate hydration preparation; and one
shared tab-membership normalizer. Invalid factory policy is represented by a
typed rejection rather than a trap. Pane snapshot byte estimation covers every
persisted dynamic content family with saturating checked arithmetic. Snapshot
finalization preserves semantic repository, tab, arrangement, pane, and drawer
order; UUID identity is never used as product ordering state.

Hydration preparation validates SQLite workspace/topology identity plus global
repository, worktree, watched-path, pane, drawer, tab, and arrangement identity
before any canonical mutation. It preserves the current invalid-worktree pane
filter and tab repair semantics while remaining `Sendable` and runnable off
MainActor. The historical duplicate-identity and duplicate-key trap shapes are
therefore rejected before live-state apply.

Fresh parent proof passed 48 tests across five focused suites, including the
multi-drawer inverse-UUID-order regression. `mise run build`, full `mise run
lint` (SwiftLint 0/1,633, architecture lint, all 31 admission mutation rows,
and release scripts), and `git diff --check` passed. The product restore/save
path is not yet cut over. The historical Packet E next step was aggregate load,
off-main preparation, typed MainActor apply, participant installation, and
pager-backed save equivalence before W5. That ordering is superseded by the
active W4.5p resume pointer below.

## ACTIVE RESUME POINTER — strict startup proof, startup DAG cut, then W4.5p

This pointer supersedes every older `next`, first-unproven-gate, Packet E,
composition, activation, S1, and W5 resume statement in this file:

```text
strict terminal identity hard cut                         0d3ec070
  -> strict composition startup                          c7e6bb17
  -> SQLite-only startup/legacy workspace path deletion  cb62c43f
  -> obsolete startup-repair proof removal               350ed632
  -> representative real-process strict-failure proof       b65bc17c
  -> prepared topology-independent Bridge mounting          d5a31bcc
  -> hard-cut serial WorkspaceBootSequence/restoreAllViews authority
       one bounded composition install
         +-> workspace shell/window
         +-> TerminalActivationOwner
         +-> NonterminalContentMountOwner
       external topology/cache/filesystem/Git/Forge lanes never gate readiness
                                                             3e99cdeb
  -> finish W4.5p semantic gateways and same-domain writer cutover
  -> assemble/prove the real production fixed-revision pager
  -> parent-verify build/tests/lint plus one focused review/remediation cycle
  -> resume W5+/event cutover and performance proof
```

Adapter-only tests, a test-only factory/applier, or extracted types without live
writer routing do not satisfy this gate.

Composition startup has no repair, normalization, adoption, identity rewrite,
fallback, legacy combined load, or post-open acknowledgement mutation. Historical
GRDB migrations remain the sole schema-open exception; after schema-open, strict
composition decode/validation is write-free. Filesystem/topology currentness
repair remains a separate external-runtime concern.

The strict-startup proof checkpoint now uses a transient
`mode=ro&readonly_shm=1` reader for preexisting current-schema core/local
databases, so committed WAL-only state remains visible without changing the
database, WAL, or SHM bytes. Older schemas run only the unchanged historical
GRDB migrations, close the writable migration pool, and reopen through the same
byte-preserving reader before strict decode. Representative real-process
failures terminate nonzero with content-safe diagnostics and unchanged durable
inputs. Parent proof passed 67 tests across nine focused suites, including the
four-scenario subprocess harness; the two lint-remediation suites passed 11/11;
`mise run build`, full `mise run lint`, and `git diff --check` passed. The next
active slice is the content-owner startup hard cut described above.

The first content-owner checkpoint now prepares one exhaustive, disjoint
terminal/nonterminal cohort from accepted composition and derives its generation
from the composition transaction's process generation and revision. A fixed
four-worker terminal activation scheduler proves active-visible, visible, then
hidden priority; exact opaque zmx identity forwarding; bounded 100/300-pane
fleets; retry; promotion; replacement cancellation; and aggregate settlement.
The nonterminal owner mounts at most four entries per MainActor turn, and
`ViewRegistry` has generation-scoped lane claims before host construction.
Prepared terminal activation no longer registers filesystem projection or reads
repository topology; steady-state topology-enriched terminal creation retains
fresh-versus-restored semantics. Parent proof passed 29 tests across five
cohort/owner suites and seven retained terminal/nonterminal factory tests;
scoped strict format, SwiftLint, and `git diff --check` passed.

The production content-owner startup cut is complete at `3e99cdeb`.
Topology-independent Bridge construction landed at `d5a31bcc`; the accepted
composition now installs one exact generation ledger, terminal activation and
nonterminal mounting run through their independent bounded owners, and
`restoreAllViews` plus its generic traversal helpers are deleted. Aggregate
settlement is the post-join failure authority, so deferred visibility intent
can produce targeted steady-state repair without rereading a parallel mount
ledger. Parent proof passed 45 tests across eight focused suites, `mise run
build`, full `mise run lint` including all 31 mutation controls, and `git diff
--check`. The next active slice is W4.5p semantic gateways and same-domain
writer cutover; no broad spec or plan review reopens.

### Current W4.5p implementation checkpoint — capture-only custody

Commit `93041f0f` adds strict composition capture descriptors and adapter-owned
capture-only APIs. They reserve fixed-revision participant preimages in
`O(changed keys)` without mutating canonical atoms or registering replacement
state. Parent verification passed the capture-only suite (3 tests), existing
pane/tab adapter suites (16 tests), `mise run build`, and `git diff --check`.

The next active slice is the installed semantic gateway layer. It must decide
typed rejection and semantic no-op before committing, then reserve every
affected participant, execute narrow atom assignments once, and
publish one revision. Sidebar width and window frame are one aggregate
window-memory writer family. The strict startup composition path is installed;
its remaining W4.5p gate is to route every steady-state pane, drawer, tab,
arrangement, topology-to-pane, and startup-diagnostic writer through the bound
semantic gateways without introducing any startup repair path.

Commit `8dd0f561` establishes the first installed semantic gateway family for
aggregate window memory. The gateway rejects preinstall use, decides equal
sidebar/frame requests before opening a transaction, captures the literal
width-and-frame preimage once, applies the pure atom setter once, and advances
one revision. Parent verification passed 10 tests across the coordinator,
window-memory adapter, and runtime suites plus `mise run build` and
`git diff --check`; the staged-file pre-commit format and SwiftLint gate also
passed.

Live pane/tab mapping proved that mechanically wrapping the remaining facades
would preserve fleet-wide MainActor work. Remaining composition families use
this split without adding planning methods to atoms/facades:

```text
pure domain transition owner
  -> planned(exact keyed domain patches + typed semantic effect)
  -> unchanged
  -> rejected(typed reason)

outer WorkspacePersistenceMutationCoordinator
  -> aggregate exact capture descriptors once per participant
  -> reserve all affected preimages
  -> commit one shared revision
  -> narrow atom assignments apply the accepted patches once
```

Domain decisions contain no persistence descriptors, revisions, adapter
references, or generic mutation closures. Pane, drawer, shell, tab graph, and
cursor changes from one semantic action remain one outer transaction. The
immediate active work is the keyed pane/tab transition substrate outside atoms;
production writer routing and domain installation follow after it is proven.

UI-memory persistence is not callback-rate. Continuous window/sidebar geometry
stays immediate in AppKit presentation and produces one latest settled canonical
checkpoint; discrete memory may commit once immediately; text-like/bursty UI
memory may update its UI owner while the persistence pump coalesces the latest
committed revision. Deterministic proof requires N callbacks -> one settled atom
assignment/revision/persistence request, zero fact posts, and zero
Observation-triggered second revision.

Each domain installation must consume its own non-copyable writer-cutover
receipt after the checked same-domain production-writer inventory is complete.
Participant construction cannot install a domain by itself. The strict SQLite
startup hard cut has deleted the old combined load/apply route and save-result
live-tab mutation; installed SQLite acknowledgements clear custody only and
never mutate canonical atoms.

### W4.5p persistence revision authority checkpoint

Commit `309761b9` removes persistence revision ownership from `AtomRegistry`.
`WorkspacePersistenceRuntime(atomRegistry:)` now creates the one
`WorkspacePersistenceRevisionOwner` and supplies that same runtime-owned
authority to its adapter bundle, participant factory, appliers, mutation
coordinator, and retained `WorkspaceStore` reference. No persistence domain was
installed, no writer was routed, and no pager behavior changed in this slice.

Parent proof passed 14 focused tests across the runtime, revision-owner, and
atom-boundary suites; `mise run build`; strict staged formatting and SwiftLint;
and `git diff --check`. The full lint static phases passed, while its unrelated
`AdmissionDoorbellTests` runtime control transiently missed a test-only waiting
state. The exact standalone selector immediately passed 11/11 tests in 0.002s.
Continue W4.5p with typed semantic planners and the complete same-domain writer
cutover. Composition installation remains prohibited until its checked writer
inventory reaches zero bypasses; there is no startup repair or migration path.

Commit `6d3f7253` adds the next pure composition-domain substrate without
activating it. Tab selection, rename, delta movement, and reorder-plus-selection
now plan strict changed/unchanged/rejected outcomes with exact displaced-shell
index preimages and correlated cursor replacements. Drawer toggle planning
produces exactly one planner-constructed expand, collapse, or switch transition;
its narrow MainActor applier rejects stale cursor state before one simple atom
assignment. Transition construction is planner-owned, so ordinary module callers
cannot fabricate correlated transition values.

Parent proof passed 13 tests across three suites, `mise run build`, scoped
strict swift-format and SwiftLint with zero violations, staged diff checks, and
the staged pre-commit gate. No atom, persistence adapter, coordinator, runtime,
production callsite, startup path, or domain lifecycle was changed. Continue
W4.5p by wiring these accepted transitions through the dormant persistence
mutation coordinator, proving fixed-base capture, and expanding pure planners
until the complete writer inventory can cut over atomically.

Commit `a1260eb5` wires the tab-leaf transitions through an installed-only,
still-dormant persistence gateway. The coordinator plans before transaction
admission, captures every shifted shell sort-index key plus the exact cursor
preimage, preflights both owners before mutation, and commits a combined reorder
and selection in one revision. It uses capture-only adapter APIs and applies
caller-approved replacements through a narrow stale-checking applier; adapters
and atoms gained no product decisions.

Parent proof passed 9 tests across two suites, scoped strict swift-format and
SwiftLint, and staged diff checks; `mise run build` passed in the implementation
lane. An independent read-only slice review returned READY with no important
findings, and parent warm-cache proof independently reproduced all 9 tests.
There are still no production callsites and composition remains preinstall.
Continue W4.5p with the drawer-toggle dormant persistence gateway, then the
remaining planner/writer families before the single production activation cut.

Commit `5d3e8057` adds the installed-only drawer-toggle persistence gateway while
leaving production routing unchanged. Expand, collapse, and switch plan from the
pane graph plus cursor; map to insertion, removal, and replacement capture; and
commit one revision through a prepared stale-checking cursor application. The
runtime change is only explicit drawer-cursor owner injection.

Parent proof passed 6 tests across two suites, scoped strict swift-format and
SwiftLint, and staged diff checks; the implementation lane also passed
`mise run build`. A read-only Luna xhigh review returned READY with no important
findings. Composition remains preinstall and the installed-only method has zero
production callsites. Continue W4.5p with the remaining pane/tab/arrangement
writer families before the one atomic production activation cut.

Commit `55989256` adds the pure pane-context planner and installed-only dormant
gateway. CWD plus repository/worktree attribution is a strict resolved-both or
unresolved-neither union; equality returns without a revision, and a change
captures one pane-graph preimage and commits one existing transition application.
No Repo/Worktree objects or correlated optional identifiers cross the gateway.

Parent proof passed 11 tests across two suites, scoped strict swift-format and
SwiftLint, and staged diff checks; the implementation lane passed `mise run
build`. Independent Luna xhigh review returned READY with no findings. Production
callers and atoms remain unchanged. The next accepted dormant slice is the
low-rate graph-only equalize/rename family; drag and keyboard resize are excluded
until their UI-rate updates can settle into one persistence checkpoint.

Commit `f0cc9a2f` adds dormant graph-only gateways for the low-rate equalize and
arrangement-rename actions. Each pure planner emits one planner-owned graph
replacement, the applier validates the full graph and the exact active-
arrangement read witness where required, and persistence captures one tab-graph
key in one revision. Production callsites remain unchanged.

Parent proof passed 11 tests across three suites, scoped strict swift-format and
SwiftLint, and staged diff checks; the implementation lane passed `mise run
build`. The one review finding was a test-only gap for typed missing-tab and
missing-arrangement branches; one remediation added the direct assertions and
the parent rerun passed. Resize/drag paths are deliberately absent because
per-sample synchronous revisions would recreate the amplification this goal is
removing. Their later production boundary must render immediately and persist
one settled checkpoint.

Commit `bd6fc1ae` adds the safe dormant webview-state planner and installed-only
pane-graph gateway. It requires existing webview content, returns typed missing/
identity/content mismatch rejection, treats equality as no-op, and replaces only
the webview content through one pane preimage and one revision.

Parent proof passed 13 tests across two suites, scoped strict swift-format and
SwiftLint, and staged diff checks; the implementation lane passed `mise run
build`. Independent Luna xhigh review returned READY with no findings. No
checkpoint owner, save hook, atom, App caller, or production route changed. The
later atomic production cut must replace save-time fleet scanning with a keyed
latest checkpoint owner; saves and acknowledgements may never mint revisions or
mutate atoms.

Commit `8a170d38` adds the dormant active-arrangement visibility family for
switching arrangements, showing minimized panes, minimizing, and expanding.
Pure planners emit typed graph, active-arrangement, active-pane, and runtime-only
zoom transitions; a narrow applier validates all read witnesses before changing
any owner. Persistence captures only changed tab-graph and arrangement-cursor
keys in one synchronous revision. Pane zoom remains outside the persisted owner
bundle and has no capture path. Missing or dangling active-arrangement cursors
remain the existing explicit switch-repair behavior.

Parent proof passed 22 tests across four suites, `mise run build`, the complete
`mise run lint` gate including architecture lint and all 31 mutation controls,
and staged diff checks. The focused review's two accepted findings are covered
by permanent stale non-target selection and keyed unrelated-owner preservation
tests. Production callsites remain unchanged and composition remains preinstall.
Continue W4.5p with the next bounded pane lifecycle family before the atomic
production writer cutover.

Commit `abab50d1` adds the pure pane-residency lifecycle substrate for
backgrounding and reactivating layout panes without activating a production
route. The strict planners classify changed, unchanged, and typed rejection;
validate the complete parent-plus-drawer-child ownership family, tab graph,
shell suffix, tab and arrangement cursors, pane selections, drawer cursors,
zoom, and retained runtime payload; and preserve the surviving tab's exact
active-arrangement cursor. The MainActor applier preflights every owner and a
fresh retained-payload witness before making only narrow residency, index, and
cursor assignments. Atoms contain no persistence, planning, revision, pager,
or workflow behavior.

Parent proof passed 29 tests across four suites on the exact final source and
`mise run build`; scoped formatting, SwiftLint, architecture lint, and staged
diff checks passed. The focused review's ownership, atom breadth, payload,
cursor, shell-delta, and stale-witness findings were handled in its one allowed
remediation cycle. Full `mise run lint` passed formatting, SwiftLint across
1,734 files, architecture lint, compiler contracts, and the other mutation
controls, but its unrelated `AdmissionDoorbellTests` runtime control missed a
transient `.consumerWaiting` observation and left the repo-wide lint gate open.
Production callsites remain zero and composition remains preinstall. Continue
W4.5p by adding the installed-only pane-residency persistence gateway with one
fixed-revision capture and one atomic application; runtime retained-payload
ownership and production cutover remain separate later slices.

Commit `6aa59b54` adds that installed-only pane-residency persistence gateway.
It constructs canonical planning witnesses from the bound atom owners, accepts
only the request plus the external retained-payload witness, preflights before
revision admission, captures every changed persisted owner under one proposed
revision, and applies the prepared transition synchronously. The strict result
returns the committed revision with the typed runtime effect or a typed
unchanged/rejection; zoom and retained runtime payload have no persistence
capture. Selection-sensitive cursor capture treats persisted `nil` selections
as absent rather than inventing optional lifecycle state.

RED proof failed only for the absent gateway/result APIs. Parent GREEN proof
passed 5 tests in one suite on the final formatted source, `mise run build`,
scoped swift-format and SwiftLint with zero violations, architecture lint, and
staged diff checks. The fixed-base tests cover background removal and shifted
shell preimages, all pane/tab/arrangement cursor owners, reactivation value
preimages and post-base insertion exclusion, unchanged/rejection, and
transaction-admission atomicity. The persistence methods have zero production
callers; the existing same-named App calls still target the legacy
`WorkspaceMutationCoordinator`. Continue W4.5p by completing the remaining
composition writer-family inventory and dormant semantic gateways before the
single production writer cutover. Runtime retained-payload custody remains part
of that later atomic cut, not this persistence gateway.

Commit `e02280ca` adds the dormant runtime-only pane-residency lifecycle owner.
It holds retained drawer payloads outside atoms, delegates each background or
reactivation request exactly once to the installed persistence gateway, changes
runtime custody only for typed changed effects, and emits a typed mount intent
only after a successful reactivation consumes its payload. Unchanged and
rejected transitions preserve custody and emit no mount. The owner shares the
existing persistence mutation coordinator and creates no second revision,
participant, persistence, or atom authority.

Parent proof passed 4 tests in one suite, `mise run build`, scoped swift-format,
SwiftLint, architecture lint, and diff checks. Independent Luna xhigh review
returned READY with no blocking finding; its additional rejected-background,
unchanged-reactivation, and per-pane-isolation cases remain nonblocking proof
extensions for the later production cutover. Source reachability remains zero
outside the runtime property/initializer and tests, so no App or Feature path can
invoke this owner yet. Continue W4.5p with the remaining pane/tab/arrangement
writer families and settled UI-memory checkpoint contract before the single
atomic production writer cutover. No startup repair or migration is permitted.

Commit `2225cd77` adds the dormant keyed arrangement-selection family for
discrete active-main-pane and active-drawer-child changes. Pure planners accept
strict target-only contexts, validate the exact active arrangement and visible
main/drawer membership, reject minimized selections explicitly, and return
typed changed/unchanged/rejected decisions. The MainActor applier preflights the
target tab, active arrangement, and exact cursor witness before assigning one
keyed cursor. The installed-only persistence gateway captures one active-pane or
active-drawer-child preimage and commits one revision. No fleet cursor snapshot,
fact-bus route, atom-owned workflow, or production callsite was added.

Parent proof passed 16 tests across three suites and `mise run build`; scoped
swift-format, SwiftLint, architecture lint, diff checks, target-only source
guards, and App/Feature reachability guards passed. The single independent
review found minimized-selection and fleet-context defects; its one remediation
cycle added typed rejection, keyed contexts, missing/no-selection insertion,
selected-to-empty tombstone, stale-drawer, and 256-entry unrelated-fleet proof.
The gateway remains production-dormant. Continue W4.5p with the strict layout
resize union and latest-settled checkpoint owner using the existing
`LatestValueSettleGate`, before the single atomic production writer cutover.

Commit `2fd3c773` adds the dormant strict layout-resize family. A four-case
discriminated checkpoint carries the exact tab, arrangement, main/drawer target,
and ratio without correlated optionals. The pure planner reads one target tab
and exact active-arrangement witness, validates ratio/split/row/collapsed-pair
semantics, and returns one keyed tab-graph replacement. The MainActor applier
preflights the keyed graph and active arrangement; the installed-only gateway
captures one tab-graph preimage and commits one revision. A thin checkpoint
owner reuses `LatestValueSettleGate`, binds one immutable resize target, rejects
cross-target offers, flushes explicitly, and reports the typed commit result.

Parent proof passed 13 tests across four suites and `mise run build`; scoped
swift-format, SwiftLint, architecture lint, diff checks, and zero App/Feature
reachability passed. The single review found an unkeyed cross-target loss hazard
and missing no-op/range/stale/revision-zero proof. One remediation bound each
owner to a strict target and added 128-to-1 latest settlement, explicit flush,
close, rejection reporting, cross-target custody, ratio boundary, stale active
arrangement, revision-zero, fixed-base, and 256-unrelated-tab proof. Missing
drawer members now reject as invalid pairs rather than falsely reporting a
cross-row failure. Production drag previews and caller cutover remain later
atomic work; this slice changes no live resize route.
