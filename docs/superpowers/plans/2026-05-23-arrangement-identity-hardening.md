# Arrangement Identity Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden pane arrangement and drawer identity boundaries so drawer-grid redesign work is built on explicit main-pane, drawer-pane, drawer, arrangement, and transient-state contracts instead of bare `UUID` convention.

**Architecture:** Keep the persisted JSON shape stable where possible, but strengthen Swift model boundaries with branded value types for view-state IDs, decode-time invariant checks, and validation that reconciles view state against canonical pane ownership instead of deriving ownership from views. Treat drawer expansion as a deliberate product decision to document, not a hidden accident.

**Tech Stack:** Swift 6.2, Swift Testing (`@Suite`, `@Test`, `#expect`), `mise run format`, `mise run lint`, `mise run test`.

---

## Scope

This plan addresses the nine validated shape issues before starting the drawer grid redesign:

1. Validate `Drawer.parentPaneId` against the owning `Pane.id`.
2. Keep `Drawer.paneIds` canonical and validate every `DrawerView.layout` mirrors it per arrangement.
3. Brand main-pane view state separately from drawer-pane view state.
4. Make the two minimized sets self-documenting through branded types.
5. Document the global `Drawer.isExpanded` product decision.
6. Replace implicit empty-drawer fallback with an explicit derived state enum.
7. Enforce exactly one default arrangement on `Tab` decode.
8. Stop deriving `TabArrangementState.allPaneIds` from arrangement layouts.
9. Make tab zoom state visibly transient rather than only excluded by `CodingKeys`.
10. Fix the management-mode show-minimized binding so UI writes user preference while reading raw user preference.
11. Stage `insertPane` across arrangements before committing so a failed fanout cannot leave partial state.

Do not implement the row-major sizing fixes or column-major drawer redesign in this plan. Those belong after this hardening lands.

Known out of scope for this PR:

- Repository/worktree persistence hard-cutover (`decodeRecoverableField` for repos/worktrees). This is real, but it is outside arrangement identity and should be a separate persistence-hardening PR.
- Cross-tab last-pane drain undo. This is real undo behavior work, not identity hardening.
- Broad silent-fallback logging cleanup. This should be a focused observability PR so log semantics can be reviewed as a set.
- Arrangement validator no-op acceptance. This is already fixed on current `origin/main` by the arrangement validator work; do not re-implement it here.

---

## File Structure

Create:

- `Sources/AgentStudio/Core/Models/PaneArrangementIdentity.swift`
  - Branded wrappers for pane arrangement view-state identities.
  - `MainPaneId`, `DrawerPaneId`, and `DrawerId` carry `UUID` but prevent assignment across main/drawer fields.
  - Small conversion helpers keep call sites explicit.

- `Sources/AgentStudio/Core/Models/DrawerViewState.swift`
  - Explicit derived state for drawer view lookup: `.empty`, `.populated(DrawerView)`, `.missingForNonEmptyDrawer`.
  - Keeps existing `drawerView(forParent:) -> DrawerView?` as a wrapper over the explicit state so existing callers receive the same value while new code can branch on the structural state.

- `Sources/AgentStudio/Core/Models/TabTransientState.swift`
  - Explicit container for non-persisted tab view state, starting with `zoomedPaneId`.

Modify:

- `Sources/AgentStudio/Core/Models/PaneArrangement.swift`
  - Change `DrawerView.activeChildId` and `DrawerView.minimizedPaneIds` to drawer-pane brands.
  - Change `PaneArrangement.activePaneId` and `PaneArrangement.minimizedPaneIds` to main-pane brands.
  - Keep JSON encoding as bare UUIDs.

- `Sources/AgentStudio/Core/Models/Pane.swift`
  - Validate decoded layout drawer parent identity.

- `Sources/AgentStudio/Core/Models/Drawer.swift`
  - Add doc text clarifying why `parentPaneId` remains stored.

- `Sources/AgentStudio/Core/Models/Tab.swift`
  - Add custom `init(from:)` that runs the existing tab preconditions as decode errors.
  - Store `zoomedPaneId` inside `TabTransientState` and keep a computed `zoomedPaneId` property for existing call sites.

- `Sources/AgentStudio/Core/Models/TabArrangementState.swift`
  - Add an initializer with invariant checks.
  - Keep `allPaneIds` as canonical input, not a value derived from arrangements.
  - Store transient state in `TabTransientState`, not as an unmarked persisted-looking field.

- `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift`
  - Reconcile arrangements against `allPaneIds`.
  - Remove the assignment that rebuilds `allPaneIds` from layouts.

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift`
  - Add `drawerViewState(forParent:)`.
  - Route old `drawerView(forParent:)` through the enum.

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
  - Update branded ID field writes.
  - Ensure drawer-view fanout validates against canonical drawer membership.
  - Stage `insertPane` updates in local copies and commit only after every arrangement update succeeds.

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabDerived.swift`
  - Assemble `Tab` with explicit transient state.

- `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
  - Read raw user `showsMinimizedPanes` preference for the toggle binding.

- `Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift`
  - Disable the show-minimized toggle while management mode is active and show explanatory copy from effective state.

Tests:

- `Tests/AgentStudioTests/Core/Models/PaneTests.swift`
- `Tests/AgentStudioTests/Core/Models/PaneArrangementIdentityTests.swift`
- `Tests/AgentStudioTests/Core/Models/TabTests.swift`
- `Tests/AgentStudioTests/Core/State/TabArrangementValidationTests.swift`
- `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerivedTests.swift`
- `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift`
- `Tests/AgentStudioTests/Helpers/PaneArrangementStateTestAdapters.swift`
- `Tests/AgentStudioTests/Helpers/ModelFactories.swift`

---

### Task 1: Validate Drawer Parent Identity On Pane Decode

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Pane.swift`
- Modify: `Sources/AgentStudio/Core/Models/Drawer.swift`
- Test: `Tests/AgentStudioTests/Core/Models/PaneTests.swift`

- [ ] **Step 1: Write the failing decode test**

Add this test near the existing pane Codable tests:

```swift
@Test
func test_decode_layoutDrawerParentMismatch_throws() throws {
    let pane = makePane(id: UUIDv7.generate())
    let mismatchedParentPaneId = UUIDv7.generate()
    let drawer = Drawer(parentPaneId: mismatchedParentPaneId)
    let invalidPane = Pane(
        id: pane.id,
        content: pane.content,
        metadata: pane.metadata,
        residency: pane.residency,
        kind: .layout(drawer: drawer)
    )

    let data = try encoder.encode(invalidPane)

    #expect(throws: DecodingError.self) {
        _ = try decoder.decode(Pane.self, from: data)
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTests/test_decode_layoutDrawerParentMismatch_throws"
```

