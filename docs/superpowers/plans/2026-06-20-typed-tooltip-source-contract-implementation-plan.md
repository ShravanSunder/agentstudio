# Typed Tooltip Source Contract Implementation Plan

Date: 2026-06-20
Goal id: `2026-06-20-typed-tooltip-source-contract`
Status: reviewed implementation plan, ready for implementation execution
Branch: `control-tooltip-source-contract`
Base: `origin/main` / `HEAD` at `39584b318a14d3f22bcf0fa2381899b21734fcad`

## Goal

Implement the typed tooltip source contract so dense AgentStudio controls stop
hand-writing parallel tooltip strings and instead render from typed command,
local-action, or feature-local shortcut descriptors.

The implementation must preserve the ownership DAG:

```text
AppCommandSpec
    -> CommandDisplayDescriptor
    -> ControlTooltipSource
    -> ControlTooltipRenderValue

AppCommandSpec
    -> AppCommandIPCExposure
    -> IPCCommandListEntry
```

This is projection, not inheritance. `AppCommand`, `AppCommandSpec`, command
routing, and IPC execution authority stay app-owned. `IPCCommandListEntry`
remains a public DTO projection and does not become a UI tooltip base class.
`SharedComponents` render resolved values only and do not consume command specs,
action specs, tooltip sources, or IPC DTOs.

The implementation also adds repo-local SwiftPM/SwiftSyntax architecture-lint
coverage so the source contract is enforced in `Tools/AgentStudioArchitectureLint`
and included in `mise run lint`.

## Non-Goals

- Do not move `AppCommand`, `AppCommandSpec`, routing, shortcut dispatch, or IPC
  privilege semantics into `Infrastructure`, `SharedComponents`, or public IPC
  contracts.
- Do not add `ControlTooltip` as a payload type. The render value is
  `ControlTooltipRenderValue`.
- Do not add `accessibilityText` to the compact tooltip value. Accessibility
  labels and descriptions remain separate UI contracts.
- Do not make `CommandDisplayProvenance` a runtime authority field for
  execution, routing, auth, IPC, or analytics.
- Do not redesign `HoverTooltip`, the command bar, IPC transport, or app command
  execution beyond the projections required by this spec.
- Do not add shell, Bazel, Java, or external custom-SwiftLint architecture lint.
- Do not merge the PR without explicit user authorization.

## Source Coverage

Read end to end before this plan:

- `docs/superpowers/specs/2026-06-19-typed-tooltip-source-contract.md`: 521
  lines, read in chunks 1-140, 141-300, and 301-521.
- `tmp/spec-workflows/2026-06-19-agent-studio-control-tooltip-source-contract-typed-tooltip-source-contract/spec-handoff.md`:
  current handoff packet read after spec rewrite.
- `tmp/spec-workflows/2026-06-19-agent-studio-control-tooltip-source-contract-typed-tooltip-source-contract/copy-paste-prompt.md`:
  current next-agent prompt read after spec rewrite.
- `tmp/spec-workflows/2026-06-19-agent-studio-control-tooltip-source-contract-typed-tooltip-source-contract/claude-review-prompt.md`:
  current external-review prompt read after spec rewrite.
- `tmp/workflow-state/2026-06-20-typed-tooltip-source-contract/details.md`: 204
  lines read.
- `docs/architecture/commands_and_shortcuts.md`
- `docs/guides/style_guide.md`
- `docs/architecture/README.md`
- `docs/architecture/architecture_lint_inventory.md`
- `docs/architecture/directory_structure.md`
- `docs/architecture/agentstudio_ipc_architecture.md`

