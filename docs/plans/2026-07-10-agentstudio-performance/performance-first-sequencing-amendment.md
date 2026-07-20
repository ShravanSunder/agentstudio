# Performance-First Sequencing Amendment

Status: user-approved sequencing correction, 2026-07-12

Parent plan: [AgentStudio Performance Boundaries Implementation Plan](implementation-plan.md)

This amendment changes execution order only. It does not change the accepted
performance contracts, product boundaries, hard-cut requirements, security
invariants, correctness semantics, or final proof gates.

## Decision

Implement and test product performance behavior before cleanup and architecture
lint expansion.

```text
performance instrumentation and baseline seams
  -> watched-folder / Ghostty / MainActor / event-admission product work
  -> focused unit and real-boundary integration proof per slice
  -> atomic product hard cuts
  -> combined runtime and stability proof
  -> cleanup and architecture lint against settled APIs
  -> final full validation and acceptance
```

S1t at `d099ce3267e41629e5655a76b6b506d406404d69` is the bounded, strict
type-state foundation used by product lanes. S1h and the remaining S1i
completion work are deferred until product admission owners and call graphs are
settled. They must not grow into a reusable semantic compiler framework.

## Lint scope after product stabilization

Only these two AgentStudio SwiftSyntax rules are in scope:

1. Extend the existing `agentstudio_runtime_signal_plane` rule for the settled
   sample/fact/admission/callback boundaries. This includes the minimum S1h
   protected-state responsibility proof required by the accepted spec.
2. Add `agentstudio_mainactor_blocking_work` for the settled typed MainActor
   capture/apply boundaries.

W11 contributes domain-specific fixtures and clauses to those rules. It does
not create additional general-purpose lint frameworks. Compiler fixtures,
mutation scripts, and runtime flood/race tests are proof for these rules, not
additional lint rules.

## Revised execution gates

### P1 — Measurement and product preparation

- Build S3 MainActor/pipeline evidence seams and the S6 validity/runner core
  needed to measure product work.
- Build S2 fact contracts and S4 cutover-ready endpoints without a second
  production bus.
- Execute watched W1a/W2a/W1b and W3–W10.
- Execute terminal T1–T11.
- Every behavior slice remains RED/GREEN and climbs its required unit and
  real-boundary integration layers before integration.

### P2 — Atomic product integration

- Land W2b and W7d only at their existing complete-participant/sole-writer
  gates.
- Land IG1 only as the existing one-transport hard cut.
- Run focused product suites and runnable debug/observability proof before any
  lint expansion.

### P3 — Cleanup and guardrails

- Remove obsolete legacy helpers and temporary preparation surfaces exposed by
  the product cuts.
- Complete S1h and remaining S1i proof against the settled Admission graph.
- Complete S5 and W11 using only the two named SwiftSyntax rules.
- Run `mise run lint` after these APIs and ownership boundaries have settled.

### P4 — Acceptance

- Approve the immutable CG1 calibration manifest before candidate measurement.
- Run W12, T12, DQ1, and IG2 with Victoria, authenticated IPC, exact-PID native
  proof, final-state oracles, memory stability, and explicit human feel.
- Run full required test/lint/PR gates and implementation review.

## Proof and rollback

Deferring lint does not defer runtime safety proof. Each product slice still
requires its focused RED/GREEN tests, real boundary integration where named,
generation/currentness/custody oracles, and clean rollback boundary. Lint is a
late guardrail over proven behavior, never a substitute for it.

If product implementation reveals that the two named rules cannot express the
settled boundaries without broad allowlists or a general semantic compiler,
narrow the rule to a mechanically sound approximation and keep runtime proof
authoritative, as required by the accepted spec.
