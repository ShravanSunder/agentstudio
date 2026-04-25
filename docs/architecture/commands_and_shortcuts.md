# Commands and Shortcuts

## TL;DR

Four files own the command + shortcut system. Each has one job. Use this
doc as the decision tree before adding a new command, keystroke, or UI
hint — it's how you avoid creating parallel constants that drift.

| File | Owns |
|------|------|
| `Sources/AgentStudio/App/Commands/AppCommand.swift` | Command **identities** (the things you can dispatch). |
| `Sources/AgentStudio/App/Commands/AppShortcut.swift` | Keyboard **bindings** + contexts where they fire. |
| `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift` | `CommandSpec` — ties an `AppCommand` to its `AppShortcut` plus command-bar metadata. |
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
                                       │  CommandDispatcher   │
                                       │  → handler           │
                                       └──────────────────────┘

   command bar / button asks:                ┌──────────────────────┐
        "what's this command's hint?"  ◄─────│  CommandSpec or      │
                                             │  LocalActionSpec     │
                                             └──────────────────────┘
```

`AppCommand` is the identity. `AppShortcut` decides which keystrokes
fire it. `CommandSpec` exposes it in the command bar. `LocalActionSpec`
provides UI text for buttons/menus that aren't part of the command bar.

## Adding a new command — decision tree

1. **New command identity?** Add a case to `AppCommand` enum.
2. **Keyboard binding?** Add a case to `AppShortcut` with its trigger and
   contexts.
3. **Visible in the command bar / used in tooltips?** Add a `CommandSpec`
   entry in `AppCommand+Catalog.swift` that ties the command to the
   shortcut plus label / icon / `helpText`.
4. **UI button or menu item that isn't in the command bar?** Add a
   `LocalActionSpec` case for label / helpText / icon.

You almost never want to skip a layer. If you find yourself hardcoding
a key character in a view OR a label string in a controller, you're
about to create a parallel system — back up to step 1.

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

## Where constants live

This decision tree governs WHICH file holds a value. Misplacing a value
is the most common drift source — once a value lives in the wrong file,
two call sites will fork and diverge.

| Goes here | When the value… | Examples |
|-----------|-----------------|----------|
| `AppShortcut` | Is a keyboard binding (key + modifiers + contexts) | `cmd-shift-D` for `addDrawerPane`, raw `P` for empty-drawer alt |
| `AppPolicies.DragAndDrop` (or other AppPolicies subdomain) | Is a runtime behavioral rule that gates filtering, hit testing, ordering, what's accepted vs rejected | `drawerMaxRows = 2`, `paneRowSideZoneFloor = 24`, `paneRowSideZoneFraction = 0.25` |
| `AppStyles.General.Layout` (or other AppStyles subdomain) | Only changes how something LOOKS (paint width, font size, opacity) | `dropTargetMarkerWidth = 8`, `paneGap = 1` |
| `LocalActionSpec` (`actionSpec.helpText` etc.) | Is UI text shown in tooltips / buttons / menus | "Add Drawer Pane", "Add a drawer pane to the active pane" |

If a value SOMETIMES gates behavior and SOMETIMES is purely visual
(rare), prefer `AppPolicies` and have the visual layer read from it.
Behavior is harder to migrate later than presentation.

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
