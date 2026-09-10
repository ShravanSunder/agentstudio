# Pane And Tab Switching Without MainActor Stalls — Specification

Date: 2026-09-04

Specification identity: `SPEC-2026-09-04-PANE-SWITCH-MAINACTOR-RESIDUALS`

Requirements: [REQ-2026-09-04-PANE-SWITCH-MAINACTOR-RESIDUALS](2026-09-04-pane-switch-mainactor-residuals-requirements.md)

## Observable model

For this specification a switch has three observable phases, each with a cost
that the consumer can measure at existing instruments:

```text
user action (tab / pane / drawer / arrangement)
  -> workspace selection write         at most one, only if selection changed
  -> sidebar reaction                  bounded refreshes, only changed rows
  -> target pane interactive           within the switch budget
```

Presentation, filesystem, and Git facts arrive on their own cadence. They may
change sidebar rows. They must not change the cost of the next switch.

## Consumer and observable-surface boundary

This view answers: who can rely on the behavior, at which observable surfaces,
and what adjacent behavior remains outside the contract?

```text
end user
  |-- switch surface: tab bar, pane click, drawer toggle/tap, ⌘ shortcuts,
  |                   arrangement change  -> target interactive within budget
  `-- sidebar surface: rows reflect facts; scroll position survives
                       content-only updates

maintainer / owner
  |-- pull-request gate: one lane fails when work per switch exceeds bound
  `-- telemetry surface: per-refresh wake_trigger, refreshes per switch,
                         MainActor queue wait, storm minutes

                 [ Agent Studio workspace shell + sidebar ]
                          (opaque product boundary)

outside this contract:
  Git/filesystem cadence; terminal hydration timing; persistence; IPC;
  commands; new UI; nonterminal pane behavior
```

## Normative requirements

### R1 — A switch completes within the switch budget

When the user performs a switch, Agent Studio MUST make the target tab, pane,
or drawer pane interactive with no more than 100 ms of MainActor queue wait and
held time attributable to sidebar, focus, or arrangement work, measured at the
existing tab-bar terminal and interaction instruments in a real-size workspace
(at least 20 repositories, 12 tabs, 30 panes).

Failure is observable when any tab-bar terminal record during a switch
workload reports queue wait above 100 ms, or when the macOS busy cursor
appears during a switch.

Basis: U1. Outcome: O1.

### R2 — Refreshes per switch are bounded and age-invariant

For any switch, the number of Repo Explorer command-presentation refreshes
attributable to that switch MUST NOT exceed two, and that bound MUST hold
regardless of how many sidebar viewport publications, content updates, or
prior switches occurred since launch.

Failure is observable when refreshes per switch grow with process age or with
the count of prior sidebar updates, or when any minute becomes a storm minute
during normal use.

Basis: U1, U2. Outcome: O2, O7.

### R3 — Unpresented facts produce no refresh

If a repository, filesystem, or Git fact changes atom state that is not part of
the currently presented sidebar rows, toolbar capabilities, or visible
worktree set, then Agent Studio MUST NOT perform a command-presentation refresh
for that change. A fact that changes a presented row MAY produce at most one
refresh.

Failure is observable when refreshes with `wake_trigger = observation` exceed
one per presented-row change, or when refreshes occur while no presented row
changed.

Basis: U3. Outcome: O3.

### R4 — Re-selecting the active target is a no-op

When the user selects a pane or drawer pane that is already the active pane
or active drawer pane of its tab, Agent Studio MUST NOT write tab, arrangement,
or drawer selection state and MUST NOT produce a refresh. Existing responder
and runtime focus behavior for such a selection is unchanged.

Failure is observable when a repeated tap on the active drawer pane produces a
selection write, a coordinator write, or a refresh.

Basis: U4. Outcome: O4.

### R5 — Content-only sidebar updates cost only the changed rows

When a Repo Explorer table update changes row content but neither row
membership, row order, nor any row's height, Agent Studio MUST keep the scroll
position exactly, MUST update only the rows whose content changed, and MUST
NOT perform a whole-table layout pass or a scroll-anchor restoration for that
update. Updates that change membership or any row height keep their current
geometry and anchor behavior.

