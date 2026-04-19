# Interaction Model — WIP

**Status:** Work in progress · Design thinking, not yet a decision
**Date:** 2026-04-18
**Related:** [Notification Inbox Spec](2026-04-17-notification-inbox-design.md)
**Scope:** clarifies "layer" vs "focus-scoped keys" across sidebar, inbox, management layer, CommandBar. Introduces `KeyboardOwner` as a derived abstraction for naming who owns keyboard interpretation at any moment. Captures the separation-of-concerns discussion before it gets baked into individual feature specs.

---

## 1. The insight hiding in plain sight

Management Layer is unique for a reason that's easy to miss. It's not just "a layer." It's a specific *kind* of keyboard modality that earns the name because of what it does to the app, not because of what sidebar it happens to touch.

```
┌─ What makes a "Layer" a Layer ──────────────────────────────────┐
│                                                                 │
│  • Visual disruption         — chrome changes, not subtle       │
│  • User-triggered            — explicit gesture, not derived    │
│  • Reinterprets normal keys  — keys that mean X now mean Y      │
│  • Global / modal            — affects the whole workspace      │
│  • Has a clear exit gesture  — you know how to leave            │
│                                                                 │
│  Today: ManagementLayer ✓ (all five boxes)                      │
│  CommandBar: ✓ mostly — it's a key window, not quite a layer    │
│  Inbox navigation: ✗ fails 3 of 5                               │
│  Repos navigation: ✗ fails 4 of 5                               │
└─────────────────────────────────────────────────────────────────┘
```

Sidebar surfaces (inbox, repos) don't earn Layer status. Calling them layers makes users wonder what "mode" they're in, when the honest answer is "none — you're just using the sidebar."

## 2. Three kinds of keyboard modality in the app

There are three — not one pattern applied repeatedly. Naming them keeps the model honest.

```
┌─ Kind 1: LAYERS (rare, explicit, modal) ────────────────────────┐
│                                                                 │
│  Global state shift. User toggles. Chrome changes dramatically. │
│  Same keys mean different things.                               │
│                                                                 │
│  Today:    ManagementLayer                                      │
│  Storage:  @Observable atom with isActive: Bool                 │
│  Monitor:  ManagementLayerMonitor                               │
│  Signal:   Strong chrome change (pane dim, panel transform)     │
│                                                                 │
│  Rule: add a new Layer only if all 5 criteria from §1 are met.  │
└─────────────────────────────────────────────────────────────────┘

┌─ Kind 2: KEY WINDOW (temporary, focus-grabbing) ────────────────┐
│                                                                 │
│  AppKit concept. A window becomes key; it gets all key events.  │
│  Built-in mechanism. Not state we manage.                       │
│                                                                 │
│  Today:    CommandBar panel                                     │
│  Storage:  NSWindow.isKeyWindow (AppKit owns it)                │
│  Monitor:  performKeyEquivalent on the panel                    │
│  Signal:   The panel is visible and focused. Obvious.           │
└─────────────────────────────────────────────────────────────────┘

┌─ Kind 3: FOCUS-SCOPED KEYS (common, derived, local) ────────────┐
│                                                                 │
│  Custom keys that only make sense when a particular surface     │
│  has focus. Active = (surface visible) AND (surface has focus). │
│  No stored "mode" — keys just work or don't based on focus.     │
│                                                                 │
│  Today:    Filter field in sidebar (⌘F via .filterSidebar)      │
│  Storage:  None (derived from @FocusState + visibility)         │
│  Monitor:  SwiftUI .keyboardShortcut() in view hierarchy, OR a  │
│            local NSViewRepresentable key monitor guarded by     │
│            @FocusState                                          │
│  Signal:   The surface is visible + has native focus ring       │
│                                                                 │
│  This is what Inbox and Repos navigation actually are.          │
└─────────────────────────────────────────────────────────────────┘
```

Kind 3 dispatches natively through SwiftUI `.keyboardShortcut()` and the AppKit responder chain. No central router is required for Kind 3 to function. However, there IS a first-class concept that names WHICH of these three modalities owns keys at any moment: `KeyboardOwner` (see §4). That concept is a derived abstraction consumed by CommandBar scope defaulting, debug/observability, and future unified dispatch — not a prerequisite for Kind 3 shortcuts to fire.

