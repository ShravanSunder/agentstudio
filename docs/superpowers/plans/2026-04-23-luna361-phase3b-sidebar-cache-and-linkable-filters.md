# LUNA-361 Phase 3b Sidebar Cache + Linkable Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split durable sidebar memory out of shell composition state, add recoverable per-slice persistence, add collapsible inbox groups, and make worktree notification pills open the inbox with a linkable filter.

**Architecture:** Workspace geometry stays on `WorkspaceMetadataAtom`; app-shell composition stays on `UIStateAtom`; durable sidebar memory moves to a new `SidebarCacheAtom`. Inbox filters travel through a short-lived `InboxFilterDraftAtom`, then the existing `.showInboxNotifications` command opens the inbox. Persistence recovery is broadened so each persisted store touched by this plan can survive corrupt slices without crashing or wiping unrelated state.

**Tech Stack:** Swift 6.2, Swift Testing, `@MainActor @Observable`, existing `AtomRegistry` / `AtomScope`, JSON persistence via `Codable`, `mise run lint`, `mise run test`.

---

## Scope Boundaries

This plan does not implement new Ghostty terminal event routing or the live OSC smoke matrix. That work lives in:

`docs/superpowers/plans/2026-04-23-luna361-phase3c-ghostty-terminal-intelligence-and-osc-smoke.md`

This plan does not move sidebar width. `WorkspaceMetadataAtom.sidebarWidth` is workspace/window geometry and remains owned by workspace metadata.

This plan does not move `UIStateAtom.sidebarCollapsed`, `UIStateAtom.sidebarSurface`, or `UIStateAtom.sidebarHasFocus`. Those are app-shell composition state.

## Hard Invariants

1. Hard cutover: no migration shims, no compatibility branches, no dual-read paths.
2. Composition state stays in `UIStateAtom`.
3. Workspace geometry stays in `WorkspaceMetadataAtom`.
4. Sidebar cache contains only durable UI memory that can default without breaking correctness.
5. Persisted corruption never crashes the app. A bad slice defaults; unrelated slices survive.
6. Tests follow the pyramid: pure unit tests first, integration tests for cross-atom flows, minimal mounted SwiftUI tests only where wiring cannot be proven otherwise.

## Ownership Model

```
WorkspaceMetadataAtom
  owns: sidebarWidth
  reason: workspace/window geometry

UIStateAtom
  owns: sidebarCollapsed, sidebarSurface, sidebarHasFocus
  reason: app-shell composition

SidebarCacheAtom
  owns: expandedGroups, checkoutColors, collapsedInboxGroups
  reason: durable sidebar memory
  key types: SidebarGroupKey, SidebarCheckoutColorKey, InboxNotificationGroupKey

InboxFilterDraftAtom
  owns: one pending InboxFilter?
  reason: short-lived open-inbox intent between worktree pill and sidebar mount
```

## File Structure

```
Sources/AgentStudio/Core/Models/
  InboxFilter.swift                                      create
  SidebarCacheKeys.swift                                 create typed key wrappers

Sources/AgentStudio/Core/State/MainActor/Atoms/
  SidebarCacheAtom.swift                                 create
  UIStateAtom.swift                                      modify
  InboxFilterDraftAtom.swift                             create
  AtomRegistry.swift                                     modify

Sources/AgentStudio/Core/State/MainActor/Persistence/
  SidebarCacheStore.swift                                create
  UIStateStore.swift                                     modify
  WorkspacePersistor.swift                               modify tests only if needed for per-slice recovery

Sources/AgentStudio/App/Boot/
  AppDelegate.swift                                      wire SidebarCacheStore / InboxFilterDraftAtom

Sources/AgentStudio/Features/InboxNotification/
  Models/InboxNotificationListModel.swift                filter + collapsed sections
  Components/InboxNotificationGroupHeader.swift          tappable collapse affordance
  Views/InboxNotificationSidebarView.swift               consume filter draft + chip + collapsed sections

Sources/AgentStudio/Features/RepoExplorer/
  RepoExplorerView.swift                                 read expansion/colors from SidebarCacheAtom
  RepoExplorerWorktreeRow.swift                          tap unread pill

Tests/AgentStudioTests/Helpers/
  ChaosStoreSeeder.swift                                 create

Tests/AgentStudioTests/Core/
  Models/InboxFilterTests.swift                          create
  State/MainActor/Atoms/SidebarCacheAtomTests.swift      create
  State/MainActor/Atoms/InboxFilterDraftAtomTests.swift  create
  State/MainActor/Persistence/*ChaosTests.swift          create/extend

Tests/AgentStudioTests/Features/
  InboxNotification/Models/InboxNotificationListModelTests.swift  extend
  InboxNotification/Views/InboxNotificationSidebarViewTests.swift extend
  RepoExplorer/RepoExplorerWorktreeRowTests.swift                 extend
```

