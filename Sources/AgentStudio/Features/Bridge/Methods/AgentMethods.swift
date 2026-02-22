import Foundation

enum AgentMethods {
    enum RequestRewriteSourceType: Decodable, Equatable, Sendable {
        case threadIds
        case prompt
        case selection
        case unknown(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            switch rawValue {
            case "threadIds":
                self = .threadIds
            case "prompt":
                self = .prompt
            case "selection":
                self = .selection
            default:
                self = .unknown(rawValue)
            }
        }
    }

    enum RequestRewriteMethod: RPCMethod {
        struct Params: Decodable {
            struct Source: Decodable {
                let type: RequestRewriteSourceType
                let threadIds: [String]
            }

            let source: Source?
            let text: String?
            let prompt: String?
            let threadIds: [String]?
        }

        typealias Result = RPCNoResponse
        static let method = "agent.requestRewrite"
    }

    enum CancelTaskMethod: RPCMethod {
        struct Params: Decodable {
            let taskId: String
        }

        typealias Result = RPCNoResponse
        static let method = "agent.cancelTask"
    }

    enum InjectPromptMethod: RPCMethod {
        struct Params: Decodable {
            let text: String
        }

        typealias Result = RPCNoResponse
        static let method = "agent.injectPrompt"
    }
}