## 3. Separation of concerns

```
┌────────────────────────────────────────────────────────────────────┐
│                                                                    │
│ Concern            Stored?    Who reads it?                        │
│ ────────────────   ────────   ──────────────────────────────────   │
│ WorkspaceFocus     snapshot   CommandBar (visibility),             │
│ (pure, unchanged)  computed   command specs                        │
│                                                                    │
│ Sidebar surface    atom       Sidebar view switcher,               │
│ .repos | .inbox    field      KeyboardOwnerDerived precondition    │
│                                                                    │
│ Sidebar focus      atom       KeyboardOwnerDerived precondition    │
│ .sidebarHasFocus   field      (published by SwiftUI @FocusState;   │
│                    (runtime)  not persisted — reset each launch)   │
│                                                                    │
│ Management layer   atom       Pane chrome, drawer panel,           │
│ .isActive          bool       CommandDispatcher.canDispatch,       │
│                               KeyboardOwnerDerived                 │
│                                                                    │
│ Key-window id      atom       KeyboardOwnerDerived precondition    │
│ (WindowLifecycle   field      (already exists today; published     │
│  Atom.keyWindowId) (existing) by ApplicationLifecycleMonitor)      │
│                                                                    │
│ Native focus       AppKit     SwiftUI @FocusState,                 │
│ (first responder)  runtime    AppKit responder chain               │
│                                                                    │
│ KeyboardOwner      derived    CommandBar scope defaulting,         │
│ (computed enum)    function   debug/observability, future unified  │
│                               dispatcher, tests                    │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

Six concerns. Five of them are either existing or are modest additions to existing atoms. One (`KeyboardOwner`) is a derived abstraction — a value type produced by a stateless factory, never stored.

### `WorkspaceFocus` stays pure

`WorkspaceFocus` is a snapshot used exclusively for command visibility (`CommandSpec.satisfiedRequirements.isSubset(of:)` at `Core/State/MainActor/Atoms/WorkspaceFocus.swift`). Zero keyboard-routing uses today. Keep it that way — extending it with keyboard ownership corrupts the pattern and turns a snapshot into a mode router.

It MAY grow additive, pure-visibility fields (e.g., `sidebarSurface: .repos | .inbox | .none`) if a concrete `CommandSpec.isVisible` use case needs it. It MUST NOT grow keyboard-ownership semantics. Keyboard ownership lives in `KeyboardOwner` (§4), not in `WorkspaceFocus`.

## 4. `KeyboardOwner` — the derived abstraction

A derived, runtime-computed concept that names who owns keyboard interpretation at a given moment. It is:

- **NOT a layer** — layers are Kind 1 (see §2). Only `ManagementLayer` qualifies today.
- **NOT WorkspaceFocus** — different question (see §4.1).
- **NOT manually toggled or persisted.**
- A pure function over atom state, mirroring the `WorkspaceFocusDerived` pattern.

### 4.1 Why it is NOT WorkspaceFocus — explicit comparison

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  WorkspaceFocus                     KeyboardOwner               │
│  ────────────────                   ──────────────              │
│                                                                 │
│  Answers:                           Answers:                    │
│    "what workspace content           "who interprets the next   │
│     is active?"                       keystroke?"               │
│                                                                 │
│  Domain:                            Domain:                     │
│    workspace model                   AppKit + atoms +           │
│    (panes, tabs, repos)              management state           │
│                                                                 │
│  Consumers:                         Consumers:                  │
│    command visibility                shortcut routing,          │
│    (CommandSpec.isVisible)           CommandBar scope,          │
│                                      debug/observability        │
│                                                                 │
│  Orthogonal. Both can be active simultaneously.                 │
│  Example:                                                       │
│    WorkspaceFocus: terminal pane in repo X on tab Y             │
│    KeyboardOwner:  .otherWindow (user opened ⌘P)                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

They share a pattern (derived snapshot) but not a concept. One does not subsume the other.

### 4.2 Why it deserves its own abstraction (not just vocabulary)

```
┌─ Four reasons ────────────────────────────────────────────────┐
│                                                               │
│  1. It has an identity                                        │
│     You can point at it: "the keyboard owner is X."           │
│     That's a fact with a type, not a turn of phrase.          │
│                                                               │
│  2. It has meaningful transitions                             │
│     Sidebar gains focus → owner changes. Management layer     │
│     turns on → owner changes. Consumers may observe these.    │
│                                                               │
│  3. Its logic is centralized or it's duplicated               │
│     Without the abstraction, CommandBar, Inbox, Repos, tests, │
│     and any future consumer each reimplement the same         │
│     precondition chain. With the abstraction, one definition. │
│                                                               │
│  4. It mirrors an existing, working pattern                   │
│     WorkspaceFocusDerived proves this shape works —           │
│     stateless factory + value type. No novelty required.      │
└───────────────────────────────────────────────────────────────┘
```

### 4.3 Shape

```swift
/// Who owns keyboard interpretation at a given moment.
/// Derived. Never stored. Never manually set.
enum KeyboardOwner: Equatable, Sendable {

