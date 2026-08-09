# Command Context and Command Surface Restoration

Date: 2026-07-27

Status: Accepted; implementation in progress

Dependency: the Pane Zoom change lands first. This contract preserves the
resulting Zoom behavior; it does not redesign or block that work.

## Outcome

Agent Studio has one typed command contract whose concepts cannot be confused:

- `AppCommand` identifies an action.
- `AppCommandSpec` describes presentation, interactive exposure, targeting,
  keyboard binding, command-context requirements, and IPC exposure.
- `WorkspaceFocusedPaneResolver` resolves the workspace pane that owns
  pane-local attention.
- `CommandContextDerived` projects workspace facts into command-policy facts.
- `CommandRequirement` describes context-derived presentation requirements.
- `AppCommandSurface` describes the interactive UI host asking whether it may
  present a command.
- `canExecute` and the validated workspace action pipeline remain the
  authoritative runtime capability and mutation gates.
- IPC exposure, target authorization, argument validation, privileges, and
  runtime command validation remain independent security boundaries.

This is a hard semantic cutover. No compatibility aliases preserve
`WorkspacePaneFocus`, `WorkspacePaneFocusDerived`, or `FocusRequirement`.

## Product and engineering intent

The user-visible command system should behave consistently regardless of
whether a command is discovered in the command bar, shown in a menu, rendered
in a toolbar, invoked by a shortcut, dispatched with an explicit target, or
discovered through IPC.

Consistency does not mean that every command appears everywhere. It means each
surface consumes the same typed declaration and the same runtime capability
owner instead of recreating command meaning locally.

This change is primarily architectural. Existing labels, icons, shortcuts,
menu placement, toolbar placement, command-bar grouping, targeting behavior,
and IPC behavior remain unchanged except where the Pane Zoom dependency has
already established new behavior.

## Problem

The current command-policy projection is named as pane focus:

- `WorkspacePaneFocus`
- `WorkspacePaneFocusDerived`
- `FocusRequirement`

That projection now performs two different jobs:

1. It normalizes `WorkspaceFocusOwnerAtom` and resolves the actual focused main
   pane, empty drawer, or drawer child.
2. It derives command presentation requirements and provides command-bar
   status presentation.

Those jobs have different reasons to change. Pane-focus resolution changes when
drawer or responder ownership changes. Command context changes when a command
needs a new workspace or presentation fact. Keeping both inside one
`WorkspacePaneFocusDerived` type recreates the terminology collision that
`CommandContext` was intended to prevent.

`AppCommandSpec` also lacks a first-class interactive surface declaration.
Today:

- command-bar exposure is represented by `isHiddenInCommandBar`;
- menus explicitly construct items and separately ask for visibility;
- toolbars explicitly construct actions and may skip context visibility;
- context menus use command presentation values but own their own inclusion
  rules;
- shortcuts use their own typed keyboard-surface policy;
- IPC uses `ipcExposure`.

The missing surface dimension makes it possible for a command to have correct
metadata yet appear in an unintended toolbar or menu. Pane Zoom exposed this
gap: a Zoom-local Viewer command needs to be present on the terminal Zoom
toolbar and in context-derived discovery, but absent from a normal pane
toolbar.

## Terminology

### Focus

Focus means user attention inside the workspace pane system.

`WorkspaceFocusOwnerAtom` remains the runtime source of requested workspace
pane focus. It distinguishes:

- a main pane;
- an empty drawer belonging to a main pane;
- a drawer child belonging to a main pane.

Focus is not command visibility.

### Command context

`CommandContext` is an immutable projection of live workspace facts used by
command presentation policy. It answers which `CommandRequirement` values are
currently satisfied.

Command context is not an AppKit first-responder model, a mutable state owner,
or authorization.

### Command surface

`AppCommandSurface` identifies an interactive UI host that is asking to
present a command. It is static host identity supplied by the consumer.

It is deliberately distinct from:

- `ActiveKeyboardSurface`, which owns keyboard routing precedence;
- `CommandBarSurfaceAtom`, which records the active command-bar scope for one
  workspace window;
- `TransientKeyboardSurfaceAtom`, which records temporary keyboard islands;
- `BridgeProductSurface`, which selects Review or Files inside Bridge;
- Ghostty/runtime surfaces.

No `AppCommandSurfaceAtom` is introduced.

### Visibility and capability

Visibility answers whether an interactive host should present a command.

Capability answers whether the command can execute against current live state
and, when applicable, an explicit target.

A visible command may be disabled. A hidden command is not thereby prohibited
from another declared surface. Neither visibility nor surface exposure grants
IPC authority or bypasses runtime validation.

## Orthogonal command-spec dimensions

Every `AppCommandSpec` has the following independent dimensions.

