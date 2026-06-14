import Foundation

struct BridgeReviewItemDescriptor: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case file
        case diff
    }

    struct ContentRoles: Codable, Equatable, Sendable {
        let base: BridgeContentHandle?
        let head: BridgeContentHandle?
        let diff: BridgeContentHandle?
        let file: BridgeContentHandle?

        init(
            base: BridgeContentHandle? = nil,
            head: BridgeContentHandle? = nil,
            diff: BridgeContentHandle? = nil,
            file: BridgeContentHandle? = nil
        ) {
            self.base = base
            self.head = head
            self.diff = diff
            self.file = file
        }

        var allHandles: [BridgeContentHandle] {
            [base, head, diff, file].compactMap { $0 }
        }
    }

    let itemId: String
    let itemKind: Kind
    let itemVersion: Int
    let basePath: String?
    let headPath: String?
    let changeKind: BridgeFileChangeKind
    let fileClass: BridgeFileClass
    let language: String?
    let `extension`: String?
    let sizeBytes: Int
    let baseContentHash: String?
    let headContentHash: String?
    let contentHashAlgorithm: String
    let additions: Int
    let deletions: Int
    let isHiddenByDefault: Bool
    let hiddenReason: String?
    let reviewPriority: BridgeReviewPriority
    let contentRoles: ContentRoles
    let cacheKey: String
    let provenance: BridgeProvenanceSummary
    let annotationSummary: BridgeAnnotationSummary
    let reviewState: BridgeFileReviewState
    let collapsed: Bool
}

struct BridgeAnnotationSummary: Codable, Equatable, Sendable {
    let threadCount: Int
    let unresolvedThreadCount: Int
    let commentCount: Int
}

struct BridgeProvenanceSummary: Codable, Equatable, Sendable {
    let paneIds: [UUID]
    let agentSessionIds: [String]
    let promptIds: [String]
    let operationIds: [String]
    let sourceKinds: [BridgeProvenanceSourceKind]

    init(
        paneIds: [UUID] = [],
        agentSessionIds: [String] = [],
        promptIds: [String] = [],
        operationIds: [String] = [],
        sourceKinds: [BridgeProvenanceSourceKind] = []
    ) {
        self.paneIds = paneIds
        self.agentSessionIds = agentSessionIds
        self.promptIds = promptIds
        self.operationIds = operationIds
        self.sourceKinds = sourceKinds
    }
}
