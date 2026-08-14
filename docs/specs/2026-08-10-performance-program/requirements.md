# Performance Program — Requirements

Requirements identity for the AgentStudio performance program. Normalized from
owner decisions confirmed 2026-08-10 (in-session, recorded decision log) and
the 2026-08-10 performance research synthesis. This document records WHY, for
whom, and within what boundary.

**Artifact set** — Requirements (this file, WHY) →
[Specification](2026-08-10-performance-program.md) (WHAT) →
[Program Design](program-design.md) (HOW) ·
supporting: [doc-drift inventory](doc-drift-inventory.md) ·
per-slice plans under [plans/](plans/) ·
tracking: [Linear — AgentStudio Performance](https://linear.app/askluna/project/agentstudio-performance-af1a052f81d5)

## Affected classes

- **Owner-user** — Shravan, the daily production user of AgentStudio. Bears
  interaction hitches, fan/heat, and startup delay directly.
- **Agents** — AI agents implementing and reviewing changes in this repo. Bear
  the cost of stale docs and missing guardrails (they re-introduce fixed
  failure classes or mis-model the system).
- **Automation** — headless jobs (cron, CI, agent sessions) that must measure
  performance without a human driving the app.

## User requirements

| U | Class | Need (owner's words, normalized) | Evidence | Authority | Priority |
|----|-------|----------------------------------|----------|-----------|----------|
| U1 | owner-user | Common user actions — opening/closing the command bar, moving tabs, opening/closing sliders (split dividers), Cmd+R, animations — must not run computations or side effects, "or we do them well." | Owner statement 2026-08-10; v0.0.76 telemetry: tabbar-terminal p95 ≈1.8s, 95.1% of invalidation outcomes `equal` | authorized | 1 |
| U2 | owner-user | The MainActor must not be blocked by work that does not need to be there; processing happens off the main actor as much as possible. | Owner framing 2026-08-10; research L2 on-main inventory; 08-07 stack samples | authorized | 1 |
| U3 | owner-user | Triggers throughout the whole system fire correctly: not over-aggressive, with proper coalescing/debouncing and admission. | Owner framing 2026-08-10; research L3 trigger audit (fixed 500ms git window, full-refresh-all, fan-out) | authorized | 1 |
| U4 | owner-user | The atom system (including the eager off-main seam) is used systematically so derivation work is keyed, narrow, and off-main. | Owner question/confirmation 2026-08-10; L4/L7: seam adopted once, Repo Explorer capture still broad-reads | authorized | 2 |
| U5 | owner-user, automation | Every improvement is proven with telemetry: marker-scoped measured improvement per slice; if a surface has no probe, the probe ships first. | Owner selection 2026-08-10 (proof-bar decision) | authorized | 1 |
| U6 | agents | Architecture docs reflect current code so future users and agents build correct mental models. | Owner statement 2026-08-10; L6 stale-claim inventory | authorized | 2 |
| U7 | agents, automation | Compile-time/lint safety, succinct agent directives, and runnable automation prevent these failure classes from recurring and let the owner analyze performance headlessly. | Owner statement 2026-08-10 ("systematic and compile time or lint safety … run this in an automation") | authorized | 2 |
| U8 | owner-user | The work lands as roughly 3–6 trackable PRs (settled: 5), step-by-step, low-hanging fruit first, tracked in a dedicated Linear project. | Owner decisions 2026-08-10 (5 PRs, docs ride along, project created: AgentStudio Performance, LUNA-400..404) | authorized | 3 |

U8 is a delivery boundary, not product behavior: it constrains how work ships,
and does not authorize any internal design.

## Goal boundary (owner-confirmed 2026-08-10)

- **Goal**: AgentStudio feels responsive in daily production use; no common
  action hitches; no background churn from work that changes nothing.
- **Foundation to reuse**: existing atom primitives (keyed `AtomFamily` slots,
  equal-write suppression), the eager off-main Tab Bar seam, the git
  circuit-breaker/backoff work, the Victoria observability stack and
  marker-scoped proof harness, the SwiftSyntax architecture linter.
- **Missing outcomes**: see U1–U7.
- **Permitted change surface**: app source (Core, Features, App,
  Infrastructure), lint tooling, mise tasks, AGENTS/CLAUDE directives,
  architecture docs. New off-main seams and keyed observation structures are
  allowed, with hard cutover.
- **Protected**: no atom/observation framework replacement; no third-party
  split/layout framework adoption; no vendor (ghostty/zmx) changes without a
  separate explicit owner authorization; stable-channel tracing defaults and
  OTLP source-scrubbing rules unchanged.
- **Non-goals**: observability overhead is not a priority surface of its own
  (it is proof infrastructure); steady-state renderer/Metal optimization is
  measure-first future work; no CQRS/command-bus reshaping.
- **Acceptable complexity**: structural moves justified per-slice; no dual
  code paths or compatibility shims (repo hard-cutover rule).
- **Acceptable evidence**: marker-scoped Victoria telemetry deltas per slice
  (see U5), plus the repo's standard test/lint gates.

## Unresolved / deferred owner choices

- Numeric improvement thresholds per slice — including per-interaction p95 /
  per-frame gesture budgets for the U1 surfaces — are set at plan level, not
  in this program's requirements (owner decisions 2026-08-10; consequence:
  each plan must state its numbers before implementation starts, and the
  program is not complete while any priority interaction misses its
  threshold). The interaction measurement boundary itself is normative in
  the Specification (R1) and is not plan-adjustable.
- Steady-state renderer work: deferred until the renderer probe (slice 5)
  produces a ranking that demands it.
