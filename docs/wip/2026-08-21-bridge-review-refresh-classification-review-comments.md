# Bridge Review Refresh Classification — Design Review Comments

Date: 2026-08-21
Result: **revised after closed review** — the original 2 blockers, 6 important
findings, and 4 minor/observation findings remain parent-verified and corrected.
The owner-authorized install-admission simplification landed afterward, so the
original independent review does not cover that revised mechanism. No second
review was run.

## Review identity

- Mode: three-artifact-design (spec-program-review); one fresh-context, read-only, candidate-only mode-complete reviewer; parent verified every finding.
- Targets:
  - [Requirements](../specs/2026-08-21-bridge-review-refresh-classification/2026-08-21-requirements.md)
  - [Specification](../specs/2026-08-21-bridge-review-refresh-classification/2026-08-21-specification.md)
  - [Program Design](../specs/2026-08-21-bridge-review-refresh-classification/2026-08-21-program-design.md)
- Governing sources: remediated 2026-08-18 bridge-latest-generation-operations set; 2026-08-06 worktree-annotations PR1 set. All read fully.
- Prior review of this target set: none. Remediation rounds used: 1 of 1.
- Reviewer independence verified: no edits to targets (dir untracked, no tracked mutations), fresh context, read-only.

## How this design helps the system (what held)

- **The structural crux is correct and verified in code.** The worker stages a pending projection and publishes Review display patches only at the atomic post-final-barrier commit (`bridge-comm-worker-review-metadata-applicator.ts` `assertCompleteFinalBarrier`; single `#publishApplication`). The main render store's active/staged banks are therefore the right — and only timely — hold point. Holding in native would invert ownership; holding in React would be too late.
- **One pipeline is genuinely preserved.** Ordinary and promoted share comparison computation, latest-generation authority, and failure paths. No second Review source of truth appears anywhere in the realization.
- **Foundation labels are honest.** Parent-verified: `BridgeReviewPublicationCoordinator` exists (`Sources/.../Runtime/ReviewFoundation/`); `BridgePaneRefreshAdmissionCoordinator` per-lane generations exist (`:131,138,296,313`); `applyBridgeWorkerMessagesToMainRenderSnapshotStore` exists (`bridge-app-review-render-snapshot-controller.ts:552`); the edit-surface registry exists today as a count-per-edit-token registry (`worktree-annotation-surface-provider.tsx:49`) exactly as the design claims; staged bank / candidate-ready / attention context are correctly labeled "added".
- **Non-goals survive realization.** No polling, no new physical route, no global interaction manager, no loading row, no timer-forced install, no second refresh engine.
- **BLO authority is not contradicted.** Computation and candidate authority still advance immediately; only the completed display swap is held, which the new owner Requirements authorize. Latest-generation fencing, last-complete retention, and the four-terminal contract are preserved.
- **It attacks the right lived problem.** This is the "review jumps under me / churn disrupts commenting" class — complementary to (not a substitute for) the recovery gaps in the 2026-08-20 implementation review.
- V-RRC-001..006 proof obligations are observable at their stated layers, including worker replacement and cross-boundary production-real proof.

## Root cause behind both blockers

Introducing a display hold makes **"displayed"** and **"native/worker current"** divergent for the first time. Only the Review presentation bank was designed for that divergence. Two other planes still equate the two:

```text
                     native/worker "current"          main "displayed"
                     ────────────────────────         ─────────────────
before this design      always equal — one identity, no divergence
after a hold            candidate B (committed)       Review A (held)
                              │                             │
   impact measurement ────────┘  measures B→C     should measure A→C   (F2)
   annotation plane ──────────┘  generation = B   comments shown on A  (F1)
```

## Findings — accepted blockers