Live repo evidence checked while drafting:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- `Sources/AgentStudio/Core/Views/HoverTooltip.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- `Sources/AgentStudio/SharedComponents/SidebarSearchField.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
- `Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift`
- `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift`
- `Tests/AgentStudioTests/App/AppCommandSpecContractTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceCommandTests.swift`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Core/ArchitectureRule.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleInventoryTests.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleParityTests.swift`

## Current Model

The current code already has a useful but string-shaped presentation layer:

1. `AppCommandSpec` owns command label, help text, shortcut, icon, visibility,
   and IPC exposure.
2. `UIActionPresentation.swift` adds `controlToolTip` helpers directly on
   `AppCommandSpec` and `ActionSpec`, returning `String`.
3. Dense surfaces such as `DrawerIconBar`, `InboxSidebarComponents`, and
   `MainWindowController` consume those strings directly or mix them with
   local string helpers.
4. `HoverTooltip` and `.help(...)` accept strings, so the final rendering layer
   is string-oriented.
5. `AgentStudioIPCCommandAdapter` projects app command specs into
   `IPCCommandListEntry`; this is already the right IPC direction and should
   stay separate from tooltip render value projection.
6. The architecture-lint package already has a central `ArchitectureRule`
   protocol, `ArchitectureRuleRegistry.rules`, `RuleInventoryTests`, and
   `RuleParityTests`. New enforcement should live there.

The spec changes the middle of that model: helpers should produce typed
descriptors and render values before a view or AppKit adapter finally asks for a
string. That gives tests and lint a stable contract to inspect, and it stops
`SharedComponents` from depending on command/app concepts.

## Requirements / Proof Matrix

| Requirement or claim | Owning task | Proof owner | Proof gate | Proof layer | Stale-proof guard | Red/green required |
|---|---|---|---|---|---|---|
| Projection model is implemented as `AppCommandSpec -> CommandDisplayDescriptor -> ControlTooltipSource -> ControlTooltipRenderValue`. | T1, T2, T3 | implementation executor + parent | `UIActionPresentationTests`, `ControlTooltipResolverTests`, `CommandSpecContractTests` | Unit | Run after replacing direct string helper call sites; tests must assert intermediate typed objects, not only final strings. | Yes |
| `Infrastructure` owns only dumb render vocabulary such as `ControlTooltipRenderValue` and shortcut-display formatting. | T1, T7 | implementation executor + reviewer | architecture lint plus source review | Static/review | Run after all new files/imports land. | Yes |
| `Core/Actions` owns app-free descriptor/resolver logic only. It does not reference App, IPC, or command routing authority, even through same-target symbols. | T2, T7 | implementation executor | architecture lint and focused resolver tests | Unit/static | Bad fixture must fail if Core tooltip files reference `AppCommand`, `AppCommandSpec`, `AppCommandIPCExposure`, or IPC DTO symbols without relying on imports. | Yes |
| `App/Commands` owns `AppCommandSpec` projection helpers, including command display provenance and IPC exposure projection. | T3, T6 | implementation executor | app command contract tests and IPC adapter tests | Unit/integration | Tests compare projections against current `AppCommand` catalog. | Yes |
| `SharedComponents` accepts resolved `ControlTooltipRenderValue`, bindings, and closures only. It does not accept arbitrary tooltip `String`s, specs, tooltip sources, display descriptors, or IPC DTOs. Final strings are allowed only inside approved adapter implementations. | T4, T7 | implementation executor | architecture lint fixtures and source scan | Static | Bad fixture under `SharedComponents` must fail; Good fixture covers `SidebarSearchField`-style non-dense raw help that is explicitly outside v1. | Yes |
| Dense SwiftUI/AppKit controls do not hand-write parallel tooltip strings when a command/local-action/feature descriptor exists. | T4, T7 | implementation executor | `agentstudio_toolbar_tooltip_source` fixtures, presentation tests | Unit/static | Include Good/Bad fixtures for raw `.help(...)`, raw local/helper string variables, raw `button.toolTip`/`item.toolTip`, and valid typed adapters. | Yes |
| Feature-local shortcuts keep route and display synchronized without being forced into global `AppShortcut`. | T5 | implementation executor | inbox/drawer shortcut descriptor tests | Unit | Test the shared route/display source, not only the rendered text. | Yes |
| Compact tooltip render value does not replace accessibility labels/descriptions. | T4, T7 | implementation executor + reviewer | source review, lint fixture or focused UI tests where practical | Static/review | Bad fixture must catch passing tooltip render value as accessibility text if feasible. | Yes, where lintable |
| IPC command discovery remains projection from `AppCommandSpec.ipcExposure` to `IPCCommandListEntry`; tooltip types do not enter public IPC DTOs. | T6 | implementation executor | `AgentStudioIPCCommandAdapterTests`, `AgentStudioAppIPCServiceCommandTests`, `IPCContractsTests` | Unit/integration | Assert no `ControlTooltip`/`ControlTooltipRenderValue` symbol appears under `Sources/AgentStudioProgrammaticControl`. | Yes |
| Durable docs describe the implemented typed tooltip contract and active lint rule. | T8 | implementation executor + parent | source diff review and `mise run lint` | Docs/static | Docs must be checked after implementation, not only before. | No |
| Runtime app proof covers native tooltip surfaces, Victoria debug launch, and live IPC command behavior on the current worktree. | T9 | parent verifier | observability debug verifier plus live IPC smoke/focused IPC tests | Smoke/e2e-ish | Use fresh marker-scoped verifier output, not stale logs; live IPC smoke must call the current debug app socket. | No code red/green; current-run proof required |
| PR readiness is proven but not merged. | T10 | parent verifier | implementation review, PR checks, review-thread state, mergeability state | PR gate | Fetch fresh PR/check/thread state during wrap-up. | No |

## Task Sequence

### Task 0: Reconfirm Baseline And Plan Review Gate

1. Re-run `git status --short --branch`.
2. Confirm `HEAD` is still current with `origin/main`. If it drifted, fetch and
   reassess before implementation.
3. Run `shravan-dev-workflow:plan-review-swarm` on this plan before product
   source edits.
4. If review finds a boundary issue, update the plan/spec first instead of
   coding through it.

Likely write surfaces:

- This plan only, until plan review is accepted.

### Task 1: Add Render Vocabulary In Infrastructure

1. Add `ControlTooltipRenderValue` and `ShortcutDisplayText` under
   `Sources/AgentStudio/Infrastructure/` or an existing infrastructure subfolder
   that matches small presentation value types.
2. Keep the render value intentionally small:
   - `text: String`
   - `shortcutDisplayText: ShortcutDisplayText?`
3. Add a final string rendering helper for `.help(...)`, `NSButton.toolTip`, and
   `HoverTooltipBubble` consumers if the plain `text` property is not enough for
   existing call sites.
4. Keep both types `Sendable`, `Equatable`, and UI-framework-free.
5. Keep accessibility out of these types. Accessibility labels and descriptions
   remain owned by semantic UI call sites.
6. Project `ShortcutTrigger` and `KeyBinding` into `ShortcutDisplayText` at the
   app or feature boundary in this slice. Do not move richer key-binding
   semantics into Infrastructure unless implementation proves shared render
   code must compute shortcut glyphs rather than merely render them.

Likely write surfaces:

- `Sources/AgentStudio/Infrastructure/ControlTooltipRenderValue.swift`
- `Sources/AgentStudio/Infrastructure/ShortcutDisplayText.swift` if the
  implementation keeps shortcut display separate instead of colocating it with
  `ControlTooltipRenderValue`
- `Tests/AgentStudioTests/Infrastructure/ControlTooltipRenderValueTests.swift`

### Task 2: Add App-Free Tooltip Source And Resolver In Core/Actions

1. Add app-free semantic display types under `Core/Actions`:
   - `CommandDisplayDescriptor`
   - `CommandDisplayProvenance`
   - `ControlTooltipSource`
   - `TooltipCopyStyle`
   - `DynamicTooltipReason`
   - `ControlTooltipResolver`
2. These types can accept already-resolved labels, help text,
   shortcut-display values, and local provenance, but not `AppCommand`,
   `AppCommandSpec`, `AppCommandIPCExposure`, IPC DTOs, or command execution
   closures.
3. Add a resolver that maps `ControlTooltipSource` to
   `ControlTooltipRenderValue`.
4. Refactor the current string-shaped `ActionSpec.controlToolTip(...)` path to
   use the resolver internally and expose a typed render-value sibling while
   preserving ergonomic string adapters for SwiftUI/AppKit call sites.
5. Do not leave app-command projection helpers in `Core/Actions`. The current
   `AppCommandSpec` extension in `UIActionPresentation.swift` is a coupling
   pressure point; move the command-specific typed projection and compatibility
   `controlToolTip` adapter into `App/Commands` during T3.
6. Keep `LocalActionSpec` in `Core/Actions` only for UI-only action presentation;
   do not turn it into an execution/catalog authority.

Likely write surfaces:

- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- `Sources/AgentStudio/Core/Actions/ControlTooltipSource.swift`
- optional `Sources/AgentStudio/Core/Actions/CommandDisplayDescriptor.swift` if
  descriptor/provenance types are split out for readability
- `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift`
- `Tests/AgentStudioTests/Core/Actions/ControlTooltipResolverTests.swift`

### Task 3: Add App Command Display Projection In App/Commands

1. Add `AppCommandSpec` projection helpers that produce the Core-owned
   `CommandDisplayDescriptor` and then `ControlTooltipSource`.
2. Keep `CommandDisplayProvenance` diagnostic/test/lint-only. It must not be
   consulted by routing, execution, authorization, IPC privilege, or analytics.
3. Preserve the existing `controlToolTip` ergonomic API as a render adapter if
   needed, but move the app-command variant into `App/Commands` and make it
   derive from the typed source contract.
4. Update app-command tests so shortcuts, overrides, and hidden command
   visibility still behave as before.
5. Add direct typed-object assertions proving
   `AppCommandSpec -> CommandDisplayDescriptor -> ControlTooltipSource ->
   ControlTooltipRenderValue`; final string parity alone is not enough.

Likely write surfaces:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- optional `Sources/AgentStudio/App/Commands/AppCommand+DisplayDescriptor.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift` only if stored
  metadata needs small call-site updates
- `Tests/AgentStudioTests/App/AppCommandTests.swift`
- `Tests/AgentStudioTests/App/AppCommandSpecContractTests.swift`
- `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift`

### Task 4: Add SwiftUI/AppKit Render Adapters And Migrate Non-Inbox Dense Controls

1. Add tiny adapters that accept `ControlTooltipSource` in product/app-owned
   paths or `ControlTooltipRenderValue` at shared/render boundaries:
   - SwiftUI `View.controlHelp(...)`
   - AppKit `NSButton.applyControlTooltip(...)`
   - AppKit `NSToolbarItem.applyControlTooltip(...)`
   - custom hover tooltip values for `FloatingHoverTooltipPresenter`
2. Keep adapters in a layer that does not force `SharedComponents` to import
   App, Core command specs, or IPC DTOs.
3. Change `FloatingHoverTooltipPresenter` so product call sites no longer pass
   `(Target) -> String?`. Its shared/render-boundary API should accept
   `(Target) -> ControlTooltipRenderValue?`, with product call sites resolving
   from `ControlTooltipSource` before rendering.
4. Migrated call sites must use `controlHelp(...)`, `applyControlTooltip(...)`,
   or typed hover adapters. They must not keep direct `.help(...)` or
   `toolTip = ...` assignments in the migrated seams.
5. Migrate these non-inbox v1 dense surfaces:
   - `DrawerIconBar`
   - `MainWindowController` titlebar/sidebar toolbar helpers
6. Defer `ManagementLayerToolbarButton.swift`, `CustomTabBar.swift`, and
   `PaneLeafContainer.swift` unless a compile-safe cutover proves one of them
   must move in this slice. If that happens, add the exact surface and a focused
   proof gate to this plan before editing it.
7. Preserve separate `accessibilityLabel`, `accessibilityIdentifier`, and
   descriptions.
8. Keep `HoverTooltip` as rendering infrastructure; do not redesign placement or
   animation unless a typed value reveals a direct blocker.

Likely write surfaces:

- `Sources/AgentStudio/Core/Views/HoverTooltip.swift` only if it needs a
  render-value convenience API or signature cutover
- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- `Tests/AgentStudioTests/Core/Views/Drawer/DrawerIconBarInboxSlotTests.swift`
- `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`
- `Tests/AgentStudioTests/App/WelcomeLauncherArchitectureTests.swift`

### Task 5: Unify Feature-Local Shortcut Display Sources And Migrate Inbox Surfaces

1. Identify feature-local shortcut routers that show shortcut text in tooltips
   without using global `AppShortcut`.
2. Keep route and display synchronized by adding small feature-local descriptor
   values beside the router, not by moving those shortcuts into global command
   specs.
3. Start with current inbox shortcut hints because `InboxSidebarComponents`
   already renders local keyboard hints.
4. Add a red/green test proving the same inbox descriptor drives both router
   behavior and tooltip source before migrating inbox tooltips.
5. Migrate the inbox v1 surfaces only after the descriptor test exists:
   - `InboxSidebarComponents`
   - icon-only controls in `PaneInboxNotificationPopover`
6. Add focused tests that prove the shortcut descriptor used by the route is the
   same descriptor used by the tooltip source.

Likely write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarKeyboard.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxSidebarToolbarPresentationTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

### Task 6: Preserve IPC Projection Boundaries

1. Keep `AgentStudioIPCCommandAdapter` projecting from app command specs through
   `AppCommandIPCExposure` into `IPCCommandListEntry`.
2. Add/update tests proving:
   - `command.list` metadata still matches the app command catalog
   - `IPCCommandListEntry` encoded keys stay limited to the current public
     schema unless a separate IPC contract change is explicitly planned
   - `command.list` rows use `definition.label` as `title`, not compact tooltip
     text or help text
   - `command.execute` remains fail-closed for commands without headless
     execution exposure
   - `ui.commandBar.open` continues to use presentation semantics without
     acquiring tooltip execution authority
3. Add a source assertion that `Sources/AgentStudioProgrammaticControl` does not
   contain `ControlTooltipSource`, `ControlTooltipRenderValue`, or
   `CommandDisplayDescriptor`.
4. Do not add public DTO fields such as `tooltip`, `helpText`, compact copy, or
   provenance to `IPCCommandListEntry` as part of this work.

Likely write surfaces:

- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
- `Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift` only if
  existing projection fields need clarification; avoid new tooltip fields
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceCommandTests.swift`
- `Tests/AgentStudioProgrammaticControlTests/IPCContractsTests.swift`