Expected: FAIL because `Pane.init(from:)` currently accepts the mismatched drawer parent.

- [ ] **Step 3: Implement decode validation**

In `Pane.init(from:)`, replace the direct kind assignment:

```swift
self.kind = try container.decode(PaneKind.self, forKey: .kind)
```

with:

```swift
let decodedKind = try container.decode(PaneKind.self, forKey: .kind)
if case .layout(let drawer) = decodedKind, drawer.parentPaneId != decodedId {
    throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: "Layout drawer parentPaneId must match Pane.id in canonical schema"
    )
}
self.kind = decodedKind
```

In `Drawer.swift`, replace the existing top comment with:

```swift
/// A drawer container attached to a parent layout pane.
///
/// `parentPaneId` intentionally duplicates the owning `Pane.id` so detached
/// drawer operations and diagnostics can name the parent without carrying the
/// whole pane. `Pane` validates this value when decoding `.layout(drawer:)`.
/// View state such as layout, focus, and minimized panes lives on
/// `PaneArrangement`.
```

- [ ] **Step 4: Run the focused test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTests/test_decode_layoutDrawerParentMismatch_throws"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Pane.swift Sources/AgentStudio/Core/Models/Drawer.swift Tests/AgentStudioTests/Core/Models/PaneTests.swift
git commit -m "Validate drawer parent identity on decode" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 2: Add Branded Main, Drawer Pane, And Drawer IDs

**Files:**
- Create: `Sources/AgentStudio/Core/Models/PaneArrangementIdentity.swift`
- Test: `Tests/AgentStudioTests/Core/Models/PaneArrangementIdentityTests.swift`

- [ ] **Step 1: Write the branded identity tests**

Create `Tests/AgentStudioTests/Core/Models/PaneArrangementIdentityTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct PaneArrangementIdentityTests {
    @Test
    func mainPaneId_roundTripsThroughCodableAsUUID() throws {
        let raw = UUIDv7.generate()
        let value = MainPaneId(raw)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(MainPaneId.self, from: data)

        #expect(decoded.rawValue == raw)
    }

    @Test
    func drawerPaneId_roundTripsThroughCodableAsUUID() throws {
        let raw = UUIDv7.generate()
        let value = DrawerPaneId(raw)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(DrawerPaneId.self, from: data)

        #expect(decoded.rawValue == raw)
    }

    @Test
    func setConversion_exposesRawUUIDsExplicitly() {
        let first = UUIDv7.generate()
        let second = UUIDv7.generate()
        let mainIds: Set<MainPaneId> = [MainPaneId(first), MainPaneId(second)]
        let drawerIds: Set<DrawerPaneId> = [DrawerPaneId(first), DrawerPaneId(second)]

        #expect(mainIds.rawUUIDs == Set([first, second]))
        #expect(drawerIds.rawUUIDs == Set([first, second]))
    }

    @Test
    func drawerId_roundTripsThroughCodableAsUUID() throws {
        let raw = UUID()
        let value = DrawerId(raw)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(DrawerId.self, from: data)

        #expect(decoded.rawValue == raw)
    }
}
```

- [ ] **Step 2: Run the failing identity tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementIdentityTests"
```

Expected: FAIL because `MainPaneId`, `DrawerPaneId`, and `DrawerId` do not exist.

- [ ] **Step 3: Add the branded identity types**

Create `Sources/AgentStudio/Core/Models/PaneArrangementIdentity.swift`:

```swift
import Foundation

/// Pane identity known to belong to a tab's main arrangement layout.
struct MainPaneId: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

/// Pane identity known to belong to a drawer child layout.
struct DrawerPaneId: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

/// Drawer container identity.
///
/// This brand is intentionally lighter-weight than changing every dictionary
/// key in the first pass. Use it at API and derived-state boundaries where a
/// drawer ID could be confused with a pane ID.
struct DrawerId: Codable, Hashable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String { rawValue.uuidString }
}

extension Collection where Element == MainPaneId {
    var rawUUIDs: [UUID] { map(\.rawValue) }
}

extension Set where Element == MainPaneId {
    var rawUUIDs: Set<UUID> { Set(map(\.rawValue)) }
}

extension Collection where Element == DrawerPaneId {
    var rawUUIDs: [UUID] { map(\.rawValue) }
}

extension Set where Element == DrawerPaneId {
    var rawUUIDs: Set<UUID> { Set(map(\.rawValue)) }
}
```

- [ ] **Step 4: Run the identity tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementIdentityTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/PaneArrangementIdentity.swift Tests/AgentStudioTests/Core/Models/PaneArrangementIdentityTests.swift
git commit -m "Add branded pane arrangement identities" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 3: Brand PaneArrangement And DrawerView Focus/Minimized Fields

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/PaneArrangement.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementSelectionRules.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementRepairRules.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Tests/AgentStudioTests/Helpers/PaneArrangementStateTestAdapters.swift`
- Test: `Tests/AgentStudioTests/Core/Models/PaneArrangementIdentityTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerivedTests.swift`

- [ ] **Step 1: Extend tests to prove JSON shape stays bare UUID**

Add these tests to `PaneArrangementIdentityTests`:

```swift
@Test
func paneArrangement_encodesMainPaneViewStateAsBareUUIDs() throws {
    let paneId = UUIDv7.generate()
    let arrangement = PaneArrangement(
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: paneId),
        minimizedPaneIds: [MainPaneId(paneId)],
        activePaneId: MainPaneId(paneId)
    )

    let data = try JSONEncoder().encode(arrangement)
    let decoded = try JSONDecoder().decode(PaneArrangement.self, from: data)

    #expect(decoded.activePaneId == MainPaneId(paneId))
    #expect(decoded.minimizedPaneIds == [MainPaneId(paneId)])
}

@Test
func drawerView_encodesDrawerPaneViewStateAsBareUUIDs() throws {
    let paneId = UUIDv7.generate()
    let drawerView = DrawerView(
        layout: DrawerGridLayout(topRow: Layout(paneId: paneId)),
        activeChildId: DrawerPaneId(paneId),
        minimizedPaneIds: [DrawerPaneId(paneId)]
    )

    let data = try JSONEncoder().encode(drawerView)
    let decoded = try JSONDecoder().decode(DrawerView.self, from: data)

    #expect(decoded.activeChildId == DrawerPaneId(paneId))
    #expect(decoded.minimizedPaneIds == [DrawerPaneId(paneId)])
}
```

