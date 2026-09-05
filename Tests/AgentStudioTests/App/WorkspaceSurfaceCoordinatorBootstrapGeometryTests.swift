import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal

/// S7's residency- and expansion-independent bootstrap geometry claims
/// (SPEC R1, R7), split from `WorkspaceSurfaceCoordinatorDrawerRestoreIntegrationTests`
/// into its own suite: these are pure `resolveInitialFrames(for:in:)`
/// resolution tests, not full mount/restore integration proofs, and that
/// sibling file was already near the repo's file-length gate.
@MainActor
@Suite("Workspace surface coordinator bootstrap geometry", .serialized)
struct WorkspaceSurfaceCoordinatorBootstrapGeometryTests {
    private let trustedBounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    @Test("a collapsed drawer child receives a bootstrap frame from the canonical arrangement")
    func aCollapsedDrawerChildReceivesABootstrapFrameFromTheCanonicalArrangement() throws {
        // Arrange
        let harness = makeWorkspaceSurfaceCoordinatorViewFactoryHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id, name: "Collapsed drawer")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawerID = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
        harness.store.tabArrangementAtom.addDrawerPaneView(
            drawerId: drawerID,
            parentPaneId: parentPane.id,
            drawerPaneId: drawerPane.id,
            inTab: tab.id
        )
        harness.store.toggleDrawer(for: parentPane.id)
        #expect(harness.store.pane(parentPane.id)?.drawer?.isExpanded == false)
        let canonicalTab = try #require(harness.store.tabLayoutAtom.tab(tab.id))

        // Act: call the real resolver directly — never hand-build the frame
        // dictionary itself, that is the false-green this proof exists to
        // rule out.
        let resolvedFrames = harness.coordinator.resolveInitialFrames(for: canonicalTab, in: trustedBounds)

        // Assert
        let drawerFrame = try #require(resolvedFrames[drawerPane.id])
        #expect(drawerFrame.width > 0)
        #expect(drawerFrame.height > 0)
    }

    @Test("a backgrounded drawer parent still yields child frames")
    func aBackgroundedDrawerParentStillYieldsChildFrames() throws {
        // Arrange
        let harness = makeWorkspaceSurfaceCoordinatorViewFactoryHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id, name: "Backgrounded drawer parent")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawerID = try #require(harness.store.pane(parentPane.id)?.drawer?.drawerId)
        harness.store.tabArrangementAtom.addDrawerPaneView(
            drawerId: drawerID,
            parentPaneId: parentPane.id,
            drawerPaneId: drawerPane.id,
            inTab: tab.id
        )
        harness.store.paneAtom.setResidency(.backgrounded, for: parentPane.id)
        let canonicalTab = try #require(harness.store.tabLayoutAtom.tab(tab.id))

        // Act
        let resolvedFrames = harness.coordinator.resolveInitialFrames(for: canonicalTab, in: trustedBounds)

        // Assert: the parent's own residency is irrelevant to bootstrap
        // geometry — only its structural drawer facts and the canonical
        // arrangement matter.
        let drawerFrame = try #require(resolvedFrames[drawerPane.id])
        #expect(drawerFrame.width > 0)
        #expect(drawerFrame.height > 0)
    }

    @Test("an ambiguous non-selected arrangement yields no frame")
    func anAmbiguousNonSelectedArrangementYieldsNoFrame() throws {
        // Arrange: the parent pane and its drawer are registered through the
        // live store, so `ownedDrawerID` is genuine. Only the `Tab` value
        // handed to the resolver is built by hand, because no live mutation
        // API can leave one arrangement holding a drawer view another
        // lacks — `addDrawerPaneView` and `insertPane` keep every
        // arrangement pane- and drawer-view-synced by construction. This is
        // not the false-green the plan warns against: that warning targets
        // fabricating the *output* frame dictionary, not constructing a
        // deliberately adversarial *input* arrangement shape.
        let harness = makeWorkspaceSurfaceCoordinatorViewFactoryHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        let parentPane = harness.store.createPane()
        let tab = Tab(paneId: parentPane.id, name: "Ambiguous arrangement")
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        let drawerPane = try #require(harness.store.addDrawerPane(to: parentPane.id))
        let drawerID = try #require(
            harness.store.paneAtom.graphAtom.paneStructuralFacts(parentPane.id)?.ownedDrawerID
        )

        let mainLayout = Layout(paneId: parentPane.id)
        let populatedArrangement = PaneArrangement(
            id: UUIDv7.generate(),
            name: "Populated",
            isDefault: false,
            layout: mainLayout,
            activePaneId: parentPane.id,
            drawerViews: [
                drawerID: DrawerView(
                    layout: DrawerGridLayout(topRow: Layout(paneId: drawerPane.id)),
                    activeChildId: drawerPane.id
                )
            ]
        )
        let selectedArrangement = PaneArrangement(
            id: UUIDv7.generate(),
            name: "Selected",
            isDefault: true,
            layout: mainLayout,
            activePaneId: parentPane.id
        )
        let ambiguousTab = Tab(
            id: tab.id,
            name: tab.name,
            allPaneIds: [parentPane.id, drawerPane.id],
            arrangements: [populatedArrangement, selectedArrangement],
            activeArrangementId: selectedArrangement.id
        )

        // Act
        let resolvedFrames = harness.coordinator.resolveInitialFrames(for: ambiguousTab, in: trustedBounds)

        // Assert: absence, never a guess — the drawer view lives only in the
        // non-selected arrangement.
        #expect(resolvedFrames[drawerPane.id] == nil)
    }
}
