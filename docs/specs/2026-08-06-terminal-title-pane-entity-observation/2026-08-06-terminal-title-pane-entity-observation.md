# Terminal Title Cadence And Pane Observation Proportionality

Date: 2026-08-06

Requirements:
[2026-08-06-terminal-title-pane-entity-observation-requirements.md](2026-08-06-terminal-title-pane-entity-observation-requirements.md)

## Observable Problem And Intended Difference

Agent Studio already contracts raw terminal titles by surface lifetime, but a
pending title can currently be published early when unrelated urgent local
presentation arrives. Each surviving title mutation is then observed through
broad pane collections. In live evidence, 33 admitted title changes produced
33 pane layouts and 33 tab-bar refreshes in 11 seconds, while process sampling
found Repo Explorer command presentation repeatedly entering whole-workspace
capability projection on MainActor.

The intended behavior has two independent observable differences:

```text
terminal title burst
  -> latest value retained for one fixed, non-sliding window
  -> urgent local presentation remains prompt but cannot publish the title
  -> latest changed title publishes by the one-second maximum or an exact barrier

one pane fact changes
  -> only consumers of that pane and relevant fact are invalidated
  -> unrelated panes, tabs, sidebar rows, and capability presentation stay quiet
```

The system boundary remains opaque to its consumers:

```text
Interactive user ── terminal UI and pane/tab/sidebar UI ──┐
IPC consumer ────── title sequence/replay/wait contract ──┤
Operator ────────── bounded aggregate runtime evidence ───┤
                                                         ▼
                                                  ┌──────────────┐
                                                  │ Agent Studio │
                                                  └──────────────┘

Negative space: no new public API, event vocabulary, persistence model,
visual design, or correctness dependency on telemetry.
```

## Title Cadence Contract

### R-T1 — Fixed maximum publication window

When a terminal surface has no pending title, the first admitted title MUST
open one fixed, non-sliding publication window. The latest admitted title for
that surface MUST be published no later than one second after that first
admission unless the surface is retired.

Later replaceable titles MUST replace the pending value without extending the
deadline. Continuous title churn MUST therefore neither starve publication nor
create more than one ordinary title publication per completed window.

### R-T2 — Independent local-presentation urgency

When cursor shape, cursor visibility, scrollbar/activity presentation, or
terminal-search presentation requires prompt publication, that work MUST remain
eligible for the existing immediate-presentation latency contract. Its
publication MUST NOT publish, reschedule, or restart pending title metadata.

This independence applies to urgency, not surface ownership or final-state
consistency. A consumer MUST still observe the latest presentation state and the
latest eventually published title for the current surface lifetime.

### R-T3 — Exact ordering barriers

When any later non-title exact command, fact, or control arrives for the same
surface, the earlier latest pending title MUST be resolved before that exact
event. Such an exact barrier MAY shorten the ordinary one-second title window.

Local presentation updates are not exact ordering barriers merely because they
require prompt publication.

### R-T4 — Changed latest value and compatibility

An ordinary or barrier-triggered title publication MUST apply at most the latest
admitted semantic title-callback kind and value for the current surface
lifetime. Independently, it MUST retain the latest admitted `setTitle` value for
that callback's existing host-side SurfaceView title effect. A later
`setTabTitle` MUST neither gain host-title authority nor erase an earlier pending
`setTitle` host update. Equal contracted values MUST produce no canonical
pane-title mutation or changed-title semantic fact.

A changed publication MUST preserve the existing title-kind distinction,
surface-title side effect, per-pane sequence, replay, EventBus, IPC
`titleChanged` wait behavior, and startup title-readiness behavior.

### R-T5 — Retirement and boundedness

Surface close, replacement, remount, cancellation, or runtime termination MUST
not apply pending title work to a retired or replacement surface. Pending state
MUST remain bounded by live surface lifetimes and fixed signal classes rather
than raw callback count.

Failure to publish a retired title is valid; publishing it to a replacement
surface is not.

## Pane Observation Contract

### R-P1 — Keyed entity invalidation

When the value associated with one pane identity changes without changing pane
membership, an observer that read only another pane identity MUST NOT be
invalidated. Observers of pane membership MUST be invalidated only when a pane
identity is added or removed.

