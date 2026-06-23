import Foundation

enum WorktreeFileSurfaceMethods {
    enum OpenSourceStreamMethod: RPCMethod {
        typealias Params = BridgeWorktreeFileSurfaceSourceSpec
        typealias Result = BridgeWorktreeSnapshotFrame

        static let method = "worktreeFileSurface.openSourceStream"
    }
}
