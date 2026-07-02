import Foundation

enum WorktreeFileSurfaceMethods {
    enum OpenSourceStreamMethod: RPCMethod {
        typealias Params = BridgeWorktreeFileSurfaceSourceSpec
        typealias Result = BridgeWorktreeFileSurfaceOpenSourceOutcome

        static let method = "worktreeFileSurface.openSourceStream"
    }

    enum RequestFileDescriptorMethod: RPCMethod {
        typealias Params = BridgeWorktreeFileDescriptorRequest
        typealias Result = RPCNoResponse

        static let method = "worktreeFileSurface.requestFileDescriptor"
    }
}
