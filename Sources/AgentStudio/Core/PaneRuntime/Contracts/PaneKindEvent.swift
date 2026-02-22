import Foundation

protocol PaneKindEvent: Sendable {
    var actionPolicy: ActionPolicy { get }
    var eventName: EventIdentifier { get }
}

enum EventIdentifier: Hashable, Sendable, CustomStringConvertible {
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
