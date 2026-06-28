import Foundation

enum WorktreeFileSurfaceMethods {
    enum OpenSourceStreamMethod: RPCMethod {
        typealias Params = BridgeWorktreeFileSurfaceSourceSpec
        typealias Result = BridgeWorktreeFileSurfaceOpenSourceOutcome

        static let method = "worktreeFileSurface.openSourceStream"
    }
}
