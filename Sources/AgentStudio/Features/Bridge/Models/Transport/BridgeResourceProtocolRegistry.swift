import Foundation

enum BridgeResourceProtocolRegistry {
    static let reviewViewerAllowedResourceKinds: [String: Set<String>] = [
        "review": Set(["content", "review-package"]),
        "worktree-file": Set(["tree", "file-content"]),
    ]
}
