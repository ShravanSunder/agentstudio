# Pane And Tab Switching Without MainActor Stalls — Requirements

Date: 2026-09-04

Requirements identity: `REQ-2026-09-04-PANE-SWITCH-MAINACTOR-RESIDUALS`

## Why this change exists

Production Agent Studio 0.0.92 paused for two to seven seconds, with the macOS
busy cursor, on every pane switch, tab switch, drawer toggle, and terminal text
selection. Telemetry from the installed process showed tab-bar terminal work
waiting up to eleven seconds for MainActor while holding it for under one
millisecond, minute-for-minute correlated with bursts of 10,000 to 30,000
Repo Explorer command-presentation refreshes per minute.

Hot patch #323 (merged 2026-09-04 as `e99ffc015`) removed the multiplier: one
leaked one-shot Observation tracking per sidebar viewport publication, each
re-arming itself forever, so a single arrangement write fanned out into
hundreds of no-op refreshes. That patch is the floor this change builds on.

Residual behavior remains after the patch. A switch still performs one expensive
Repo Explorer refresh per tracked atom write, filesystem-driven writes are far
more frequent since #321, a drawer tap re-selects an already active pane, every
content-only sidebar update forces table layout twice and restores the scroll
anchor, and nothing in the test suite fails when a switch costs more work than
it should. The product owner's directive is a fully fleshed-out fix with tests
that would have caught this, and verification in a debug app and in production
telemetry.

## Authority and applicability

The product owner authorized this work in the 2026-09-04 production-stall
session: "that's PR 1 and PR 2 would be a more comprehensive correct fix",
"switching panes, switching tabs, all that stuff needs to be fixed", "make sure
pane switching is tested in the right test lane in CI so we don't have this
issue in the future", "confirm the OTEL signatures for this pause", "without
causing any data corruption", and "no performance or stability issues with the
system and you can verify it". Each authorized row below records that meaning.
Rows marked `evidence-derived` name a concrete residual the owner's blanket
directive covers; the observable outcome is owner-authorized, the mechanism is
evidence, not authority.

Governing evidence (observational, not authority for desired behavior):

- Debug artifact with samples and telemetry:
  `agent-studio.fix-sidebar-mainactor-stall/tmp/debug-workflows/2026-09-04-agent-studio-fix-sidebar-mainactor-stall-command-presentation-storm/debug-investigation.md`.
- Live burst sample of the production process during a storm
  (`/tmp/agentstudio-storm-loop-4.sample.txt`): 80 % of main-thread samples inside
  the batch refresh reached through its Observation wake; 320 samples inside
  `AtomFamilySlot.acceptValue` notifying leaked trackings on one write.
- VictoriaLogs stable series 2026-09-04: 0.0.91 refreshes per switch grew 1.8 →
  125 within five minutes of launch; 0.0.92 storm minutes carried 2–7 s waits;
  0.0.92 emitted ~18× the filesystem stage outcomes and ~2× the coordinator
  writes per minute of 0.0.91.
- Three fresh-context research receipts (2026-09-04): #321 does not touch the
  focus, gesture, atom, or batch paths; the content-click decider is guarded for
  an already active pane while the drawer decider is not; equal-value atom
  writes are already suppressed by `AtomFamily` and the `@Observable` macro.
- Current source at `main` `e99ffc015` establishes the behavior described below.

## Consumers and authorized needs

### U1 — Switching stays responsive in a real workspace

- Affected class: an end user switching panes, tabs, drawers, and arrangements
  in a workspace with many repositories, worktrees, and terminals.
- Authority state: authorized by the product owner on 2026-09-04.
- Priority: required, assigned by the product owner.
- Need: a switch completes without a perceptible pause; no sidebar, focus, or
  arrangement work attributable to the switch may hold or queue MainActor for
  longer than a frame-scale budget.
- Why it matters: the pause hits every interaction the user performs hundreds
  of times a day.

### U2 — Responsiveness does not degrade with session age

- Affected class: an end user who keeps the app running for hours or days.
- Authority state: authorized by the product owner on 2026-09-04.
- Priority: required, assigned by the product owner.
- Need: the cost of a switch after many hours and thousands of sidebar
  updates is the same as after launch.