## Task A1: Add ChaosStoreSeeder

**Files:**
- Create: `Tests/AgentStudioTests/Helpers/ChaosStoreSeeder.swift`

- [ ] **Step 1: Create the helper**

```swift
import Foundation

enum ChaosStoreSeeder {
    enum Flavor: CaseIterable {
        case missing
        case empty
        case truncatedJSON
        case wrongShape
        case sliceMissing
        case sliceTypeError
        case sliceUnknownEnum
        case unknownSchemaVersion
        case garbage
    }

    static func seed(_ flavor: Flavor, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch flavor {
        case .missing:
            try? FileManager.default.removeItem(at: url)
        case .empty:
            try Data().write(to: url, options: .atomic)
        case .truncatedJSON:
            try Data("{".utf8).write(to: url, options: .atomic)
        case .wrongShape:
            try Data("[1,2,3]".utf8).write(to: url, options: .atomic)
        case .sliceMissing:
            try Data(#"{"schemaVersion":1,"unknownSlice":{}}"#.utf8).write(to: url, options: .atomic)
        case .sliceTypeError:
            try Data(#"{"schemaVersion":1,"sidebarSurface":42}"#.utf8).write(to: url, options: .atomic)
        case .sliceUnknownEnum:
            try Data(#"{"schemaVersion":1,"sidebarSurface":"not-a-surface"}"#.utf8).write(to: url, options: .atomic)
        case .unknownSchemaVersion:
            try Data(#"{"schemaVersion":99999}"#.utf8).write(to: url, options: .atomic)
        case .garbage:
            try Data([0xff, 0x00, 0xde, 0xad, 0xbe, 0xef]).write(to: url, options: .atomic)
        }
    }
}
```

- [ ] **Step 2: Run helper compile check**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "ChaosStoreSeeder"
```

Expected: build succeeds or no tests match; helper compiles.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/Helpers/ChaosStoreSeeder.swift
git commit -m "test(persistence): add chaos store seeder

Co-authored-by: Codex <noreply@openai.com>"
```

## Task A2: Add SidebarCacheAtom

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/SidebarCacheAtom.swift`
- Create: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/SidebarCacheAtomTests.swift`

- [ ] **Step 1: Write failing tests**

Test defaults, repo group expansion, checkout colors, collapsed inbox groups, hydrate, and clear.

Required assertions:

```swift
#expect(atom.expandedGroups.isEmpty)
#expect(atom.checkoutColors.isEmpty)
#expect(atom.collapsedInboxGroups.isEmpty)

atom.setGroupExpanded(SidebarGroupKey("repo-a"), isExpanded: true)
#expect(atom.expandedGroups.contains(SidebarGroupKey("repo-a")))

atom.setCheckoutColor("#ffaa00", for: SidebarCheckoutColorKey("repo-a/worktree-a"))
#expect(atom.checkoutColors[SidebarCheckoutColorKey("repo-a/worktree-a")] == "#ffaa00")

atom.setInboxGroupCollapsed(InboxNotificationGroupKey("today"), isCollapsed: true)
#expect(atom.collapsedInboxGroups == [InboxNotificationGroupKey("today")])
#expect(atom.isInboxGroupCollapsed(InboxNotificationGroupKey("today")))
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SidebarCacheAtomTests"
```

Expected: fails because `SidebarCacheAtom` does not exist.

- [ ] **Step 3: Implement atom**

Create `SidebarCacheAtom` with exactly these stored fields:

```swift
@MainActor
@Observable
final class SidebarCacheAtom {
    private(set) var expandedGroups: Set<SidebarGroupKey> = []
    private(set) var checkoutColors: [SidebarCheckoutColorKey: String] = [:]
    private(set) var collapsedInboxGroups: Set<InboxNotificationGroupKey> = []

    func setGroupExpanded(_ key: SidebarGroupKey, isExpanded: Bool) { ... }
    func setCheckoutColor(_ colorHex: String?, for key: SidebarCheckoutColorKey) { ... }
    func setInboxGroupCollapsed(_ groupKey: InboxNotificationGroupKey, isCollapsed: Bool) { ... }
    func toggleInboxGroupCollapse(_ groupKey: InboxNotificationGroupKey) { ... }
    func isInboxGroupCollapsed(_ groupKey: InboxNotificationGroupKey) -> Bool { ... }
    func hydrate(
        expandedGroups: Set<SidebarGroupKey>,
        checkoutColors: [SidebarCheckoutColorKey: String],
        collapsedInboxGroups: Set<InboxNotificationGroupKey>
    ) { ... }
    func clear() { ... }
}
```

