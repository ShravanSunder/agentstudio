import Foundation

struct BridgeChangeGrouping: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case flat
        case folder
        case fileClass
        case changeKind
        case reviewState
        case agentStream
        case prompt
        case session
        case checkpoint
        case timeWindow
        case custom
    }

    let kind: Kind
    let label: String?

    init(kind: Kind = .flat, label: String? = nil) {
        self.kind = kind
        self.label = label
    }
}