| Dimension | Owner | Question answered |
| --- | --- | --- |
| Identity | `AppCommand` | What action is being requested? |
| Presentation | label, icon, help text, grouping, display shortcut projection | How is the action described? |
| Interactive surfaces | `AppCommandSurfacePolicy` | Which UI hosts may present it? |
| Keyboard binding | `AppShortcut` plus `AppShortcutDispatchPolicy` | Which key gesture may request it, and which keyboard owner may route it? |
| Command context | `Set<CommandRequirement>` evaluated against `CommandContext` | Which live workspace facts must hold for contextual presentation? |
| Targeting | `AppCommandTargeting` | Is it contextual, targeted, or both, and which target kinds are valid? |
| Execution prerequisites | current management-layer prerequisite plus `canExecute` | Is the request currently executable? |
| IPC exposure | `AppCommandIPCExposure` and argument schema | Is it discoverable/headless/presentation-only over IPC, with which target kinds and privileges? |
| Mutation validation | `WorkspaceCommandValidator`, feature/runtime validators, and execution owner | Is the resolved operation safe and valid immediately before mutation? |

No field is allowed to stand in for another. In particular:

- `visibleWhen` is not `canExecute`;
- `AppCommandSurface` is not `ActiveKeyboardSurface`;
- `AppCommandTargeting` is not IPC authorization;
- IPC headless exposure is not interactive surface exposure;
- a command-bar row is not proof that a command may execute headlessly.

## Requirements

### R1 — Restore command terminology

The command-policy types are named `CommandContext`,
`CommandContextDerived`, and `CommandRequirement`.

There are no aliases, deprecated wrappers, or duplicate old names.

### R2 — Separate pane focus from command projection

Actual workspace pane-focus resolution is owned by
`WorkspaceFocusedPaneResolver`.

Command-policy projection is owned by `CommandContextDerived`.

`CommandContextDerived` consumes a resolved focused-pane value; it does not
normalize `WorkspaceFocusOwner` itself.

The exact names are intentional:

- `WorkspaceFocusedPaneResolver` names a stateless operation that resolves the
  pane currently owning workspace attention.
- `CommandContextDerived` names a stateless projection into command policy.

`WorkspacePaneFocusDerived` is not retained because that name cannot state
which of those jobs it owns.

### R3 — Keep focus state ownership unchanged

`WorkspaceFocusOwnerAtom` remains the only mutable owner for requested
workspace pane focus.

The restoration introduces no mutable command-context atom and no new global
ambient scope.

### R4 — Normalize stale focus before projection

The focused-pane resolver preserves current normalization behavior:

- a drawer owner is valid only for the active main pane;
- a collapsed or mismatched drawer falls back to the active main pane;
- a minimized or stale drawer child resolves to the current visible drawer
  child when one exists;
- an expanded drawer with no visible child resolves as empty-drawer focus;
- a missing active pane produces no focused pane.

The result retains whether focus is on the main pane, an empty drawer, or a
drawer child. Empty-drawer focus uses the parent main pane as contextual pane
identity/content while retaining the explicit empty-drawer owner state.

### R5 — Command context is derived, immutable state

`CommandContext` is an immutable `Equatable` and `Sendable` value.

It contains only command-policy inputs and identity needed by contextual
command consumers:

- active tab identity;
- focused pane/repo/worktree identity when one resolves;
- focused pane content classification needed by command requirements;
- satisfied `CommandRequirement` values.

UI display copy and icons for the focused-pane status strip do not belong to
`CommandContext`.

### R6 — Focus presentation has its own value

The focused-pane resolver returns an immutable focused-pane value suitable for
the command-bar status strip and other actual focus readers.

That value owns:

- normalized focus owner;
- active main pane identity;
- focused pane identity;
- focused repo/worktree identity;
- focused pane content classification.

Display projection for the status strip derives from this value rather than
from `CommandContext`.

### R7 — Preserve requirement normalization

Content requirements remain mutually exclusive by construction.

The focused content classification, not a caller-supplied set, determines
exactly one of:

- `paneIsTerminal`;
- `paneIsWebview`;
- `paneIsBridge`;
- `paneIsCodeViewer`;
- no content requirement for unsupported/no pane.

Callers cannot construct contradictory content requirements that survive
normalization.

### R8 — Preserve Pane Zoom semantics

After the Pane Zoom dependency lands,
`CommandRequirement.hasActiveTerminalZoom` is retained through this hard
cutover.

It is satisfied only when:

1. the active tab has a `ZoomPresentation`;
2. `sourcePaneId` resolves to a live pane;
3. the source pane is a terminal.

It is not implemented as `hasActiveZoom + paneIsTerminal`.
`paneIsTerminal` describes the focused/context pane and may refer to a drawer
child or retained Viewer while the Zoom source remains the original terminal.

The Zoom-local Viewer command retains the command identity and behavior
established by the Pane Zoom change. This spec only migrates its declaration
onto restored command-context and command-surface vocabulary.

### R9 — Introduce a typed interactive command surface

`AppCommandSurface` is a `Hashable` and `Sendable` enum with the initial
surface vocabulary:

```swift
enum AppCommandSurface: Hashable, Sendable {
    case commandBar
    case mainMenu
    case contextMenu
    case toolbar(AppCommandToolbarSurface)
    case inlineControl
}

enum AppCommandToolbarSurface: Hashable, Sendable {
    case app
    case pane
    case terminalZoom
}
```

The names may follow normal source-file placement conventions, but their
semantics are fixed by this contract.

`terminalZoom` identifies the Zoom-wide parent toolbar for a terminal source.
It does not identify Bridge Review/Files or a Ghostty surface.

