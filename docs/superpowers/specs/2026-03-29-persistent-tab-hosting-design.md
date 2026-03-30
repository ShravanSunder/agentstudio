# Persistent Tab Hosting Design

**Date:** 2026-03-29

## Goal

Keep every tab's pane hierarchy alive in memory so switching tabs never removes terminal or webview panes from the AppKit window hierarchy.

## Problem

The current main content area uses one `NSHostingView<ActiveTabContent>` to render exactly one tab subtree at a time. When `store.activeTabId` changes, `ActiveTabContent.body` swaps from one tab's `FlatTabStripContainer` to another.

That causes SwiftUI to:

- dismantle the leaving tab's `PaneViewRepresentable` instances
- detach the leaving tab's pane subtree from the window (`window=false`)
- recreate or reattach the entering tab's pane subtree

This behavior is now clearly separated from the startup bug:

- Startup relaunch is fixed.
- New pane insertion is structurally healthy.
- Tab switching still churns because the architecture only keeps one tab subtree in the live SwiftUI/AppKit hierarchy.

## Why The Current Architecture Fails

`PaneTabViewController` owns one `splitHostingView`, and `ActiveTabContent` renders only the active tab:

```swift
if let activeTabId, let tab {
    FlatTabStripContainer(layout: tab.layout, ...)
}
```

That means inactive tabs are not hidden; they are absent from the view tree. For lightweight SwiftUI views this is acceptable. For heavy `NSViewRepresentable` content such as Ghostty surfaces and webviews, this destroys the exact invariant we want: background tabs staying alive in memory and remaining attached to the window hierarchy.

## Chosen Architecture

Move tab retention to AppKit.

`PaneTabViewController` will own one persistent content host per tab. Each host stays attached to the terminal container for the lifetime of its tab. Tab switching will show the selected host and hide the others, instead of replacing a single shared SwiftUI subtree.

### High-level shape

```text
PaneTabViewController
  terminalContainer
    tabHostView(tab A)  -> hidden/shown by AppKit
      NSHostingView<SingleTabContent(tabId: A)>
    tabHostView(tab B)  -> hidden/shown by AppKit
      NSHostingView<SingleTabContent(tabId: B)>
    tabHostView(tab C)  -> hidden/shown by AppKit
      NSHostingView<SingleTabContent(tabId: C)>
```

The key change is that the SwiftUI root stops selecting the active tab. AppKit selects the active host. Each SwiftUI tab subtree always renders the same tab ID for its entire lifetime.

## Core Design Decisions

### 1. One persistent AppKit host per tab

Each `Tab` gets a dedicated AppKit-owned host object, created once and removed only when the tab is actually closed.

Recommended form:

- `PersistentTabHostView`
- contains one `NSHostingView<SingleTabContent>`
- pinned to the shared `terminalContainer`
- inactive hosts use `isHidden = true`

This keeps the AppKit window ancestry stable for every pane in inactive tabs.

### 2. Replace `ActiveTabContent` with `SingleTabContent`

The main content root should stop reading `store.activeTabId`.

Instead:

- `SingleTabContent(tabId: UUID, ...)` renders exactly one tab
- it reads `store.tab(tabId)` and the pane state for that specific tab
- if the tab no longer exists, the host becomes eligible for removal by `PaneTabViewController`

This gives each tab subtree stable identity independent of selection changes.

### 2a. Remove closure-driven subtree identity churn

Per-tab hosts fix cross-tab teardown, but they do not automatically prevent teardown *within* a tab.

If `SingleTabContent` continues to build `FlatTabStripContainer` with fresh closure values on every `@Observable` update, SwiftUI can still treat the container subtree as newly constructed and dismantle representables even though the tab host itself stayed alive.

So the design must also replace closure props used for pane actions and drop routing with a stable reference type owned by AppKit.

Recommended form:

- `PaneTabActionDispatcher` or equivalent `@MainActor` reference type
- owned by `PaneTabViewController`
- passed into `SingleTabContent` as a stable object reference
- exposes methods for:
  - pane action dispatch
  - drop acceptance
  - drop commit
  - split persistence / resize-finalization actions that currently flow through `onPersist`

This dispatcher cannot stop at `SingleTabContent`. It must replace closure props throughout the visible tab subtree, including:

- `FlatTabStripContainer`
- `FlatPaneStripContent`
- `PaneLeafContainer`
- `CollapsedPaneBar`
- `FlatPaneDivider`
- `DrawerPanelOverlay`
- `SplitContainerDropCaptureOverlay`

This keeps the visible tab subtree stable across normal store changes such as:

- `viewRevision`
- active pane changes
- minimized/zoomed changes
- tab metadata changes

