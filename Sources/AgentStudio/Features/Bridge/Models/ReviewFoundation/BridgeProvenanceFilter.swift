import Foundation

enum BridgeProvenanceSourceKind: String, Codable, Equatable, Sendable {
    case runtimeEvent
    case filesystemWatch
    case gitStatus
    case manualScan
}

struct BridgeProvenanceFilter: Codable, Equatable, Sendable {
    let paneIds: [UUID]
    let agentSessionIds: [String]
    let promptIds: [String]
    let operationIds: [String]
    let createdAfterUnixMilliseconds: Int64?
    let createdBeforeUnixMilliseconds: Int64?
    let sourceKinds: [BridgeProvenanceSourceKind]

    init(
        paneIds: [UUID] = [],
        agentSessionIds: [String] = [],
        promptIds: [String] = [],
        operationIds: [String] = [],
        createdAfterUnixMilliseconds: Int64? = nil,
        createdBeforeUnixMilliseconds: Int64? = nil,
        sourceKinds: [BridgeProvenanceSourceKind] = []
    ) {
        self.paneIds = paneIds
        self.agentSessionIds = agentSessionIds
        self.promptIds = promptIds
        self.operationIds = operationIds
        self.createdAfterUnixMilliseconds = createdAfterUnixMilliseconds
        self.createdBeforeUnixMilliseconds = createdBeforeUnixMilliseconds
        self.sourceKinds = sourceKinds
    }
}