### R10 — Every command explicitly declares interactive exposure

`AppCommandSpec` has a required `surfacePolicy` with no permissive default:

```swift
enum AppCommandSurfacePolicy: Equatable, Sendable {
    case exposed(Set<AppCommandSurface>)
    case notPresented
}
```

`notPresented` covers shortcut-only, IPC-only, generated-target-row, and
internal dispatch identities that do not own an independently presented
interactive control.

`isHiddenInCommandBar` is removed. Command-bar inclusion is represented by
exposure to `.commandBar`.

Adding a command requires an explicit surface policy in the exhaustive
`AppCommand.definition` catalog.

`.exposed([])` is invalid; a command with no interactive presentation uses
`.notPresented`.

### R11 — Surface exposure does not own placement

Interactive hosts continue to own layout, ordering, grouping, spacing,
selected state, and control construction.

The surface policy answers only whether the host may present the command. It
must not become an auto-generated menu or toolbar framework.

### R12 — Contextual presentation is typed

An interactive host presents a contextual command only when:

1. the command exposes that `AppCommandSurface`; and
2. `visibleWhen` is a subset of the current
   `CommandContext.satisfiedRequirements`.

The result controls presence, not enablement.

### R13 — Targeting is explicit

The ambiguous `appliesTo` plus separate `isTargetableCommand` split is replaced
by:

```swift
enum AppCommandTargeting: Equatable, Sendable {
    case contextual
    case targeted(Set<SearchItemType>)
    case contextualAndTargeted(
        Set<SearchItemType>,
        preferredInvocation: AppCommandPreferredInvocation
    )
}

enum AppCommandPreferredInvocation: Equatable, Sendable {
    case contextual
    case targetSelection
}
```

`SearchItemType` remains the existing internal target-kind vocabulary in this
change and gains explicit `Hashable`/`Sendable` conformance as required by the
typed policies. Renaming the public/internal target taxonomy is not required.

The target set for `.targeted` and `.contextualAndTargeted` must be non-empty.

The preferred invocation removes the current command-bar ambiguity:

- `.contextual` dispatches the root row directly;
- `.targetSelection` drills into the declared target kinds;
- a targeted-only command always uses target selection.

Other hosts may choose either declared mode when both are supported, but may
not invent an undeclared mode.

The targeting declaration drives:

- whether a root command row dispatches contextually or drills into targets;
- which generated target kinds are legal;
- whether a context menu or inline control may attach the command to its
  target kind;
- targeted dispatcher preflight before the execution owner is called.

Special multi-stage target builders, such as moving a pane to another tab, may
retain their feature-specific row construction, but their supported target
kinds still come from `AppCommandTargeting`.

### R14 — Presentation queries preserve orthogonality

Shared presentation policy accepts a typed subject:

```swift
enum AppCommandPresentationSubject: Equatable, Sendable {
    case contextual(CommandContext)
    case targeted(SearchItemType)
    case contextualTarget(CommandContext, SearchItemType)
}

struct AppCommandPresentationQuery: Equatable, Sendable {
    let surface: AppCommandSurface
    let subject: AppCommandPresentationSubject
}
```

The presentation decision applies:

- surface exposure for every subject;
- `visibleWhen` for subjects carrying a `CommandContext`;
- target-kind support for subjects carrying a target kind.

No target UUID or mutable store reference belongs in the presentation query.
Target existence and validity remain runtime concerns.

### R15 — Runtime capability remains authoritative

After a command is presented:

- contextual controls use `AppCommandDispatcher.canDispatch(_:)`;
- targeted controls use
  `AppCommandDispatcher.canDispatch(_:target:targetType:)`;
- execution repeats the corresponding check;
- workspace mutations pass through `WorkspaceCommandValidator`;
- terminal/runtime commands pass through their existing typed runtime
  validators.

Presentation policy never returns an authorization or mutation result.

The existing `AppCommandExecutionContext` remains the runtime distinction
between interactive and headless IPC execution. It is not renamed to or
replaced by `AppCommandSurface`.

### R16 — Keyboard routing remains independently exhaustive

`AppShortcut`, `ShortcutContext`, `ActiveKeyboardSurface`,
`KeyboardRoutingContext`, and `AppShortcutDispatchPolicy` keep their current
responsibilities.

Shortcut dispatch:

1. resolves a typed `AppShortcut`;
2. applies `ActiveKeyboardSurface` routing policy;
3. resolves the command from the spec/catalog;
4. calls the same contextual or source-targeted dispatcher;
5. remains subject to `canExecute` and runtime validation.

`AppCommandSurface` does not duplicate keyboard routing cases.

### R17 — Consumer convergence

The following consumers use the same `AppCommandSpec` contract:

- command bar;
- AppKit main menu validation;
- SwiftUI context menus;
- app/titlebar toolbars;
- pane and terminal-Zoom toolbars;
- command-backed inline controls;
- shortcuts;
- contextual dispatcher;
- targeted dispatcher;
- IPC command discovery and execution.

Consumers may project the fields they own, but they may not recreate command
identity, labels, icons, target kinds, command-context requirements, or IPC
exposure in parallel constants.

### R18 — Preserve typed tooltip projection

