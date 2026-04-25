import CoreGraphics
import Foundation

enum AppPolicies {
    enum WorkspaceFocus {
        enum Terminal {
            static let stickyBottomBufferPx: CGFloat = 60
        }
    }

    enum InboxNotification {
        /// Maximum number of notifications retained in the inbox per workspace.
        /// When `append` would exceed this cap, the oldest entry is evicted.
        static let maxRetained: Int = 1000
        static let maxTitleCharacters: Int = 200
        static let maxBodyCharacters: Int = 8000
        static let maxRPCPostsPerWindow: Int = 20
        static let rpcPostRateLimitWindowSeconds: TimeInterval = 60

        /// Minimum command duration before an unfocused command-finished event
        /// is promoted into inbox history.
        static let commandFinishedMinDurationSeconds: UInt64 = 10
    }
}
