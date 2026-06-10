import Foundation

struct BridgeReviewQuery: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case compare
        case openFile
        case browseTree
        case filterPackage
        case groupPackage
    }

    enum ComparisonSemantics: String, Codable, Equatable, Sendable {
        case twoDot
        case threeDot
        case checkpointDelta
        case indexDelta
        case workingTreeDelta
        case notApplicable
    }

    let queryId: String
    let queryKind: Kind
    let repoId: UUID
    let worktreeId: UUID
    let baseEndpointId: String?
    let headEndpointId: String?
    let comparisonSemantics: ComparisonSemantics
    let pathScope: [String]
    let fileTarget: String?
    let viewFilter: BridgeViewFilter
    let grouping: BridgeChangeGrouping
    let provenanceFilter: BridgeProvenanceFilter
}