No width, no surface, no collapsed flag, no focus flag.
Use `SidebarCacheKeys.swift` wrappers so cache-key domains cannot be accidentally mixed at compile time. The persistence payload still stores raw strings; conversion happens only at `SidebarCacheStore`.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SidebarCacheAtomTests"
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/SidebarCacheAtom.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/SidebarCacheAtomTests.swift
git commit -m "feat(sidebar): add sidebar cache atom

Co-authored-by: Codex <noreply@openai.com>"
```

## Task A3: Add SidebarCacheStore and wire registry

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Create: `Tests/AgentStudioTests/Core/State/MainActor/Persistence/SidebarCacheStoreTests.swift`

- [ ] **Step 1: Write persistence tests**

Cover save/restore, missing file defaults, and one corrupt field defaulting without losing siblings.

- [ ] **Step 2: Implement store**

Use a `PersistableSidebarCache` payload with per-field decode:

```swift
struct PersistableSidebarCache: Codable {
    var schemaVersion: Int = 1
    var workspaceId: UUID
    var expandedGroups: Set<String> = []
    var checkoutColors: [String: String] = [:]
    var collapsedInboxGroups: Set<String> = []

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 1
        expandedGroups = (try? container.decode(Set<String>.self, forKey: .expandedGroups)) ?? []
        checkoutColors = (try? container.decode([String: String].self, forKey: .checkoutColors)) ?? [:]
        collapsedInboxGroups = (try? container.decode(Set<String>.self, forKey: .collapsedInboxGroups)) ?? []
    }
}
```

The persisted payload uses raw strings only at the disk boundary. `SidebarCacheStore.restore` converts those to `SidebarGroupKey`, `SidebarCheckoutColorKey`, and `InboxNotificationGroupKey`; `flush` converts typed keys back to raw values.

- [ ] **Step 3: Wire atom and store**

Add the atom to `AtomRegistry` and initialize/restore/save it in app boot following existing `UIStateStore` and `RepoCacheStore` patterns.

- [ ] **Step 4: Verify**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SidebarCacheStoreTests|AtomRegistryTests|AppBootSequenceTests"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift Sources/AgentStudio/App/Boot/AppDelegate.swift Tests/AgentStudioTests/Core/State/MainActor/Persistence/SidebarCacheStoreTests.swift
git commit -m "feat(sidebar): persist sidebar cache state

Co-authored-by: Codex <noreply@openai.com>"
```

## Task A4: Move cache fields out of UIStateAtom

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Modify: repo explorer call sites that read `expandedGroups` or `checkoutColors`
- Modify: affected tests

- [ ] **Step 1: Write/adjust failing tests**

Assertions:

```swift
#expect(uiState.sidebarCollapsed == false)
#expect(uiState.sidebarSurface == .repos)
#expect(uiState.sidebarHasFocus == false)
```

There must be no `UIStateAtom.expandedGroups` or `UIStateAtom.checkoutColors` references after the task.

- [ ] **Step 2: Hard cutover**

Remove only:

```swift
expandedGroups
checkoutColors
```

Keep:

```swift
sidebarCollapsed
sidebarSurface
sidebarHasFocus
```

- [ ] **Step 3: Update call sites**

Repo explorer expansion and color reads/writes use `SidebarCacheAtom`.

- [ ] **Step 4: Boundary grep**

Run:

```bash
rg -n "uiState\\.(expandedGroups|checkoutColors)|expandedGroups|checkoutColors" Sources/AgentStudio Tests/AgentStudioTests
```

Expected: remaining `expandedGroups` / `checkoutColors` references are on `SidebarCacheAtom`, its store, or tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift Sources/AgentStudio Tests/AgentStudioTests
git commit -m "refactor(sidebar): move durable sidebar memory to cache atom

Co-authored-by: Codex <noreply@openai.com>"
```

## Task A5: Broaden chaos persistence tests

**Files:**
- Create/extend chaos tests for `UIStateStore`, `SidebarCacheStore`, `WorkspaceStore` or `WorkspacePersistor`, `RepoCacheStore`, `InboxNotificationStore`

- [ ] **Step 1: Add chaos tests**

Each suite loops over `ChaosStoreSeeder.Flavor.allCases` and verifies restore does not throw or crash and defaults only the affected slice.

- [ ] **Step 2: Run chaos slice**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "Chaos"
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests
git commit -m "test(persistence): prove persisted stores survive corrupt slices

Co-authored-by: Codex <noreply@openai.com>"
```

## Task B1: Collapse inbox groups

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

- [ ] **Step 1: Write model tests**

`collapsedGroups: [InboxNotificationGroupKey("today")]` keeps the section header but hides that section's rows. Empty set keeps all rows visible.

- [ ] **Step 2: Update list model**

