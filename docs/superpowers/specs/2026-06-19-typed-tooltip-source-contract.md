# AgentStudio Typed Tooltip Source Contract

Date: 2026-06-19
Status: design draft
Scope: common tooltip infrastructure, command/local action presentation, shortcut display provenance, and architecture-lint forcing functions.

## Purpose

Recent inbox-toolbar work exposed the same failure mode that already exists in drawer, webview, titlebar, and pane popover controls: a control can look correct while tooltip copy and shortcut hints are hand-written at the call site. The current docs ask developers to use `AppCommandSpec.controlToolTip(...)` or `LocalActionSpec.actionSpec.controlToolTip(...)`, but the code still accepts raw `String` tooltip APIs everywhere.

This design makes tooltip provenance explicit. Dense controls should describe their tooltip source as a typed value, and renderers should apply that value to SwiftUI `.help`, custom hover bubbles, and AppKit `toolTip` without re-authoring text. The goal is not a prettier bubble. The goal is a forcing function: shortcut and action copy should drift only when a typed source drifts, and lint/tests should catch unsupported raw tooltip strings.

## Current-State Evidence

### Command and action presentation

- `AppCommand` is the dispatchable command identity. `AppCommand.definition` returns an `AppCommandSpec`, and `AppCommandDispatcher` registers all `AppCommand.allCases.map(\.definition)`.
- `AppCommandSpec` owns command metadata: command id, optional `AppShortcut`, optional `displayShortcutTrigger`, label, icon, help text, visibility, grouping, and command-bar hiding.
- `LocalActionSpec` plus `ActionSpec` own UI-only labels/help/icons for actions that are not dispatcher-backed commands.
- `AppCommandSpec.controlToolTip(...)` and `ActionSpec.controlToolTip(...)` already format compact tooltip strings, but both allow call-site overrides.
- `ShortcutTrigger.displayString`, `KeyBinding.displayString`, and `CommandBarItem.ShortcutKey` formatting duplicate glyph-order logic in several places.

Primary files:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`

### Tooltip renderers and call sites

The app currently has three tooltip paths:

- Custom SwiftUI hover bubble: `HoverTooltipBubble`, `hoverTooltipAnchor`, and `FloatingHoverTooltipPresenter` in `Sources/AgentStudio/Core/Views/HoverTooltip.swift`.
- Native SwiftUI `.help(...)` on the same controls, often beside the custom hover presenter.
- AppKit `NSButton.toolTip` / `NSToolbarItem.toolTip` in `MainWindowController`.

Current adopters of the custom hover presenter are narrow:

- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`

Both surfaces still pass or derive raw `String` tooltip text locally. Examples include drawer overrides such as `"Open in Finder"` and inbox overrides such as `"Sort inbox"`, `"Attention only"`, and `"Group"`.

### Enforcement today

Existing tests pin formatting and some source usage, but they do not prevent the next dense toolbar from calling `.help("...")` directly.

- `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift` tests `controlToolTip(...)` formatting.
- `Tests/AgentStudioTests/App/AppCommandSpecContractTests.swift` tests command/shortcut contracts.
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxSidebarToolbarPresentationTests.swift` snapshots inbox toolbar tooltip strings.
- `Tests/AgentStudioTests/App/WelcomeLauncherArchitectureTests.swift` includes source assertions that a toolbar item uses `definition.controlToolTip`.

The repo has a SwiftSyntax architecture-lint tool. Rules are registered in `ArchitectureRuleRegistry`, fixture-tested through Good/Bad corpora, listed in `RuleInventoryTests`, and run by `mise run lint`. That is the right place for a tooltip-source rule once a typed adapter exists.

## Target Model

### Projection, not inheritance

Do not make one giant `CommandContracts` supertype that every command, action,
IPC row, and shared component implements. The middle shape is a set of
projections:

```text
AppCommandSpec
    -> CommandDisplayDescriptor
    -> ControlTooltipSource
    -> ControlTooltipRenderValue

AppCommandSpec
    -> AppCommandIPCExposure
    -> IPCCommandListEntry
```

The arrows are value projection and resolution, not inheritance. `AppCommandSpec`
remains the concrete app command catalog. `IPCCommandListEntry` remains the
public IPC DTO. `SharedComponents` receives render values and closures, not
semantic command sources.

### Shared render vocabulary

Introduce low-power render values in `Infrastructure/`. These are safe for
`SharedComponents` because they do not mention app commands, actions, feature
state, IPC privileges, or execution behavior:

```swift
struct ControlTooltipRenderValue: Equatable, Sendable {
    let text: String
    let shortcutDisplayText: ShortcutDisplayText?
}

