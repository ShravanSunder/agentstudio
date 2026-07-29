import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite(.serialized)
struct WorkspacePanePresentationAtomTests {
    @Test
    func zoomPresentationsAreIndependentAcrossTabs() throws {
        let atom = WorkspacePanePresentationAtom()
        let firstTabId = UUID()
        let secondTabId = UUID()
        let firstPaneId = UUID()
        let secondPaneId = UUID()

        atom.enterZoom(
            inTab: firstTabId,
            sourcePaneId: firstPaneId,
            viewerPresentation: .unavailable
        )
        atom.enterZoom(
            inTab: secondTabId,
            sourcePaneId: secondPaneId,
            viewerPresentation: .retryable
        )
        atom.cancelZoom(inTab: firstTabId)

        #expect(atom.zoomPresentation(forTab: firstTabId) == nil)
        #expect(atom.zoomPresentation(forTab: secondTabId)?.sourcePaneId == secondPaneId)
    }

    @Test
    func retargetingZoomPreservesCompanionCache() throws {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let firstSourcePaneId = UUID()
        let secondSourcePaneId = UUID()
        let firstCompanion = makeCompanion(tabId: tabId)
        atom.cacheZoomCompanion(firstCompanion, forSourcePane: firstSourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: firstSourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: firstCompanion.companionPaneId)
        )

        let didRetarget = atom.retargetZoom(
            inTab: tabId,
            to: secondSourcePaneId,
            viewerPresentation: .retryable
        )