- [ ] **Step 2: Run the tests and capture compile failures**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementIdentityTests"
```

Expected: FAIL because `PaneArrangement` and `DrawerView` still use bare UUID fields.

- [ ] **Step 3: Update `DrawerView` field types**

In `PaneArrangement.swift`, change `DrawerView` fields and initializer:

```swift
var activeChildId: DrawerPaneId?
var minimizedPaneIds: Set<DrawerPaneId>

init(
    layout: DrawerGridLayout = DrawerGridLayout(),
    activeChildId: DrawerPaneId? = nil,
    minimizedPaneIds: Set<DrawerPaneId> = []
) {
    self.layout = layout
    self.activeChildId = Self.normalizedActiveChildId(activeChildId, paneIds: layout.paneIds)
    self.minimizedPaneIds = minimizedPaneIds.filtering(toRawPaneIds: Set(layout.paneIds))
}
```

Add these helpers below `DrawerView`:

```swift
extension Set where Element == DrawerPaneId {
    func filtering(toRawPaneIds paneIds: Set<UUID>) -> Set<DrawerPaneId> {
        filter { paneIds.contains($0.rawValue) }
    }
}
```

Update decode to rely on the initializer:

```swift
self.init(
    layout: try container.decode(DrawerGridLayout.self, forKey: .layout),
    activeChildId: try container.decodeIfPresent(DrawerPaneId.self, forKey: .activeChildId),
    minimizedPaneIds: try container.decode(Set<DrawerPaneId>.self, forKey: .minimizedPaneIds)
)
```

Update the normalizer:

```swift
private static func normalizedActiveChildId(_ activeChildId: DrawerPaneId?, paneIds: [UUID]) -> DrawerPaneId? {
    guard !paneIds.isEmpty else { return nil }
    guard let activeChildId, paneIds.contains(activeChildId.rawValue) else {
        return DrawerPaneId(paneIds[0])
    }
    return activeChildId
}
```

- [ ] **Step 4: Update `PaneArrangement` field types**

In `PaneArrangement.swift`, change fields and initializer:

```swift
var minimizedPaneIds: Set<MainPaneId>
var activePaneId: MainPaneId?
```

Use this initializer signature:

```swift
init(
    id: UUID = UUID(),
    name: String = "Default",
    isDefault: Bool = true,
    layout: Layout,
    minimizedPaneIds: Set<MainPaneId> = [],
    showsMinimizedPanes: Bool = true,
    activePaneId: MainPaneId? = nil,
    drawerViews: [UUID: DrawerView] = [:]
)
```

Normalize with:

```swift
self.minimizedPaneIds = minimizedPaneIds.filtering(toRawPaneIds: Set(layout.paneIds))
self.activePaneId = Self.normalizedActivePaneId(
    activePaneId, layout: layout, minimizedPaneIds: self.minimizedPaneIds)
```

Add:

```swift
extension Set where Element == MainPaneId {
    func filtering(toRawPaneIds paneIds: Set<UUID>) -> Set<MainPaneId> {
        filter { paneIds.contains($0.rawValue) }
    }
}
```

Update decode:

```swift
minimizedPaneIds =
    try container.decode(Set<MainPaneId>.self, forKey: .minimizedPaneIds)
    .filtering(toRawPaneIds: Set(layout.paneIds))
activePaneId = Self.normalizedActivePaneId(
    try container.decodeIfPresent(MainPaneId.self, forKey: .activePaneId),
    layout: layout,
    minimizedPaneIds: minimizedPaneIds
)
```

Update `normalizedActivePaneId`:

```swift
private static func normalizedActivePaneId(
    _ activePaneId: MainPaneId?,
    layout: Layout,
    minimizedPaneIds: Set<MainPaneId>
) -> MainPaneId? {
    guard !layout.isEmpty else { return nil }
    if let activePaneId, layout.contains(activePaneId.rawValue), !minimizedPaneIds.contains(activePaneId) {
        return activePaneId
    }
    return layout.paneIds.first { !minimizedPaneIds.contains(MainPaneId($0)) }.map(MainPaneId.init)
        ?? layout.paneIds.first.map(MainPaneId.init)
}
```

- [ ] **Step 5: Update call sites explicitly**

Use compile errors to update every call site by applying these patterns:

```swift
// bare UUID -> main view-state field
arrangement.activePaneId = MainPaneId(paneId)
arrangement.minimizedPaneIds.insert(MainPaneId(paneId))
arrangement.minimizedPaneIds.remove(MainPaneId(paneId))
arrangement.minimizedPaneIds.contains(MainPaneId(paneId))

// main view-state field -> bare UUID for layout/pane lookup
arrangement.activePaneId?.rawValue
arrangement.minimizedPaneIds.rawUUIDs

// bare UUID -> drawer view-state field
drawerView.activeChildId = DrawerPaneId(drawerPaneId)
drawerView.minimizedPaneIds.insert(DrawerPaneId(drawerPaneId))
drawerView.minimizedPaneIds.remove(DrawerPaneId(drawerPaneId))
drawerView.minimizedPaneIds.contains(DrawerPaneId(drawerPaneId))

// drawer view-state field -> bare UUID for layout/pane lookup
drawerView.activeChildId?.rawValue
drawerView.minimizedPaneIds.rawUUIDs
```

When an API still returns `UUID?`, convert at the boundary:

```swift
return tabLayoutAtom.tab(tabId)?.activeArrangement.activePaneId?.rawValue
```

When an API still returns `Set<UUID>`, convert at the boundary:

```swift
return tabLayoutAtom.tab(tabId)?.activeArrangement.minimizedPaneIds.rawUUIDs ?? []
```

- [ ] **Step 6: Run the model and derived tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementIdentityTests|WorkspaceArrangementViewDerivedTests|TabArrangementValidationTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio Tests/AgentStudioTests
git commit -m "Brand arrangement pane view state IDs" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 4: Make Drawer View Lookup State Explicit

**Files:**
- Create: `Sources/AgentStudio/Core/Models/DrawerViewState.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerivedTests.swift`

- [ ] **Step 1: Add failing tests for explicit drawer state**

In `WorkspaceArrangementViewDerivedTests`, update the empty drawer test with:

```swift
#expect(derived.drawerViewState(forParent: parentPane.id) == .empty)
```

Update the non-empty missing view test with:

```swift
#expect(derived.drawerViewState(forParent: parentPane.id) == .missingForNonEmptyDrawer(drawerId: DrawerId(parentPane.drawer!.drawerId)))
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceArrangementViewDerivedTests"
```

Expected: FAIL because `DrawerViewState` and `drawerViewState(forParent:)` do not exist.

- [ ] **Step 3: Add the enum**

Create `Sources/AgentStudio/Core/Models/DrawerViewState.swift`:

```swift
import Foundation

