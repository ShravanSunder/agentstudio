import Foundation

enum AgentMethods {
    enum RequestRewriteMethod: RPCMethod {
        struct Params: Decodable {
            struct Source: Decodable {
                let type: String
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
