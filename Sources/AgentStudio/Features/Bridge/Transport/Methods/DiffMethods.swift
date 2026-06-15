import Foundation

enum DiffMethods {
    enum LoadDiffMethod: RPCMethod {
        struct Params: Decodable, Sendable {
            let worktreeId: UUID
            let diffId: UUID?
            let head: String?
            let base: String?
        }

        typealias Result = RPCNoResponse
        static let method = "diff.loadDiff"
    }
}