Failure is observable when a content-only update moves the visible scroll
offset, rebinds unchanged rows, or records a forced layout pass or an explicit
scroll restoration.

Basis: U5. Outcome: O5.

### R6 — A presentation update republishes nothing unchanged

When SwiftUI updates the sidebar presentation host without a change to the
visible worktree snapshot or the command-presentation delta, Agent Studio MUST
NOT republish the visible snapshot to the command batch or the sidebar
runtime state. A changed snapshot is published exactly once.

Failure is observable when repeated identical presentation updates produce
snapshot publications or refreshes.

Basis: U1, U2. Outcome: O2.

### R7 — The pull-request gate bounds work per switch

The pull-request gate MUST include an automated lane that mounts the real
sidebar composition with a real workspace store containing repositories,
worktrees, tabs, and panes, performs at least one pane switch and one tab
switch, and fails when refreshes per switch exceed the R2 bound, when table
applies per switch exceed one, or when the batch never engages.

Failure is observable when a change that raises refreshes or applies per
switch above the bound passes the gate.

Basis: U6. Outcome: O6.

### R8 — Every refresh reports its trigger and the released build is comparable

Every command-presentation refresh MUST carry its wake trigger
(`visible_snapshot` or `observation`) in telemetry, exported through OTLP, so
that refreshes per switch, refreshes per trigger, storm minutes, and MainActor
queue wait can be compared across service versions.

Failure is observable when a refresh record lacks the trigger, or when the
released build's telemetry cannot be compared with 0.0.91 and 0.0.92 on those
measures.

Basis: U7. Outcome: O7.

### R9 — No persisted or public contract changes

Agent Studio MUST NOT change persisted schema, pane or session identity,
residency, IPC methods, or commands for this change, and MUST remain
installable and revertible across 0.0.92, 0.0.93, and the fixed build with no
migration.

Failure is observable when a downgrade or upgrade requires a migration or
loses workspace state.

Basis: U8. Outcome: O8.

## Observable contracts

### Switch contract

- Input/precondition: a user switch in a workspace of the R1 size; the
  process may have been running for any duration.
- Postcondition: at most one selection write when the selection changed; at
  most two refreshes; target interactive within the switch budget.
- Idempotence: repeating the same selection produces no write and no refresh.
- Compatibility: focus responder behavior, tab-bar rendering, and drawer
  visuals are unchanged.
- Explicitly undefined: ordering of sidebar row updates relative to the
  switch; this contract bounds cost, not order.

### Sidebar reaction contract

- Input: a Repo Explorer projection candidate accepted for the current
  generation.
- Content-only: scroll offset unchanged; only changed rows rebind; no forced
  layout pass; no anchor restoration.
- Membership or height change: existing behavior (frame update, anchor
  restoration to the surviving row, height re-measurement).
- Fact that changes nothing presented: no refresh.
- Explicitly undefined: the exact frame in which a changed row repaints.

### Gate contract

- Input: a pull request on `main`.
- Postcondition: the switch lane runs on every pull request and reports
  refreshes per switch, applies per switch, and batch engagement.
- Failure: exceeding the bound or non-engagement fails the lane and blocks
  readiness under the existing `mise run test` aggregate.

### Telemetry contract

- Records: `performance.repo_explorer.command_presentation` with
  `agentstudio.performance.repo_explorer.wake_trigger`, existing tab-bar
  terminal queue-wait and held-time attributes, existing stage snapshots.
- Comparison: by `service.version` and a fresh marker for debug runs.
- Privacy: no new attribute carries paths, repository names, or content.

### Boundary examples

- A user presses ⌘L forty times in a minute after twelve hours of use: at most
  eighty refreshes and no tab-bar queue wait above 100 ms.
- A build touches 300 files in a repository whose rows are not visible: zero
  refreshes.
- A Git status changes the ahead/behind count of one visible row: one refresh,
  one row rebinds, scroll offset unchanged.
- A user taps the already active drawer pane three times: no selection write,
  no refresh, focus stays where it is.
- A row's wrapped title grows to a second line: that row's height is
  re-measured and the anchor is restored, as today.

## Failure and negative space

- The switch budget is a bound on sidebar, focus, and arrangement work. It does
  not promise terminal surface readiness within the same budget; a pane that
  is still hydrating remains governed by the hydration design.