Command-backed dense controls continue to project:

```text
AppCommandSpec
  -> CommandDisplayDescriptor
  -> ControlTooltipSource
  -> ControlTooltipRenderValue
```

`AppCommandSurface` does not add a new tooltip path.

### R19 — IPC remains explicitly separate from UI exposure

IPC continues to project only:

- command identifier and title;
- execution modes;
- IPC target handle kinds;
- required privileges;
- typed argument schema.

Interactive surface declarations and command-context requirements are not
exported as authority and do not change the public IPC DTO schema.

### R20 — Preserve hard security gates

Headless execution still requires all existing gates:

- the spec marks the command headless-executable;
- the authenticated IPC service grants the required privilege classes;
- arguments match the typed schema;
- a required handle is present;
- the handle kind is permitted by `ipcExposure`;
- the durable target authorizer confirms membership;
- targeted `canDispatch` accepts the target;
- the execution owner and mutation/runtime validator accept the request.

Visibility, command surfaces, or a satisfied `CommandRequirement` cannot bypass
any gate.

### R21 — Hard-cut all consumers

All source, tests, AtomRegistry accessors, status-strip models, menu validators,
command-bar caches, command catalog helpers, and the Commands and Shortcuts
architecture document use the restored vocabulary in one change.

There is no dual read path and no transition period.

### R22 — Preserve behavior outside the named cutover

The change does not alter:

- command labels, icons, help text, shortcut strings, or command-bar groups;
- user-visible menu or toolbar placement;
- existing selected/disabled behavior;
- durable target resolution;
- IPC execution modes, handle kinds, privilege classes, or argument schemas;
- BridgeWeb protocol, worker, transport, activity, construction identity, or
  scheduling policy;
- Pane Zoom lifecycle or Viewer lifecycle.

### R23 — Keep IPC synchronized by command identity, not UI policy

`AppCommand` remains the exhaustive identity shared by the interactive and IPC
planes. Every command identity must have:

- one `AppCommandSpec` definition;
- one exhaustive IPC privilege classification;
- one exhaustive IPC durable-target-kind classification;
- an IPC execution-mode and argument-schema projection.

`AgentStudioIPCCommandAdapter.listCommands()` enumerates
`AppCommand.allCases`, resolves each command's `AppCommandSpec`, and projects
that definition into `IPCCommandListEntry`. IPC command identifiers and titles
therefore remain synchronized with command identity and canonical presentation
copy.

Synchronization does not mean deriving IPC authority from interactive policy.
`surfacePolicy`, `targeting`, `preferredInvocation`, `visibleWhen`, and
`CommandContext` must never derive, widen, or narrow IPC execution modes,
durable handle kinds, privileges, or argument schemas. Those values remain
owned by the exhaustive `AppCommand.ipcSpec` companion projection and are
exposed through `AppCommandSpec.ipcExposure` and
`AppCommandSpec.argumentSchema`.

Internal IPC optionality and execution modes use discriminated unions rather
than empty arrays, booleans, or optional field combinations:

```swift
enum AppCommandIPCExposure {
    case notExposed
    case interactive(
        target: AppCommandIPCDurableTargetContract,
        requiredPrivilege: IPCPrivilegeClass
    )
    case uiPresentation
    case headless(
        target: AppCommandIPCDurableTargetContract,
        requiredPrivilege: IPCPrivilegeClass
    )
    case headlessAndInteractive(
        target: AppCommandIPCDurableTargetContract,
        requiredPrivilege: IPCPrivilegeClass
    )
}

enum AppCommandIPCDurableTargetContract {
    case targetless
    case required(
        primary: IPCHandleKind,
        additional: [IPCHandleKind]
    )
}

enum AppCommandIPCArgumentContract {
    case noArguments
    case repoSidebarSortOrder
    case inboxRowStateFilter
    case inboxContentMode
}

enum AppCommandExecutionArguments {
    case noArguments
    case repoSidebarSortOrder(RepoExplorerSortOrder)
    case inboxRowStateFilter(InboxNotificationRowStateFilter)
    case inboxContentMode(InboxNotificationContentMode)
}
```

The adapter switches exhaustively on `AppCommandIPCDurableTargetContract` to
decide whether a durable target is absent or required. Empty target-kind arrays
exist only in the unchanged public IPC DTO projection; they are not an internal
optionality discriminator. `AppCommandExecutionRequest.arguments` is
non-optional and defaults to `.noArguments`; the IPC argument contract decodes
exhaustively into the matching typed execution payload. Filter and argument
variants therefore remain finite states with exhaustive projections and no
`default` branches.

These internal enums project to the existing public arrays and argument-schema
DTOs. They do not change public encoding. The `AppCommand.ipcSpec` exposure and
argument-contract switches are exhaustive and contain no `default`; adding an
`AppCommand` must produce compiler errors until its IPC behavior and argument
shape are classified explicitly.

Adding or changing a command is incomplete until both exhaustive planes compile
and the catalog/IPC contract tests prove:

- command-list cardinality matches `AppCommand.allCases`;
- each public entry's id and title match its `AppCommandSpec`;
- its execution modes, target kinds, required privileges, and argument schema
  match the accepted IPC contract;