enum DrawerViewState: Equatable {
    case empty
    case populated(DrawerView)
    case missingForNonEmptyDrawer(drawerId: DrawerId)

    var drawerView: DrawerView? {
        switch self {
        case .empty:
            DrawerView()
        case .populated(let drawerView):
            drawerView
        case .missingForNonEmptyDrawer:
            nil
        }
    }
}
```

- [ ] **Step 4: Add the derived reader**

In `WorkspaceArrangementViewDerived`, add:

```swift
func drawerViewState(forParent parentPaneId: UUID) -> DrawerViewState? {
    guard
        let tab = tabLayoutAtom.tabContaining(paneId: parentPaneId),
        let drawer = paneAtom.pane(parentPaneId)?.drawer
    else { return nil }
    if let drawerView = tab.activeArrangement.drawerViews[drawer.drawerId] {
        return .populated(drawerView)
    }
    return drawer.paneIds.isEmpty ? .empty : .missingForNonEmptyDrawer(drawerId: DrawerId(drawer.drawerId))
}
```

Then replace `drawerView(forParent:)` with:

```swift
func drawerView(forParent parentPaneId: UUID) -> DrawerView? {
    drawerViewState(forParent: parentPaneId)?.drawerView
}
```

- [ ] **Step 5: Run the focused tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceArrangementViewDerivedTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Models/DrawerViewState.swift Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerivedTests.swift
git commit -m "Expose explicit drawer view state" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 5: Enforce Tab Arrangement Defaults On Decode

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Tab.swift`
- Test: `Tests/AgentStudioTests/Core/Models/TabTests.swift`

- [ ] **Step 1: Add failing decode tests**

Add to `TabTests`:

```swift
@Test
func test_decode_zeroDefaultArrangements_throws() throws {
    let paneId = UUID()
    let arrangement = PaneArrangement(name: "Custom", isDefault: false, layout: Layout(paneId: paneId))
    let tab = Tab(
        panes: [paneId],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id,
        activePaneId: paneId
    )
    let data = try JSONEncoder().encode(tab)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(Tab.self, from: data)
    }
}

@Test
func test_decode_multipleDefaultArrangements_throws() throws {
    let paneA = UUID()
    let paneB = UUID()
    let first = PaneArrangement(name: "Default", isDefault: true, layout: Layout(paneId: paneA))
    let second = PaneArrangement(name: "Also Default", isDefault: true, layout: Layout(paneId: paneB))
    let tab = Tab(
        panes: [paneA, paneB],
        arrangements: [first, second],
        activeArrangementId: first.id,
        activePaneId: paneA
    )
    let data = try JSONEncoder().encode(tab)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(Tab.self, from: data)
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabTests/test_decode_zeroDefaultArrangements_throws|TabTests/test_decode_multipleDefaultArrangements_throws"
```

Expected: FAIL because synthesized Codable accepts both shapes.

- [ ] **Step 3: Add custom decode**

In `Tab.swift`, add `init(from:)`:

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let id = try container.decode(UUID.self, forKey: .id)
    let name = try container.decode(String.self, forKey: .name)
    let allPaneIds = try container.decode([UUID].self, forKey: .allPaneIds)
    let arrangements = try container.decode([PaneArrangement].self, forKey: .arrangements)
    let activeArrangementId = try container.decode(UUID.self, forKey: .activeArrangementId)

    guard !arrangements.isEmpty else {
        throw DecodingError.dataCorruptedError(
            forKey: .arrangements,
            in: container,
            debugDescription: "Tab must have at least one arrangement"
        )
    }
    guard arrangements.filter(\.isDefault).count == 1 else {
        throw DecodingError.dataCorruptedError(
            forKey: .arrangements,
            in: container,
            debugDescription: "Tab must have exactly one default arrangement"
        )
    }
    guard arrangements.contains(where: { $0.id == activeArrangementId }) else {
        throw DecodingError.dataCorruptedError(
            forKey: .activeArrangementId,
            in: container,
            debugDescription: "Tab activeArrangementId must resolve to an arrangement"
        )
    }

    self.init(
        id: id,
        name: name,
        allPaneIds: allPaneIds,
        arrangements: arrangements,
        activeArrangementId: activeArrangementId,
        zoomedPaneId: nil
    )
}
```

- [ ] **Step 4: Run `TabTests`**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Tab.swift Tests/AgentStudioTests/Core/Models/TabTests.swift
git commit -m "Fail closed on invalid tab arrangement defaults" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 6: Stop Deriving Tab Pane Ownership From Arrangement Views

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/TabArrangementState.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift`
- Test: `Tests/AgentStudioTests/Core/State/TabArrangementValidationTests.swift`

- [ ] **Step 1: Add failing canonical ownership test**

Add to `TabArrangementValidationTests`:

```swift
@Test
func validate_preservesCanonicalAllPaneIdsWhenArrangementLayoutIsCorrupt() {
    let canonicalPane = UUID()
    let corruptPane = UUID()
    let arrangement = PaneArrangement(
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: corruptPane),
        activePaneId: MainPaneId(corruptPane)
    )
    let state = TabArrangementState(
        tabId: UUID(),
        allPaneIds: [canonicalPane],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id,
        zoomedPaneId: nil
    )

    let validated = TabArrangementValidation.validating([state])

    #expect(validated[0].allPaneIds == [canonicalPane])
    #expect(validated[0].arrangements[0].layout.paneIds == [canonicalPane])
    #expect(validated[0].arrangements[0].activePaneId == MainPaneId(canonicalPane))
}
```

- [ ] **Step 2: Run the failing validation test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabArrangementValidationTests/validate_preservesCanonicalAllPaneIdsWhenArrangementLayoutIsCorrupt"
```

Expected: FAIL because validation currently rebuilds `allPaneIds` from arrangement layouts.

- [ ] **Step 3: Add a guarded initializer**

Replace `TabArrangementState` with:

```swift
import Foundation

struct TabArrangementState: Equatable {
    let tabId: UUID
    var allPaneIds: [UUID]
    var arrangements: [PaneArrangement]
    var activeArrangementId: UUID
    var zoomedPaneId: UUID?

    init(
        tabId: UUID,
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        zoomedPaneId: UUID?
    ) {
        precondition(!arrangements.isEmpty, "TabArrangementState must have at least one arrangement")
        precondition(
            arrangements.filter(\.isDefault).count == 1,
            "TabArrangementState must have exactly one default arrangement"
        )
        precondition(
            arrangements.contains { $0.id == activeArrangementId },
            "TabArrangementState activeArrangementId must resolve"
        )
        self.tabId = tabId
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
        self.activeArrangementId = activeArrangementId
        self.zoomedPaneId = zoomedPaneId
    }
}
```

- [ ] **Step 4: Change validation to reconcile views to canonical membership**

In `TabArrangementValidation.validating`, delete this block:

```swift
let allArrangementPaneIds = Set(
    updatedStates[tabIndex].arrangements.flatMap { arrangement in
        arrangement.layout.paneIds + arrangement.drawerViews.flatMap { $0.value.layout.paneIds }
    })