- Bounding refreshes does not change which rows the sidebar presents or when
  facts are admitted; Git and filesystem cadence are out of scope.
- A content-only update that turns out to change a measured height is treated
  as a height change and keeps anchor restoration; the classification must be
  conservative, never optimistic.
- The gate lane bounds counts on a mounted composition; it does not measure
  wall-clock time and is not a performance benchmark.
- Re-selection is a no-op for selection state only; responder and runtime
  focus reconciliation remain as today.

## Cross-cutting obligations

- Reliability: no persisted state, identity, or residency changes; every
  correction is inside an existing owner and revertible by code.
- Performance: R1 budget, R2 bound, R3 zero-refresh rule, R5 cost rule; all
  observable at existing instruments plus the wake trigger.
- Responsiveness: the switch budget applies to the first interaction after
  the switch, not only to steady state.
- Observability: refresh trigger, refreshes per switch, applies per switch,
  storm minutes, and queue wait are derivable from exported records without
  raw paths or content.
- Privacy and security: no new data collection; no new trust boundary.
- Accessibility: no UI change; existing focus and responder contracts hold.
- Platform compatibility: existing macOS, AppKit, SwiftUI, Ghostty boundary.

## Requirement-to-proof coverage

```text
U1,U2 -> P1,P4,P5 -> O1,O2 -> R1,R2,R6 -> switch contract
      -> V1 automated refresh-per-switch bound on the mounted composition
         + V2 debug-app switch workload with marker-scoped queue wait
         + V3 production telemetry comparison by service.version

U3    -> P5 -> O3 -> R3 -> sidebar reaction contract
      -> V4 automated: unpresented fact yields zero observation refreshes;
         presented fact yields one

U4    -> P2 -> O4 -> R4 -> switch contract (idempotence)
      -> V5 automated decider + executor: repeated active selection writes
         nothing

U5    -> P3 -> O5 -> R5 -> sidebar reaction contract
      -> V6 automated materializer: content-only plan performs no forced
         layout, no anchor restoration, keeps offset; height plan restores

U6    -> P6 -> O6 -> R7 -> gate contract
      -> V7 the lane itself, wired into mise run test; fails on a seeded
         regression

U7    -> O7 -> R8 -> telemetry contract
      -> V8 OTLP projection retains wake_trigger; V3 comparison

U8    -> O8 -> R9 -> compatibility
      -> V9 install/downgrade round trip with unchanged workspace state
```

## Proof obligations

- V1 — Automated behavior evidence on the mounted sidebar composition with a
  real store: one pane switch and one tab switch produce at most two refreshes
  each and at most one table apply each, and the count is unchanged after 200
  prior viewport publications and content updates.
- V2 — A marker-scoped debug-app run against the shared collector with a
  real-size workspace and a scripted switch workload of at least 40 switches:
  every tab-bar terminal record within budget, refreshes per switch within
  bound, no storm minute.
- V3 — Production telemetry of the released build over at least one hour of
  normal use compared with 0.0.91 and 0.0.92: zero storm minutes, refreshes per
  switch bounded, wake trigger present on every record.
- V4 — Automated evidence that a repository or filesystem fact affecting no
  presented row produces no observation refresh, and one affecting a presented
  row produces exactly one.
- V5 — Automated evidence that a content click or drawer tap on the already
  active target produces no selection write, no coordinator write, and no
  refresh, while a click on a different target produces exactly one write.
- V6 — Automated materializer evidence that a content-only plan keeps the
  scroll offset, rebinds only changed rows, and records zero forced layout
  passes and zero explicit scroll restorations, while a height or membership
  plan restores its anchor.
- V7 — The gate lane fails on a seeded regression (for example, re-enabling
  per-update republication) and passes on the fixed build; it is part of
  `mise run test`.
- V8 — OTLP projection evidence that `wake_trigger` is exported as a string
  attribute.
- V9 — Install, use, downgrade to 0.0.92, and upgrade again with workspace
  state intact.

The Program Design must expose proof seams for refresh counting per switch on
the mounted composition, for tracked-read bounding in the batch, for
content-only classification in the materializer, and for idempotent selection
in the deciders. No required proof modality is waived.
