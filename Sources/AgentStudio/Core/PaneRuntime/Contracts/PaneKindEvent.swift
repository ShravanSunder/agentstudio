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
    case bellRang
    case scrollbarChanged
    case navigationCompleted
    case pageLoaded
    case diffLoaded
    case hunkApproved
    case contentSaved
    case fileOpened
    case unhandled
    case consoleMessage
    case allApproved
    case diagnosticsUpdated
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
        case .bellRang: return "bellRang"
        case .scrollbarChanged: return "scrollbarChanged"
        case .navigationCompleted: return "navigationCompleted"
        case .pageLoaded: return "pageLoaded"
        case .diffLoaded: return "diffLoaded"
        case .hunkApproved: return "hunkApproved"
        case .contentSaved: return "contentSaved"
        case .fileOpened: return "fileOpened"
        case .unhandled: return "unhandled"
        case .consoleMessage: return "consoleMessage"
        case .allApproved: return "allApproved"
        case .diagnosticsUpdated: return "diagnosticsUpdated"
        case .plugin(let value): return value
        }
    }

    var description: String { rawValue }
}
