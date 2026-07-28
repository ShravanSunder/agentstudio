import Foundation
import Observation

enum ZoomViewerPresentation: Equatable, Sendable {
    case unavailable
    case retryable
    case retainedHidden(companionPaneId: UUID)
    case retainedVisible(companionPaneId: UUID)

    var companionPaneId: UUID? {
        switch self {
        case .unavailable, .retryable:
            nil
        case .retainedHidden(let companionPaneId), .retainedVisible(let companionPaneId):
            companionPaneId
        }
    }
}

struct ZoomPresentation: Equatable, Sendable {
    var sourcePaneId: UUID
    var viewerPresentation: ZoomViewerPresentation
    var transientSplitRatio: Double?
}

enum ZoomViewerVisibility: Equatable, Sendable {
    case hidden
    case visible
}

struct ZoomCompanionMetadata: Equatable, Sendable {
    var owningTabId: UUID
    let resolvedWorktreeId: UUID
    let companionPaneId: UUID
    var lastZoomVisibility: ZoomViewerVisibility
}

@MainActor
@Observable
final class WorkspacePanePresentationAtom {
    private(set) var zoomPresentationsByTabId: [UUID: ZoomPresentation] = [:]
    private(set) var zoomCompanionsBySourcePaneId: [UUID: ZoomCompanionMetadata] = [:]
    private var zoomSplitRatiosBySourcePaneId: [UUID: Double] = [:]

    func zoomPresentation(forTab tabId: UUID) -> ZoomPresentation? {
        zoomPresentationsByTabId[tabId]
    }

    func zoomCompanion(forSourcePane sourcePaneId: UUID) -> ZoomCompanionMetadata? {
        zoomCompanionsBySourcePaneId[sourcePaneId]
    }

    func enterZoom(
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

    func cancelZoom(inTab tabId: UUID) {
        zoomPresentationsByTabId.removeValue(forKey: tabId)
    }

    @discardableResult
    func setZoomSplitRatio(
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
    func retargetZoom(
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

    func cacheZoomCompanion(
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
    func setZoomViewerVisible(
        _ isVisible: Bool,
        forSourcePane sourcePaneId: UUID
    ) -> Bool {
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

    func removeZoomSourcePane(_ sourcePaneId: UUID) {
        zoomCompanionsBySourcePaneId.removeValue(forKey: sourcePaneId)
        zoomSplitRatiosBySourcePaneId.removeValue(forKey: sourcePaneId)
        zoomPresentationsByTabId = zoomPresentationsByTabId.filter {
            $0.value.sourcePaneId != sourcePaneId
        }
    }

    func reassociateZoomCompanion(
        _ companion: ZoomCompanionMetadata,
        forSourcePane sourcePaneId: UUID,
        to tabId: UUID
    ) {
        var companion = companion
        companion.owningTabId = tabId
        zoomCompanionsBySourcePaneId[sourcePaneId] = companion
    }

    func markZoomCompanionLost(
        forSourcePane sourcePaneId: UUID,
        viewerWorktreeStillResolves: Bool
    ) {
        zoomCompanionsBySourcePaneId.removeValue(forKey: sourcePaneId)
        for (tabId, var presentation) in zoomPresentationsByTabId
        where presentation.sourcePaneId == sourcePaneId {
            presentation.viewerPresentation = viewerWorktreeStillResolves ? .retryable : .unavailable
            zoomPresentationsByTabId[tabId] = presentation
        }
    }

    func removeZoomTab(_ tabId: UUID) {
        zoomPresentationsByTabId.removeValue(forKey: tabId)
        zoomCompanionsBySourcePaneId = zoomCompanionsBySourcePaneId.filter {
            $0.value.owningTabId != tabId
        }
    }

    func clearAllZoomRuntimeState() {
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
        case .unavailable, .retryable:
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
