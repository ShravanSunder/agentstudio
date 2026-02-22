import Foundation

protocol PaneKindEvent: Sendable {
    var actionPolicy: ActionPolicy { get }
    var eventName: EventIdentifier { get }
}

struct EventIdentifier: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String { rawValue }

    static let commandFinished = EventIdentifier("commandFinished")
    static let cwdChanged = EventIdentifier("cwdChanged")
    static let titleChanged = EventIdentifier("titleChanged")
    static let bellRang = EventIdentifier("bellRang")
    static let scrollbarChanged = EventIdentifier("scrollbarChanged")
    static let navigationCompleted = EventIdentifier("navigationCompleted")
    static let pageLoaded = EventIdentifier("pageLoaded")
    static let diffLoaded = EventIdentifier("diffLoaded")
    static let hunkApproved = EventIdentifier("hunkApproved")
    static let contentSaved = EventIdentifier("contentSaved")
    static let fileOpened = EventIdentifier("fileOpened")
}