- encoded public DTO keys contain no interactive presentation policy.

## Technical contract

### Focus resolution

`WorkspaceFocusedPaneResolver` is a stateless pure resolver. It receives:

- the active tab and its active main-pane identity;
- pane lookup;
- drawer expansion/membership and active drawer-child projection;
- the requested `WorkspaceFocusOwner`.

It returns a `WorkspaceFocusedPane` value or no focused pane.

```text
WorkspaceFocusOwnerAtom
          │ requested owner
          ▼
WorkspaceFocusedPaneResolver
          │ validates against active tab, pane, drawer, visibility
          ▼
WorkspaceFocusedPane
  normalized owner
  active main pane id
  focused pane/repo/worktree ids
  focused content type
```

`WorkspaceFocusOwnerNormalizer` may remain the pure normalization primitive
used by the resolver. The resolver owns composition of normalized owner plus
pane identity; it does not absorb mutable state.

### Command-context projection

`CommandContextDerived` receives:

- active tab/layout facts;
- the resolved `WorkspaceFocusedPane`;
- pane counts, tab counts, drawer facts, and arrangement facts;
- presentation facts required by commands, including active terminal Zoom.

It returns `CommandContext`.

```text
WorkspaceFocusedPane ────────────────┐
tab/layout facts ────────────────────┤
runtime presentation facts ─────────┤
                                     ▼
                           CommandContextDerived
                                     │
                                     ▼
                              CommandContext
                         satisfied CommandRequirement
```

The projector never writes state and never consults AppKit responder objects.

### Command presentation

`AppCommandSpec` exposes one pure presentation query:

```text
AppCommandPresentationQuery
  surface: AppCommandSurface
  subject: contextual | targeted | contextualTarget
                      │
                      ▼
              AppCommandSpec.shouldPresent
                ├─ surface is exposed?
                ├─ requirements satisfied, if contextual?
                └─ target kind supported, if targeted?
                      │
                      ▼
                  present / omit
```

Enablement is evaluated afterward through `canDispatch`.

### Command catalog and IPC synchronization

The command identity is shared. Interactive presentation and IPC authority are
separate typed projections from that identity:

```text
                               AppCommand
                     exhaustive command identity
                                   │
                 ┌─────────────────┴─────────────────┐
                 │                                   │
                 ▼                                   ▼
       AppCommand.definition                 AppCommand.ipcSpec
            AppCommandSpec                    AppCommandIPCSpec
       ┌────────────────────┐          ┌────────────────────────┐
       │ label / icon / help│          │ execution modes        │
       │ shortcut           │          │ durable target kinds   │
       │ surfacePolicy      │          │ required privileges    │
       │ targeting          │          │ argument contract      │
       │ visibleWhen        │          └────────────┬───────────┘
       └─────────┬──────────┘                       │
                 │                                  │
                 └──────────────┬───────────────────┘
                                ▼
                 AppCommandSpec.ipcCommandListEntry
                 id from AppCommand
                 title from AppCommandSpec
                 authority/schema from ipcSpec
                                │
                                ▼
              AgentStudioIPCCommandAdapter.listCommands()
                 enumerate all AppCommand.allCases
                 project exactly one entry per identity
                 sort by public command identifier
```

The composition point synchronizes identity and canonical title. It does not
collapse the two policy planes:

```text
interactive request
  surface + subject
      │
      ▼
AppCommandSpec.shouldPresent          presence only
      │
      ▼
matching canDispatch / dispatch
      │
      ▼
execution owner + validator

authenticated IPC request
  command id + arguments + optional durable handle
      │
      ▼
AppCommandSpec.ipcExposure            execution mode + privileges
      │
      ▼
argument-schema validation
      │
      ├─ no handle ─► headless shell execution context
      │
      └─ handle
          ▼
        declared IPC handle kind
          ▼
        durable target membership
          ▼
        targeted canDispatch / dispatch
          ▼
        execution owner + validator
```

The authenticated IPC service enforces the required privilege scopes before
the adapter's execution path. The adapter then enforces execution mode,
argument shape, target requirements, durable-handle kind and membership, live
capability, and owner validation. Interactive surface exposure and command
context participate in none of those authority decisions.

Invalid drift states and their required correction:

| Invalid state | Failure | Required correction |
| --- | --- | --- |
| IPC target kinds are derived from `AppCommandTargeting` | A UI target addition silently widens remote authority. | Restore the independently reviewed `AppCommand.ipcSpec` target-kind classification. |
| `command.list` uses a hand-maintained command allowlist | New commands disappear from discovery or stale commands survive. | Enumerate `AppCommand.allCases` and project each canonical definition. |
| IPC duplicates command labels | Interactive and programmatic discovery disagree. | Project the public title from `AppCommandSpec.label`. |
| IPC DTOs encode surface or command-context fields | Presentation vocabulary becomes an accidental public/security contract. | Keep the public DTO limited to id, title, execution modes, target kinds, privileges, and argument schema. |
| A target handle passes kind checks but not durable membership | A stale or cross-workspace UUID reaches execution. | Reject before targeted `canDispatch`; never treat presentation targeting as membership proof. |
| Interactive policy changes alter accepted IPC bytes without an explicit IPC decision | The restoration changes the public contract accidentally. | Restore the accepted IPC projection and byte/value characterization fixtures. |
| An IPC switch uses `default` or empty arrays as an internal state discriminator | A new command silently inherits accidental exposure, privileges, or arguments. | Use exhaustive `AppCommand` switches and the internal exposure/argument discriminated unions. |

