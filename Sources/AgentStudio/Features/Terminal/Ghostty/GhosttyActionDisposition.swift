import Foundation

enum TerminalLocalPresentationAction: Sendable, Equatable {
    case mouseShape(TerminalMouseShape)
    case mouseVisibility(Bool)
    case searchMatches(Int?)
    case searchSelection(Int?)
}

enum TerminalLocalActivityEvidence: Sendable, Equatable {
    case scrollbar(ScrollbarState)
}

enum TerminalLocalLifecycleAction: Sendable, Equatable {
    case searchStarted(query: String?)
    case searchEnded
}

enum TerminalLatestSemanticMetadataAction: Sendable, Equatable {
    case titleChanged(String)
    case tabTitleChanged(String)
}

enum GhosttyDiagnosticDisposition: Sendable, Equatable {
    case directHostState
    case localOnly
    case deferred
    case unhandled
}

enum GhosttyActionDisposition: Sendable, Equatable {
    case exactFactOrControl(GhosttyEvent)
    case latestPresentation(TerminalLocalPresentationAction)
    case latestSemanticMetadata(TerminalLatestSemanticMetadataAction)
    case activityEvidence(TerminalLocalActivityEvidence)
    case exactLocalLifecycle(TerminalLocalLifecycleAction)
    case diagnostic(GhosttyDiagnosticDisposition)

    static func classify(_ event: GhosttyEvent) -> Self {
        switch event {
        case .mouseShapeChanged(let shape):
            return .latestPresentation(.mouseShape(shape))
        case .mouseVisibilityChanged(let isVisible):
            return .latestPresentation(.mouseVisibility(isVisible))
        case .searchMatchesUpdated(let totalMatches):
            return .latestPresentation(.searchMatches(totalMatches))
        case .searchSelectionChanged(let selectedMatchIndex):
            return .latestPresentation(.searchSelection(selectedMatchIndex))
        case .titleChanged(let title):
            return .latestSemanticMetadata(.titleChanged(title))
        case .tabTitleChanged(let title):
            return .latestSemanticMetadata(.tabTitleChanged(title))
        case .scrollbarChanged(let state):
            return .activityEvidence(.scrollbar(state))
        case .searchStarted(let query):
            return .exactLocalLifecycle(.searchStarted(query: query))
        case .searchEnded:
            return .exactLocalLifecycle(.searchEnded)
        case .cellSizeChanged, .initialSizeChanged, .sizeLimitChanged, .configChanged:
            return .diagnostic(.directHostState)
        case .mouseLinkHovered, .keySequenceChanged, .keyTableChanged, .colorChanged:
            return .diagnostic(.localOnly)
        case .deferred:
            return .diagnostic(.deferred)
        case .unhandled:
            return .diagnostic(.unhandled)
        case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
            .toggleSplitZoom, .cwdChanged, .commandFinished,
            .progressReportUpdated, .readOnlyChanged, .secureInputRequested, .secureInputChanged,
            .rendererHealthChanged, .configReloadRequested, .promptTitleRequested,
            .desktopNotificationRequested, .openURLRequested, .undoRequested, .redoRequested,
            .copyTitleToClipboardRequested, .bellRang:
            return .exactFactOrControl(event)
        }
    }
}