struct ShortcutDisplayText: Equatable, Sendable {
    let value: String
}
```

`ControlTooltipRenderValue` is what shared UI primitives may consume. It is not
the source of truth and carries no execution authority. It also does not replace
accessibility labels or accessibility descriptions. Compact tooltip copy such as
`Group (⌥G)` must not become the accessible name of a control; accessibility
continues to come from the semantic owner or the existing action presentation
seam.

### Semantic display descriptor

Introduce a product-level display descriptor near the existing action
presentation types. It is the shape command specs and local action specs project
into before tooltip resolution:

```swift
struct CommandDisplayDescriptor: Equatable, Sendable {
    let provenance: CommandDisplayProvenance
    let label: String
    let helpText: String
    let compactTooltipText: String?
    let shortcutDisplayText: ShortcutDisplayText?
}

enum CommandDisplayProvenance: Equatable, Sendable {
    case appCommand(rawValue: String)
    case localAction(rawValue: String)
    case localShortcut(rawValue: String)
    case dynamicData(DynamicTooltipReason)
}
```

`provenance` is inspectable source metadata for tests, diagnostics, and future
lint/debug assertions. It must never be used for routing, execution, command
authorization, or IPC projection.

`CommandDisplayDescriptor` must not store `AppCommand`, `AppCommandSpec`,
`ShortcutTrigger`, `KeyBinding`, `IPCCommandListEntry`, or IPC privilege types.
When a richer app-owned type is needed to build the descriptor, the projection
belongs in the app or feature owner that already knows that type.

### Tooltip source and resolver

Introduce a discriminated source value that resolves display descriptors into
render values:

```swift
enum ControlTooltipSource: Sendable {
    case display(CommandDisplayDescriptor, style: TooltipCopyStyle = .compact)
    case dynamicData(DynamicTooltipReason, text: String, shortcut: ShortcutDisplayText? = nil)
}

enum TooltipCopyStyle: Sendable {
    case compact
    case helpText
    case label
}

enum DynamicTooltipReason: Sendable {
    case filesystemPath
    case userDataLabel
    case stateReadout
    case compositeMenuSummary
}
```

Rules:

- No generic `.custom(String)` or `.literal(String)` case.
- Dynamic strings must declare a reason. Dynamic reasons should be rare and named enough that code review can challenge them.
- Command-backed controls project `AppCommandSpec` into `CommandDisplayDescriptor`
  from `App/Commands`; they do not pass `AppCommand` into `Core/Actions`.
- UI-only controls project `LocalActionSpec.actionSpec` into the same descriptor shape.
- Feature-local shortcuts stay local, but route and display must share one typed
  source before producing `ShortcutDisplayText`.
- Composite menu buttons use one summary tooltip source, not concatenated child command help.

### Resolver

Add a pure resolver near the semantic action-presentation types:

```swift
enum ControlTooltipResolver {
    static func resolve(_ source: ControlTooltipSource) -> ControlTooltipRenderValue
}
```

The resolver should be the only place that joins text plus shortcut glyphs. It should internally reuse or replace the existing `controlToolTip(...)` behavior so callers do not manually append `(" + shortcut + ")`.

### UI adapters

Product call sites should resolve from `ControlTooltipSource`. Shared UI
primitives should accept `ControlTooltipRenderValue` or a tiny render-only
protocol, not arbitrary `String` and not semantic command/action types.

SwiftUI native help:

```swift
view.controlHelp(command.definition.controlTooltipRenderValue())
```

Custom hover presenter:

```swift
FloatingHoverTooltipPresenter(
    activeTarget: activeTarget,
    anchorFrames: frames,
    availableWidth: width,
    tooltip: { target in tooltipSource(for: target).map(ControlTooltipResolver.resolve) }
)
```

AppKit:

```swift
item.applyControlTooltip(command.definition.controlTooltipRenderValue())
button.applyControlTooltip(command.definition.controlTooltipRenderValue())
```

Product command/action owners resolve `ControlTooltipSource` to
`ControlTooltipRenderValue` before crossing a UI render boundary. The adapter
layer owns applying the resolved `.text` to `.help`, `HoverTooltipBubble`,
`NSButton.toolTip`, or `NSToolbarItem.toolTip`. Shared components render only the
resolved value.

## Ownership Boundaries

### `Infrastructure`

Owns the lowest shared render vocabulary that `SharedComponents` may consume.
These types are intentionally dumb: they describe rendered text and shortcut
display, not command identity, action routing, IPC privileges, focus
requirements, or feature state.

Likely files:

- New: `Sources/AgentStudio/Infrastructure/ControlTooltipRenderValue.swift`
- Existing style/policy precedent:
  `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  `Sources/AgentStudio/Infrastructure/AppPolicies.swift`