        #expect(didRetarget)
        #expect(atom.zoomPresentation(forTab: tabId)?.sourcePaneId == secondSourcePaneId)
        #expect(atom.zoomCompanion(forSourcePane: firstSourcePaneId) == firstCompanion)
    }

    @Test
    func retargetingZoomLoadsTargetSourceSplitRatio() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let firstSourcePaneId = UUID()
        let secondSourcePaneId = UUID()
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: secondSourcePaneId,
            viewerPresentation: .retryable
        )
        #expect(atom.setZoomSplitRatio(0.25, inTab: tabId))
        atom.cancelZoom(inTab: tabId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: firstSourcePaneId,
            viewerPresentation: .retryable,
            transientSplitRatio: 0.5
        )

        let didUpdateRatio = atom.setZoomSplitRatio(0.7, inTab: tabId)
        let didRetarget = atom.retargetZoom(
            inTab: tabId,
            to: secondSourcePaneId,
            viewerPresentation: .retryable
        )

        #expect(didUpdateRatio)
        #expect(didRetarget)
        #expect(atom.zoomPresentation(forTab: tabId)?.transientSplitRatio == 0.25)
    }

    @Test
    func retargetingZoomUsesBalancedSplitForSourceWithoutCachedRatio() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let firstSourcePaneId = UUID()
        let secondSourcePaneId = UUID()
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: firstSourcePaneId,
            viewerPresentation: .retryable
        )
        #expect(atom.setZoomSplitRatio(0.7, inTab: tabId))

        let didRetarget = atom.retargetZoom(
            inTab: tabId,
            to: secondSourcePaneId,
            viewerPresentation: .retryable
        )

        #expect(didRetarget)
        #expect(atom.zoomPresentation(forTab: tabId)?.transientSplitRatio == 0.5)
    }

    @Test(
        "Zoom split ratio rejects endpoints and nonfinite values",
        arguments: [0.0, 1.0, -.infinity, .infinity, .nan]
    )
    func zoomSplitRatioRejectsInvalidValues(splitRatio: Double) {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: UUID(),
            viewerPresentation: .retryable,
            transientSplitRatio: 0.5
        )

        let didUpdateRatio = atom.setZoomSplitRatio(splitRatio, inTab: tabId)

        #expect(!didUpdateRatio)
        #expect(atom.zoomPresentation(forTab: tabId)?.transientSplitRatio == 0.5)
    }

    @Test
    func zoomSplitRatioAcceptsInteriorValueNearEndpoint() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: UUID(),
            viewerPresentation: .retryable,
            transientSplitRatio: 0.5
        )

        let didUpdateRatio = atom.setZoomSplitRatio(0.05, inTab: tabId)

        #expect(didUpdateRatio)
        #expect(atom.zoomPresentation(forTab: tabId)?.transientSplitRatio == 0.05)
    }

    @Test
    func userAdjustedSplitRatioSurvivesCancelAndReentryForRetainedSource() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let companion = makeCompanion(tabId: tabId)
        atom.cacheZoomCompanion(companion, forSourcePane: sourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: companion.companionPaneId)
        )
        #expect(atom.setZoomSplitRatio(0.7, inTab: tabId))

        atom.cancelZoom(inTab: tabId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: companion.companionPaneId)
        )

        #expect(atom.zoomPresentation(forTab: tabId)?.transientSplitRatio == 0.7)
    }

    @Test
    func companionMetadataIsIndependentAcrossSourcePanes() {
        let atom = WorkspacePanePresentationAtom()
        let firstSourcePaneId = UUID()
        let secondSourcePaneId = UUID()
        let firstCompanion = makeCompanion(tabId: UUID())
        let secondCompanion = makeCompanion(tabId: UUID())

        atom.cacheZoomCompanion(firstCompanion, forSourcePane: firstSourcePaneId)
        atom.cacheZoomCompanion(secondCompanion, forSourcePane: secondSourcePaneId)

        #expect(atom.zoomCompanion(forSourcePane: firstSourcePaneId) == firstCompanion)
        #expect(atom.zoomCompanion(forSourcePane: secondSourcePaneId) == secondCompanion)
    }

    @Test
    func focusValueTypesAreSendable() {
        requireSendable(ZoomViewerPresentation.self)
        requireSendable(ZoomPresentation.self)
        requireSendable(ZoomViewerVisibility.self)
        requireSendable(ZoomCompanionMetadata.self)
    }

    @Test
    func enteringFocusWithoutTargetSourceMetadataNormalizesRetainedViewerToRetryable() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let focusedSourcePaneId = UUID()
        let unrelatedSourcePaneId = UUID()
        let unrelatedCompanion = makeCompanion(tabId: tabId)
        atom.cacheZoomCompanion(unrelatedCompanion, forSourcePane: unrelatedSourcePaneId)

        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: focusedSourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: unrelatedCompanion.companionPaneId)
        )

        #expect(atom.zoomPresentation(forTab: tabId)?.viewerPresentation == .retryable)
    }

    @Test
    func enteringFocusDerivesRetainedIdentityAndVisibilityFromMatchingCache() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let staleCompanionPaneId = UUID()
        let retainedCompanion = makeCompanion(tabId: tabId, visibility: .hidden)
        atom.cacheZoomCompanion(retainedCompanion, forSourcePane: sourcePaneId)

        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: staleCompanionPaneId)
        )

        #expect(
            atom.zoomPresentation(forTab: tabId)?.viewerPresentation
                == .retainedHidden(companionPaneId: retainedCompanion.companionPaneId)
        )
    }

    @Test
    func enteringFocusRejectsCompanionOwnedByAnotherTab() {
        let atom = WorkspacePanePresentationAtom()
        let focusedTabId = UUID()
        let sourcePaneId = UUID()
        let companion = makeCompanion(tabId: UUID())
        atom.cacheZoomCompanion(companion, forSourcePane: sourcePaneId)

        atom.enterZoom(
            inTab: focusedTabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: companion.companionPaneId)
        )

        #expect(atom.zoomPresentation(forTab: focusedTabId)?.viewerPresentation == .retryable)
    }

    @Test
    func retargetingFocusDerivesRetainedStateFromTargetSourceCache() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let firstSourcePaneId = UUID()
        let secondSourcePaneId = UUID()
        let firstCompanion = makeCompanion(tabId: tabId)
        let secondCompanion = makeCompanion(tabId: tabId, visibility: .hidden)
        atom.cacheZoomCompanion(firstCompanion, forSourcePane: firstSourcePaneId)
        atom.cacheZoomCompanion(secondCompanion, forSourcePane: secondSourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: firstSourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: firstCompanion.companionPaneId)
        )

        let didRetarget = atom.retargetZoom(
            inTab: tabId,
            to: secondSourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: firstCompanion.companionPaneId)
        )

        #expect(didRetarget)
        #expect(
            atom.zoomPresentation(forTab: tabId)?.viewerPresentation
                == .retainedHidden(companionPaneId: secondCompanion.companionPaneId)
        )
    }

    @Test
    func replacingCompanionMetadataUpdatesMatchingFocusWithoutRetiredIdentity() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let firstCompanion = makeCompanion(tabId: tabId)
        let replacementCompanion = makeCompanion(tabId: tabId, visibility: .hidden)
        atom.cacheZoomCompanion(firstCompanion, forSourcePane: sourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: firstCompanion.companionPaneId)
        )

        atom.cacheZoomCompanion(replacementCompanion, forSourcePane: sourcePaneId)

        #expect(atom.zoomCompanion(forSourcePane: sourcePaneId) == replacementCompanion)
        #expect(
            atom.zoomPresentation(forTab: tabId)?.viewerPresentation
                == .retainedHidden(companionPaneId: replacementCompanion.companionPaneId)
        )
        #expect(
            atom.zoomPresentation(forTab: tabId)?.viewerPresentation.companionPaneId
                != firstCompanion.companionPaneId
        )
    }

    @Test
    func viewerVisibilityUpdatesPresentationAndCompanionMetadataTogether() throws {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let companion = makeCompanion(tabId: tabId)
        atom.cacheZoomCompanion(companion, forSourcePane: sourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: companion.companionPaneId)
        )

        let didHide = atom.setZoomViewerVisible(false, forSourcePane: sourcePaneId)

        #expect(didHide)
        #expect(
            atom.zoomPresentation(forTab: tabId)?.viewerPresentation
                == .retainedHidden(companionPaneId: companion.companionPaneId)
        )
        #expect(atom.zoomCompanion(forSourcePane: sourcePaneId)?.lastZoomVisibility == .hidden)
    }

    @Test
    func removingSourcePaneClearsItsCacheAndMatchingZoomPresentation() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let unrelatedSourcePaneId = UUID()
        let companion = makeCompanion(tabId: tabId)
        let unrelatedCompanion = makeCompanion(tabId: UUID())
        atom.cacheZoomCompanion(companion, forSourcePane: sourcePaneId)
        atom.cacheZoomCompanion(unrelatedCompanion, forSourcePane: unrelatedSourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: companion.companionPaneId)
        )

        atom.removeZoomSourcePane(sourcePaneId)

        #expect(atom.zoomCompanion(forSourcePane: sourcePaneId) == nil)
        #expect(atom.zoomCompanion(forSourcePane: unrelatedSourcePaneId) == unrelatedCompanion)
        #expect(atom.zoomPresentation(forTab: tabId) == nil)
    }

    @Test
    func unexpectedCompanionLossKeepsFocusRetryableWhenWorktreeResolves() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let companion = makeCompanion(tabId: tabId)
        atom.cacheZoomCompanion(companion, forSourcePane: sourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedVisible(companionPaneId: companion.companionPaneId)
        )

        atom.markZoomCompanionLost(
            forSourcePane: sourcePaneId,
            viewerWorktreeStillResolves: true
        )

        #expect(atom.zoomCompanion(forSourcePane: sourcePaneId) == nil)
        #expect(atom.zoomPresentation(forTab: tabId)?.viewerPresentation == .retryable)
    }

    @Test
    func unexpectedCompanionLossKeepsFocusUnavailableWhenWorktreeDoesNotResolve() {
        let atom = WorkspacePanePresentationAtom()
        let tabId = UUID()
        let sourcePaneId = UUID()
        let companion = makeCompanion(tabId: tabId)
        atom.cacheZoomCompanion(companion, forSourcePane: sourcePaneId)
        atom.enterZoom(
            inTab: tabId,
            sourcePaneId: sourcePaneId,
            viewerPresentation: .retainedHidden(companionPaneId: companion.companionPaneId)
        )

        atom.markZoomCompanionLost(
            forSourcePane: sourcePaneId,
            viewerWorktreeStillResolves: false
        )

        #expect(atom.zoomCompanion(forSourcePane: sourcePaneId) == nil)
        #expect(atom.zoomPresentation(forTab: tabId)?.viewerPresentation == .unavailable)
    }

    @Test
    func removingTabClearsOnlyItsPresentationAndOwnedCompanions() {
        let atom = WorkspacePanePresentationAtom()
        let removedTabId = UUID()
        let retainedTabId = UUID()
        let removedSourcePaneId = UUID()
        let retainedSourcePaneId = UUID()
        atom.cacheZoomCompanion(makeCompanion(tabId: removedTabId), forSourcePane: removedSourcePaneId)
        atom.cacheZoomCompanion(makeCompanion(tabId: retainedTabId), forSourcePane: retainedSourcePaneId)
        atom.enterZoom(
            inTab: removedTabId,
            sourcePaneId: removedSourcePaneId,
            viewerPresentation: .retryable
        )
        atom.enterZoom(
            inTab: retainedTabId,
            sourcePaneId: retainedSourcePaneId,
            viewerPresentation: .retryable
        )

        atom.removeZoomTab(removedTabId)

        #expect(atom.zoomPresentation(forTab: removedTabId) == nil)
        #expect(atom.zoomCompanion(forSourcePane: removedSourcePaneId) == nil)
        #expect(atom.zoomPresentation(forTab: retainedTabId) != nil)
        #expect(atom.zoomCompanion(forSourcePane: retainedSourcePaneId) != nil)
    }

    private func makeCompanion(
        tabId: UUID,
        visibility: ZoomViewerVisibility = .visible
    ) -> ZoomCompanionMetadata {
        ZoomCompanionMetadata(
            owningTabId: tabId,
            resolvedWorktreeId: UUID(),
            companionPaneId: UUID(),
            lastZoomVisibility: visibility
        )
    }

    private func requireSendable<T: Sendable>(_ type: T.Type) {}
}