    /// Some other window is key (CommandBar panel, sheet, alert).
    /// AppKit routes keys there; the workspace is passive.
    case otherWindow

    /// Management Layer is active. Its monitor interprets keys.
    case managementLayer

    /// Sidebar is visible, has responder focus, and is showing
    /// a surface. The surface's local shortcuts are live.
    case sidebar(SidebarSurface)

    /// Main window is key and nothing above applies.
    /// Responder chain handles keys normally (pane content, etc.).
    case none
}

/// Stateless factory; mirrors WorkspaceFocusDerived.
@MainActor
struct KeyboardOwnerDerived {
    func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom
    ) -> KeyboardOwner {

        //  1. Workspace window must be key. Otherwise some other
        //     window (CommandBar panel, sheet, alert) has focus.
        guard windowLifecycle.isWorkspaceWindowKey else {
            return .otherWindow
        }

        //  2. Management Layer preempts sidebar ownership.
        if managementLayer.isActive {
            return .managementLayer
        }

        //  3. Sidebar owns keys if it is visible AND focused.
        if !uiState.sidebarCollapsed && uiState.sidebarHasFocus {
            return .sidebar(uiState.sidebarSurface)
        }

        //  4. Otherwise: responder chain handles keys normally.
        return .none
    }
}
```

`WindowLifecycleAtom.isWorkspaceWindowKey` is a computed read over existing state:

```swift
var isWorkspaceWindowKey: Bool {
    keyWindowId.map { registeredWindowIds.contains($0) } ?? false
}
```

The atom already tracks `keyWindowId` and `registeredWindowIds` today (see `Core/State/MainActor/Atoms/WindowLifecycleAtom.swift`) — this is a one-line accessor, not new storage.

### 4.4 Inputs: AppKit state published to atoms (the γ pattern)

Every input `KeyboardOwnerDerived` reads is atom-sourced. AppKit runtime facts are published into atoms via monitors — the existing pattern for AppKit ingress in this codebase (`ApplicationLifecycleMonitor`, `WindowLifecycleAtom`).

```
┌─ AppKit → monitor → atom → derived reader ─────────────────────┐
│                                                                │
│  AppKit event         →  Monitor         →  Atom               │
│  ────────────────────    ─────────────      ──────────────     │
│                                                                │
│  NSWindow.didBecomeKey   ApplicationLife    WindowLifecycle    │
│  NSWindow.didResignKey   cycleMonitor       Atom               │
│                          (exists today)     • keyWindowId      │
│                                             • registeredIds    │
│                                             (already tracked)  │
│                                                                │
│  SwiftUI @FocusState     onChange publisher UIStateAtom        │
│  inside root sidebar     inside SidebarCon-  • sidebarHas-     │
│  view                    tainerView           Focus (new)      │
│                                                                │
│  Then KeyboardOwnerDerived reads only atoms — zero AppKit      │
│  in the function, zero new seam patterns.                      │
└────────────────────────────────────────────────────────────────┘
```

This is **coherent with the existing architecture**. `CLAUDE.md` explicitly describes `ApplicationLifecycleMonitor` as "ingress-only and mutates lifecycle stores directly from AppKit callbacks." We are extending that pattern, not inventing a new one.

**Reactivity for free.** Consumers observing `uiState` or `windowLifecycle` via `@Observable` re-evaluate `KeyboardOwnerDerived.current(...)` naturally during SwiftUI view body evaluation. No special observation wiring. CommandBar scope defaulting becomes a one-line read during body evaluation.

**Testability for free.** Tests set atom state directly (`uiState.setSidebarHasFocus(true)`) and assert on `KeyboardOwnerDerived.current(...)`. No AppKit fakes required.

### 4.5 Placement

`Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift`

Mirrors `WorkspaceFocusDerived.swift` at the same location. Core because multiple features (CommandBar, Inbox, RepoExplorer, ManagementLayer observers) read it.

### 4.6 Implementation timing

**Implemented in v1** (LUNA-361). Consumer: CommandBar scope defaulting — when the user opens ⌘P with owner == `.sidebar(.inbox)`, CommandBar opens with the `.inbox` scope by default.

The inbox's custom shortcuts (⌥F, ⌥G, ⌥S, etc.) themselves fire natively via SwiftUI `.keyboardShortcut()` + AppKit responder chain; they do not call `KeyboardOwnerDerived` at runtime. But the type exists, is tested, and is consumed by CommandBar default-scope logic.

Future consumers:

1. **Repos navigation keymap** — when repos sidebar gains arrow-key navigation, it benefits from the same derived reader (symmetric with inbox).
2. **Debug / observability** — logging owner on keystrokes in debug builds.
3. **Future unified keyboard dispatcher** — if the three parallel interception mechanisms are ever unified, `KeyboardOwner` is the switch value.

### 4.7 Consumers (documented intent)

1. **Vocabulary in specs/docs.** Specs refer to "owner" when talking about keyboard state, grounded in a real type.
2. **CommandBar scope defaulting.** `isVisible: owner == .sidebar(.inbox)` → show inbox-scoped commands by default.
3. **Debug / observability.** Log owner on keystrokes in debug builds.
4. **Future unified dispatcher.** If the three parallel interception mechanisms (key window, management monitor, responder chain) are unified into a `KeyboardDispatcher`, owner is its switch value.
5. **Tests.** Assert owner in a readable way: `#expect(owner == .sidebar(.inbox))`.