- Why it matters: the 0.0.92 stall was invisible in a fresh process and
  catastrophic after seventeen hours; a fix that only resets on restart is not
  a fix.

### U3 — Background facts do not tax the foreground

- Affected class: an end user whose repositories produce frequent Git and
  filesystem facts (builds, agents, watchers).
- Authority state: authorized by the product owner on 2026-09-04
  (`evidence-derived` mechanism: filesystem-driven tracked-atom writes rose ~18×
  in #321 and each wakes the sidebar command batch).
- Priority: required, assigned by the product owner.
- Need: repository and filesystem fact updates that change nothing the sidebar
  presents do not produce sidebar recomputation on MainActor.
- Why it matters: reliable filesystem delivery is correct behavior; paying a
  sidebar refresh for each delivery is not.

### U4 — Repeating a selection is free

- Affected class: an end user clicking or tapping a pane or drawer pane that is
  already active.
- Authority state: authorized by the product owner on 2026-09-04
  (`evidence-derived` mechanism: the drawer focus decider re-selects on every
  tap; the content-click decider already keeps).
- Priority: required, assigned by the product owner.
- Need: selecting what is already selected changes no workspace state and
  triggers no downstream work.
- Why it matters: repeated taps and text selection are the most common
  gestures in a terminal pane.

### U5 — Sidebar content updates cost only what changed

- Affected class: an end user whose sidebar rows update while they work.
- Authority state: authorized by the product owner on 2026-09-04
  (`evidence-derived` mechanism: content-only table applies force layout twice
  and restore the scroll anchor since #320; 800 of 4,731 main-thread samples in
  the 12:21 production sample).
- Priority: required, assigned by the product owner.
- Need: a sidebar update that changes row content but no row height or
  membership must not move the scroll position, relayout the whole table, or
  rebind rows that did not change.
- Why it matters: those updates arrive continuously and each one currently
  costs tens to hundreds of milliseconds on MainActor.

### U6 — The suite fails when a switch gets expensive

- Affected class: maintainers and reviewers merging changes; the product owner
  as release gate.
- Authority state: authorized by the product owner on 2026-09-04 ("we can't let
  something like this pass CI again").
- Priority: required, assigned by the product owner.
- Need: an automated lane in the pull-request gate that mounts the real sidebar
  composition, performs pane and tab switches, and fails when refreshes or table
  applies per switch exceed a stated bound.
- Why it matters: every correctness test passed while production stalled; only
  a cost-bounded test on the real composition catches a hop-shape regression.

### U7 — The fix is verifiable outside the suite

- Affected class: the product owner and operators reading telemetry.
- Authority state: authorized by the product owner on 2026-09-04 ("confirm the
  OTEL signatures", "you can verify it").
- Priority: required, assigned by the product owner.
- Need: a debug-app run of a scripted switch workload and the production
  telemetry of the released build show bounded refreshes per switch, no storm
  minutes, and MainActor waits within budget, with the wake trigger of each
  refresh visible.
- Why it matters: "feels fine" was wrong once today; the proof must be
  marker-scoped and comparable across versions.

### U8 — No data-corruption surface

- Affected class: every user with persisted workspaces.
- Authority state: authorized by the product owner on 2026-09-04.
- Priority: required, assigned by the product owner.
- Need: the change touches no persisted schema, identity, residency, IPC, or
  command contract, and rollback is code-only.
- Why it matters: a responsiveness fix must not put workspace state at risk.

## Current problem and protected constraints

- P1 — Leaked Observation trackings multiplied every tracked write into
  hundreds of refreshes (fixed in #323; must remain fixed).
- P2 — `PaneDrawerFocusDecider` re-selects an already active drawer pane on
  every tap; the content-click path keeps.
- P3 — Content-only sidebar table applies update the table frame, force layout
  twice, rebind every represented cell, and restore the scroll anchor even when
  no row height or membership changed.
- P4 — The sidebar presentation coordinator republishes the current visible
  snapshot on every SwiftUI update, arming one tracking per republish before
  #323 and still performing redundant downstream work after it.
- P5 — Filesystem and Git fact writes that change nothing presented still wake
  the sidebar command batch, whose refresh recomposes arrangement and pane
  location state on MainActor at about one millisecond each; #321 raised that
  write rate ~18×.
- P6 — No test bounds the work a switch performs on the mounted sidebar
  composition, and the parked probe that mounts it never engaged the batch.
- P7 — Protected: pane focus decision model, Repo Explorer projection and
  materialization architecture, atom public contracts, persistence, IPC,
  commands, and the separate geometry-driven terminal hydration design.

## Terms at the product boundary

- **Switch:** a user action that changes the active tab, active pane, drawer
  expansion or drawer pane, or arrangement.
- **Switch budget:** the MainActor time attributable to sidebar, focus, and
  arrangement work for one switch, measured as queue wait plus held time at the
  existing tab-bar and interaction instruments.
- **Refresh:** one execution of the Repo Explorer command-presentation batch
  refresh, recorded as one `performance.repo_explorer.command_presentation`
  record with its `wake_trigger`.
- **Content-only update:** a Repo Explorer table update whose row membership,
  order, and row heights are unchanged.
- **Storm minute:** a minute with more than 1,000 refreshes.

## Desired outcomes

- O1 — Every switch completes within the switch budget in a real-size
  workspace, in a debug run and in production telemetry.
- O2 — Refreshes per switch stay bounded and constant across process age.
- O3 — Filesystem and Git facts that change nothing presented produce no
  refresh.
- O4 — Selecting an already active pane or drawer pane produces no workspace
  write and no refresh.
- O5 — Content-only sidebar updates preserve the scroll position and rebind
  only changed rows, with no forced whole-table layout.
- O6 — The pull-request gate contains a lane that fails on refresh or apply
  counts per switch above the stated bound.
- O7 — Production telemetry for the released build shows zero storm minutes
  under normal use and reports the wake trigger of every refresh.
- O8 — No persisted state, schema, or identity changes; rollback is code-only.

## User journey and pain relationship

```text
U1/U2/U3/U4/U5

launch, work for hours, many repos and terminals
  -> press ⌘L / click a pane / open a drawer
       desired: the target appears within a frame, no cursor change
       current pain (0.0.92): 2–7 s pause with busy cursor; worse each hour
  -> tap the pane that is already focused, or drag to select text
       desired: nothing changes, nothing recomputes
       current pain: drawer taps rewrite selection; each write wakes the sidebar
  -> a build writes files; git facts arrive for visible repos
       desired: sidebar rows that changed update; the rest is untouched
       current pain: every fact wakes a refresh; content updates relayout the
       table and move the scroll anchor
```

## Boundary and non-goals

Permitted change surface: `Features/RepoExplorer`, `App/Windows` (command
batch, sidebar host, presentation coordinator), `App/Panes` and
`Core/PaneFocus` (deciders and executor), and `Tests`.

It does not authorize:

- a new atom, store, event type, coordinator, queue, or persisted state;
- changes to Git or filesystem cadence, admission, or scope;
- changes to persistence, schema, pane or session identity, IPC, or commands;
- changes to the pane focus decision model beyond idempotent selection;
- changes to the geometry-driven terminal hydration design (separate track);
- removing the #323 tracking-generation guard or the `wake_trigger` attribute.

Acceptable complexity: bounded corrections inside existing owners, each with a
red-first test. A new state owner or signaling path reopens this boundary.

## Acceptable evidence

The owner accepts: red-then-green automated tests per residual; a cost-bounded
automated lane on the mounted sidebar composition in the pull-request gate; a
marker-scoped debug-app run of a scripted switch workload with the shared
collector; and production telemetry of the released build compared with
0.0.91 and 0.0.92. Feel, screenshots, and unit tests alone are not sufficient
for the responsiveness outcomes.

## Open questions

No product decision remains open. Program Design decides how the batch bounds
its tracked reads, how the materializer classifies content-only updates, how
the coordinator avoids redundant republication, and how the CI lane mounts the
composition so the batch engages.