updatedStates[tabIndex].allPaneIds = Array(allArrangementPaneIds)
```

Replace it with:

```swift
let canonicalPaneIds = Set(updatedStates[tabIndex].allPaneIds)
```

Then update duplicate logic to use `canonicalPaneIds`:

```swift
let duplicatePaneIds = canonicalPaneIds.intersection(seenPaneIds)
```

After duplicate pruning, set:

```swift
let validPaneIds = Set(updatedStates[tabIndex].allPaneIds)
```

For each arrangement, ensure main layout contains every canonical main pane without wiping the user's split order and ratios. Do not rebuild to `Layout.autoTiled(...)` for every mismatch. Use an incremental reconciliation helper: remove invalid pane IDs, append missing canonical main pane IDs, and preserve the surviving layout structure.

```swift
let drawerPaneIds = Set(
    updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews.flatMap { $0.value.layout.paneIds }
)
let canonicalMainPaneIds = updatedStates[tabIndex].allPaneIds.filter { !drawerPaneIds.contains($0) }
updatedStates[tabIndex].arrangements[arrangementIndex].layout = reconcilingMainLayout(
    updatedStates[tabIndex].arrangements[arrangementIndex].layout,
    canonicalMainPaneIds: canonicalMainPaneIds
)
```

Add these helpers to `TabArrangementValidation`:

```swift
private static func reconcilingMainLayout(
    _ layout: Layout,
    canonicalMainPaneIds: [UUID]
) -> Layout {
    var updatedLayout = layout
    let canonicalSet = Set(canonicalMainPaneIds)

    for paneId in updatedLayout.paneIds where !canonicalSet.contains(paneId) {
        updatedLayout = updatedLayout.removing(
            paneId: paneId,
            sizingMode: .proportional
        ) ?? Layout.autoTiled(updatedLayout.paneIds.filter { $0 != paneId })
    }

    for paneId in canonicalMainPaneIds where !updatedLayout.contains(paneId) {
        updatedLayout = appendingPane(paneId, to: updatedLayout)
    }

    return updatedLayout
}

private static func appendingPane(_ paneId: UUID, to layout: Layout) -> Layout {
    guard let targetPaneId = layout.paneIds.last else {
        return Layout(paneId: paneId)
    }

    return layout.inserting(
        paneId: paneId,
        at: targetPaneId,
        direction: .horizontal,
        position: .after,
        sizingMode: .proportional
    ) ?? Layout.autoTiled(layout.paneIds + [paneId])
}
```

Add a second assertion to the test so it proves this repair is surgical:

```swift
let repairedLayout = validated[0].arrangements[0].layout
#expect(repairedLayout.paneIds == [canonicalPane])
#expect(!repairedLayout.contains(corruptPane))
```

- [ ] **Step 5: Run validation tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabArrangementValidationTests|PaneArrangementInvariantTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Models/TabArrangementState.swift Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift Tests/AgentStudioTests/Core/State/TabArrangementValidationTests.swift
git commit -m "Preserve canonical tab pane ownership during validation" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 7: Validate Drawer Membership Mirrors DrawerView Layouts

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- Test: `Tests/AgentStudioTests/Core/State/TabArrangementValidationTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift`

- [ ] **Step 1: Add failing drawer mirror validation test**

Add to `TabArrangementValidationTests`:

```swift
@Test
func validate_removesDrawerViewPaneIdsThatAreNotInCanonicalDrawerMembership() {
    let parentPane = UUID()
    let canonicalDrawerPane = UUID()
    let strayDrawerPane = UUID()
    let drawerId = UUID()
    let arrangement = PaneArrangement(
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: parentPane),
        activePaneId: MainPaneId(parentPane),
        drawerViews: [
            drawerId: DrawerView(
                layout: DrawerGridLayout(
                    topRow: Layout(paneId: canonicalDrawerPane)
                        .inserting(
                            paneId: strayDrawerPane,
                            at: canonicalDrawerPane,
                            direction: .horizontal,
                            position: .after,
                            sizingMode: .halveTarget
                        )!
                ),
                activeChildId: DrawerPaneId(strayDrawerPane),
                minimizedPaneIds: [DrawerPaneId(strayDrawerPane)]
            )
        ]
    )
    let state = TabArrangementState(
        tabId: UUID(),
        allPaneIds: [parentPane, canonicalDrawerPane],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id,
        zoomedPaneId: nil
    )

    let validated = TabArrangementValidation.validating([state])

    let drawerView = validated[0].arrangements[0].drawerViews[drawerId]
    #expect(drawerView?.layout.paneIds == [canonicalDrawerPane])
    #expect(drawerView?.activeChildId == DrawerPaneId(canonicalDrawerPane))
    #expect(drawerView?.minimizedPaneIds.isEmpty == true)
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabArrangementValidationTests/validate_removesDrawerViewPaneIdsThatAreNotInCanonicalDrawerMembership"
```

Expected: FAIL until validation consistently uses canonical drawer membership.

- [ ] **Step 3: Add a validation helper**

In `TabArrangementValidation`, add:

```swift
private static func pruningDrawerViewsToCanonicalPaneMembership(
    arrangement: PaneArrangement,
    validPaneIds: Set<UUID>
) -> [UUID: DrawerView] {
    TabArrangementRepairRules.pruningInvalidDrawerViewPaneIds(
        validPaneIds: validPaneIds,
        from: arrangement.drawerViews
    )
}
```

Use it in the per-arrangement validation loop:

```swift
updatedStates[tabIndex].arrangements[arrangementIndex].drawerViews =
    pruningDrawerViewsToCanonicalPaneMembership(
        arrangement: updatedStates[tabIndex].arrangements[arrangementIndex],
        validPaneIds: validPaneIds
    )