## 5. Shortcut resolution pipeline

```
Keystroke arrives
       │
       ▼
┌─────────────────────────────────────────────────────┐
│ Is some non-workspace window key-window?            │  ← KeyboardOwner
│   (e.g., CommandBar panel, sheet, alert)            │    names this
│   YES → AppKit routes to that window's responder    │    level:
│         → CommandBar or whatever intercepts         │    .otherWindow
│   NO  → fall through                                │
└───────────────────────────┬─────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│ Is ManagementLayer.isActive?                        │  ← .management-
│   YES → ManagementLayerMonitor decides              │    Layer
│   NO  → fall through                                │
└───────────────────────────┬─────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│ AppKit responder chain                              │  ← .sidebar(…)
│   first responder gets first look                   │    when focus is
│   ├─ If focus is in sidebar filter → filter acts    │    in sidebar;
│   ├─ If focus is in inbox list → inbox .keyboard-   │    .none when
│   │   Shortcut() modifiers fire                     │    focus is in
│   ├─ If focus is in repos list → repos .keyboard-   │    pane/main
│   │   Shortcut() modifiers fire                     │    content
│   └─ Else → pane content handles it                 │
└─────────────────────────────────────────────────────┘
                            │
                            ▼
                        Global app shortcuts
                  (⌘I, ⌘S, ⌘T, ⌘P, ⌘W, etc.)
```

Each interception point corresponds to a `KeyboardOwner` case:
- Key window intercept → `.otherWindow`
- Management layer monitor → `.managementLayer`
- Responder chain, focus in sidebar → `.sidebar(surface)`
- Responder chain, focus elsewhere → `.none`

Global shortcuts are orthogonal to ownership. `KeyboardOwner` doesn't CHANGE dispatch — it NAMES what's happening.

**Inbox and repos custom keys (⌥F/⌥G/⌥S etc.) fit inside #3**, not as new mechanisms. They're standard responder-chain shortcuts that happen to be attached to views in the sidebar hierarchy. No new interception mechanism is added.

### Deferred architectural debt

Today the three interception points are parallel mechanisms (no unified dispatcher). As sidebar surfaces grow (inbox now, richer repos nav later), the responder-chain branch of this pipeline accumulates more `.keyboardShortcut()` attachments. That's fine for now. A future refactor could introduce a `KeyboardDispatcher` that switches on `KeyboardOwner` and replaces the parallel monitors with a single table-driven dispatch. Out of scope for LUNA-361; flagged.