### Spec boundary / separability map

```text
workspace focus domain
  owns:
    requested workspace pane focus
    stale-focus normalization
    focused pane identity
  source of truth:
    WorkspaceFocusOwnerAtom + workspace pane/tab state
  exposes:
    WorkspaceFocusedPaneResolver -> WorkspaceFocusedPane

                         WorkspaceFocusedPane
                                  │
                                  ▼

command policy domain
  owns:
    CommandContext projection
    CommandRequirement vocabulary
    AppCommandSpec declarations
    interactive surface exposure
    contextual/targeting presentation policy
  source of truth:
    AppCommand.definition catalog + live derived workspace facts
  exposes:
    CommandContext
    AppCommandSpec.shouldPresent(...)

                                  │
                                  ▼

execution owners
  own:
    canExecute / canDispatch
    target resolution
    WorkspaceCommandValidator and runtime validation
    mutation sequencing
  source of truth:
    PaneTabViewController / AppDelegate shell owner / validated action owners

                                  │
                                  ▼

IPC boundary
  owns:
    authenticated discovery and execution
    public target handles
    privilege scopes
    argument schema validation
    durable target authorization
  source of truth:
    AppCommandIPCExposure + App IPC adapters/service
```

Allowed dependency direction:

```text
focused-pane resolver -> workspace state models
command context projector -> focused-pane value + workspace/presentation facts
AppCommandSpec presentation policy -> CommandContext + target kind
UI consumers -> AppCommandSpec projections + dispatcher
IPC projection -> AppCommandSpec.ipcExposure
execution owners -> validators and state owners
```

Disallowed dependency direction:

```text
WorkspaceFocusOwnerAtom -> AppCommandSpec
CommandContext -> AppKit responder mutation
AppCommandSurface -> ActiveKeyboardSurface mutation
UI visibility -> IPC authorization
IPC exposure -> toolbar/menu placement
CommandContext -> workspace mutation
```

## Pane Zoom migration contract

This spec assumes the Pane Zoom change has already established the behavior and
tests for terminal Zoom and the Zoom-local Viewer command.

During this cutover:

- `FocusRequirement.hasActiveTerminalZoom` becomes
  `CommandRequirement.hasActiveTerminalZoom`;
- its semantic derivation is unchanged;
- the Zoom-wide terminal parent toolbar identifies itself as
  `.toolbar(.terminalZoom)`;
- a normal pane toolbar identifies itself as `.toolbar(.pane)`;
- the Zoom-local Viewer command exposes only the interactive surfaces selected
  by the accepted Pane Zoom contract, including the terminal-Zoom toolbar and
  any contextual discovery surface already specified there;
- the durable Viewer command remains a distinct command;
- no Zoom-local command gains a durable fallback;
- runtime `canExecute` continues to use the Pane Zoom capability resolver.

The command-context restoration does not add another Zoom state owner,
companion resolver, or Bridge path.

## Consumer contracts

### Command bar

The command bar:

- requests `.commandBar` contextual presentation;
- uses `CommandContext` for `visibleWhen`;
- uses `AppCommandTargeting` to decide direct dispatch versus target drill-in;
- uses the dispatcher for enabled/dimmed state;
- uses `WorkspaceFocusedPane` presentation for the status strip;
- keeps command-bar scope ownership unchanged.

### Main menu

AppKit main-menu validation:

- requests `.mainMenu` contextual presentation;
- hides commands not exposed or whose requirements are unsatisfied;
- uses `canDispatch` for enabled state;
- continues to read title and shortcut from `AppCommandSpec`.

### Context menus

Context menus:

- request `.contextMenu` targeted presentation with their target kind;
- use `AppCommandTargeting` instead of local copies of supported target kinds;
- use targeted `canDispatch` for enabled state;
- retain explicit host-owned ordering and conditional sections.

The tab context menu targets the clicked tab, not whichever tab happens to be
active. It requests `.targeted(.tab)` presentation rather than
`.contextualTarget`: `CommandContext` contains active-tab and focused-pane
facts, so it must not filter an inactive clicked tab. Clicked-tab conditions
such as whether the tab is split remain host-owned conditional sections, and
targeted `canDispatch` validates the clicked tab immediately before execution.

Every command-backed row in that menu has a real `.tab` targeting declaration,
targeted capability check, and targeted execution path. Split, equalize,
save-arrangement, and floating-terminal actions resolve their inputs from the
clicked tab inside the execution owner. A floating terminal uses the clicked
tab's active pane CWD facet and falls back to a nil launch directory when that
facet is absent.

Rows that only open the arrangement panel are local presentation actions and
use `LocalActionSpec`. The tab context menu does not retain command-labelled
rows whose callback has no effect. A submenu title that groups split commands
is likewise a `LocalActionSpec`, not a borrowed command label.

