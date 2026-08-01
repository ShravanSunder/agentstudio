import Foundation
import Observation

package enum ZoomViewerPresentation: Equatable, Sendable {
    case unavailable
    case unavailableVisible
    case retryable
    case retainedHidden(companionPaneId: UUID)
    case retainedVisible(companionPaneId: UUID)

    package var companionPaneId: UUID? {
        switch self {
        case .unavailable, .unavailableVisible, .retryable:
            nil
        case .retainedHidden(let companionPaneId), .retainedVisible(let companionPaneId):
            companionPaneId
        }
    }
}

package struct ZoomPresentation: Equatable, Sendable {
    package var sourcePaneId: UUID
    package var viewerPresentation: ZoomViewerPresentation
    package var transientSplitRatio: Double?

    package init(
        sourcePaneId: UUID,
        viewerPresentation: ZoomViewerPresentation,
        transientSplitRatio: Double?
    ) {
        self.sourcePaneId = sourcePaneId
        self.viewerPresentation = viewerPresentation
        self.transientSplitRatio = transientSplitRatio
    }
}

package enum ZoomViewerVisibility: Equatable, Sendable {
    case hidden
    case visible
}

package struct ZoomCompanionMetadata: Equatable, Sendable {
    package var owningTabId: UUID
    package let resolvedWorktreeId: UUID
    package let companionPaneId: UUID
    package var lastZoomVisibility: ZoomViewerVisibility

    package init(
        owningTabId: UUID,
        resolvedWorktreeId: UUID,
        companionPaneId: UUID,
        lastZoomVisibility: ZoomViewerVisibility
    ) {
        self.owningTabId = owningTabId
        self.resolvedWorktreeId = resolvedWorktreeId
        self.companionPaneId = companionPaneId
        self.lastZoomVisibility = lastZoomVisibility
    }
}