Reading a missing pane identity MUST remain observable so later insertion or
removal of that identity produces a correct update.

### R-P2 — Fact-relevant invalidation

A title-only mutation MUST invalidate only presentation whose observable output
can depend on that pane title. It MUST NOT by itself trigger:

- Repo Explorer command-capability presentation;
- command-capability whole-workspace snapshot construction;
- pane projection for unrelated pane identities; or
- tab presentation for tabs whose visible label and controls cannot depend on
  the changed title.

If a custom tab name or worktree-derived label overrides a runtime title, the
title mutation MUST NOT be treated as a visible label change for that tab.

### R-P3 — Capability correctness

When pane membership, layout, residency, content kind, drawer ownership,
topology, or another capability-relevant fact changes, affected command
presentation MUST update before the next user interaction that depends on it.
Actual command execution MUST continue to validate current authoritative state
and reject invalid or stale invocation.

Optimizing presentation MUST NOT broaden execution authority.

### R-P4 — Explicit bulk work

Persistence, restore, cold bridges, diagnostics, and deliberately fleet-shaped
operations MAY consume complete pane snapshots. Hot UI and command-presentation
reads MUST NOT obtain keyed state by reconstructing an observed whole-pane
snapshot.

Runtime evidence MUST distinguish keyed reads and mutations from explicit bulk
snapshot operations so an accidental hot-path regression is observable.

### R-P5 — Final-state and lifecycle equivalence

After any accepted sequence of pane insertions, updates, removals, replacement,
restore, and teardown, the keyed observable state and every explicit bulk
snapshot MUST represent the same current pane membership and values. Removed
or missing observed keys MUST not retain unbounded observation storage or apply
later writes to a different pane lifetime.

## Cross-Cutting Constraints

### Performance

- Immediate local-presentation batches retain the accepted p95 below 8 ms and
  p99 below 16 ms callback-to-current-batch-commit budgets under terminal
  pressure.
- Ordinary title-only publication MUST occur no later than 1,000 ms after the
  first pending title admission. Exact barriers are reported separately.
- Under a controlled title-only mutation with Repo Explorer visible, unrelated
  Repo Explorer command-resolution and whole-workspace capability-snapshot
  counts MUST remain zero.
- Updating one pane identity MUST not cause keyed-read invalidations for any
  other pane identity.

### Reliability and compatibility

Exact fact ordering, title sequence/replay/IPC behavior, final current state,
surface replacement safety, command enablement, and command rejection behavior
must remain equivalent except for the authorized title cadence.

### Privacy and observability

Proof telemetry MUST remain aggregate and content-safe. It MUST NOT export pane
IDs, titles, paths, query text, terminal contents, or command payloads. Telemetry
may measure signal class, trigger class, count, duration, revision class, and
bounded fleet size. Telemetry is evidence only and owns no correctness state.

### Accessibility and platform behavior

Cursor shape/visibility, search feedback, scrollbar behavior, typing, focus, and
tab/sidebar interaction must retain their native macOS behavior. This change
introduces no new accessibility surface or visual language.

## Failure And Boundary Behavior

```text
Condition                              Required observable result
────────────────────────────────────────────────────────────────────────────
Continuous title churn                 Latest title publishes once per fixed
                                       window; deadline never slides.

Urgent local presentation              Presentation commits promptly; pending
                                       title remains pending.

Exact event after pending title         Latest preceding title resolves first.

Surface retires with pending title      No stale apply reaches a replacement.

Equal contracted title                  No pane mutation or semantic title fact.

Pane B changes                          Pane-A-only observer remains quiet.

Pane identity added or removed          Membership observers update.

Title changes with Repo Explorer open   Capability presentation remains quiet.

Capability-relevant structure changes   Affected UI updates; execution still
                                       validates current authority.
```

Partial success is not an accepted state for either slice: correct title
cadence with reordered facts fails, and keyed pane storage that is immediately
converted into a hot observed bulk snapshot fails proportionality.

## Proof Obligations

### V-T1 — Deterministic title timing and contraction