### F1 — Annotation plane still equates "current" with "displayed"; a hold breaks comments, placement, and output fencing
- **Severity:** blocker. **Disposition:** accepted (parent-reproduced).
- **Requirement:** U-RRC-004/005, R-RRC-005, R-RRC-007 — commenting stays usable during a hold, comments bind to the Review actually shown, origins re-evaluate only after install.
- **Evidence (parent-verified):** `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:686-693` — `onReviewMetadataEvent` applies the event then calls `setReviewAnnotationProjectionGeneration(activeReviewSourceIdentity?.reviewGeneration)`. The annotation projection generation advances at **worker application**, not main-thread installation. Also `Sources/AgentStudio/Features/Bridge/Transport/WorktreeAnnotations/WorktreeAnnotationSourceCapture.swift` — origin capture resolves against `committedPublicationForReplay` and throws `invalidSource` when the browser-supplied displayed identity no longer matches the committed publication.
- **Consequence:** under a promoted hold, placement evaluation, projection demand, and the PR1 output displayed-scope fence (R-P1-010) follow candidate B while the reviewer sees A: comment cards evaluated against the wrong material; Copy/Export either persistently conflicted (convergence can't arrive while install is held) or silently B-relative; a new comment on displayed A can be rejected `invalidSource`.
- **Smallest correction:** Program Design adds the rule and owner: annotation projection demand, placement evaluation, and the output-scope fence follow the **installed (displayed) generation** until staged-bank promotion; name the edge that keeps native able to resolve the displayed publication's source handles while a hold or staged bank exists.
- **Route:** program-design.

### F2 — Impact provider's "displayed source identity" input has no owner; displayed-material retention during a hold is undesigned
- **Severity:** blocker. **Disposition:** accepted (parent independently derived the same defect before the receipt).
- **Requirement:** R-RRC-002 — facts MUST describe displayed-source→candidate change.
- **Evidence:** Program Design "Refresh impact" says the provider "accepts the displayed source identity" but no edge supplies it; forbidden edge "native refresh owners do not read React interaction state" blocks the shortcut; the call-path delta has no main→native install-receipt edge. Native's last complete publication (B) diverges from displayed (A) once staging exists.
- **Consequence:** successor C is measured B→C instead of A→C: a small B→C delta classifies C ordinary and silently jumps the display A→C — exactly the disruption promotion exists to prevent; a revert-shaped C is needlessly promoted. Displayed publication A's identity/material may be released while still needed.
- **Smallest correction:** Program Design names the displayed-source authority and its carrying edge (an install receipt on the existing command route updating the coordinator's displayed-source record — no new physical route), plus native retention of the displayed publication's identity/material while any hold or staged bank exists.
- **Route:** program-design. (Fixing F2 supplies the identity F1's rule needs — resolve together.)

## Findings — accepted important

### F3 — Successor-candidate class after stagedReady is contradictory
- Design state model forces every newer C into the promoted `receiving(A, C)` path (program-design "State model"); "Installation admission" sends ordinary candidates down the normal install path; the spec never defines an ordinary-class successor while `Update ready` shows. Two implementers produce different visible behavior.
- **Correction:** Spec: one sentence/boundary example — successors classify against the *displayed* Review; an ordinary successor installs normally and releases the staged candidate and bar. Design: add `stagedReady(A,B) + ordinary C ready -> active(C)`.
- **Route:** spec-design -> program-design.

### F4 — "Review item owning the reading position" has no determination rule and no existing signal owner
- No reading-position/visibility/scroll-anchor tracking exists in the viewer today (selection only, `bridge-app-review-viewer-mode.tsx:131,374-383`; scrollTop internal to code-view). Which item "owns the reading position" is implementer-invented; prior repo history shows app-side scroll anchors conflict with Pierre's scroll ownership, so the mechanism is not a free choice.
- **Correction:** Spec defines the reading-position rule observably (one sentence); Design names the signal owner and a Pierre-compatible mechanism.
- **Route:** spec-design -> program-design.

### F5 — Apply now target: "captured at action admission" contradicts "applies the newer candidate"
- Program Design "Supersession and concurrency" bullets 4 and 5 state both. Also unstated whether a superseding candidate applied via Apply now re-runs the continuity check.
- **Correction:** one rule — Apply now admits an install request; at commit the gate promotes the newest complete staged candidate present at that moment, subject to the same continuity check; if none is complete, presentation returns to `Updating…`.
- **Route:** program-design.

### F6 — Unknown-reason promotion has no affected-set semantics during computation
- `promoted(unknown)` carries no affected file identities, yet the computing-phase `Updating…` bar renders only by intersection with the affected set. Whether the bar shows for any/all/no attention is a guess until candidate readiness.
- **Correction:** state that unknown impact treats every Review context as affected (conservative) until the candidate-ready affected-item set replaces it.
- **Route:** program-design.

### F7 — Provisional bank missing from the state model; one-staged-Review bound can be exceeded
- The ordinary-with-editor provisional bank holds a normalized Review but appears nowhere in the state model, has no release edges (supersession, worker reset, pane close), and can coexist with a staged promoted bank: active A + staged B + provisional C = three normalized Reviews, exceeding R-RRC-012's "active + one newest staged" bound. (The third-presentation-class concern resolves benignly: worker publication is commit-time-atomic, so the provisional bank is a within-delivery apply buffer, not an observable class.)
- **Correction:** Spec: one clause in R-RRC-012 acknowledging one transient in-flight candidate bank (or requiring serialization). Design: add provisional states and release edges to the state model.
- **Route:** spec-design -> program-design.

### F8 — Staged-state discard on worker replacement has no named owner or edge
- "Worker reset: staged worker-derived state is discarded" is asserted with no replacement→store edge in the delta table. Replacement is observable main-side today (`bridge-pane-runtime.ts:153`), but if a replaced worker never emits a new-epoch review event, the staged bank and `Update ready` bar persist with no discard trigger. (Consistent with implementation-review H1: worker retirement settles nothing synthetically.)
- **Correction:** name the owner (the pane runtime / app review controller that observes replacement) and the discard call into the main render store at replacement time, not next-event time.
- **Route:** program-design.

## Findings — accepted minor / observation

- **F9 (minor):** spec `updateReady` vs design `stagedReady`; "candidate-ready **terminal**" collides with the 2026-08-18 terminal-outcome vocabulary. Correction: one state name (prefer `updateReady`); call the worker event a candidate-ready event, not terminal. Route: program-design.
- **F10 (minor):** presentation-class ownership split — the native coordinator owns the class enum including reason `activeAnchor`, but only main can detect anchor unpreservability. Correction: main installation gate owns the final effective class and emits the escalation reason; native owns only the pre-delivery class. Route: program-design.
- **F11 (observation):** candidate-ready event "containing the Review package" reads as payload duplication; say "package identity". Route: program-design.
- **F12 (minor):** "same-source" used normatively, never defined. Correction: one sentence (same worktree lineage and unchanged comparison-target selection). Route: spec-design.

## Coverage

- Covered: identity separation; bidirectional U↔R traceability (all 8 needs covered, all 12 Rs trace back); program-design grounding, ownership, interfaces, state, call-path deltas, failure/concurrency/recovery, cutover, proof seams; three-artifact integration; crux attack; planner-readiness probe.
- Gaps (named, not silent): Git-scheduler capability to produce displayed→candidate commit/file/line deltas within current bounds not audited (folded into F2's correction); R-RRC-011 accessibility judged at contract level only (header chrome components not inspected); 2026-08-18 implementation status treated as design authority (its seams verified in source).
- Unverifiable claims recorded: wire patch-limit never splitting a very large ordinary replacement into multiple visible applications (`bridge-worker-contracts.ts:765-775` bounds patches per event; single-commit publication makes this likely fine, unproven).

## Parent-verified remediation

- **F1/F2:** the Specification now keeps annotation projection, placement,
  root-source validation, and output fencing on the displayed generation until
  installation. Program Design uses lineage-monotonic `nativeCurrent` and
  `acknowledgedDisplayed` registers, one exact install-admission CAS, and the
  existing `review.publication.applied` receipt after main promotion. Divergence
  classifies conservatively and retains exact annotation source resolution.
- **F3/F12:** same-source is defined, every successor measures from the Review
  actually displayed, and an ordinary successor releases an older held
  candidate and installs without inheriting its bar.
- **F4:** the Specification defines the leading-edge reading-position owner.
  Program Design extends the existing Pierre-owned visible-item callback without
  adding a scroll owner, observer, or polling path.
- **F5/F6:** Apply now resolves the newest complete candidate at commit, while
  unknown impact treats every current Review context as affected until an exact
  affected-file set arrives.
- **F7:** provisional and update-ready are mutually exclusive roles of one
  candidate bank, preserving the active-plus-one bound through supersession,
  failure, close, and worker replacement.
- **F8:** the existing pane-runtime worker-replacement edge explicitly discards
  candidate state and promoted chrome; after bootstrap main resends the existing
  applied receipt for its retained active bank.
- **F9/F10/F11:** state names use `updateReady`; candidate readiness is an event;
  native owns only the pre-delivery class, main owns the final effective class;
  and the event carries package identity rather than duplicating the package.

Parent verification re-read the corrected Specification and Program Design,
checked every original finding against its new anchor, ran whitespace/diff
checks, and confirmed that Requirements U-RRC-001 through U-RRC-008, all
non-goals, the single update pipeline, and existing physical routes remain
intact. The post-review simplification removes transition identifiers,
prepare/confirm/abort state, forced replacement recovery, thread-level
affectedness, prescribed editor-field duplication, and prescribed candidate
cloning. Planning-readiness now requires either explicit permission for a second
independent design review or an owner decision to proceed on parent self-check
alone; implementation acceptance is not claimed.