### `Core/Actions`

Owns semantic action presentation for Core-owned local actions and descriptor
resolution that does not depend on `AppCommand`. This layer may own
`CommandDisplayDescriptor`, `ControlTooltipSource`, `ControlTooltipResolver`,
and `DynamicTooltipReason` only if those types remain free of `App/`,
`Features/`, and IPC DTO references.

Likely files:

- New: `Sources/AgentStudio/Core/Actions/ControlTooltipSource.swift`
- Existing: `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`

Do not add new `Core/Actions` APIs that accept `AppCommand` or
`AppCommandSpec`. The current `UIActionPresentation.swift` extension on
`AppCommandSpec` is a coupling pressure point; the tooltip implementation should
move new app-command projections into `App/Commands` instead of widening that
Core-to-App reference.

### `App/Commands`

Keeps command identity and command metadata. `AppCommandSpec` remains the
concrete command catalog. It may grow a compact-tooltip phrase if call-site
overrides currently express stable product copy that belongs with the command.
It also owns projection from `AppCommandSpec` into the semantic display
descriptor and IPC exposure projection into `IPCCommandListEntry`.

Likely files:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Commands/AppShortcut.swift`

Do not move `AppCommand` into `Core`, `Infrastructure`,
`AgentStudioProgrammaticControl`, or `SharedComponents`.

### `AgentStudioProgrammaticControl` and `App/IPCComposition`

`IPCCommandListEntry` remains a public IPC DTO, not the internal display
contract. App IPC adapters continue to project `AppCommandSpec.ipcExposure` into
`IPCCommandListEntry` for `command.list`.

Likely files:

- `Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift`
- `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`

### `Core/Views` and `SharedComponents`

Own generic visual adapters for SwiftUI help/hover rendering. They must not own
command semantics. `SharedComponents` may accept `ControlTooltipRenderValue` or
a tiny render-only protocol because those live at the Infrastructure/render
boundary. It must not accept `ControlTooltipSource`, `CommandDisplayDescriptor`,
`AppCommandSpec`, `ActionSpec`, or IPC command DTOs.

Likely files:

- `Sources/AgentStudio/Core/Views/HoverTooltip.swift`
- Possibly a shared dense-control helper under `SharedComponents/` only if two feature surfaces need the same button construction semantics.

### Feature slices

Feature-local keyboard routes stay in the feature, but route and display must come from one typed source. For inbox, replace independent `InboxSidebarKeyboardRouter` and `InboxSidebarKeyboardHint` drift with a small local shortcut descriptor that both routing and tooltip display consume.

Likely files:

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarKeyboard.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`

### `Tools/AgentStudioArchitectureLint`

Owns the hard rule that dense tooltip surfaces use the typed adapter.

Likely files:

- New: `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/TooltipSourceRule.swift`
- Update: `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Core/ArchitectureRule.swift`
- Update: `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleInventoryTests.swift`
- Update: `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/RuleParityTests.swift`
- Add Good/Bad fixtures under `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/Fixtures/`

## Enforcement Strategy

### Type-level forcing

The first forcing function is API shape:

- `FloatingHoverTooltipPresenter` should no longer accept `(Target) -> String?` for product call sites. It should accept `(Target) -> ControlTooltipRenderValue?` at the shared/render boundary, with product call sites resolving from `ControlTooltipSource`.
- SwiftUI dense controls should use `controlHelp(...)`, not `.help(...)` directly.
- AppKit helper constructors should accept `ControlTooltipSource` in app-owned adapter paths or `ControlTooltipRenderValue` in shared/render-only paths, not raw `String`.

This makes the happy path typed.

### Architecture-lint forcing

Add a SwiftSyntax rule with a narrow v1 scope:

- Rule id: `agentstudio_toolbar_tooltip_source`
- Severity: `error`
- Initial target: dense icon controls and controls participating in shared hover-tooltip infra.
- Flag direct string/interpolated string passed to `.help(...)` on dense controls.
- Flag direct `toolTip = "..."` or `toolTip = someLocalString` outside approved AppKit tooltip adapters.
- Allow typed seams such as `controlHelp(...)`, `applyControlTooltip(...)`, `.controlToolTip(...)` only inside resolver/adapter implementation, and dynamic data reasons.

Recommended v1 heuristic to avoid false positives:

- Inspect `Button` and `Menu` chains.
- Fire when the modifier chain contains `.hoverTooltipAnchor(...)`, or when the chain looks like an icon toolbar control (`.buttonStyle(.borderless)`, `.buttonStyle(.plain)`, or `.menuStyle(.borderlessButton)`) and the label body is icon-only.
- Do not broadly ban all `.help("...")` in v1. Search fields, data rows, and explanatory labels are not the same architecture problem.

### Tests

Add tests at three levels:

- Pure formatting/provenance tests in `UIActionPresentationTests` for `ControlTooltipResolver`.
- Feature tests for local shortcut descriptors, starting with inbox `⌥F`, `⌥G`, `⌥S`, group movement, Return, and Space.
- Architecture-lint Good/Bad fixtures proving dense controls fail with raw `.help("...")` and pass through typed adapters.

## Migration Plan

### Phase 1: Add typed model and adapters

- Add `ControlTooltipRenderValue`, `ShortcutDisplayText`, `CommandDisplayDescriptor`, `ControlTooltipSource`, and resolver.
- Add app-command projection helpers under `App/Commands`, not in `Core/Actions`.
- Keep existing `controlToolTip(...)` helpers temporarily as resolver internals or compatibility wrappers.
- Add `controlHelp(...)` SwiftUI modifier and AppKit `applyControlTooltip(...)`
  helpers in UI-owned layers, not in `Infrastructure`.
- Add tests for command, local action, automatic shortcut, explicit trigger, local shortcut, and dynamic data cases.

### Phase 2: Migrate highest-risk dense surfaces

Start with surfaces that already proved the problem:

1. `DrawerIconBar`
2. `InboxSidebarComponents`
3. `PaneInboxNotificationPopover`
4. `MainWindowController` titlebar/toolbar helper path

Each migration should remove local tooltip string assembly and make both `.help`
and hover bubble read the same resolved `ControlTooltipRenderValue`, with
product code deriving that value from `ControlTooltipSource`.

### Phase 3: Add architecture lint as error

After the first surfaces are migrated, add `agentstudio_toolbar_tooltip_source` as an error for the migrated patterns.

Do not make the first lint rule global. A narrow rule that catches the toolbar class of failures is better than a broad noisy rule that everyone works around.

### Phase 4: Update docs and progressive disclosure

Update:

- `docs/architecture/commands_and_shortcuts.md`: replace old helper-only language with the typed source contract; normalize `CommandSpec` wording to `AppCommandSpec`.
- `docs/guides/style_guide.md`: dense controls use typed tooltip sources, not direct `.help` or raw text.
- `docs/architecture/README.md`: route UI tooltip/dense toolbar changes to both style guide and commands/shortcuts.
- `AGENTS.md`: explicitly say toolbar/tooltip UI work must read style guide, app architecture, and commands/shortcuts before editing.
- `docs/architecture/architecture_lint_inventory.md`: document the new lint rule.

## Alternatives Considered

### Helper-only cleanup

Keep `controlToolTip(...)`, ask developers to use it, and update docs.

Gain: smallest implementation.
Pay: same failure mode returns because direct `.help("...")` still compiles and local strings remain easy.
Verdict: insufficient. This is what the repo effectively has today.

### Force every shortcut into `AppShortcut`

Make all tooltip shortcuts app-wide so command specs can own everything.

Gain: one global shortcut source.
Pay: breaks feature-local keyboard ownership and contradicts current command docs. Inbox keys like `⌥S` are local sidebar routes, not global app shortcuts.
Verdict: reject.

### Broad ban on `.help(...)`

Use architecture lint to reject direct `.help(...)` on migrated dense controls
outside adapters immediately. Do not turn v1 into a repo-wide ban on explanatory
or data-row help.

Gain: strongest enforcement.
Pay: too noisy. Data rows, search fields, and explanatory help text are different from dense icon toolbar controls.
Verdict: defer. Use a narrow dense-control rule first.

### Tooltip renderer owns all copy

Move compact strings into `HoverTooltip` or a shared SwiftUI component.