Arrangement actions query the exact physical host surface for each placement:

- switching from an arrangement chip and saving from the panel use
  `.inlineControl`;
- the rename pencil and double-click gesture use `.inlineControl`;
- the arrangement-chip right-click Rename and Delete rows use `.contextMenu`;
- the tab context menu's Save Arrangement row uses `.contextMenu`.

The same command may therefore be resolved independently for its inline and
right-click placements. Each resolution converges on the same targeted
capability and dispatch path. The historical `.tab` target kind carries an
arrangement identity for switch, rename, and delete; this restoration does not
rename the target-kind taxonomy.

Removing the prior no-op tab-menu rows and making the floating-terminal row
functional are accepted behavior corrections for this surface, not behavior
that R22 requires preserving.

### Toolbars

Toolbars:

- request their exact toolbar surface;
- use `.targeted(.pane)` for controls attached to a physical pane, including
  normal-pane and terminal-Zoom controls, because the global
  `CommandContext` may describe another focused split;
- use `contextualTarget` only when both the current command context and the
  explicit target describe the same presentation subject;
- use contextual or targeted `canDispatch` for enabled state;
- use `AppCommandSpec` display/tooltip projections;
- retain explicit host-owned ordering, spacing, selected state, and callbacks.

The exact toolbar surface keeps the terminal-Zoom toolbar and normal pane
toolbar from accidentally sharing the Viewer exposure rule. Targeted
presentation keeps a physical pane's valid controls from disappearing merely
because another split owns global focus.

### Inline controls

Command-backed inline controls request `.inlineControl` with contextual,
targeted, or contextual-target presentation as appropriate.

`LocalActionSpec` remains correct for UI-only actions that are not dispatchable
app commands.

### Shortcuts

Shortcuts remain non-visual invocation paths. They do not request an
`AppCommandSurface`. Their command identity and binding still come from the
same spec/catalog, and execution still converges on the same dispatcher.

### Contextual and targeted dispatch

Dispatch preflight rejects:

- a command whose targeting mode does not support contextual dispatch;
- a targeted request whose kind is not declared;
- a missing or stale target;
- a request rejected by the execution owner.

The execution owner revalidates immediately before effects.

### IPC

IPC does not request an interactive command surface. It consumes
`AppCommandSpec.ipcExposure`, argument schema, and command identity.

Interactive exposure and IPC exposure may differ by design.

## Failure behavior

- Missing active tab: only requirements independent of an active tab may be
  satisfied.
- Missing focused pane: pane identity and pane-content requirements are absent.
- Stale drawer focus: resolver normalizes to a valid main/visible drawer/empty
  drawer result.
- Stale Zoom source: `hasActiveTerminalZoom` is absent even if a stale
  `ZoomPresentation` record exists.
- Unsupported presentation surface: the command is omitted from that host.
- Unsupported target kind: the command is omitted or rejected before execution.
- Capability changes after rendering: execution-time validation rejects the
  stale request.
- IPC metadata mismatch or insufficient privilege: IPC rejects before
  dispatch.

## Alternatives and tradeoffs

### Rename the current combined type only

This is the smallest textual change, but it keeps actual focus normalization
and command-policy projection coupled. The next drawer or presentation
requirement can again change a type consumed by unrelated status and command
surfaces.

Rejected.

### Keep `isHiddenInCommandBar` and add only a Zoom toolbar check

This ships the immediate Zoom UI, but it leaves command-bar exposure as a
special boolean and toolbar eligibility as local logic. It does not restore the
missing surface dimension or prevent recurrence.

Rejected for this later command-system change. The Pane Zoom change may use the
current system temporarily because it lands first.

### Introduce a mutable global command-surface atom

This would make presentation depend on whichever UI host most recently wrote
ambient state, complicate multiple windows, and conflate static host identity
with keyboard or presentation state.

Rejected.

### Route visibility through `canExecute`

This removes the intentional visible-but-disabled state and risks using
mutation authorization as display policy.

Rejected.

### Auto-generate menus and toolbars from specs

This centralizes placement but removes host control over native grouping,
spacing, selected state, and contextual sections. It is far beyond the
required consistency boundary.

Rejected.

### Accepted tradeoff

Every command must explicitly classify its interactive surfaces and targeting
mode. That increases catalog verbosity.

The cost is borne once at declaration time and buys deny-by-default exposure,
typed consumer convergence, and reviewable command intent. Hosts still own
their visual composition, so the catalog does not become a UI layout engine.

## Security and IPC context

Assets:

- workspace layout and pane state;
- terminal input capability;
- sidebar preferences;
- authenticated programmatic-control privileges;
- durable pane/tab/repo identities.

Trust boundaries:

- interactive in-process UI to dispatcher;
- authenticated IPC request to app adapter;
- public string handle to canonical durable target;
- app command to validated workspace/runtime action.

Required invariants:

- UI presence never grants IPC execution;
- headless IPC is opt-in per command;
- required privileges remain explicit and non-empty for headless mutation;
- target handle kind and membership are both validated;
- argument validation precedes execution;
- ephemeral Pane Zoom companions are not admitted as durable IPC pane targets;
- command context and surface policy are read-only presentation inputs.

Security non-goals:

