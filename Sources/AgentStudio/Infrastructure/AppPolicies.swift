import CoreGraphics

enum AppPolicies {
    enum WorkspaceFocus {
        enum Terminal {
            static let stickyBottomBufferPx: CGFloat = 60
        }
    }

    enum InboxNotification {
        /// Maximum number of notifications retained in the inbox per workspace.
        /// When `append` would exceed this cap, the oldest entry is evicted.
        /// Provisional; revisit if real usage requires deeper history. (LUNA-361)
        static let maxRetained: Int = 1000
    }
}
