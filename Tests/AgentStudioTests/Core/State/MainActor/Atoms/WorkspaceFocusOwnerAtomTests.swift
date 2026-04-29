import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceFocusOwnerAtomTests {
    @Test("empty drawer focus is first-class")
    func emptyDrawerFocus_isFirstClass() {
        let atom = WorkspaceFocusOwnerAtom()
        let parentPaneId = UUID()

        atom.focusEmptyDrawer(parentPaneId: parentPaneId)

        #expect(atom.owner == .emptyDrawer(parentPaneId: parentPaneId))
    }

    @Test("normalizer keeps valid empty drawer focus")
    func normalizer_keepsValidEmptyDrawerFocus() {
        let parentPaneId = UUID()
        let normalized = WorkspaceFocusOwnerNormalizer.normalize(
            requested: .emptyDrawer(parentPaneId: parentPaneId),
            context: .init(
                activeMainPaneId: parentPaneId,
                expandedDrawerParentPaneId: parentPaneId,
                drawerPaneIds: [],
                activeDrawerPaneId: nil,
                minimizedDrawerPaneIds: []
            )
        )

        #expect(normalized == .emptyDrawer(parentPaneId: parentPaneId))
    }

    @Test("normalizer collapses stale empty drawer focus after drawer closes")
    func normalizer_collapsesStaleEmptyDrawerFocusAfterDrawerCloses() {
        let parentPaneId = UUID()
        let normalized = WorkspaceFocusOwnerNormalizer.normalize(
            requested: .emptyDrawer(parentPaneId: parentPaneId),
            context: .init(
                activeMainPaneId: parentPaneId,
                expandedDrawerParentPaneId: nil,
                drawerPaneIds: [],
                activeDrawerPaneId: nil,
                minimizedDrawerPaneIds: []
            )
        )

        #expect(normalized == .mainPane(paneId: parentPaneId))
    }

    @Test("normalizer keeps valid drawer pane focus")
    func normalizer_keepsValidDrawerPaneFocus() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let normalized = WorkspaceFocusOwnerNormalizer.normalize(
            requested: .drawerPane(parentPaneId: parentPaneId, paneId: drawerPaneId),
            context: .init(
                activeMainPaneId: parentPaneId,
                expandedDrawerParentPaneId: parentPaneId,
                drawerPaneIds: [drawerPaneId],
                activeDrawerPaneId: drawerPaneId,
                minimizedDrawerPaneIds: []
            )
        )

        #expect(normalized == .drawerPane(parentPaneId: parentPaneId, paneId: drawerPaneId))
    }

    @Test("normalizer respects explicit main pane focus while drawer is expanded")
    func normalizer_respectsExplicitMainPaneFocusWhileDrawerExpanded() {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let normalized = WorkspaceFocusOwnerNormalizer.normalize(
            requested: .mainPane(paneId: parentPaneId),
            context: .init(
                activeMainPaneId: parentPaneId,
                expandedDrawerParentPaneId: parentPaneId,
                drawerPaneIds: [drawerPaneId],
                activeDrawerPaneId: drawerPaneId,
                minimizedDrawerPaneIds: []
            )
        )

        #expect(normalized == .mainPane(paneId: parentPaneId))
    }

    @Test("normalizer collapses cross-parent drawer focus to active main pane")
    func normalizer_collapsesCrossParentDrawerFocusToActiveMainPane() {
        let activeParentPaneId = UUID()
        let staleParentPaneId = UUID()
        let drawerPaneId = UUID()
        let normalized = WorkspaceFocusOwnerNormalizer.normalize(
            requested: .emptyDrawer(parentPaneId: staleParentPaneId),
            context: .init(
                activeMainPaneId: activeParentPaneId,
                expandedDrawerParentPaneId: activeParentPaneId,
                drawerPaneIds: [drawerPaneId],
                activeDrawerPaneId: drawerPaneId,
                minimizedDrawerPaneIds: []
            )
        )

        #expect(normalized == .mainPane(paneId: activeParentPaneId))
    }
}
