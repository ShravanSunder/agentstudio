import Foundation

enum SystemMethods {
    enum HealthMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = RPCNoResponse
        static let method = "system.health"
    }

    enum CapabilitiesMethod: RPCMethod {
        struct Params: Decodable {}

        typealias Result = RPCNoResponse
        static let method = "system.capabilities"
    }

    enum ResyncAgentEventsMethod: RPCMethod {
        struct Params: Decodable {
            let fromSeq: Int
        }

        typealias Result = RPCNoResponse
        static let method = "system.resyncAgentEvents"
    }
}