### Task 7: Add SwiftSyntax Architecture Lint Enforcement

1. Add `TooltipSourceRule` under
   `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/`.
2. Register it in
   `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Core/ArchitectureRule.swift`.
3. Add the expected rule to
   `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleInventoryTests.swift`
   with id `agentstudio_toolbar_tooltip_source`.
4. Add Good/Bad fixtures through the existing `RuleParityTests` fixture pattern.
5. Scope v1 to the migrated dense surfaces and exact syntax shapes, not a broad
   semantic guess about whether a typed source exists:
   - migrated paths: `Core/Views/Drawer/DrawerIconBar.swift`,
     `Features/InboxNotification/Views/InboxSidebarComponents.swift`,
     icon-only migrated controls in
     `Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`, and
     `App/Windows/MainWindowController.swift`
   - denied SwiftUI chains: dense/icon-only `Button` or `Menu` chains that use
     `.hoverTooltipAnchor(...)`, `.buttonStyle(.plain)`,
     `.buttonStyle(.borderless)`, or `.menuStyle(.borderlessButton)` and then
     call raw `.help(...)`
   - denied raw help argument shapes: string literals, local string variables,
     helper calls returning `String`, and `renderValue.text` outside approved
     adapter implementations
   - denied AppKit shapes: `button.toolTip = ...` and `item.toolTip = ...`
     outside approved `applyControlTooltip(...)` adapters, including local
     variables and helper-returned strings
   - denied same-target references: Core tooltip files may not reference
     `AppCommand`, `AppCommandSpec`, `AppCommandIPCExposure`, IPC DTOs, or
     app-owned helper namespaces, even when no import statement exists
   - denied `SharedComponents` signatures/imports: `SharedComponents` may not
     import or accept `ControlTooltipSource`, `CommandDisplayDescriptor`,
     `AppCommandSpec`, arbitrary tooltip `String`s for dense action controls, or
     `IPCCommandListEntry`
   - Good: App/Commands projection helper produces a typed source.
   - Good: SharedComponents consumes `ControlTooltipRenderValue`.
   - Good: a `SidebarSearchField`-style `SharedComponents` clear button with
     raw `clearHelp` remains allowed because it is outside the v1 dense action
     control contract.
   - Good: public IPC DTOs remain tooltip-free.
