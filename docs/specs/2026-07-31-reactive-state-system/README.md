# Reactive State System — Program Design

This is the family-level Program Design: the integrated structural How for the
reactive-state work. Read Requirements for the authorized need, Specification
for the observable contract, then only the linked slice design that owns the
internal implementation question.

## Entry Point

[Reactive State System Requirements](2026-07-31-reactive-state-system-requirements.md)
is the authoritative Why: affected people, authorized needs, priorities,
boundary, and non-goals.

[Reactive State System Specification](2026-07-31-reactive-state-system-specification.md)
is the authoritative What: problems, outcomes, normative requirements
RS-01–RS-28, observable contracts, failure behavior, and proof obligations.

## Structural Slices

| Program Design | Primary ownership | Read when deciding internal How |
|---|---|---|
| [Reactive Atoms and Derived Values](2026-07-31-reactive-atoms-and-derived-values-program-design.md) | RS-01–RS-08, RS-10, and atom-specific RS-21–RS-23 realization | Source ownership, `AtomFamily`, lazy `DerivedAtom`, keyed observation, coherent aggregate reads, or Repo Explorer's first reactive slice |
| [Off-Main Materialization and Lifecycle](2026-07-31-off-main-materialization-and-lifecycle-program-design.md) | RS-09–RS-14 and eager/performance RS-24–RS-28 realization | `EagerDerivedAtom`, checked transfer, latest-wins lifecycle, Tab Bar projection, native interaction proof, or performance continuity |
| [SQLite Authority and Update Boundaries](2026-07-31-sqlite-authority-and-update-boundaries-program-design.md) | RS-15–RS-20 and persistence-specific RS-24–RS-28 realization | Core/local authority, dirty lanes, settings transactions, restore freshness, rollback/crash proof, or upgrade/relaunch behavior |

RS-21–RS-28 are cross-cutting. Each design owns only the guardrail,
observability, and proof realization for its slice; none introduces a parallel
lint, telemetry, benchmark, debug-launch, or SQLite test framework.

## System Map

```text
Requirements — authoritative Why
  -> Specification — authoritative What
       -> Program Design
            -> Reactive atoms — source and lazy graph HOW
            -> Off-main materialization — replaceable CPU projection HOW
            -> SQLite boundaries — authority-specific durability HOW

Every Program Design extends the existing ArchitectureLint, debug IPC/UI,
Victoria/comparator, and SQLite test systems. None creates a parallel system.
```

## Integrated Ownership and Proof

| Accepted need | Observable contract | Structural owner | Existing proof system extended |
|---|---|---|---|
| U1, U2, U4 | Key isolation, coherent mutation, current lazy/eager output | Core/Feature product owners over Infrastructure atom primitives; App only where cross-Feature composition is required | Swift Observation behavior suites and ArchitectureLint |
| U3 | Compatibility across each hard cut | The product owner of the selected source, projection, or persistence lane | Isolated debug interaction plus supported-data save/reload and relaunch |
| U5 | Checked off-main replaceable computation | Product capture/projector plus retained `EagerDerivedAtom` lifecycle | Compiler-negative transfer proof and deterministic overlap/cancellation tests |
| U6, U7 | Honest enforcement and provenance-bound evidence | Existing ArchitectureLint, trace tags, Victoria workload, and comparator owners | Static, semantic, runtime, and matched-distribution gates at their actual boundaries |
| U8 | Authority-specific atomic save and stale-completion admission | Existing Core/App stores and authority-specific repositories | Real GRDB rollback, overlap, crash/reopen, and relaunch suites |
| U9 | Narrow independently provable adoption | Each linked slice; no family-wide runtime coordinator | Slice inventory through the existing lint, test, debug, and performance systems |

## Current Two-PR Atom Scope

The current implementation scope is exactly two pull requests:

```text
PR 1  AtomFamily + lazy DerivedAtom
      └── Repo Explorer keyed worktree-facts admission

PR 2  eager/off-main EagerDerivedAtom
      └── Tab Bar projection and current-result publication
```

PR 1 does not depend on eager materialization or persistence changes. PR 2
depends on the cancellation-only eager primitive and current Core/Feature
source contracts, not on the SQLite design or deferred pane/tab family
migrations. The measurement correction described by the off-main design is a
PR 2 proof prerequisite, not a third reactive-state implementation PR.

The SQLite program design remains a separate future design surface. Combined
settings and lane-aware Core/local persistence are not part of either current
atom PR.

Deferred pane, tab, topology, session, terminal-activity, Repo Explorer-worker,
Inbox-worker, and Command Bar migrations require their own measured or
correctness-proven slices. This family does not authorize a whole-state-system
rewrite.

## Shared Proof Boundaries

| Concern | Existing proof system to extend |
|---|---|
| Source/derived declaration and target direction | Existing `Tools/AgentStudioArchitectureLint`; add the required executable compile-negative driver because the current excluded fixtures alone are not proof |
| Semantic observation | Swift Testing suites using real Swift Observation |
| Native behavior | Worktree-isolated LaunchServices debug app, authenticated debug IPC, and native UI inspection |
| Performance | Existing Victoria workload summaries and provenance-enforcing comparator, after the standalone measurement prerequisite makes hot attributes lazy, reports trace-queue completeness, and adds interaction-to-visible/current-result boundaries |
| SQLite rollback/crash/restore | Current file-backed GRDB suites and disposable subprocess/probe pattern |
| Telemetry safety | Existing OTLP allowlist and fail-open suites |

Program designs define seams and obligations. A later implementation plan owns
exact tasks, commands, ordering, and evidence locations.