Gain: visual layer becomes easy to use.
Pay: violates separation of concerns. Rendering should not own command/local action semantics.
Verdict: reject.

### IPC command list as the internal base contract

Make `IPCCommandListEntry` the shared command/tooltip contract so the app,
tooltips, and command discovery all share one row type.

Gain: one shape already exists for command discovery.
Pay: confuses a public serialized DTO with internal UI semantics. IPC rows
carry automation exposure and privilege metadata; shared tooltip UI does not
need that authority surface, and command display still has richer app-local
copy/shortcut rules.
Verdict: reject. Keep `IPCCommandListEntry` as a projection result from
`AppCommandSpec.ipcExposure`.

### Infrastructure owns semantic command contracts

Move command display/source protocols into `Infrastructure` so
`SharedComponents` can import them.

Gain: every layer can see the same protocol.
Pay: pulls product command/action semantics into the lowest layer and makes the
DAG less useful. Infrastructure should hold render vocabulary, not command
authority.
Verdict: reject. Put only `ControlTooltipRenderValue` and primitive shortcut
display values in Infrastructure.

## Security Context

This design is not directly security-sensitive in the sense of auth, secrets, subprocess execution, network calls, or filesystem mutation. It does touch architecture lint and app command presentation, so the main safety risk is authority confusion: a tooltip must not imply a command or shortcut exists when the action is actually UI-local or unavailable.

Security-relevant guardrails:

- Tooltip work must not change the existing IPC command model:
  `AppCommandSpec` stays the source catalog, `AppCommandIPCExposure` stays the
  app-owned automation projection, and `IPCCommandListEntry` stays the public
  DTO returned by `command.list`.
- Do not expose tooltip provenance as a public IPC authority surface.
- Do not route behavior through tooltip descriptors. They are presentation only.
- Do not make dynamic tooltip text a place to export paths or sensitive data over telemetry. If provenance is logged later, log only enum cases, not dynamic text payloads.

## Validation Strategy

For implementation planning, require these proof gates:

- Focused unit tests:
  - `UIActionPresentationTests`
  - command spec contract tests
  - feature-local shortcut descriptor tests for migrated features
  - migrated toolbar presentation tests
  - AppKit/titlebar source-assertion coverage for migrated `MainWindowController`
    `toolTip` seams
- Architecture-lint package tests:
  - `swift test --package-path Tools/AgentStudioArchitectureLint`
- Repo lint:
  - `mise run lint`
- Native UI smoke/manual proof for migrated surfaces:
  - `mise run observability:up`
  - `mise run run-debug-observability -- --detach`
  - `mise run verify-debug-observability`
  - Hover drawer and inbox toolbar controls with native UI proof after the
    runner/verifier path passes.
  - Verify native `.help`, custom hover text, and AppKit `toolTip` text match
    where each surface applies.

## Open Decisions

1. Should compact tooltip copy become a stored property on `ActionSpec` / `AppCommandSpec`, or should `TooltipCopyStyle` plus optional typed phrases live only in `CommandDisplayDescriptor`?

Recommended default: add compact copy only when stable product copy differs from label/help text. Avoid turning every spec into three strings.

2. Should v1 lint include `PaneInboxNotificationPopover`?

Recommended default: include it if its controls are icon-only dense controls; otherwise leave it for v2. Do not make the rule noisy before the main toolbar surfaces are migrated.

3. Should direct `.help(...)` remain allowed for non-interactive explanatory labels and data rows?

Recommended default: yes, with dynamic-data reasons or out-of-scope lint paths. The architecture bug is dense action controls, not every help string.

4. Should `ShortcutTrigger` / `KeyBinding` display formatting move toward an
Infrastructure-safe display primitive now, or should Phase 1 project them to
`ShortcutDisplayText` at the app/feature boundary?

Recommended default: project to `ShortcutDisplayText` at the app/feature
boundary in Phase 1. Move richer key-chord primitives downward only if multiple
shared components need to compute, not just render, shortcut glyphs.

## Recommended Next Workflow

Use `shravan-dev-workflow:spec-review-swarm` again after any next revision, or
move to `shravan-dev-workflow:plan-create` if the review finds no blocker. The
review should specifically attack:

- Whether `ControlTooltipSource` is too heavy for common call sites.
- Whether the architecture-lint rule is narrow enough to avoid false positives.
- Whether feature-local shortcut descriptors are enough to prevent hint/router drift.
- Whether the migration plan should make AppKit typed adapters part of Phase 1 or Phase 2.
