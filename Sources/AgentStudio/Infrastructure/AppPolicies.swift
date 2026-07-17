import CoreGraphics
import Foundation

enum AppPolicies {
    enum SidebarProjection {
        static let cancellationItemStride: Int = 256
        static let cancellationGroupStride: Int = 64

        enum Trigger: String, Equatable, Sendable {
            case groupingSwitch = "grouping_switch"
            case surfaceSwitch = "surface_switch"
            case search
            case sortOrder = "sort_order"
            case visibilityMode = "visibility_mode"
            case collapseToggle = "collapse_toggle"
            case dataRefresh = "data_refresh"
            case startupDiagnostic = "startup_diagnostic"
        }
    }

    enum Diagnostics {
        static let traceEventQueueBufferLimit: Int = 4096
    }

    enum Bridge {
        static let contentCacheMaxBytes: Int = 50 * 1024 * 1024
        static let contentMaxBytesPerItem: Int = 50 * 1024 * 1024
    }

    enum WorkspacePersistence {
        static let debouncedAutosaveFailureDampingThreshold: Int = 3
    }

    enum GitRefresh {
        static let defaultPolicy = Policy()
        static let defaultStatusReadTimeout: Duration = .seconds(1)
        static let defaultDiscoveryReadTimeout: Duration = .seconds(2)

        struct Policy: Equatable, Sendable {
            let activeCadence: Duration
            let backgroundStripeCount: Int
            let maxConcurrentStatusComputes: Int
            let oldestStaleReservedSlots: Int
            let suppressedWorktreeTombstoneLimit: Int
            let maxNilStatusRetries: Int
            let nilStatusRetryDelay: Duration

            init(
                activeCadence: Duration = .seconds(15),
                backgroundStripeCount: Int = 16,
                maxConcurrentStatusComputes: Int = 4,
                oldestStaleReservedSlots: Int = 1,
                suppressedWorktreeTombstoneLimit: Int = 1024,
                maxNilStatusRetries: Int = 1,
                nilStatusRetryDelay: Duration = .seconds(5)
            ) {
                precondition(backgroundStripeCount > 0)
                precondition(maxConcurrentStatusComputes > 0)
                precondition(oldestStaleReservedSlots >= 0)
                precondition(suppressedWorktreeTombstoneLimit > 0)
                precondition(maxNilStatusRetries >= 0)

                self.activeCadence = activeCadence
                self.backgroundStripeCount = backgroundStripeCount
                self.maxConcurrentStatusComputes = maxConcurrentStatusComputes
                self.oldestStaleReservedSlots = oldestStaleReservedSlots
                self.suppressedWorktreeTombstoneLimit = suppressedWorktreeTombstoneLimit
                self.maxNilStatusRetries = maxNilStatusRetries
                self.nilStatusRetryDelay = nilStatusRetryDelay
            }

            var backgroundCadence: Duration {
                Self.scaled(activeCadence, by: backgroundStripeCount)
            }

            func backgroundStripe(for worktreeId: UUID) -> Int {
                Int(Self.stableHash(for: worktreeId) % UInt64(backgroundStripeCount))
            }

            func isBackgroundWorktreeDue(_ worktreeId: UUID, tick: UInt64) -> Bool {
                let currentStripe = Int(tick % UInt64(backgroundStripeCount))
                return backgroundStripe(for: worktreeId) == currentStripe
            }

            private static func scaled(_ duration: Duration, by multiplier: Int) -> Duration {
                var scaledDuration = Duration.zero
                for _ in 0..<multiplier {
                    scaledDuration += duration
                }
                return scaledDuration
            }

            private static func stableHash(for worktreeId: UUID) -> UInt64 {
                var hash: UInt64 = 14_695_981_039_346_656_037
                let prime: UInt64 = 1_099_511_628_211

                withUnsafeBytes(of: worktreeId.uuid) { bytes in
                    for byte in bytes {
                        hash ^= UInt64(byte)
                        hash &*= prime
                    }
                }

                return hash
            }
        }
    }

    enum ZmxStartup {
        static let reconciliationTimeout: Duration = .seconds(3)
    }

    enum StartupDiagnostic {
        static let appActivationTimeout: Duration = .seconds(2)
        static let launchRestoreBoundsTimeout: Duration = .seconds(3)
        static let ipcTerminalSmokeReadinessTimeout: Duration = .seconds(10)
    }

    enum SelectablePopover {
        static let maxNumberedShortcuts: Int = 9
    }

    enum PaneInbox {
        static let maxVisibleNotifications: Int = 25
        static let unreadBadgeDisplayLimit: Int = 9
    }

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

        /// Minimum command duration before a command-finished event
        /// is promoted into inbox history.
        static let commandFinishedMinDurationNanoseconds: UInt64 = 10_000_000_000
        /// Durations beyond one week are treated as corrupt runtime payloads.
        static let commandFinishedMaxTrustedDurationNanoseconds: UInt64 = 604_800_000_000_000
        static let terminalActivityOutputBurstThresholdRows: Int = 30
        static let terminalActivityQuietDebounceDuration: Duration = .milliseconds(750)
        static let agentSettledMinimumRows: Int = 100
        static let agentSettledHighConfidenceRows: Int = 500
        static let agentSettledMinimumCandidateDuration: Duration = .seconds(60)
        static let agentSettledMinimumActiveDuration: Duration = .seconds(360)
        static let agentSettledQuietDuration: Duration = .seconds(180)
        static let terminalActivitySessionIdleTimeoutDuration: Duration = .seconds(300)
    }

    /// Drag-and-drop behavioral rules. These are decisions about HOW the
    /// drag system works, not how it looks. Visual constants (marker
    /// width, opacity, animation) live in `AppStyles`.
    enum DragAndDrop {
        /// Cursor zone partition for a pane in a row: each side gets
        /// this fraction of the pane width, the center keeps the rest.
        ///
        ///     ┌──────┬─────────────────────┬──────┐
        ///     │ 1/4  │        1/2          │ 1/4  │
        ///     │ left │       center        │ right│
        ///     └──────┴─────────────────────┴──────┘
        ///
        /// Side zones resolve to slot targets (between/edge insert);
        /// the center zone resolves to a split target.
        static let paneRowSideZoneFraction: CGFloat = 0.25

        /// Side-zone hittability floor in points. On narrow panes the
        /// natural side fraction collapses below this; the side zones
        /// grow to this floor and the center zone shrinks (or
        /// disappears when the pane can't host all three zones).
        static let paneRowSideZoneFloor: CGFloat = 24

        /// Drawer new-row creation band — fraction of drawer panel
        /// height for the top/bottom drop zones that create a new row.
        /// Only applies to single-row drawers (two-row is at max).
        static let drawerNewRowBandRatio: CGFloat = 0.2

        /// Floor for the drawer new-row creation band height. On short
        /// drawers the ratio drops below this; the band stays at this
        /// minimum height.
        static let drawerNewRowBandMinHeight: CGFloat = 28

        /// Drawer hard cap on number of stacked rows. The drawer never
        /// exceeds this; new-row band targets are unavailable when the
        /// drawer is at this row count.
        static let drawerMaxRows: Int = 2

        /// Minimum pane size after a split or resize. Splits that would
        /// produce a child smaller than this are forbidden.
        static let splitMinimumPaneSize: CGFloat = 10
    }
}