Automated behavior with an injected clock MUST prove first-title deadline,
latest-value replacement, non-sliding continuous churn, one-second maximum,
ordinary follow-up windows, and zero starvation.

### V-T2 — Mixed urgency and ordering

Automated behavior MUST interleave titles with cursor, scrollbar/activity,
search, exact facts/controls, drain-in-progress offers, close, replacement, and
remount. It must prove immediate-presentation latency, title independence,
exact-barrier order, final latest values, bounded claims/storage, and zero final
debt.

### V-T3 — Runtime title compatibility

Integration evidence MUST prove changed-only pane mutation, title-kind surface
behavior, sequence, replay, EventBus, IPC waits, startup readiness, and stale
surface rejection. Mixed-kind proof under both the ordinary deadline and an
exact barrier MUST show that `setTitle("window")` followed by
`setTabTitle("tab")` leaves the host title exactly `"window"`, publishes exactly
one semantic event `tabTitleChanged("tab")`, and grants `setTabTitle` no
host-title authority.

### V-P1 — Keyed observation oracle

Automated observation behavior MUST register readers for present and missing
pane identities plus membership, then prove that update, insertion, removal,
replacement, and pruning wake exactly the expected readers.

### V-P2 — Consumer invalidation and capability proof

Integration evidence with affected and unaffected tabs and visible Repo
Explorer rows MUST count title-triggered body/projection work, command
resolution, and whole-workspace capability snapshots. Title-only mutation must
produce zero unrelated work, while capability-relevant structural mutation must
update the affected presentation and retain live execution rejection.

### V-P3 — Bulk/keyed equivalence

Automated state inspection MUST compare an independent final-state oracle with
keyed values, membership, and explicit bulk snapshots across mutation,
restore/replacement, and teardown sequences. Retained slot count must remain
bounded by live plus actively observed missing identities and return to its
expected quiescent bound after pruning.

### V-R1 — Runtime interaction and performance

Marker-scoped runtime evidence MUST correlate title admission, ordinary versus
barrier publication, immediate local presentation, pane mutation class, keyed
invalidation, Repo Explorer command resolution, capability snapshot count,
tab-bar refresh scope, and interaction readiness. A bounded native smoke must
confirm typing, cursor, search, scrolling, focus, tab, and sidebar behavior.

## Requirement Coverage

```text
Need  Problem  Outcome  Requirements       Contract                 Proof
──────────────────────────────────────────────────────────────────────────────
U1    P1       O1       R-T1,R-T2,R-T5     title cadence/lifetime   V-T1,V-T2,
                                                                    V-R1
U2    P2       O2       R-T2,R-T3          urgency independence     V-T2,V-R1
U3    P3       O3       R-T3,R-T4,R-T5     ordering/compatibility   V-T2,V-T3
U4    P4       O4       R-P1,R-P2,R-P3     keyed/fact relevance     V-P1,V-P2,
                                                                    V-R1
U5    P5       O5       R-P4,R-P5          bulk/keyed equivalence   V-P3,V-R1
```

P1 is title-triggered MainActor pressure. P2 is urgency coupling between local
presentation and titles. P3 is compatibility risk from contraction. P4 is
whole-collection invalidation from one pane fact. P5 is loss of attributable
keyed behavior when hot and cold reads share one bulk shape.

O1 is bounded title cadence. O2 is prompt independent presentation. O3 is
preserved semantic behavior. O4 is proportional pane/UI invalidation. O5 is
explicit, equivalent, and measurable keyed versus bulk state.

## Undefined And Out-Of-Scope Behavior

- The exact internal scheduling, storage, revision, projection, and observation
  mechanisms are intentionally undefined here.
- No guarantee is made that every legitimate structural mutation avoids a
  SwiftUI render; only irrelevant title-only and cross-pane invalidation is
  prohibited.
- No general global-MainActor utilization ceiling is introduced. Proof is scoped
  to the title and pane-observation paths above.
- No title delivery guarantee survives termination of the owning surface; stale
  cross-lifetime publication remains prohibited.
- No new public compatibility promise is created for diagnostic telemetry names
  beyond their use in the scoped proof.
