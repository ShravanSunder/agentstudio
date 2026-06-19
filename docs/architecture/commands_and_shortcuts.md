# Commands and Shortcuts

## TL;DR

Four files own the command + shortcut system. Each has one job. Use this
doc as the decision tree before adding a new command, keystroke, or UI
hint — it's how you avoid creating parallel constants that drift.

| File | Owns |
|------|------|
| `Sources/AgentStudio/App/Commands/AppCommand.swift` | Command **identities** (the things you can dispatch). |
| `Sources/AgentStudio/App/Commands/AppShortcut.swift` | Keyboard **bindings** + contexts where they fire. |
| `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift` | `AppCommandSpec` — ties an `AppCommand` to its `AppShortcut` plus command-bar metadata. |
| `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift` | `LocalActionSpec` — UI **presentation** for tooltips, button labels, menu items. |

## The four layers

```
                                     ┌──────────────────────┐
   user presses key                   │  AppShortcut         │
        │                            │  (key + context)     │
        ▼                            └──────────┬───────────┘
   ┌──────────────────────┐                    │ resolves to
   │  ShortcutDecoder     │                    ▼
   │  (event → trigger)   │            ┌──────────────────────┐
   └──────────┬───────────┘            │  AppCommand          │
              │                        │  (dispatchable id)   │
              └─── matches in context ─►└──────────┬───────────┘
                                                  │ executed by
                                                  ▼
                                       ┌──────────────────────┐
                                       │ AppCommandDispatcher │
                                       │ → handler            │
                                       └──────────────────────┘

   command bar / button asks:                ┌──────────────────────┐
        "what's this command's hint?"  ◄─────│ AppCommandSpec or    │
                                             │ LocalActionSpec      │
                                             └──────────────────────┘
```

`AppCommand` is the identity. `AppShortcut` decides which keystrokes
fire it. `AppCommandSpec` exposes it in the command bar. `LocalActionSpec`
provides UI text for buttons/menus that aren't part of the command bar.

## Command planes

The command system has multiple planes. Use the narrowest plane that owns the
behavior:

```text
┌─ Command Plane Decision Map ────────────────────────────────────┐
│ AppCommand + AppCommandSpec                                      │
│   app command identity, shortcut metadata, command-bar rows      │
│                                                                  │
│ WorkspaceActionCommand                                           │
│   resolved workspace graph mutations: tabs, panes, drawers,      │
│   arrangements, worktrees, orphaned panes, repairs               │
│                                                                  │
│ PaneRuntimeCommand                                               │
│   one targeted pane runtime: terminal input/scroll/prompt jump,  │
│   browser navigation, diff/editor/runtime-specific operations    │
│                                                                  │
│ UI presentation                                                  │
│   command bar, picker, sheet, panel, prompt                      │
│                                                                  │
│ Runtime events                                                   │
│   facts after work happened; waits, subscriptions, replay        │
└──────────────────────────────────────────────────────────────────┘
```

Commands ask owners to do work. Runtime events report facts after work happened.
Do not route commands through EventBus, and do not make `command.execute`
silently present UI.

## Adding a new command — decision tree

1. **New command identity?** Add a case to `AppCommand` enum.
2. **Keyboard binding?** Add a case to `AppShortcut` with its trigger and
   contexts.
3. **Visible in the command bar / used in tooltips?** Add a `AppCommandSpec`
   entry in `AppCommand+Catalog.swift` that ties the command to the
   shortcut plus label / icon / `helpText`.
4. **UI button or menu item that isn't in the command bar?** Add a
   `LocalActionSpec` case for label / helpText / icon.

You almost never want to skip a layer. If you find yourself hardcoding
a key character in a view OR a label string in a controller, you're
about to create a parallel system — back up to step 1.

## Choosing the execution owner

`AppCommandDispatcher` can route to two handler families:

| Handler | Owns | Examples |
|---------|------|----------|
| `ShellCommandHandling` (`AppDelegate`) | App/window/sidebar/command-bar shell actions that do not need pane-local focus or drawer resolution. | `newWindow`, `closeWindow`, `showCommandBarEverything`, `toggleSidebar`, `showInboxNotifications`, `showWorktreeSidebar`, sign-in flows. |
| `WorkspaceCommandHandling` (`PaneTabViewController`) | Tab, pane, drawer, and workspace actions that need active pane state, drawer focus, pane target resolution, or workspace validation. | `toggleDrawer`, `addDrawerPane`, `openPaneLocationInEditorMenu`, `openPaneLocationInFinder`, `showPaneInboxNotifications`, focus and layout commands. |