```

- [ ] **Step 4: Add a fanout assertion test**

In `PaneArrangementInvariantTests`, add a test that creates one tab with three arrangements, adds a drawer pane through the atom method, and asserts every arrangement has the drawer pane in its `DrawerView.layout`.

Use this structure:

```swift
@Test
@MainActor
func addDrawerPaneView_fansOutToEveryArrangementContainingParent() {
    let parentPane = UUID()
    let drawerPane = UUID()
    let drawerId = UUID()
    let defaultArrangement = PaneArrangement(
        name: "Default",
        isDefault: true,
        layout: Layout(paneId: parentPane),
        activePaneId: MainPaneId(parentPane)
    )
    let layoutOne = PaneArrangement(
        name: "Layout 1",
        isDefault: false,
        layout: Layout(paneId: parentPane),
        activePaneId: MainPaneId(parentPane)
    )
    let layoutTwo = PaneArrangement(
        name: "Layout 2",
        isDefault: false,
        layout: Layout(paneId: parentPane),
        activePaneId: MainPaneId(parentPane)
    )
    let atom = WorkspaceTabArrangementAtom()
    let tabId = UUID()
    atom.appendState(
        TabArrangementState(
            tabId: tabId,
            allPaneIds: [parentPane, drawerPane],
            arrangements: [defaultArrangement, layoutOne, layoutTwo],
            activeArrangementId: defaultArrangement.id,
            zoomedPaneId: nil
        )
    )

    atom.addDrawerPaneView(
        drawerId: drawerId,
        parentPaneId: parentPane,
        drawerPaneId: drawerPane,
        inTab: tabId
    )

    let state = atom.arrangementState(tabId)!
    #expect(state.arrangements.allSatisfy { $0.drawerViews[drawerId]?.layout.paneIds == [drawerPane] })
}
```

- [ ] **Step 5: Run invariant tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabArrangementValidationTests|PaneArrangementInvariantTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift Tests/AgentStudioTests/Core/State/TabArrangementValidationTests.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift
git commit -m "Validate drawer view membership mirrors canonical drawers" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 8: Make Zoom State Explicitly Transient

**Files:**
- Create: `Sources/AgentStudio/Core/Models/TabTransientState.swift`
- Modify: `Sources/AgentStudio/Core/Models/Tab.swift`
- Modify: `Sources/AgentStudio/Core/Models/TabArrangementState.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabDerived.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- Modify: `Tests/AgentStudioTests/Helpers/PaneArrangementStateTestAdapters.swift`
- Test: `Tests/AgentStudioTests/Core/Models/TabTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/TabArrangementValidationTests.swift`

- [ ] **Step 1: Add transient-state round-trip test**

Add to `TabTests`:

```swift
@Test
func test_codable_zoomedPaneId_isTransientAndRestoresNil() throws {
    let paneId = UUID()
    let tab = Tab(paneId: paneId).withTransientState(TabTransientState(zoomedPaneId: paneId))

    let data = try JSONEncoder().encode(tab)
    let decoded = try JSONDecoder().decode(Tab.self, from: data)

    #expect(tab.zoomedPaneId == paneId)
    #expect(decoded.zoomedPaneId == nil)
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabTests/test_codable_zoomedPaneId_isTransientAndRestoresNil"
```

Expected: FAIL because `TabTransientState` and `withTransientState` do not exist.

- [ ] **Step 3: Add `TabTransientState`**

Create `Sources/AgentStudio/Core/Models/TabTransientState.swift`:

```swift
import Foundation

/// Non-persisted tab view state.
///
/// This state can affect presentation while the app is running but must not be
/// encoded into workspace persistence.
struct TabTransientState: Equatable, Hashable {
    var zoomedPaneId: UUID?

    init(zoomedPaneId: UUID? = nil) {
        self.zoomedPaneId = zoomedPaneId
    }
}
```

- [ ] **Step 4: Move `Tab.zoomedPaneId` behind transient state**

In `Tab.swift`, replace:

```swift
var zoomedPaneId: UUID?
```

with:

```swift
var transientState: TabTransientState

var zoomedPaneId: UUID? {
    get { transientState.zoomedPaneId }
    set { transientState.zoomedPaneId = newValue }
}
```

Initialize with:

```swift
self.transientState = TabTransientState(zoomedPaneId: zoomedPaneId)
```

Add this helper:

```swift
func withTransientState(_ transientState: TabTransientState) -> Self {
    var copy = self
    copy.transientState = transientState
    return copy
}
```

Keep `transientState` out of `CodingKeys`.

- [ ] **Step 5: Move `TabArrangementState` zoom behind transient state too**

In `TabArrangementState`, replace:

```swift
var zoomedPaneId: UUID?
```

with:

```swift
var transientState: TabTransientState

var zoomedPaneId: UUID? {
    get { transientState.zoomedPaneId }
    set { transientState.zoomedPaneId = newValue }
}
```

Update the initializer parameter from `zoomedPaneId` to `transientState`:

```swift
init(
    tabId: UUID,
    allPaneIds: [UUID],
    arrangements: [PaneArrangement],
    activeArrangementId: UUID,
    transientState: TabTransientState = TabTransientState()
) {
    precondition(!arrangements.isEmpty, "TabArrangementState must have at least one arrangement")
    precondition(
        arrangements.filter(\.isDefault).count == 1,
        "TabArrangementState must have exactly one default arrangement"
    )
    precondition(
        arrangements.contains { $0.id == activeArrangementId },
        "TabArrangementState activeArrangementId must resolve"
    )
    self.tabId = tabId
    self.allPaneIds = allPaneIds
    self.arrangements = arrangements
    self.activeArrangementId = activeArrangementId
    self.transientState = transientState
}
```

Update call sites that still pass `zoomedPaneId:` to pass:

```swift
transientState: TabTransientState(zoomedPaneId: zoomedPaneId)
```

Do not leave a same-named stored `zoomedPaneId` field on `TabArrangementState`; the computed bridge is allowed only as a transition aid for existing atom code.

- [ ] **Step 6: Run tab tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabTests|WorkspaceTabDerivedTests|WorkspaceStoreArrangementTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Tab.swift Sources/AgentStudio/Core/Models/TabTransientState.swift Sources/AgentStudio/Core/Models/TabArrangementState.swift Tests/AgentStudioTests/Core/Models/TabTests.swift
git commit -m "Make tab zoom state explicitly transient" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 9: Document The Global Drawer Expansion Decision

**Files:**
- Modify: `docs/superpowers/specs/2026-05-10-drawer-grid-layout-redesign-design.md`
- Modify: `Sources/AgentStudio/Core/Models/Drawer.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift`

- [ ] **Step 1: Add a behavior test that locks global expansion across arrangement switches**

Add to `PaneArrangementInvariantTests`:

```swift
@Test
func drawerExpansionRemainsGlobalWhenSwitchingArrangements() throws {
    let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
    let tab = Tab(paneId: parentPane.id)
    store.appendTab(tab)
    _ = try #require(store.addDrawerPane(to: parentPane.id))
    let customArrangementId = try #require(store.createArrangement(name: "Focus", inTab: tab.id))

    #expect(store.pane(parentPane.id)?.drawer?.isExpanded == true)

    store.switchArrangement(to: customArrangementId, inTab: tab.id)

    #expect(store.tab(tab.id)?.activeArrangementId == customArrangementId)
    #expect(store.pane(parentPane.id)?.drawer?.isExpanded == true)
}
```

- [ ] **Step 2: Run the test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementInvariantTests/drawerExpansionRemainsGlobalWhenSwitchingArrangements"
```

Expected: PASS. If this fails, stop and inspect whether drawer expansion was accidentally moved into arrangement view state.

- [ ] **Step 3: Update drawer docs**

In `Drawer.swift`, ensure the doc comment includes:

```swift
/// Expansion is global to the parent pane shell. Arrangement-specific drawer
/// view state owns layout, active child, and minimized drawer children, but it
/// does not decide whether the drawer panel is open.
```

- [ ] **Step 4: Replace the stub's Q4 uncertainty with a decision**

In `docs/superpowers/specs/2026-05-10-drawer-grid-layout-redesign-design.md`, add this under the drawer column-major section:

```markdown
### Drawer expansion contract

`Drawer.isExpanded` remains global to the parent pane, not per arrangement.
The drawer is part of the parent pane shell. Arrangements own how drawer
children are ordered, which drawer child is active, and which drawer children
are minimized. They do not own whether the shell is open.