Add a `collapsedGroups: Set<InboxNotificationGroupKey> = []` parameter to the list model builder and section shape.

- [ ] **Step 3: Update header/view**

Group header toggles `SidebarCacheAtom.toggleInboxGroupCollapse(groupKey)`. Keyboard navigation skips hidden rows.

- [ ] **Step 4: Verify**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationListModelTests|InboxNotificationSidebarViewTests"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification Tests/AgentStudioTests/Features/InboxNotification
git commit -m "feat(notification-inbox): support collapsible inbox groups

Co-authored-by: Codex <noreply@openai.com>"
```

## Task C1: Add InboxFilter and InboxFilterDraftAtom

**Files:**
- Create: `Sources/AgentStudio/Core/Models/InboxFilter.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/InboxFilterDraftAtom.swift`
- Create tests for both.

- [ ] **Step 1: Add model**

```swift
enum InboxFilter: Equatable, Hashable, Sendable, Codable {
    case worktree(UUID)
    case repo(UUID)
}
```

- [ ] **Step 2: Add draft atom**

```swift
@MainActor
@Observable
final class InboxFilterDraftAtom {
    private var pendingFilter: InboxFilter?

    func set(_ filter: InboxFilter) {
        pendingFilter = filter
    }

    func consume() -> InboxFilter? {
        defer { pendingFilter = nil }
        return pendingFilter
    }
}
```

- [ ] **Step 3: Wire into registry**

Add `inboxFilterDraft` to `AtomRegistry`.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Models/InboxFilter.swift Sources/AgentStudio/Core/State/MainActor/Atoms/InboxFilterDraftAtom.swift Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift Tests/AgentStudioTests
git commit -m "feat(notification-inbox): add linkable inbox filter draft

Co-authored-by: Codex <noreply@openai.com>"
```

## Task C2: Apply filters in inbox sidebar

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- Modify tests.

- [ ] **Step 1: Add model tests**

Worktree filter includes only notifications with matching `worktreeId`. Repo filter includes only matching `repoId`.

- [ ] **Step 2: Update list model**

Add `filter: InboxFilter? = nil` and apply it before grouping.

- [ ] **Step 3: Update sidebar view**

On mount/activation, consume `InboxFilterDraftAtom`. Show a clearable filter chip when active.

- [ ] **Step 4: Verify**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "InboxNotificationListModelTests|InboxNotificationSidebarViewTests"
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification Tests/AgentStudioTests/Features/InboxNotification
git commit -m "feat(notification-inbox): apply linkable inbox filters

Co-authored-by: Codex <noreply@openai.com>"
```

## Task C3: Worktree pill opens filtered inbox

**Files:**
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- Modify tests.

- [ ] **Step 1: Add row/view tests**

Clicking a worktree notification pill sets `InboxFilter.worktree(worktreeId)` on `InboxFilterDraftAtom` and dispatches existing `.showInboxNotifications`.

- [ ] **Step 2: Implement**

Do not add a new `AppCommand` case. Use the existing open-inbox command after setting the draft.

- [ ] **Step 3: Verify**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "RepoExplorerWorktreeRowTests|InboxNotificationSidebarViewTests"
```

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/RepoExplorer Tests/AgentStudioTests/Features/RepoExplorer
git commit -m "feat(repo-explorer): open filtered inbox from worktree pill

Co-authored-by: Codex <noreply@openai.com>"
```

## Task D1: Final verification

- [ ] **Step 1: Run lint**

```bash
mise run lint
```

Expected: exit `0`.

- [ ] **Step 2: Run full test suite**

```bash
mise run test
```

Expected: exit `0`.

- [ ] **Step 3: Update WIP checklist**

Update `docs/wip/luna361-phase3-gaps-and-followup-2026-23-04.md` with the Phase 3b status.

- [ ] **Step 4: Commit docs/status**

```bash
git add docs/wip/luna361-phase3-gaps-and-followup-2026-23-04.md
git commit -m "docs(notification-inbox): update phase 3b status

Co-authored-by: Codex <noreply@openai.com>"
```

## Self-Review Notes

- Spec coverage: sidebar cache split, UIState composition preservation, width ownership, collapsed inbox groups, linkable filters, pill click, and broadened chaos tests are all mapped to tasks.
- Placeholder scan: no task depends on `TBD` or an unnamed future type.
- Type consistency: `SidebarCacheAtom` uses `SidebarGroupKey`, `SidebarCheckoutColorKey`, and `InboxNotificationGroupKey`; filter transport uses the discriminated `InboxFilter` union plus `InboxFilterDraftAtom.consume()`.
- Scope split: Ghostty terminal intelligence and live OSC verification are intentionally moved to the companion Phase 3c plan.
