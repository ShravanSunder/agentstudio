import Foundation

enum BridgeFileClass: String, Codable, Equatable, Sendable {
    case source
    case test
    case docs
    case config
    case generated
    case vendor
    case binary
    case large
    case fixture
    case unknown
}

enum BridgeFileChangeKind: String, Codable, Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
}

enum BridgeFileReviewState: String, Codable, Equatable, Sendable {
    case unreviewed
    case viewed
    case annotated
    case resolved
}

enum BridgeReviewPriority: String, Codable, Equatable, Sendable {
    case low
    case normal
    case high
}