When switching arrangements, an expanded drawer remains expanded. The active
drawer child and minimized drawer children are read from the destination
arrangement's `DrawerView`. An empty drawer renders as an explicit empty drawer
state, not as persisted fake drawer view data.
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Drawer.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift docs/superpowers/specs/2026-05-10-drawer-grid-layout-redesign-design.md
git commit -m "Document global drawer expansion contract" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 10: Fix Management-Mode Show-Minimized Binding

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerivedTests.swift`

- [ ] **Step 1: Add a failing raw-versus-effective derived test**

Add to `WorkspaceArrangementViewDerivedTests`:

```swift
@Test
func userShowsMinimizedPanes_returnsStoredPreferenceWhenManagementOverridesEffectiveValue() {
    let paneA = UUID()
    let paneB = UUID()
    let layout = Layout(paneId: paneA)
        .inserting(
            paneId: paneB,
            at: paneA,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )!
    let arrangement = PaneArrangement(
        name: "Default",
        isDefault: true,
        layout: layout,
        minimizedPaneIds: [MainPaneId(paneB)],
        showsMinimizedPanes: false,
        activePaneId: MainPaneId(paneA)
    )
    let tab = Tab(
        name: "Tab",
        allPaneIds: [paneA, paneB],
        arrangements: [arrangement],
        activeArrangementId: arrangement.id
    )
    let tabLayout = WorkspaceTabLayoutAtom()
    let paneAtom = WorkspacePaneAtom()
    let managementLayer = ManagementLayerAtom()
    tabLayout.appendTab(tab)
    let derived = WorkspaceArrangementViewDerived(
        tabLayoutAtom: tabLayout,
        paneAtom: paneAtom,
        managementLayerAtom: managementLayer
    )

    managementLayer.activate()

    #expect(derived.userShowsMinimizedPanes(forTab: tab.id) == false)
    #expect(derived.effectiveShowsMinimizedPanes(forTab: tab.id) == true)
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceArrangementViewDerivedTests/userShowsMinimizedPanes_returnsStoredPreferenceWhenManagementOverridesEffectiveValue"
```

Expected: FAIL because `userShowsMinimizedPanes(forTab:)` does not exist.

- [ ] **Step 3: Add the raw user preference reader**

In `WorkspaceArrangementViewDerived`, add:

```swift
func userShowsMinimizedPanes(forTab tabId: UUID) -> Bool {
    guard let arrangement = tabLayoutAtom.tab(tabId)?.activeArrangement else { return true }
    return arrangement.showsMinimizedPanes
}
```

Keep `effectiveShowsMinimizedPanes(forTab:)` as the read-time management override:

```swift
func effectiveShowsMinimizedPanes(forTab tabId: UUID) -> Bool {
    guard let arrangement = tabLayoutAtom.tab(tabId)?.activeArrangement else { return true }
    return effectiveShowsMinimizedPanes(for: arrangement)
}
```

- [ ] **Step 4: Bind the UI toggle to the raw preference**

In `CollapsedPaneBar`, change the arrangement panel binding from:

```swift
showsMinimizedPanesBinding: Binding(
    get: { atom(\.arrangementView).effectiveShowsMinimizedPanes(forTab: tabId) },
    set: { actionDispatcher.dispatch(.setShowsMinimizedPanes(tabId: tabId, value: $0)) }
),
```

to:

```swift
showsMinimizedPanesBinding: Binding(
    get: { atom(\.arrangementView).userShowsMinimizedPanes(forTab: tabId) },
    set: { actionDispatcher.dispatch(.setShowsMinimizedPanes(tabId: tabId, value: $0)) }
),
```

In `ArrangementPanel`, disable the switch while management mode is active:

```swift
Toggle(
    "",
    isOn: showsMinimizedPanesBinding
)
.toggleStyle(.switch)
.controlSize(.mini)
.labelsHidden()
.disabled(atom(\.managementLayer).isActive)
```

The explanatory copy remains driven by the raw preference plus management-mode state:

```swift
if !showsMinimizedPanesBinding.wrappedValue && atom(\.managementLayer).isActive {
    Text("Minimized panes are always shown in management mode")
        .font(.system(size: AppStyles.General.Typography.textXs))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceArrangementViewDerivedTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerivedTests.swift
git commit -m "Separate user and effective minimized pane visibility" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 11: Stage Insert Pane Fanout Before Committing

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Tests/AgentStudioTests/Helpers/WorkspaceStoreTestAccess.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift`

- [ ] **Step 1: Add a failing three-arrangement fanout test**

Extend `insertPaneAddsPaneToEveryArrangementInTab` in `PaneArrangementInvariantTests` so the tab has at least three arrangements before the second insert:

```swift
let customArrangementId = try #require(store.createArrangement(name: "Focus", inTab: tab.id))
let reviewArrangementId = try #require(store.createArrangement(name: "Review", inTab: tab.id))
```

Then assert the inserted pane landed everywhere:

```swift
let updatedTab = try #require(store.tab(tab.id))
let customArrangement = try #require(updatedTab.arrangements.first { $0.id == customArrangementId })
let reviewArrangement = try #require(updatedTab.arrangements.first { $0.id == reviewArrangementId })
#expect(updatedTab.arrangements.allSatisfy { Set($0.layout.paneIds) == Set(updatedTab.allPaneIds) })
#expect(customArrangement.layout.contains(thirdPane.id))
#expect(reviewArrangement.layout.contains(thirdPane.id))
```

- [ ] **Step 2: Run the focused invariant test**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementInvariantTests/insertPaneAddsPaneToEveryArrangementInTab"
```

Expected: PASS today for the normal path. This test is a guard that the staged rewrite preserves the all-arrangements fanout contract.

- [ ] **Step 3: Stage `insertPane` mutations before assignment**

In `WorkspaceTabArrangementAtom.insertPane`, remove `@discardableResult`.

Change the method so it mutates a local `TabArrangementState` copy and assigns it back only after every arrangement update succeeds:

```swift
func insertPane(
    _ paneId: UUID,
    inTab tabId: UUID,
    at targetPaneId: UUID,
    direction: Layout.SplitDirection,
    position: Layout.Position,
    sizingMode: DropSizingMode
) -> Bool {
    guard let tabIndex = arrangementStates.firstIndex(where: { $0.tabId == tabId }) else {
        workspaceTabArrangementLogger.warning("insertPane: tab \(tabId) not found")
        return false
    }

    var stagedState = arrangementStates[tabIndex]
    guard let activeIndex = stagedState.arrangements.firstIndex(where: { $0.id == stagedState.activeArrangementId }) else {
        workspaceTabArrangementLogger.warning("insertPane: active arrangement missing for tab \(tabId)")
        return false
    }

    guard
        let activeLayout = stagedState.arrangements[activeIndex].layout.inserting(
            paneId: paneId,
            at: targetPaneId,
            direction: direction,
            position: position,
            sizingMode: sizingMode
        )
    else {
        workspaceTabArrangementLogger.warning("insertPane: active arrangement rejected pane \(paneId)")
        return false
    }

    stagedState.arrangements[activeIndex].layout = activeLayout
    stagedState.arrangements[activeIndex].activePaneId = MainPaneId(paneId)
    stagedState.arrangements[activeIndex].minimizedPaneIds.remove(MainPaneId(paneId))

    for arrangementIndex in stagedState.arrangements.indices where arrangementIndex != activeIndex {
        if stagedState.arrangements[arrangementIndex].layout.contains(paneId) {
            continue
        }
        guard let appendedLayout = Self.appendingPane(paneId, to: stagedState.arrangements[arrangementIndex].layout) else {
            workspaceTabArrangementLogger.warning(
                "insertPane: arrangement \(stagedState.arrangements[arrangementIndex].id) rejected pane \(paneId)"
            )
            return false
        }
        stagedState.arrangements[arrangementIndex].layout = appendedLayout
        stagedState.arrangements[arrangementIndex].minimizedPaneIds.remove(MainPaneId(paneId))
    }

    if !stagedState.allPaneIds.contains(paneId) {
        stagedState.allPaneIds.append(paneId)
    }
    stagedState.zoomedPaneId = nil
    arrangementStates[tabIndex] = stagedState
    return true
}
```

If the real method has additional bookkeeping, keep it, but preserve this invariant: no write to `arrangementStates[tabIndex]` happens until every arrangement layout update has succeeded.

- [ ] **Step 4: Make call sites handle the result**

In `PaneCoordinator+ActionExecution.swift`, replace discarded calls with checked calls:

```swift
guard store.tabArrangementAtom.insertPane(
    paneId,
    inTab: tabId,
    at: targetPaneId,
    direction: direction,
    position: position,
    sizingMode: sizingMode
) else {
    Self.logger.error("insertPane failed for pane \(paneId) in tab \(tabId)")
    return
}
```

In `WorkspaceStoreTestAccess`, remove `@discardableResult` from the helper so tests also acknowledge failures.

- [ ] **Step 5: Run focused insert tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementInvariantTests|WorkspaceStoreArrangementTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift Tests/AgentStudioTests/Helpers/WorkspaceStoreTestAccess.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift
git commit -m "Stage pane insertion across arrangements" -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 12: Full Verification

**Files:**
- No source changes.

- [ ] **Step 1: Format**

Run:

```bash
mise run format
```

Expected: exit 0, "Formatted all Swift sources".

- [ ] **Step 2: Run focused identity/model tests**

Run:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneArrangementIdentityTests|PaneTests|TabTests|TabArrangementValidationTests|WorkspaceArrangementViewDerivedTests|PaneArrangementInvariantTests"
```

Expected: PASS.

- [ ] **Step 3: Run lint**

Run:

```bash
mise run lint
```

Expected: exit 0, swift-format OK, swiftlint 0 violations, Core boundary check passed.

- [ ] **Step 4: Run full tests**

Run:

```bash
mise run test
```

Expected: exit 0. The default E2E and Zmx E2E lanes may be skipped by project environment unless explicitly enabled; record that exactly in the final report.

- [ ] **Step 5: Commit verification-only doc adjustment if needed**

If `mise run format` changed committed source files, commit those formatting changes:

```bash
git status --short
git add Sources Tests docs
git commit -m "Format arrangement identity hardening changes" -m "Co-authored-by: Codex <noreply@openai.com>"
```

If `git status --short` is empty, skip this step.

---

## Self-Review Checklist

- Spec coverage:
  - Drawer parent identity: Task 1.
  - Drawer membership and drawer view mirror: Tasks 6 and 7.
  - Main vs drawer active/minimized ID branding: Tasks 2 and 3.
  - Global drawer expansion decision: Task 9.
  - Empty drawer explicit state: Task 4.
  - Exactly one default arrangement: Task 5.
  - Canonical all-pane ownership: Task 6.
  - Transient zoom state: Task 8.
  - Management-mode minimized-pane override remains read-time only while the toggle edits raw user preference: Task 10.
  - Insert-pane fanout commits only after every arrangement update succeeds: Task 11.

- Placeholder scan:
  - No unresolved placeholder markers or unspecified implementation steps.
  - Each code-changing task includes the concrete test, implementation shape, command, expected result, and commit command.

- Type consistency:
  - `MainPaneId` is used for main arrangement active/minimized state.
  - `DrawerPaneId` is used for drawer active/minimized state.
  - Existing layout structures continue storing raw `UUID` until a separate layout-generic redesign is justified.

---

## Execution Notes

- Implement tasks in order. Task 3 deliberately creates many compile errors because it changes type signatures at the model boundary; fix those errors by applying the conversion patterns in Task 3 Step 5.
- Do not start drawer row-major sizing fixes or column-major drawer layout work in this PR.
- After this plan lands, the drawer grid redesign spec can be rewritten against a clearer identity model.