If a command operates on a pane, drawer, or pane-adjacent control, it
belongs in `PaneTabViewController`. Do not route pane-local commands
through `AppDelegate` and then infer the active pane from
`WorkspaceStore`; that bypasses the drawer-aware focus and selection
helpers used by the rest of the pane system.

`showPaneInboxNotifications` is pane-scoped even though the bell control
lives in the pane drawer toolbox. Its target is the active parent pane
plus that pane's drawer children. It must stay enabled for a focused
parent pane even when the drawer is closed or empty.

The drawer command pattern is:

```text
AppShortcut → AppCommand → AppCommandDispatcher
  → PaneTabViewController.execute(...)
  → drawer-aware target resolver
  → atom/binding read by DrawerIconBar
```

The command bar uses the same `AppCommandDispatcher.dispatch(...)` path as
keyboard shortcuts. If a command works from a button but not from
`Cmd-P`, the execution owner is probably wrong or the command is using a
side channel instead of the same binding/state model as the button.

Programmatic control uses the same command metadata, but it does not treat
command-bar presentation as command execution. `command.list` projects
`AppCommandSpec` IPC metadata for discovery, including execution mode, target
handle kinds, and required privileges. `command.execute` is still reserved for
headless semantic commands and exposes command-bar presentation explicitly as
`ui.commandBar.open`; see
[AgentStudio IPC Architecture](agentstudio_ipc_architecture.md#command-and-ui-presentation-boundary).
If a command row only opens a chooser or requires interactive input, add a
semantic IPC method with explicit parameters before exposing it through
`command.execute`.

## Navigation And Terminal Shortcut Map

| Command | Shortcut | Owner | Notes |
| --- | --- | --- | --- |
| `selectTab1...9` | `⌘1...9` | `PaneTabViewController` | Selects tab ordinal in the active workspace window. |
| `prevTab` | `⌘J` | `PaneTabViewController` | Selects previous tab in the active workspace window. |
| `nextTab` | `⌘L` | `PaneTabViewController` | Selects next tab in the active workspace window. |
| `focusPane1...9` | `⌥1...9` | `PaneTabViewController` | Focuses visible pane ordinal in the active arrangement. |
| `switchArrangement` | `⌘⌥I` | `PaneTabViewController` + arrangement panel presentation atom | Shows the arrangement surface for the active tab. |
| `previousArrangement` | `⌘⌥J` | `PaneTabViewController` | Selects previous arrangement in the current tab. |
| `nextArrangement` | `⌘⌥L` | `PaneTabViewController` | Selects next arrangement in the current tab. |
| `scrollToBottom` | `⌘⇧K` | Terminal runtime | Terminal-owned; dispatches `scroll_to_bottom`. |
| `scrollPageUp` | `⌘⇧I` | Terminal runtime | Terminal-owned; dispatches `scroll_page_up`. |
| `jumpToPreviousPrompt` | `⌘⇧J` | Terminal runtime | Terminal-owned; dispatches `jump_to_prompt:-1`. |
| `jumpToNextPrompt` | `⌘⇧L` | Terminal runtime | Terminal-owned; dispatches `jump_to_prompt:1`. |
| `editPaneNote` | `⌘⌥⇧N` | `PaneTabViewController` | Opens the note editor for the active main pane only. |
| `copyCurrentPanePath` | `⌘⌥⇧O` | `PaneTabViewController` | Copies the active main pane's live cwd, falling back to launch directory. |
| `showInboxNotifications` | `⌘U` | `AppDelegate` shell | Shows the inbox sidebar notification surface. |
| `showPaneInboxNotifications` | `⌘⇧U` | `PaneTabViewController` | Shows notifications scoped to the active pane/drawer family. |
| Ghostty clear scrollback | none | `GhosttySurfaceView` host override | `⌘K` is swallowed and never forwarded to Ghostty. |

## Command Bar Scope Ownership

The command bar is split by ownership, not by implementation convenience:

| Scope | Owns | Does not own |
|-------|------|--------------|
| `>` Commands | Dispatchable verbs: close, rename, copy current pane path, edit pane note, arrangement commands. | Repo/worktree browsing. |
| `$` Pane | Existing pane and tab navigation. Search includes pane title, note, tab title, repo/worktree context, and cwd identity. | Opening new locations or path-management actions. |
| `#` Repo | Locations and opening: repos, worktrees, worktree path commands, opening a new pane, and navigating to existing panes for that worktree. | Generic verbs and arbitrary pane selection. |

`#` is an object navigator. Root rows represent repos. Repo rows drill into
worktrees. Worktree rows drill into actions for that concrete filesystem
location. A chevron means Return drills in; no chevron means Return executes.
Container rows may expose skip-ahead shortcuts such as `⌘↩` or `⌥↩`; leaf rows
do not invent modifier variants unless there is a separate, explicit action.

Path actions use `LocalActionSpec.copyPath` and
`LocalActionSpec.revealInFinder` for labels and icons. The execution helper is
shared so sidebar context menus and command-bar rows do not drift.

## Multiple bindings per command — `alternateTriggers`

A command can have one **primary** trigger plus any number of
**alternate** triggers. Use this when a command needs to fire under a
different keystroke shape in a specific context.

Example — `addDrawerPane`:

```swift
case .addDrawerPane:
    return .init(
        trigger: .init(key: .character(.d), modifiers: [.command, .shift]),
        alternateTriggers: [
            .init(key: .character(.p), modifiers: [])
        ],
        contexts: [.global, .terminalAppOwned, .emptyDrawer]
    )
```

  ▸ **Primary**: `cmd-shift-D` — fires globally and in
    `terminalAppOwned` context. Shows in the command bar.
  ▸ **Alternate**: raw `P` (no modifier) — fires only in
    `.emptyDrawer` context. Shown in the empty-drawer hint.

Both dispatch the SAME `AppCommand.addDrawerPane`. The display layer
asks for the right one per context via
`AppShortcut.addDrawerPane.displayKeyBinding(in: .emptyDrawer)`.

## Contexts

`ShortcutContext` gates **where** a binding fires. Each binding declares
which contexts it belongs to.

| Context | Where it fires |
|---------|----------------|
| `.global` | Anywhere — installed via the app's local key monitor. |
| `.terminalAppOwned` | Inside a terminal pane host (terminal owns key routing first). |
| `.managementLayer` | When management layer is active (raw character bindings without modifiers are common here). |
| `.emptyDrawer` | Drawer is open + empty + focused. Raw-character bindings here MUST be gated upstream on a neutral responder so text fields keep receiving keystrokes. |

Add a new context only when an existing one would cause cross-routing
(a binding firing in a place it shouldn't). Don't add contexts for
"nice to organize" reasons — the routing layer enumerates contexts to
find a match, so each new context is a small cost on every keystroke.

## Keyboard Surface Contract

Keyboard interpretation resolves in this precedence order:

1. Command-bar activation reservation.
2. `ActiveKeyboardSurface.commandBar(scope:)`
3. `ActiveKeyboardSurface.transient(kind:)`
4. `ActiveKeyboardSurface.stable(owner:)`

Stable owners are long-lived focus regions:

- `.mainWindowChain`
- `.managementLayer`
- `.sidebar(.repos)`
- `.sidebar(.inbox)`
- `.otherWindow`

Command bar is a privileged overlay surface. While active, it owns keyboard
interpretation through its AppKit panel and local command-bar router. Its
activation shortcuts remain available from workspace-owned surfaces even when a
pane-local transient surface is active. Command bar surface state is scoped to
the workspace window that presented the panel, so an open command bar in one
workspace window does not suppress or reclassify shortcuts in another workspace
window.

The `⌘T` repo command-bar activation is named `AppShortcut.newTab` at the
shortcut layer but dispatches `AppCommand.showCommandBarRepos`. It belongs in
both `.global` and `.terminalAppOwned` contexts so a focused terminal pane can
decode it directly rather than relying on AppKit main-menu fallback.

Command bar activation is not a transient-surface allowance. It is a
higher-precedence reservation checked before active surface policy. The
reserved activations are `⌘T`, `⌘P`, `⌘⇧P`, and `⌘⌥P`; they are still blocked
when the stable owner is `.otherWindow`.

Transient surfaces are temporary pane-local keyboard islands:

- `.tabRename(tabId:)`
- `.arrangementPanel(tabId:)`
- `.arrangementRename(tabId:arrangementId:)`
- `.paneInbox(parentPaneId:)`
- `.editorChooser(paneId:)`
- `.paneNote(paneId:)`

Transient surfaces suppress app/global/management shortcuts by default while
their local responder handles local keys such as Return, Escape, arrows, and
number selection. A transient surface may explicitly allow a small set of
app-owned shortcuts it owns. Those allow/block decisions live in
`AppShortcutDispatchPolicy` as exhaustive switches; adding an `AppShortcut` or
`TransientKeyboardSurfaceKind` must force a compile-time classification.

Current surface-owned app shortcuts:

- `.arrangementPanel(tabId:)` allows `.previousArrangement`, `.nextArrangement`,
  `.prevTab`, `.nextTab`, and `selectTab1...9` so the user can jump tabs
  without closing the panel first.
- `.tabRename(tabId:)`, `.arrangementRename(tabId:arrangementId:)`,
  `.paneInbox(parentPaneId:)`, `.editorChooser(paneId:)`, and
  `.paneNote(paneId:)` own no app shortcuts.

SwiftUI/AppKit surfaces that know their owning workspace window pass that
`workspaceWindowId` into registration; the key/focused-window fallback is only
a last-resort resolution path. A transient surface keeps the same workspace
owner across kind changes such as arrangement panel to arrangement rename.

Arrangement panel presentation is tab-local. Command dispatch may create a
request in `ArrangementPanelPresentationAtom`, but the tab bar or collapsed bar
consumes that request only when its tab matches. Switching tabs while the tab
bar arrangement panel is open closes that panel instead of retargeting it to
the new active tab. Pane inbox popovers are pane-local panels; inbox sidebar
remains the stable `.sidebar(.inbox)` surface.

This suppression intentionally includes destructive global shortcuts such as
`closeWindow`. When a transient popover or editor is open, local cancellation
or close behavior belongs to that responder; the workspace window should not
close from an app-level shortcut underneath it.

Repo sidebar and inbox sidebar are separate stable keyboard surfaces. They are
tested by setting sidebar visibility, selected surface, and sidebar focus; they
do not require a shortcut that creates the surface.

## Displaying the bound key in the UI

Use the helper, never reach for the raw character:

```swift
Text("Press \(AppShortcut.addDrawerPane
        .displayKeyBinding(in: .emptyDrawer)?
        .displayString ?? "") to \(LocalActionSpec.addDrawerPane
        .actionSpec.helpText.lowercased())")
```

`displayKeyBinding(in:)` returns the alternate trigger when the context
prefers one (today only `.emptyDrawer` does), otherwise the primary.
`KeyBinding.displayString` formats as `⌘⇧D` / `P` / `↑` etc.

If the context's binding is non-character (an arrow, escape), the
helper returns `nil` — handle that case explicitly.

## Tooltips, help text, and compact control copy

`ActionSpec.helpText` is descriptive command help. It is appropriate for command
palette rows, menus, accessibility descriptions, and other places where the
user is reading an action description.

Icon buttons and dense toolbars need compact control text instead. For
command-backed controls, use `CommandSpec.controlToolTip(...)` so labels and
shortcuts stay centralized. For UI-only controls, use
`ActionSpec.controlToolTip(...)` from the owning `LocalActionSpec.actionSpec`.
SwiftUI `.help(...)`, AppKit `toolTip`, and custom hover-tooltip presenters
should all read from the same compact tooltip source for a given control.

Do not build one oversized tooltip by concatenating multiple command or local
action help strings. If a control opens a menu or summarizes several actions,
give that control one short tooltip such as "Clear notifications"; keep the
longer action-specific descriptions on the individual menu items or command
rows.

Shortcut text still comes from `AppShortcut.displayKeyBinding(in:)` when the
shortcut is app-wide. Feature-local keyboard shortcuts should use a small helper
near that feature's keyboard router and pass the display string into
`controlToolTip(...)`; do not promote a local shortcut into `AppShortcut` only
to render a tooltip.

## Where constants live

This decision tree governs WHICH file holds a value. Misplacing a value
is the most common drift source — once a value lives in the wrong file,
two call sites will fork and diverge.

| Goes here | When the value… | Examples |
|-----------|-----------------|----------|
| `AppShortcut` | Is a keyboard binding (key + modifiers + contexts) | `cmd-shift-D` for `addDrawerPane`, raw `P` for empty-drawer alt |
| `AppPolicies.DragAndDrop` (or other AppPolicies subdomain) | Is a runtime behavioral rule that gates filtering, hit testing, ordering, what's accepted vs rejected | `drawerMaxRows = 2`, `paneRowSideZoneFloor = 24`, `paneRowSideZoneFraction = 0.25` |
| `AppStyles.General.Layout` (or other AppStyles subdomain) | Only changes how something LOOKS (paint width, font size, opacity) | `dropTargetMarkerWidth = 8`, `paneGap = 1` |
| `LocalActionSpec` (`actionSpec.label`, `actionSpec.helpText`, `actionSpec.controlToolTip`) | Is UI text shown in buttons, menus, command rows, or compact tooltips | "Add Drawer Pane", "Add a drawer pane to the active pane", "Clear notifications" |

If a value SOMETIMES gates behavior and SOMETIMES is purely visual
(rare), prefer `AppPolicies` and have the visual layer read from it.
Behavior is harder to migrate later than presentation.

Use `AppStyles` only when changing the value cannot alter routing,
validation, retention, state transitions, event emission, or which
commands are accepted. Shared UI controls, such as sidebar search
fields, should read visual constants from `AppStyles` and receive all
feature behavior through values and closures. If changing the value can
alter behavior, it belongs in `AppPolicies`.

## Adding a raw-character contextual shortcut

A common pattern: a single keystroke (no modifiers) that fires only in
one UI context. Example: `P` in empty drawer creates the first pane.

Steps:

1. Add the context to `ShortcutContext` if it doesn't exist.
2. Find the `AppShortcut` case (or add one) for the command.
3. Add the no-modifier `ShortcutTrigger` to `alternateTriggers`.
4. Include the context in the spec's `contexts` set.
5. Wire the gate site (e.g. `PaneTabViewController`) to use
   `ShortcutDecoder.shortcut(for: trigger, in: .yourContext)` — match
   the resolved `AppShortcut` against the expected case.
6. Wire the UI hint site to use
   `AppShortcut.yourCase.displayKeyBinding(in: .yourContext)`.
7. **Critical for raw characters** — gate on
   `PaneTabViewController.isNeutralResponderForRawCharacter(_:)` (or
   an equivalent neutral-responder check). Otherwise the keystroke
   will be intercepted while a text field has focus and steal user
   input.

## Common mistakes

  ▸ **Hardcoding the key character in a view's text label.** Drifts
    from the AppShortcut binding. Use `displayKeyBinding(in:)`.
  ▸ **Hardcoding the action description string.** Drifts from
    `LocalActionSpec`. Use `LocalActionSpec.foo.actionSpec.helpText`.
  ▸ **Creating a parallel constant for "this raw key fires this
    action".** Add an alternate trigger to the existing `AppShortcut`
    case. Parallel constants always drift — the AppShortcut system
    is the source of truth.
  ▸ **Skipping the neutral-responder gate for raw characters.** Will
    cause text fields to lose keystrokes. Check the existing helper
    or add one.
  ▸ **Adding a new ShortcutContext to disambiguate similar cases.**
    Usually means the existing routing isn't expressive enough; add
    an alternate trigger first.

## Testing

  ▸ Pure helpers (e.g. neutral-responder checks) get isolated unit
    tests — see `PaneTabViewControllerNeutralResponderTests`.
  ▸ End-to-end shortcut routing is harder to test through AppKit
    directly; pin the contract at the spec level (assert
    `AppShortcut.foo.spec.alternateTriggers` contains what you expect)
    plus the gate site's behavior with synthetic NSEvents.
  ▸ For UI hints, snapshot the displayed string from the same helpers
    the production code uses — don't hardcode the expected character
    (it should come from the spec).
