# SDD ledger — plan: docs/specs/2026-07-31-reactive-state-system/plans/2026-08-06-pr2-eager-derived-tabbar-implementation.md

Base: f95da6877
Task 1: complete (070e14ea2; 11 selected tests, compiler-negative + script proof, scoped lint/architecture, clean fix re-review)
Task 2: complete (465f742bc + d733b4a4b; shared topology/facet policy, direct per-path cancellation regression, 9 selected projector tests, scoped lint/architecture)
Task 3: complete (56343c9ae; 4 projector + 28 existing atom tests, scoped lint/architecture, approved task review)
Task 3: minor (deferred): direct regression test for the projector's 256-item cancellation cadence
Task 4: complete (9c56426b7 + be186e9df; 39 selected tests, scoped lint/architecture; review Important stopped-node retention fixed)
Task 4: minor (deferred): drawer bridge test observes any freshness transition rather than requiring the successor generation to reach current
Task 5: complete (26b637f0b; distinct window-owned adapters, explicit idempotent close/replacement/termination shutdown, focused lifecycle proof, approved task review)
Task 5: minor (deferred): close-lifecycle test uses cooperative cancellation; cancellation-ignoring stale completion remains covered at EagerDerivedAtom level
Task 6: complete (b7d82594c + 47df9dd21; lazy disabled telemetry, bounded queue completeness, aggregate-only OTLP, exact per-sequence Tab Bar lifecycle with stop settlement and current/publication/visible phases, provenance/final-state comparator correction; 94 initial + 34 remediation selected tests, architecture/scoped quality proof, one independent review and bounded remediation pass)
Task 7: in progress (removed recovery-path forced try; replaced scheduler-yield test polling with bounded exact-event continuations using UUIDv7; 22 AppBootSequence + 2 formerly flaky eager tests + 116 broad focused tests passed; lint and 29 architecture tests passed; full isolated PR gate and runtime/performance proof remain)
Task 8: pending
