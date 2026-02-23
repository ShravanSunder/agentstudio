# Bridge + Diff Viewer Execution Plan

> Scope: Linear project `AgentStudio Bridge & Diff Viewer`  
> Date: 2026-02-23  
> Purpose: one detailed delivery plan with ticket-mapped sections and explicit multi-worktree execution rules.

## Canonical Architecture References

- [`docs/architecture/swift_react_bridge_design.md`](../architecture/swift_react_bridge_design.md)
- [`docs/architecture/pane_runtime_architecture.md`](../architecture/pane_runtime_architecture.md)
- [`docs/architecture/component_architecture.md`](../architecture/component_architecture.md)
- [`docs/architecture/window_system_design.md`](../architecture/window_system_design.md)
- [`docs/architecture/session_lifecycle.md`](../architecture/session_lifecycle.md)

## Canonical Ticket Graph

```text
LUNA-325 + LUNA-347 -> LUNA-337 -> (LUNA-338, LUNA-339) -> (LUNA-340, LUNA-348) -> LUNA-341
Optional tail: LUNA-337 -> LUNA-346
```

## Multi-Worktree / Multi-Agent Rules

1. One active ticket per worktree (`luna-337-*`, `luna-338-*`, etc.).
2. Never run two agents in one worktree.
3. Never mix scope from multiple tickets in one branch.
4. Rebase/merge only after direct blockers are landed.
5. If a contract changes, land fixtures + docs in the same changeset before downstream UI work.

---

<a id="section-1-contract-baseline"></a>
## Section 1: Contract Baseline (`LUNA-347`, `LUNA-337`)

### Ownership

- `LUNA-347`: runtime-independent contract/fixture freeze.
- `LUNA-337`: runtime-coupled bridge integration and delivery behavior.
- Runtime contracts stay owned by pane runtime architecture (`LUNA-325` family).

### Deliverables

1. Freeze bridge contract shapes shared by Swift + TS.
2. Validate canonical/invalid/stale fixture behavior in both runtimes.
3. Implement runtime-coupled content delivery semantics:
   - generation/epoch guards,
   - stale-drop,
   - cancellation and replay-safe behavior.
4. Keep transport envelope shape single-source; no parallel variants.

### Acceptance Criteria

1. No contract drift between Swift and TS fixture suites.
2. `LUNA-337` behavior is deterministic across restart/cancel/reload paths.
3. Downstream tickets can consume contracts without redefining them.

### Ticket Mapping

- `LUNA-347`: contract + fixture freeze only.
- `LUNA-337`: runtime-coupled integration only.

---

<a id="section-2-parallel-delivery-tracks"></a>
## Section 2: Parallel Delivery Tracks (`LUNA-338`, `LUNA-339`)

### Ownership

- `LUNA-338`: Pierre diff viewer integration and interaction UX.
- `LUNA-339`: CWD file viewer track that reuses shared bridge delivery contracts.

### Deliverables

1. Split execution into parallel tracks after `LUNA-337` baseline lands.
2. Keep both tracks compatible with the same bridge contract.
3. Ensure CWD track does not fork transport/data envelope shapes.
4. Preserve explicit in-scope/out-of-scope boundaries in each ticket.

### Acceptance Criteria

1. `LUNA-338` and `LUNA-339` can be implemented independently in separate worktrees.
2. Both tracks merge cleanly against the same Section 1 baseline.
3. No duplicate contract types introduced by parallel branches.

### Ticket Mapping

- `LUNA-338`: diff renderer + file tree + UI/store integration.
- `LUNA-339`: CWD tree/file view + shared content pipeline reuse.

---

<a id="section-3-fan-in-hardening"></a>
## Section 3: Fan-In Hardening (`LUNA-340`, `LUNA-348`, `LUNA-341`, optional `LUNA-346`)

### Ownership

- `LUNA-340`: review model + agent workflow integration.
- `LUNA-348`: transport-layer security hardening baseline.
- `LUNA-341`: post-fan-in viewer/workflow hardening.
- `LUNA-346`: optional push/backpressure hardening tail.

### Deliverables

1. Land review/agent domain features on top of `LUNA-338`.
2. Land transport security baseline before final fan-in hardening.
3. Execute final cross-feature hardening only after `LUNA-339`, `LUNA-340`, and `LUNA-348` converge.
4. Keep `LUNA-346` gated by profiling evidence (not default critical path).

### Acceptance Criteria

1. Combined review + viewer + transport flows satisfy lifecycle and security invariants.
2. Final hardening covers page crash, cancellation, slow-consumer, and resume paths.
3. `LUNA-346` remains optional unless measured pressure requires it.

### Ticket Mapping

- `LUNA-340`: review and agent lifecycle.
- `LUNA-348`: transport security controls.
- `LUNA-341`: fan-in hardening after `LUNA-339` + `LUNA-340` + `LUNA-348`.
- `LUNA-346`: optional backlog hardening.

---

## Ticket Description Standard (Required)

Each active ticket in this project must include:

1. Explicit in-scope and out-of-scope bullets.
2. Hard blockers (`blockedBy`) and downstream dependents (`blocks`).
3. Architecture references (from the list above).
4. Link to the exact section anchor in this plan file.

Legacy stale tickets (`LUNA-328` to `LUNA-333`) remain superseded and are not execution sources.
