import Foundation

enum BridgeReadyMethod: RPCMethod {
    struct Params: Decodable {}
    typealias Result = RPCNoResponse

    static let method = "bridge.ready"
}

enum BridgeIntakeReadyMethod: RPCMethod {
    struct Params: Decodable {
        let protocolId: String
        let streamId: String?
        let generation: Int?

        init(protocolId: String, streamId: String?, generation: Int? = nil) {
            self.protocolId = protocolId
            self.streamId = streamId
            self.generation = generation
        }
    }
    typealias Result = RPCNoResponse

    static let method = "bridge.intakeReady"
}

enum BridgeError: Error, LocalizedError, Sendable {
    case encoding(String)

    var errorDescription: String? {
        switch self {
        case .encoding(let message):
            return message
        }
    }
}

struct BridgeMethodUnimplementedError: Error, LocalizedError, Sendable {
    let method: String

    var errorDescription: String? {
        "Unimplemented bridge method: \(method)"
    }
}