## 6. Visual feedback — what communicates "where am I"

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│ KeyboardOwner state         Visual signal                       │
│ ──────────────────────      ──────────────────────────────      │
│ .none                       Standard app chrome                 │
│                                                                 │
│ .managementLayer            Strong existing chrome change       │
│                             (pane dim, panel transform, etc.)   │
│                             + toolbar button lit                │
│                                                                 │
│ .otherWindow                The non-workspace window itself is  │
│                             visible — CommandBar panel, sheet, │
│                             or alert. Signal is the window.     │
│                                                                 │
│ .sidebar(.inbox)            Sidebar content IS the inbox        │
│                             + inbox toolbar icon tinted         │
│                             + native focus ring / selection     │
│                                                                 │
│ .sidebar(.repos)            Sidebar content IS the repos tree   │
│                             + native focus ring / selection     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The "how will users know what layer they're on" concern dissolves when we stop calling sidebar surfaces layers. Visual signals for `.sidebar(...)` are already present:

- Sidebar is visibly showing this surface
- Sidebar has a visible focus ring / selection highlight

That's enough. No "INBOX MODE" badge. No confusion about modes because there is no mode — the user is using the sidebar, and the sidebar has focus.

Management Layer keeps its strong chrome change because it *is* modal and has earned the ceremony.

## 7. Applied to the Notification Inbox spec

```
┌─ DROP ──────────────────────────────────────────────────────────┐
│ • NotificationInboxLayerAtom                                    │
│ • CommandBarScope.inbox gated by "isActive"                     │
│ • Concept of "⌘I toggles a layer"                               │
└─────────────────────────────────────────────────────────────────┘

┌─ ADD ───────────────────────────────────────────────────────────┐
│ • UIStateAtom.sidebarSurface: .repos | .inbox                   │
│   (persisted; default .repos)                                   │
│ • UIStateAtom.sidebarHasFocus: Bool                             │
│   (not persisted — runtime-only; published from root sidebar    │
│   view's @FocusState onChange handler)                          │
│ • ⌘I as composite command (mirrors the existing                 │
│   MainSplitViewController.showSidebarFilter() pattern):         │
│     - ensure sidebar visible                                    │
│     - set sidebarSurface = .inbox                               │
│     - move focus to the inbox list (first row)                  │
│     - do not force focus move if CommandBar is key              │
│ • ⌘S as composite command:                                      │
│     - ensure sidebar visible                                    │
│     - set sidebarSurface = .repos                               │
│     - (don't force focus — respects current focus)              │
└─────────────────────────────────────────────────────────────────┘

┌─ KEEP ──────────────────────────────────────────────────────────┐
│ • WorkspaceFocus pure — does not grow to hold shortcut state    │
│ • ManagementLayer as it is — the one true layer                 │
│ • CommandBar key-window mechanism                               │
└─────────────────────────────────────────────────────────────────┘

┌─ REFERENCE ─────────────────────────────────────────────────────┐
│ • Inbox keymap documentation refers to KeyboardOwner as the     │
│   thing that names the keyboard state when inbox keys are live: │
│     "when KeyboardOwner == .sidebar(.inbox), ⌥F focuses the     │
│      search field"                                              │
│ • Inbox does NOT call KeyboardOwnerDerived at runtime — its     │
│   shortcuts dispatch natively via SwiftUI + responder chain.    │
└─────────────────────────────────────────────────────────────────┘
```

## 8. Surface selection — where does `sidebarSurface` live?

Feature atoms own their domain (clean). Surface selection (which view is currently showing in the sidebar) is a separate concern. Three options were considered:

```
┌─ Option A: each feature atom has `isShownInSidebar` flag ──────┐
│                                                                │
│  NotificationInboxAtom.isShownInSidebar: Bool                  │
│  RepoExplorerAtom.isShownInSidebar: Bool                       │
│                                                                │
│  PRO: fully feature-isolated                                   │
│  CON: two booleans that MUST be mutually exclusive —           │
│       enforcement is by convention, not by type.               │
│  CON: invariant "only one true" has no owner by default.       │
└────────────────────────────────────────────────────────────────┘

┌─ Option B: surface selection on existing UIStateAtom ──────────┐
│                                                                │
│  UIStateAtom (existing, Core)                                  │
│    + sidebarSurface: .repos | .inbox   (enum — type-enforced)  │
│    + sidebarHasFocus: Bool                                     │
│    + setSidebarSurface(...)                                    │
│    + setSidebarHasFocus(...)                                   │
│                                                                │
│  Feature atoms own only domain state (clean).                  │
│  Surface selection is type-safe (one value at a time).         │
│                                                                │
│  PRO: UIStateAtom already holds "view state"                   │
│       (expanded groups, colors, filter state) —                │
│       surface selection is a peer concept.                     │
│  PRO: one source of truth, type enforces mutex.                │
│  PRO: sidebarHasFocus sits naturally alongside                 │
│       sidebarSurface.                                          │
│  CON: UIStateAtom grows.                                       │
└────────────────────────────────────────────────────────────────┘

┌─ Option C: surface in a controller, not an atom ───────────────┐
│                                                                │
│  MainSplitViewController.currentSidebarSurface: SidebarSurface │
│                                                                │
│  PRO: "which view is showing" is naturally a controller concern│
│  CON: SwiftUI views reading an AppKit controller property      │
│       needs a seam (@Observable wrapper or env object)         │
│  CON: KeyboardOwnerDerived must then read from the controller, │
│       breaking the "reads only atoms" property                 │
└────────────────────────────────────────────────────────────────┘
```

**Chosen: Option B.** Reasons:

1. Type-enforced mutex. An enum makes "only one surface active" a compile-time guarantee.
2. `UIStateAtom` already holds view preferences of exactly this shape.
3. Feature atoms stay pure. `NotificationInboxAtom` knows nothing about "am I showing?" — it just holds notifications.
4. CommandBar scope gating is trivial: `isVisible: uiState.sidebarSurface == .inbox`.
5. Free persistence via existing `UIStateStore` (for `sidebarSurface` — `sidebarHasFocus` is runtime-only, not persisted).
6. Preserves the "KeyboardOwnerDerived reads only atoms" property (rules out Option C).

### Persistence note

