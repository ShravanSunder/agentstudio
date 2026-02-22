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

    static let commandFinished = Self("commandFinished")
    static let cwdChanged = Self("cwdChanged")
    static let titleChanged = Self("titleChanged")
    static let bellRang = Self("bellRang")
    static let scrollbarChanged = Self("scrollbarChanged")
    static let navigationCompleted = Self("navigationCompleted")
    static let pageLoaded = Self("pageLoaded")
    static let diffLoaded = Self("diffLoaded")
    static let hunkApproved = Self("hunkApproved")
    static let contentSaved = Self("contentSaved")
    static let fileOpened = Self("fileOpened")
}