@MainActor
@Observable
package final class WorkspacePanePresentationAtom {
    package private(set) var zoomPresentationsByTabId: [UUID: ZoomPresentation] = [:]
    package private(set) var zoomCompanionsBySourcePaneId: [UUID: ZoomCompanionMetadata] = [:]
    private var zoomSplitRatiosBySourcePaneId: [UUID: Double] = [:]

    package func zoomPresentation(forTab tabId: UUID) -> ZoomPresentation? {
        zoomPresentationsByTabId[tabId]
    }

    package func zoomCompanion(forSourcePane sourcePaneId: UUID) -> ZoomCompanionMetadata? {
        zoomCompanionsBySourcePaneId[sourcePaneId]
    }

    package func enterZoom(
        inTab tabId: UUID,
        sourcePaneId: UUID,
        viewerPresentation: ZoomViewerPresentation,
        transientSplitRatio: Double? = nil
    ) {
        zoomPresentationsByTabId[tabId] = ZoomPresentation(
            sourcePaneId: sourcePaneId,
            viewerPresentation: normalizedViewerPresentation(
                viewerPresentation,
                forSourcePane: sourcePaneId,
                inTab: tabId
            ),
            transientSplitRatio: transientSplitRatio ?? zoomSplitRatiosBySourcePaneId[sourcePaneId]
        )
    }

    package func cancelZoom(inTab tabId: UUID) {
        zoomPresentationsByTabId.removeValue(forKey: tabId)
    }

    @discardableResult
    package func setZoomSplitRatio(
        _ splitRatio: Double,
        inTab tabId: UUID
    ) -> Bool {
        guard splitRatio.isFinite,
            splitRatio > 0,
            splitRatio < 1,
            var presentation = zoomPresentationsByTabId[tabId]
        else {
            return false
        }
        presentation.transientSplitRatio = splitRatio
        zoomPresentationsByTabId[tabId] = presentation
        zoomSplitRatiosBySourcePaneId[presentation.sourcePaneId] = splitRatio
        return true
    }

    @discardableResult
    package func retargetZoom(
        inTab tabId: UUID,
        to sourcePaneId: UUID,
        viewerPresentation: ZoomViewerPresentation
    ) -> Bool {
        guard var presentation = zoomPresentationsByTabId[tabId] else {
            return false
        }
        presentation.sourcePaneId = sourcePaneId
        presentation.viewerPresentation = normalizedViewerPresentation(
            viewerPresentation,
            forSourcePane: sourcePaneId,
            inTab: tabId
        )
        presentation.transientSplitRatio = zoomSplitRatiosBySourcePaneId[sourcePaneId] ?? 0.5
        zoomPresentationsByTabId[tabId] = presentation
        return true
    }

    package func cacheZoomCompanion(
        _ metadata: ZoomCompanionMetadata,
        forSourcePane sourcePaneId: UUID
    ) {
        zoomCompanionsBySourcePaneId[sourcePaneId] = metadata
        guard var presentation = zoomPresentationsByTabId[metadata.owningTabId],
            presentation.sourcePaneId == sourcePaneId
        else {
            return
        }
        presentation.viewerPresentation = retainedViewerPresentation(for: metadata)
        zoomPresentationsByTabId[metadata.owningTabId] = presentation
    }

    @discardableResult
    package func setZoomViewerVisible(
        _ isVisible: Bool,
        forSourcePane sourcePaneId: UUID
    ) -> Bool {
        if let (tabId, unavailablePresentation) = zoomPresentationsByTabId.first(
            where: { _, presentation in
                presentation.sourcePaneId == sourcePaneId
                    && (presentation.viewerPresentation == .unavailable
                        || presentation.viewerPresentation == .unavailableVisible)
            }
        ) {
            var presentation = unavailablePresentation
            presentation.viewerPresentation = isVisible ? .unavailableVisible : .unavailable
            zoomPresentationsByTabId[tabId] = presentation
            return true
        }

        guard var companion = zoomCompanionsBySourcePaneId[sourcePaneId],
            var presentation = zoomPresentationsByTabId[companion.owningTabId],
            presentation.sourcePaneId == sourcePaneId,
            presentation.viewerPresentation.companionPaneId == companion.companionPaneId
        else {
            return false
        }

        if isVisible {
            presentation.viewerPresentation = .retainedVisible(companionPaneId: companion.companionPaneId)
            companion.lastZoomVisibility = .visible
        } else {
            presentation.viewerPresentation = .retainedHidden(companionPaneId: companion.companionPaneId)
            companion.lastZoomVisibility = .hidden
        }
        zoomPresentationsByTabId[companion.owningTabId] = presentation
        zoomCompanionsBySourcePaneId[sourcePaneId] = companion
        return true
    }

    package func removeZoomSourcePane(_ sourcePaneId: UUID) {
        zoomCompanionsBySourcePaneId.removeValue(forKey: sourcePaneId)
        zoomSplitRatiosBySourcePaneId.removeValue(forKey: sourcePaneId)
        zoomPresentationsByTabId = zoomPresentationsByTabId.filter {
            $0.value.sourcePaneId != sourcePaneId
        }
    }

    package func reassociateZoomCompanion(
        _ companion: ZoomCompanionMetadata,
        forSourcePane sourcePaneId: UUID,
        to tabId: UUID
    ) {
        var companion = companion
        companion.owningTabId = tabId
        zoomCompanionsBySourcePaneId[sourcePaneId] = companion
    }

    package func markZoomCompanionLost(
        forSourcePane sourcePaneId: UUID,
        viewerWorktreeStillResolves: Bool
    ) {
        zoomCompanionsBySourcePaneId.removeValue(forKey: sourcePaneId)
        for (tabId, var presentation) in zoomPresentationsByTabId
        where presentation.sourcePaneId == sourcePaneId {
            if viewerWorktreeStillResolves {
                presentation.viewerPresentation = .retryable
            } else {
                let wasVisible =
                    switch presentation.viewerPresentation {
                    case .unavailableVisible, .retainedVisible:
                        true
                    case .unavailable, .retryable, .retainedHidden:
                        false
                    }
                presentation.viewerPresentation =
                    wasVisible ? .unavailableVisible : .unavailable
            }
            zoomPresentationsByTabId[tabId] = presentation
        }
    }

    package func removeZoomTab(_ tabId: UUID) {
        zoomPresentationsByTabId.removeValue(forKey: tabId)
        zoomCompanionsBySourcePaneId = zoomCompanionsBySourcePaneId.filter {
            $0.value.owningTabId != tabId
        }
    }

    package func clearAllZoomRuntimeState() {
        zoomPresentationsByTabId.removeAll()
        zoomCompanionsBySourcePaneId.removeAll()
        zoomSplitRatiosBySourcePaneId.removeAll()
    }

    private func normalizedViewerPresentation(
        _ viewerPresentation: ZoomViewerPresentation,
        forSourcePane sourcePaneId: UUID,
        inTab tabId: UUID
    ) -> ZoomViewerPresentation {
        switch viewerPresentation {
        case .unavailable, .unavailableVisible, .retryable:
            return viewerPresentation
        case .retainedHidden, .retainedVisible:
            guard let metadata = zoomCompanionsBySourcePaneId[sourcePaneId],
                metadata.owningTabId == tabId
            else {
                return .retryable
            }
            return retainedViewerPresentation(for: metadata)
        }
    }

    private func retainedViewerPresentation(
        for metadata: ZoomCompanionMetadata
    ) -> ZoomViewerPresentation {
        switch metadata.lastZoomVisibility {
        case .hidden:
            .retainedHidden(companionPaneId: metadata.companionPaneId)
        case .visible:
            .retainedVisible(companionPaneId: metadata.companionPaneId)
        }
    }
}