6. Add dedicated rule-specific tests that lint one fixture per banned/allowed
   shape and assert rule id plus line/path. Do not rely only on the corpus-wide
   superset test.
7. Update `ArchitectureLintCommandTests` if command-output expectations need the
   new rule id.
8. Reconcile `docs/architecture/architecture_lint_inventory.md` with the final
   implemented rule wording and move the row from planned to active after the
   implementation is in place.

Likely write surfaces:

- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/TooltipSourceRule.swift`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Core/ArchitectureRule.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleInventoryTests.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleParityTests.swift`
- fixture files under `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/Fixtures/`
- `docs/architecture/architecture_lint_inventory.md`

### Task 8: Reconcile Durable Docs

1. Update docs after implementation to describe the actual shipped names,
   adapters, rule scope, and proof commands.
2. Required docs to check:
   - `docs/architecture/commands_and_shortcuts.md`
   - `docs/guides/style_guide.md`
   - `docs/architecture/README.md`
   - `docs/architecture/architecture_lint_inventory.md`
   - `AGENTS.md`
3. Move `agentstudio_toolbar_tooltip_source` from planned to active in the lint
   inventory only after the rule and fixtures exist.
4. Keep the source spec as design history; update it only if implementation
   uncovers a design correction that must be recorded.

### Task 9: Focused Verification, Runtime Proof, And IPC Proof

