import Foundation

enum InboxMethods {
    enum PostMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let title: String
            let body: String?
        }

        typealias Result = RPCNoResponse
        static let method = "inbox.post"
    }
}