The goal is not just “persistent tab hosts,” but “persistent tab hosts plus stable within-tab subtree identity.”

Without this deeper replacement, the failure mode just moves:

```text
before:
  cross-tab teardown from one active-tab hosting tree

after per-tab hosts only:
  within-tab teardown from closure-heavy parent views rebuilding
```

### 3. AppKit owns tab visibility

`PaneTabViewController` becomes responsible for:

- creating a host when a new tab appears
- removing a host when a tab is closed
- toggling host visibility when `activeTabId` changes
- ensuring focus and geometry sync target only the visible host

This fits the existing AppKit-first architecture and keeps lifecycle control out of SwiftUI conditionals.

### 3a. Concrete tab host, not generic infrastructure

We do not need a reusable generic `TabContentHostView<Root>`.

The problem is specific:

- one tab
- one `NSHostingView<SingleTabContent>`
- one persistent AppKit container

So the preferred implementation is a concrete tab host type, for example:

- `PersistentTabHostView`

This keeps the change surface small and avoids introducing a generic abstraction that the codebase does not otherwise need.

### 4. ViewRegistry remains pane-scoped

`ViewRegistry` already maps pane IDs to persistent `PaneHostView`s. That remains valid.

The new design does not replace `ViewRegistry`. It adds a tab-level retention layer above it:

- `ViewRegistry` keeps pane hosts stable
- `PaneTabViewController` keeps tab content hosts stable

Together they prevent both pane-level and tab-level churn.

## Data Flow

### Tab creation

1. User creates a tab.
2. `WorkspaceStore` mutates tab state.
3. `PaneTabViewController` observes the new tab ID.
4. It creates a persistent tab content host for that tab.
5. The host renders `SingleTabContent(tabId: newTabId)`.
6. The new host is shown if it is the active tab.

### Tab switch

1. User selects another tab.
2. `WorkspaceStore.activeTabId` changes.
3. `PaneTabViewController` hides the old host and shows the new host.
4. The old tab's SwiftUI subtree remains attached but hidden.
5. Terminal/webview pane hierarchies stay alive; no `dismantleNSView`, no `window=false`.

### Tab close

1. User closes a tab.
2. `WorkspaceStore` removes the tab.
3. `PaneTabViewController` removes that tab's persistent host.
4. Only then is the tab subtree dismantled.

## Invariants

The implementation should enforce these invariants:

1. A tab switch never calls `PaneViewRepresentable.dismantleNSView` for panes that belong to still-existing tabs.
2. A tab switch never causes `Ghostty.SurfaceView.viewDidMoveToWindow window=false` for panes in still-existing tabs.
3. Creating a new tab creates one new tab host and leaves existing tab hosts attached.
4. Closing a tab removes only that tab's host.
5. Startup restore creates the active tab host once and does not replace it during launch.

## Testing Strategy

### Unit / controller tests

Add tests proving:

- switching tabs reuses the same per-tab host objects
- switching away from a tab and back returns to the same host identity
- adding a tab creates one additional host without replacing existing ones
- closing a tab removes only its host

### Architecture tests

Add assertions proving:

- `PaneTabViewController` no longer relies on a single active-tab `NSHostingView`
- the main SwiftUI root for tab content is tab-scoped, not active-tab-scoped

### Runtime trace checks

On manual runs, confirm:

- no `dismantleNSView` on tab switch
- no `window=false` / `reparent=true` on tab switch for still-existing tabs
- no `dismantleNSView` on ordinary within-tab state changes such as focus changes, `viewRevision` bumps, or pane minimize/expand within the active tab

## Tradeoffs

### Benefits

- Matches the desired mental model: tabs stay alive in the background
- Prevents terminal/webview detach churn on tab switch
- Fits the AppKit-first architecture already used by the app
- Keeps lifecycle ownership explicit and inspectable

### Costs

- More AppKit container management in `PaneTabViewController`
- Higher memory usage because all tabs stay alive at once
- More tab-host bookkeeping when tabs are added, removed, or restored
- Potentially higher GPU and renderer residency cost because inactive terminal and webview panes remain attached and alive

These costs are accepted for now because the product requirement is “all tabs stay alive.”

## Non-Goals

This design does not try to:

- optimize inactive-tab memory or GPU usage
- change pane persistence or layout semantics
- solve narrow-pane redraw behavior by itself
- refactor the entire pane hosting system beyond the tab-retention boundary

## Recommendation

Implement per-tab persistent AppKit hosts now.

This directly solves the remaining structural bug with the least ambiguity: it removes the single-host active-tab swap that current logs show as the source of tab-switch teardown.
