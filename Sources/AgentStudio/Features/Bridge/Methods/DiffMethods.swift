import Foundation

enum DiffMethods {
    enum RequestFileContentsMethod: RPCMethod {
        struct Params: Decodable {
            let fileId: String
        }

        typealias Result = RPCNoResponse
        static let method = "diff.requestFileContents"
    }

    enum LoadDiffMethod: RPCMethod {
        struct Params: Decodable {
            let source: String?
            let head: String?
            let base: String?
        }

        typealias Result = RPCNoResponse
        static let method = "diff.loadDiff"
    }
}