- no new privilege classes;
- no authentication-mode changes;
- no IPC protocol or DTO expansion;
- no new unsafe/debug bypass;
- no BridgeWeb or worker trust-boundary change.

## Proof expectations

### Pure unit proof

Focused-pane resolver tables cover:

- main pane;
- valid drawer child;
- empty drawer;
- collapsed drawer;
- mismatched parent;
- minimized/stale active drawer child;
- missing active pane.

Command-context tables cover:

- no active tab;
- active tab and pane counts;
- drawer requirements;
- focused content requirement normalization;
- active terminal Zoom;
- stale Zoom source;
- non-terminal Zoom source;
- terminal Zoom while focus is in a non-terminal drawer child or Viewer.

Presentation-policy tables cover every surface/subject combination:

- unsupported surface omitted;
- contextual requirements enforced;
- target kind enforced;
- contextual-target enforces both;
- `.notPresented` never appears on an interactive surface.

### Command catalog contract proof

Structural tests prove:

- every `AppCommand` has exactly one `AppCommandSpec`;
- every spec has explicit surface and targeting policy;
- `.exposed` and targeted policies never carry empty sets;
- every `AppShortcut` maps to the matching command spec;
- command-bar rows mirror `.commandBar` specs;
- command-bar target drill-in follows `AppCommandTargeting`;
- tooltip projection remains spec-backed;
- no `isHiddenInCommandBar`, `FocusRequirement`,
  `WorkspacePaneFocus`, or `WorkspacePaneFocusDerived` references remain.

### Consumer integration proof

Focused tests prove:

- command bar and main menu agree on contextual visibility;
- context menus reject undeclared target kinds;
- arrangement inline and right-click placements request their exact declared
  surfaces and preserve Rename/Delete capability rechecks;
- the tab context menu targets the clicked tab, including when it is inactive;
- split-only tab rows follow the clicked tab rather than the active tab;
- no command-labelled tab-menu row lacks a targeted execution path;
- a clicked-tab floating terminal uses that tab's active-pane CWD and falls
  back to no launch directory when the CWD is absent;
- normal pane and terminal-Zoom toolbars use distinct surface identities;
- the Zoom-local Viewer is absent outside terminal Zoom and available in
  terminal Zoom according to its capability state;
- shortcuts still obey `ActiveKeyboardSurface` precedence and dispatch through
  the shared dispatcher;
- contextual and targeted dispatch reject unsupported modes and stale targets.

### IPC and security proof

Characterization tests prove:

- `command.list` public DTO shape is unchanged;
- every command's execution modes, IPC target kinds, required privileges, and
  argument schema are unchanged from the accepted post-Zoom baseline;
- UI-presentation commands remain non-headless;
- headless target handles still require authorization and targeted
  `canDispatch`;
- malformed arguments, wrong handle kinds, stale handles, missing active
  windows, and insufficient privileges remain rejected;
- ephemeral Zoom companion identities are not accepted as durable pane
  handles.

Catalog/IPC synchronization proof additionally covers every command identity:

- `command.list` count equals `AppCommand.allCases.count`;
- each command id and title are projected from its canonical definition;
- interactive surface/targeting changes cannot change IPC execution modes,
  durable target kinds, privileges, argument schemas, or encoded DTO keys;
- exhaustive privilege and durable-target-kind switches continue to force a
  classification for new `AppCommand` identities.

### Quality and manual proof

The implementation plan must operationalize:

- focused Swift tests first;
- the full applicable command/IPC test suites;
- repository lint and format gates;
- a native debug app run confirming unchanged menus, command bar, shortcuts,
  normal pane toolbar, and terminal-Zoom toolbar.

Manual proof is behavior characterization, not a request to redesign the UI.

## Non-goals

- Implementing or redesigning Pane Zoom.
- Choosing a new Zoom-local Viewer command identity.
- Changing retained Viewer lifecycle.
- Changing Bridge Review/Files behavior.
- Changing BridgeWeb protocol, worker, transport, activity, construction
  identity, Git scheduling, or foreground admission.
- Adding commands, shortcuts, menus, toolbar controls, or IPC methods.
- Auto-generating visual layout from the catalog.
- Introducing a mutable command-context or command-surface atom.
- Replacing `ActiveKeyboardSurface`.
- Renaming the entire target-kind taxonomy.
- Changing IPC privileges, authentication, handles, or public schemas.
- Unrelated command catalog cleanup.

## Open questions

No product decision is required to implement this contract.

The implementation plan must inventory the accepted post-Zoom command catalog
and record each existing interactive host in the explicit surface policy. If
the inventory reveals that a command is currently presented on one host but
has no agreed semantic meaning there, that is a product-design contradiction,
not permission to silently remove or add the command.

## Acceptance boundary

The restoration is accepted when:

- command terminology describes command policy rather than attention state;
- actual workspace pane focus has a separate pure resolver and value;
- every interactive command exposure is typed and deny-by-default;
- command context, targeting, keyboard routing, capability, validation, and IPC
  remain distinct;
- Pane Zoom's terminal-source requirement survives unchanged;
- all consumers use the same catalog without changing accepted behavior;
- IPC and Bridge boundaries remain intact.
