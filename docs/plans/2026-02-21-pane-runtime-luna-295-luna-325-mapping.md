# Pane Runtime Architecture — LUNA-295 and LUNA-325 Mapping Plan

## Purpose

Provide an explicit contract mapping between:
- `LUNA-295` (pane attach orchestration, priority scheduling, anti-flicker)
- `LUNA-325` (bridge pattern, surface state, runtime refactor)

This is a design-only mapping artifact to guide implementation sequencing and review.

## Scope

1. Map `LUNA-295` lifecycle and scheduler contracts to pane runtime lifecycle contracts.
2. Map `LUNA-325` adapter/runtime/event contracts to the unified pane runtime model.
3. Define integration points and boundaries so both tickets compose without overlap/conflict.
4. Define Swift 6 strict typing/concurrency requirements for shared contracts.

## Contract Mapping

### LUNA-295 → Pane Runtime

1. `PaneAttachStateMachine` maps to `PaneRuntimeLifecycle` + attach sub-state machine.
2. `PaneAttachSchedulerService` maps to coordinator-owned scheduling/orchestration logic.
3. Priority tiers (`p0..p3`) map to event/action priority policy and routing urgency.
4. Attach events map into lifecycle event family with pane/worktree identity.
5. Background attach behavior maps to lifecycle invariants for non-foreground panes.

### LUNA-325 → Pane Runtime

1. Bridge-per-surface contract maps to adapter layer responsibility.
2. Ghostty callback translation maps to exhaustive `GhosttyEvent` enum boundary.
3. Runtime state ownership maps to per-pane runtime instance and `@Observable` UI state.
4. Typed event transport maps to unified coordination stream with envelopes.
5. Surface/state/runtime split maps to adapter/runtime/coordinator layering.

## Integration Rules (No Ambiguity)

1. `LUNA-295` owns attach scheduling semantics and lifecycle transition policy.
2. `LUNA-325` owns terminal adapter/runtime contract and Ghostty event coverage.
3. Shared types are defined once in pane runtime contract sections and referenced by both.
4. No NotificationCenter or untyped event dispatch in new plumbing.
5. Cross-ticket behavior changes must preserve lifecycle and event envelope invariants.

## Swift 6 Design Requirements

1. All cross-boundary contract types are `Sendable`.
2. Public runtime protocol methods remain async to preserve actor-upgrade path.
3. No stringly typed core contract surfaces for lifecycle/event identity.
4. Existentials are explicit (`any`) only where required by protocol boundaries.
5. C callback entry points use Swift 6-safe actor handoff patterns.
6. Error types crossing async boundaries are strictly typed and `Sendable`.

## Deliverables

1. Updated architecture doc sections that reference this mapping.
2. A checklist in review notes confirming each mapped item is addressed or deferred.
3. Cross-reference links in both ticket sections (`LUNA-295`, `LUNA-325`) to shared contracts.

## Status

Open. This file is the canonical mapping checkpoint for `LUNA-295` + `LUNA-325`.

