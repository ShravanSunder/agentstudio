import Foundation

enum BridgeResourceProtocolRegistry {
    static let reviewContentResourceKinds: [String: Set<String>] = [
        "review": Set(["content"])
    ]

    static let reviewViewerAllowedResourceKinds: [String: Set<String>] = [
        "review": Set(["content"]),
        "worktree-file": Set([
            "worktree.fileContent",
            "worktree.fileRange",
        ]),
    ]
}