- `sidebarSurface` — persisted in `UIStateStore`. User's last surface survives relaunch.
- `sidebarHasFocus` — NOT persisted. Runtime-only. Reset to false on launch (the sidebar doesn't auto-focus at startup).

## 9. Feature atoms — the growth picture

Feature slices for sidebar surfaces will grow. Worth checking forward compatibility.

### RepoExplorer growth trajectory

```
┌─ Today ────────────────────────────────────────────────────────┐
│  Features/Sidebar/                                             │
│    just views, no feature-owned atoms                          │
│    reads from Workspace atoms + UIStateAtom                    │
└────────────────────────────────────────────────────────────────┘

┌─ Near future (collections, UI state) ──────────────────────────┐
│  Features/RepoExplorer/State/                                  │
│    RepoExplorerAtom                                            │
│      • expanded group ids                                      │
│      • selected worktree id                                    │
│      • filter text                                             │
│      • sort preference                                         │
│    RepoCollectionsAtom           ← when collections land       │
│      • collections: [RepoCollection]                           │
│      • collection membership: [RepoId: CollectionId]           │
│      • collection ordering                                     │
│    RepoExplorerStore                                           │
│      • persists both atoms into one file (like WorkspaceStore  │
│        wraps multiple atoms)                                   │
└────────────────────────────────────────────────────────────────┘

┌─ Further out (probably) ───────────────────────────────────────┐
│    RepoExplorerSearchAtom       ← first-class repo search      │
│    RepoExplorerPinsAtom         ← pinned / favorite repos      │
│                                                                │
│    Each earns its own atom when it earns its own domain.       │
│    RepoExplorerStore can wrap them all if they persist         │
│    together.                                                   │
└────────────────────────────────────────────────────────────────┘
```

### How UIStateAtom's surface tag grows

```
v1 (inbox lands)
  sidebarSurface: .repos | .inbox

v2 (settings sidebar lands)
  sidebarSurface: .repos | .inbox | .settings

v3 (search sidebar lands)
  sidebarSurface: .repos | .inbox | .settings | .search

Each new surface adds one enum case.
UIStateAtom doesn't know what BACKS that surface (which feature
atom, which view) — it just holds the tag.
`KeyboardOwner.sidebar(SidebarSurface)` grows the same way.
```

### What growth does NOT change

- Surface selection stays on `UIStateAtom` as a thin enum.
- Feature atoms stay feature-scoped — they don't leak knowledge of sidebar presentation.
- Collections, pins, search — all land in `Features/RepoExplorer/State/`.
- ⌘S's composite command may take arguments (e.g., a collection id) — that's a command-plane concern, not an atom-placement concern.

## 10. Summary: the mental model

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Kinds of keyboard modality (§2)                                │
│  ───────────────────────────────                                │
│  • Layer          (rare, explicit, modal)                       │
│      — ManagementLayer is the only one                          │
│  • Key Window     (AppKit owns it)                              │
│      — CommandBar uses this                                     │
│  • Focus-scoped   (derived from focus + visibility)             │
│      — inbox, repos, future sidebar surfaces                    │
│                                                                 │
│                                                                 │
│  Where state lives                                              │
│  ──────────────────                                             │
│  • Feature atoms hold feature domain                            │
│      NotificationInboxAtom, RepoExplorerAtom, ...               │
│  • UIStateAtom holds thin view-state tags                       │
│      sidebarSurface: .repos | .inbox | ...                      │
│      sidebarHasFocus: Bool                                      │
│  • ManagementLayerAtom holds isActive bool                      │
│  • WindowLifecycleAtom holds key/focused window identity        │
│  • WorkspaceFocus remains a pure visibility snapshot            │
│                                                                 │
│                                                                 │
│  Derived abstractions (pure functions over atoms)               │
│  ──────────────────────────────────────────────                 │
│  • WorkspaceFocusDerived  (exists)                              │
│      → value for command visibility                             │
│  • KeyboardOwnerDerived   (v1 — in Core, per §4)                │
│      → value for keyboard ownership at a moment                 │
│                                                                 │
│                                                                 │
│  How shortcuts resolve (§5)                                     │
│  ─────────────────────────                                      │
│  1. Key window intercept (CommandBar, sheets)                   │
│  2. ManagementLayer monitor (when active)                       │
│  3. AppKit responder chain + SwiftUI .keyboardShortcut()        │
│  4. Global app shortcuts                                        │
│                                                                 │
│  KeyboardOwner names each level. It does not change dispatch.   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 11. Open questions / TBD

- **Unify keyboard dispatch?** Currently three parallel mechanisms (key window, management layer monitor, responder chain). The responder-chain branch accumulates more `.keyboardShortcut()` attachments as sidebar surfaces grow. Out of scope for LUNA-361; flagged as accumulating debt. `KeyboardOwner` is the switch value for such a dispatcher if we build one.
- **When does focus auto-move into the sidebar?** ⌘I moves focus to the inbox list (first row). ⌘S does NOT force focus — user may be typing filter into repos. Validate against real usage.
- **`WorkspaceFocus.sidebarSurface` (pure-visibility)?** Only add if a concrete `CommandSpec` needs it. Do not proactively extend.
- **How do multiple sidebars interact with split panes?** Not addressed — currently sidebar is window-level. If per-pane sidebars appear, surface state may need to move to a different atom.
- **Does `.otherWindow` need sub-cases?** Flat for v1 (no consumer distinguishes CommandBar from sheet from alert). Refine if a use case appears.

## 12. Next steps

1. Land this doc as WIP. Iterate.
2. Revise [`2026-04-17-notification-inbox-design.md`](2026-04-17-notification-inbox-design.md):
    - Drop `NotificationInboxLayerAtom`
    - Adopt `UIStateAtom.sidebarSurface` and `UIStateAtom.sidebarHasFocus`
    - ⌘I / ⌘S as composite commands
    - Reference `KeyboardOwner` as the naming concept (no code dependency)
    - Refactor §5 accordingly
3. `KeyboardOwnerDerived` is implemented in LUNA-361 (v1 consumer: CommandBar scope defaulting). Future consumers (repos navigation, debug logging, unified dispatcher) extend the same derived reader without re-design.
4. When ideas here solidify across real consumers, promote to `docs/architecture/interaction_model.md` (non-WIP).
5. Reference this doc from future specs that introduce new sidebar surfaces or keyboard semantics.
