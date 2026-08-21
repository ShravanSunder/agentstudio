# Demand Admission Regression — Requirements

## Source Authority

- The product owner authorizes this work to remove the `v0.0.89` and `v0.0.90` performance regressions while preserving their intended sidebar activity and pull-request-loading outcomes. The owner identifies `v0.0.88` as the acceptable pre-regression control, expects the app normally to remain below 30% CPU under the same real workload, and prioritizes eliminating unnecessary work, broken admission/coalescing, and inappropriate MainActor execution.
- [Demand-Driven Derived-State Refresh](../../architecture/state/demand_driven_derived_state_refresh.md) is the normative mechanism-selection and stage vocabulary.
- [Workspace Data Architecture — Sidebar Data Flow](../../architecture/state/workspace_data_architecture.md#sidebar-data-flow), [Atom and Persistence Boundaries](../../architecture/state/atom_persistence_boundaries.md#atom-and-actor-placement), and [Pane Runtime Architecture — Contract 7](../../architecture/runtime/pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction) are normative owner boundaries.
- [Repository-Branch Pull Request Facts](../2026-08-10-repo-branch-pr-facts/requirements.md) remains normative for visible PR state, honest unknown/loading behavior, demand, single-flight refresh, and currentness.
- Tagged source and the [debug investigation](../../../tmp/debug-workflows/2026-08-20-agent-studio-issues-perf-mainactor-regression/debug-investigation.md) are observational evidence of the current failure; they do not authorize preserving accidental mechanisms.

## Affected Classes

- **U1 — Interactive Agent Studio users:** users operating real workspaces with many repositories, worktrees, tabs, panes, and active terminal output.
- **U2 — Sidebar users:** users relying on By Repository, By Pane, and By Tab rows for current activity, focus, recency, Git, and pull-request presentation.
- **U3 — Operators and maintainers:** people diagnosing performance through local OTLP/Victoria evidence without perturbing the measured workload or losing records.

## Authorized Needs And Outcomes

### U-PERF-1 — Restore steady interactive performance

**Priority:** P0, assigned by the product owner.

U1 needs `v0.0.89` and `v0.0.90` outcomes without their MainActor saturation. Under the same real heavy workspace where `v0.0.88` is acceptable, settled background operation should normally remain below 30% process CPU and must not produce sustained actor starvation, multi-second terminal round trips, or interaction loss caused by unnecessary derived-state work.

### U-ADMISSION-1 — Reject unnecessary work before expensive boundaries

**Priority:** P0, assigned by the product owner and required by the demand-driven architecture.

High-frequency or broad source changes must be reduced to the smallest consumer-relevant semantic fact, equality-suppressed, coalesced, and demand-admitted before they schedule or perform expensive MainActor capture, filesystem work, provider work, or OTLP emission.

### U-CURRENTNESS-1 — Preserve visible sidebar meaning

**Priority:** P0, assigned by the product owner.

U2 must retain current By Pane and By Tab activity rows, focus state, terminal-derived secondary content, recency presentation, Git/branch state, and honest PR unknown/loading/available state. A performance gate must not make a demanded visible row stale, drop the latest changed value, or confuse unknown, loading, unavailable, confirmed empty, and confirmed facts.

### U-ISOLATION-1 — Keep heavy derivation off MainActor

**Priority:** P0, required by repository architecture.

MainActor must remain the owner of canonical UI-observed state and final compact publication. Fleet-scale iteration, path canonicalization, filesystem access, full-surface reconstruction, provider work, and other heavy derivation must occur before or behind an actor boundary and cross to MainActor only as compact immutable facts, deltas, requests, or results.

### U-BOUNDS-1 — Bound every active lane

**Priority:** P0, required by repository architecture.

Every lane classified as often or heavy must name an admission policy, bounded pending state, equality/currentness rule, and failure behavior. Latest-state lanes must not become ordered trigger queues. Ordered facts must not be incorrectly replaced. Deferral must retain the latest required invalidation until the next demanded checkpoint.

### U-OBSERVABILITY-1 — Make regressions attributable without causing them

**Priority:** P0, assigned by the product owner and required by the demand-driven architecture.

U3 needs bounded per-stage outcome evidence that distinguishes observed, suppressed, coalesced, admitted, executed, superseded, published, and materialized work. Telemetry must expose waste and MainActor occupancy while remaining source-scrubbed and must not flood or drop the very records needed for diagnosis.

### U-PRESERVATION-1 — Retain sound existing mechanisms

**Priority:** P1.

The repair must preserve useful keyed state, Forge repository demand and single-flight provider execution, off-main Repo Explorer projection, generation/currentness validation, changed-result suppression, and exact ordered facts where their contracts remain valid.

## Boundaries

- Scope is the `v0.0.89` sidebar activity regression and the `v0.0.90` PR-loading amplification, including their terminal, Repo Explorer, Forge/cache, MainActor, and telemetry seams.
- Use the existing owners and typed domain-specific admission paths. This work must not create a generic admission framework, new state service, compatibility path, feature flag, or fleet-wide polling system.
- Hard cut over the faulty paths. Do not keep the broad observation/capture or raw work-intent publication as a fallback.
- Preserve `v0.0.88` behavior outside the named outcomes and corrections.
- Security, authentication, persistence schema, Git refresh policy outside the affected fan-out, Bridge transport, and unrelated UI redesign are non-goals.
- The 30% CPU objective is a workload-bound owner target, not a universal hardware promise. Proof must bind it to a recorded real-size workload and compare the same workload before and after the repair.

## Unresolved Evidence, Not Owner Decisions

- Current OTLP cannot attribute each Repo Explorer observation wake to one exact input key. The design must add a bounded attribution seam or deterministic proof without exporting raw identifiers.
- The real Ghostty full-viewport read duration is not instrumented. Its placement is known; its steady and worst-case cost still requires proof.
- `v0.0.88` per-row evaluation telemetry already floods the trace queue. It is an independent observability defect that the proof design must avoid carrying forward, but it is not the cause of the `v0.0.89` product regression.