Run focused gates first, then broad gates:

```bash
swift test --filter UIActionPresentationTests
swift test --filter ControlTooltipResolverTests
swift test --filter CommandSpecContractTests
swift test --filter InboxSidebarToolbarPresentationTests
swift test --filter DrawerIconBarInboxSlotTests
swift test --filter PaneInboxNotificationPopoverTests
swift test --filter MainWindowControllerInboxToolbarButtonTests
swift test --filter WelcomeLauncherArchitectureTests
swift test --filter AgentStudioIPCCommandAdapterTests
swift test --filter AgentStudioAppIPCServiceCommandTests
swift test --filter IPCContractsTests
swift test --package-path Tools/AgentStudioArchitectureLint
mise run lint
```

Then collect current-worktree debug proof:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 \
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 \
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=ipc-terminal-smoke \
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-agentstudio-ipc-phase-a-smoke
```

Update `scripts/verify-agentstudio-ipc-phase-a-smoke.sh` in the implementation
if needed so the live socket proof covers this goal's IPC boundary:

1. `command.list` succeeds against the launched debug app.
2. `command.execute(showCommandBarCommands)` fails with the expected
   `requires presentation` error.
3. `ui.commandBar.open(scope: commands)` succeeds.

For native tooltip confidence after lower gates pass:

1. Launch the debug app through the same observability path.
2. Require LaunchServices-backed GUI proof before Peekaboo/manual hover checks:
   either run `verify-debug-observability` with
   `AGENTSTUDIO_REQUIRE_LAUNCHSERVICES=1`, or check the state file for
   `AGENTSTUDIO_OBSERVABILITY_LAUNCH_METHOD=launchservices`.
3. Use Peekaboo or a manual hover checklist as visual/render evidence only.
4. Verify at least one migrated SwiftUI custom hover surface and one AppKit
   titlebar/toolbar tooltip seam.

If Victoria or LaunchServices is blocked by an unrelated environment issue,
stop and report the blocker with the focused unit/lint status. Do not modify
observability infrastructure unless separately authorized.

### Task 10: Review, PR Readiness, And Handoff

1. Run `shravan-dev-workflow:implementation-review-swarm` on the implementation
   diff after all local proof gates pass or after a scoped blocker is documented.
2. Address valid findings. Explicitly reject invalid findings with evidence.
3. Update durable docs if implementation changed the shape from the plan/spec.
4. Push the branch and create or update a PR.
5. Fetch fresh PR checks, review-thread state, and mergeability.
6. Stop at PR-ready state. Do not merge without explicit authorization.

## Risk Register

Risk: The typed contract becomes a second presentation system beside existing
`controlToolTip` helpers.
Mitigation: Preserve ergonomic string APIs as thin render adapters only, and
test that they derive from typed sources.

Risk: Architecture lint overreaches and flags legitimate literal help text on
non-dense controls.
Mitigation: Scope the first rule to known dense control directories, AppKit
toolbar/titlebar seams, and typed-source import boundaries. Expand only after
review.

Risk: `SharedComponents` becomes too constrained to render reusable tooltip UI.
Mitigation: Allow `ControlTooltipRenderValue` and render-only closures, keep
final strings inside approved adapter implementations, and forbid semantic
command/spec/source DTOs.

Risk: IPC proof drifts into command execution redesign.
Mitigation: Keep the IPC work to projection assertions and focused existing
command-list/execute tests.

Risk: Runtime proof is blocked by unrelated Victoria, LaunchServices, or app
boot issues.
Mitigation: Report scoped unit/lint pass/fail separately, stop before changing
infrastructure, and use the existing debug observability runbook.

## Plan Review Decisions

1. `ControlTooltipRenderValue` stores the resolved tooltip text plus optional
   `ShortcutDisplayText`. It does not grow extra secondary-hint or accessibility
   fields in this slice. The resolver owns the final string assembly so call
   sites do not append shortcut glyphs manually.
2. SwiftUI/AppKit render adapters live in UI layers such as `Core/Views` or
   app-owned AppKit helper paths. `Infrastructure` stays SwiftUI/AppKit-free and
   owns only render vocabulary.
3. `agentstudio_toolbar_tooltip_source` v1 is bounded to dense action controls,
   custom hover-tooltip participants, AppKit titlebar/toolbar seams, and
   SharedComponents import/parameter boundaries. It does not broadly ban every
   `.help("...")` call.

## Phase Footer

phase_result: complete
evidence:
- `docs/superpowers/specs/2026-06-19-typed-tooltip-source-contract.md`
- `tmp/workflow-state/2026-06-20-typed-tooltip-source-contract/details.md`
- `docs/superpowers/plans/2026-06-20-typed-tooltip-source-contract-implementation-plan.md`
recommended_next_workflow: `shravan-dev-workflow:implementation-execute-plan`
recommended_transition_reason: Plan review has been completed separately in `tmp/workflow-state/2026-06-20-typed-tooltip-source-contract/plan-review-report.md`; implementation should now execute the reviewed plan.
