import Foundation

enum ReviewMethods {
    enum AddCommentMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            enum Side: String, Decodable, Sendable {
                case left
                case right
            }

            let fileId: String
            let lineNumber: Int?
            let side: Side?
            let text: String
        }

        typealias Result = RPCNoResponse
        static let method = "review.addComment"
    }

    enum ResolveThreadMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let threadId: String
        }

        typealias Result = RPCNoResponse
        static let method = "review.resolveThread"
    }

    enum UnresolveThreadMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let threadId: String
        }

        typealias Result = RPCNoResponse
        static let method = "review.unresolveThread"
    }

    enum DeleteCommentMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let commentId: String
        }

        typealias Result = RPCNoResponse
        static let method = "review.deleteComment"
    }

    enum MarkFileViewedMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let fileId: String
        }

        typealias Result = RPCNoResponse
        static let method = "review.markFileViewed"
    }

    enum UnmarkFileViewedMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let fileId: String
        }

        typealias Result = RPCNoResponse
        static let method = "review.unmarkFileViewed"
    }

    enum MetadataInterestUpdateMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            private enum CodingKeys: String, CodingKey {
                case protocolId = "protocol"
                case streamId
                case generation
                case itemIds
                case paths
                case lane
                case loadedBy = "loaded_by"
            }

            let protocolId: String
            let streamId: String?
            let generation: Int?
            let itemIds: [String]?
            let paths: [String]?
            let lane: BridgeDemandLane
            let loadedBy: BridgeReviewMetadataLoadedBy?
        }

        typealias Result = RPCNoResponse
        static let method = "bridge.metadata_interest.update"
    }
}
