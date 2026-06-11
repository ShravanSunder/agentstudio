# Pane Shell Decomposition: PaneTabViewController Extraction + Coordinator Domain Logic

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

The coordination-plane audit found the event/command boundaries themselves are
healthy (commands never route through fact buses, stores are mutated only via
their own methods, TopologyEffectHandler ordering is respected, AppEventBus
carries only notifications). The drift is **responsibility accumulation**:

1. **`PaneTabViewController` is 3,245 lines** — the largest file in the repo,
   3.6× the repo's own "refactoring prompt" threshold (900 lines). It owns at
   least four separable domains: tab-bar UI coordination (drag/drop/rename/
   reorder), workspace focus ownership (a genuine state machine: trigger →
   context → executor → owner application), pane view lifecycle/restoration,
   and arrangement-bar/drawer presentation. Every change to any of these
   domains churns one file, and the focus state machine is untestable in
   isolation.
2. **Domain decisions live in `PaneCoordinator+ActionExecution` (1,000
   lines).** Example: `openTerminal(for:in:)` decides *whether to reuse an
   existing tab* by scanning tab layout — a domain policy, not sequencing.
   CLAUDE.md's own test: "if a coordinator method has an `if` that decides
   what to do with domain data, that logic belongs in a store."

## Current Evidence

- `wc -l Sources/AgentStudio/App/Panes/PaneTabViewController.swift` → 3245.
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift:661-675` — focus
  trigger handling delegates through `makePaneFocusContext` /
  `makePaneFocusExecutor` / `applyWorkspaceFocusOwner`, all hosted in the same
  type alongside tab drag/drop and popover presentation (responsibility
  inventory in the audit found ~13 distinct jobs).
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift:25-43`
  — `openTerminal` contains the find-existing-tab-or-create policy inline
  (`store.tabLayoutAtom.tabs.first(where:)` + `setActiveTab` + early return).
- CLAUDE.md "Coordinator Sequences, Doesn't Own" and "Files over 600 lines are
  a smell; over 900 is a refactoring prompt."

## Non-Goals

- No behavior changes. This is structure-only: same commands, same shortcuts,
  same focus semantics, same rendering.
- No changes to the command planes, event buses, or atom boundaries.
- Not a full decomposition to <900 lines in one pass — this plan extracts the
  two highest-leverage domains (focus, tab bar) and the one coordinator
  policy; further extraction is follow-up.

## Scope

Write surfaces:
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` — shrink by
  delegation.
- `Sources/AgentStudio/App/Panes/` — new `WorkspaceFocusController.swift`
  (focus state machine host) and `TabBarInteractionController.swift` (tab bar
  drag/drop/rename/reorder + popovers), named per repo conventions.
- `Sources/AgentStudio/Core/Actions/WorkspaceCommandResolver.swift` (or a new
  small resolver) — home for the tab-reuse decision.
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
  — call the extracted policy.
- Tests for the extracted focus controller and the tab-reuse policy.

Read-only context:
- `docs/architecture/appkit_swiftui_architecture.md` and
  `docs/architecture/commands_and_shortcuts.md` — controller ownership rules
  (pane/drawer/focus commands route through `PaneTabViewController`; the
  extraction must preserve that routing surface).
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtom.swift`
  — the state the focus machine writes.

## Task Sequence

1. **Characterize before moving.** Write tests against the *current* focus
   behavior at the `PaneTabViewController` seam (trigger → resulting
   `WorkspaceFocusOwnerAtom` state) for the main transitions: pane click,
   drawer focus, tab switch refocus, empty-drawer focus. These tests must pass
   before and after extraction.
2. **Extract `WorkspaceFocusController`.** Move focus trigger handling,
   context building, executor creation, refocus scheduling, and scope
   normalization into a `@MainActor` type owned by `PaneTabViewController`.
   The view controller keeps thin forwarding methods (the command-routing
   surface contract from `commands_and_shortcuts.md` is unchanged).
3. **Extract `TabBarInteractionController`.** Move tab drag/drop, rename
   popover, and reorder handling. Keep `CustomTabBar` delegate conformance on
   the new type; the view controller wires it.
4. **Extract the tab-reuse policy.** Add a pure function (e.g.
   `WorkspaceCommandResolver.existingTabForWorktree(_:in:)`) returning the
   reuse decision from a snapshot; `openTerminal` becomes
   resolve-then-sequence. Unit-test the policy directly.
5. **Re-measure.** `PaneTabViewController` should land well under 2,000 lines
   with extraction targets each under ~500. Update the CLAUDE.md component
   table and `appkit_swiftui_architecture.md` in the same changeset (repo rule
   for boundary changes).

## Proof Gates

- Red/green: characterization tests from task 1 pass unchanged after tasks
  2-4; new policy unit tests.
- Focused validation: `mise run test -- --filter "Focus"`,
  `mise run test -- --filter "PaneTab"`, plus full
  `mise run test` and `mise run lint` (zero errors).
- Manual: Peekaboo pass over focus flows — click panes/drawers/tabs, keyboard
  shortcuts for pane navigation, drawer expansion focus, tab rename popover —
  against the debug build (PID targeting).
- Line-count gate: `wc -l` on the three files; no file over 900 among the new
  extractions.

## Stop Conditions

- Stop if extraction forces changes to command routing visible in
  `commands_and_shortcuts.md` contracts (e.g. a `LocalActionSpec` or resolver
  signature change) — that is a boundary change requiring discussion first.
- Stop if characterization tests reveal existing focus behavior that is
  ambiguous or buggy — report the behavior before locking it in as a test.
- Atom/store boundary changes are explicitly out — if the extraction seems to
  need one, stop and ask (CLAUDE.md rule).

## Risks

- Focus is the most regression-prone domain in the app (see memory of prior
  drawer/focus work): mitigated by characterization-first sequencing and the
  Peekaboo manual gate.
- Hidden coupling via private helpers shared across the extracted domains —
  surface them as explicit injected dependencies rather than re-merging.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-pane-shell-decomposition.md
Start by validating the plan against current git state before editing files.
Execute strictly in order (characterize → extract → extract → policy →
re-measure). Do not parallelize tasks 2 and 3 — both edit
PaneTabViewController. Parent owns integration and final proof
(mise run test, mise run lint, Peekaboo focus pass).
```
