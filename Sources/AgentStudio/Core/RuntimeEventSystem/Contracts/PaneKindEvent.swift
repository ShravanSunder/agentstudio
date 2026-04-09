import Foundation

protocol PaneKindEvent: Sendable {
    var actionPolicy: ActionPolicy { get }
    var eventName: EventIdentifier { get }
}

enum EventIdentifier: Hashable, Sendable, CustomStringConvertible {
    // Keep identifiers globally unique across all pane kinds. For new events, prefer
    // kind-qualified names when semantic overlap exists (for example, browserNewTab).
    case newTab
    case closeTab
    case gotoTab
    case moveTab
    case newSplit
    case gotoSplit
    case resizeSplit
    case equalizeSplits
    case toggleSplitZoom
    case commandFinished
    case cwdChanged
    case titleChanged
    case tabTitleChanged
    case progressReportUpdated
    case readOnlyChanged
    case secureInputChanged
    case rendererHealthChanged
    case cellSizeChanged
    case initialSizeChanged
    case sizeLimitChanged
    case mouseShapeChanged
    case mouseVisibilityChanged
    case mouseLinkHovered
    case keySequenceChanged
    case keyTableChanged
    case colorChanged
    case configReloadRequested
    case configChanged
    case searchStarted
    case searchEnded
    case searchMatchesUpdated
    case searchSelectionChanged
    case promptTitleRequested
    case desktopNotificationRequested
    case openURLRequested
    case undoRequested
    case redoRequested
    case copyTitleToClipboardRequested
    case bellRang
    case scrollbarChanged
    case navigationCompleted
    case pageLoaded
    case diffLoaded
    case hunkApproved
    case contentSaved
    case fileOpened
    case deferred
    case unhandled
    case consoleMessage
    case allApproved
    case diagnosticsUpdated
    case fsCwdSubtreeChanged
    case fsGitWorkingTreeInCwd
    case plugin(String)

    var rawValue: String {
        switch self {
        case .newTab: return "newTab"
        case .closeTab: return "closeTab"
        case .gotoTab: return "gotoTab"
        case .moveTab: return "moveTab"
        case .newSplit: return "newSplit"
        case .gotoSplit: return "gotoSplit"
        case .resizeSplit: return "resizeSplit"
        case .equalizeSplits: return "equalizeSplits"
        case .toggleSplitZoom: return "toggleSplitZoom"
        case .commandFinished: return "commandFinished"
        case .cwdChanged: return "cwdChanged"
        case .titleChanged: return "titleChanged"
        case .tabTitleChanged: return "tabTitleChanged"
        case .progressReportUpdated: return "progressReportUpdated"
        case .readOnlyChanged: return "readOnlyChanged"
        case .secureInputChanged: return "secureInputChanged"
        case .rendererHealthChanged: return "rendererHealthChanged"
        case .cellSizeChanged: return "cellSizeChanged"
        case .initialSizeChanged: return "initialSizeChanged"
        case .sizeLimitChanged: return "sizeLimitChanged"
        case .mouseShapeChanged: return "mouseShapeChanged"
        case .mouseVisibilityChanged: return "mouseVisibilityChanged"
        case .mouseLinkHovered: return "mouseLinkHovered"
        case .keySequenceChanged: return "keySequenceChanged"
        case .keyTableChanged: return "keyTableChanged"
        case .colorChanged: return "colorChanged"
        case .configReloadRequested: return "configReloadRequested"
        case .configChanged: return "configChanged"
        case .searchStarted: return "searchStarted"
        case .searchEnded: return "searchEnded"
        case .searchMatchesUpdated: return "searchMatchesUpdated"
        case .searchSelectionChanged: return "searchSelectionChanged"
        case .promptTitleRequested: return "promptTitleRequested"
        case .desktopNotificationRequested: return "desktopNotificationRequested"
        case .openURLRequested: return "openURLRequested"
        case .undoRequested: return "undoRequested"
        case .redoRequested: return "redoRequested"
        case .copyTitleToClipboardRequested: return "copyTitleToClipboardRequested"
        case .bellRang: return "bellRang"
        case .scrollbarChanged: return "scrollbarChanged"
        case .navigationCompleted: return "navigationCompleted"
        case .pageLoaded: return "pageLoaded"
        case .diffLoaded: return "diffLoaded"
        case .hunkApproved: return "hunkApproved"
        case .contentSaved: return "contentSaved"
        case .fileOpened: return "fileOpened"
        case .deferred: return "deferred"
        case .unhandled: return "unhandled"
        case .consoleMessage: return "consoleMessage"
        case .allApproved: return "allApproved"
        case .diagnosticsUpdated: return "diagnosticsUpdated"
        case .fsCwdSubtreeChanged: return "fsCwdSubtreeChanged"
        case .fsGitWorkingTreeInCwd: return "fsGitWorkingTreeInCwd"
        case .plugin(let value): return value
        }
    }

    var description: String { rawValue }
}
