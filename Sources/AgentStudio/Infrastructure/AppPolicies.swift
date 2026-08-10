import CoreGraphics
import Foundation

package enum AppPolicies {
    package enum CommandBar {
        package static let maximumHistoryCount: Int = 8
    }

    package enum EntityRecency {
        package static let maximumRetainedEntityCountPerKind: Int = 15
    }

    package enum SidebarProjection {
        package static let cancellationItemStride: Int = 256
        package static let cancellationGroupStride: Int = 64

        package enum Trigger: String, Equatable, Sendable {
            case groupingSwitch = "grouping_switch"
            case surfaceSwitch = "surface_switch"
            case search
            case sortOrder = "sort_order"
            case collapseToggle = "collapse_toggle"
            case dataRefresh = "data_refresh"
            case startupDiagnostic = "startup_diagnostic"
        }
    }

    package enum Diagnostics {
        package static let traceEventQueueBufferLimit: Int = 4096
        /// Native hot-path performance facts must shed before reaching
        /// swift-otel. Topology lookup telemetry is informational, so repeated
        /// derived/UI reads should never be able to saturate the exporter.
        package static let topologyLookupTraceAdmissionWindow: Duration = .seconds(1)
        package static let topologyLookupTraceAdmissionLimit: Int = 32
        /// Downstream swift-otel log batch queue. swift-otel drops newly
        /// emitted logs once this fills, so keep it above the app trace event
        /// queue and let the app-side queue remain the oldest-shedding layer.
        package static let otlpLogMaxQueueSize: Int = 8192
        package static let otlpLogMaxExportBatchSize: Int = 1024
        package static let otlpLogScheduleDelay: Duration = .seconds(1)
        package static let otlpTraceScheduleDelay: Duration = .seconds(1)
        package static let otlpMetricsExportInterval: Duration = .seconds(60)
        package static let otlpExportTimeout: Duration = .seconds(30)
    }

    package enum Bridge {
        /// Retention cap for one content body: a single item must never evict
        /// the whole byte cache, and larger bodies render as oversized.
        package static let contentMaxBytesPerItem: Int = 16 * 1024 * 1024
        /// Desktop byte-cache residency target. At 128MB this keeps at least
        /// 8 max-size content bodies warm, avoiding re-fetch/re-highlight
        /// churn without letting one item define total retention.
        package static let contentCacheMaxBytes: Int = 128 * 1024 * 1024
        package static let defaultGitDataPlaneReadTimeout: Duration = .seconds(30)
        /// Recovery guardrail for queued Bridge Git reads in each operation
        /// class. S10b owns workload calibration; this value prevents the
        /// pre-calibration scheduler from accepting an unbounded backlog.
        package static let gitReadSchedulerMaxQueuedOperationsPerClass: Int = 64
        /// Recovery guardrail for callers sharing one identical physical Git
        /// read. S10b may recalibrate this after the multi-worktree workload.
        package static let gitReadSchedulerMaxLogicalWaitersPerOperation: Int = 16
        /// File tree admission may enrich from full git status only when that
        /// read fits inside the native viewer journey budget. On timeout the
        /// tracked-aware filesystem fallback keeps tree publication moving.
        package static let worktreeFileManifestStatusReadTimeout: Duration = .milliseconds(100)
        package static let ipcMaxResponsePayloadBytes: Int = 768 * 1024
        /// Worktree/File metadata window size for the startup snapshot and
        /// continuation tree windows. Provisional until the OD4 profiling
        /// gate graduates it; proof asserts observed windows equal this
        /// constant rather than a literal.
        package static let worktreeFileTreeMetadataWindowRowLimit: Int = 200
        /// Idle no-starvation budget for the metadata lane scheduler: after
        /// this many higher-lane jobs drain while idle work waits, the next
        /// dispatch is one idle batch. Provisional until the OD4 profiling
        /// gate graduates it.
        package static let metadataIdleNoStarvationBudget: Int = 4
        /// Background review content fill yields as soon as this many
        /// selected/visible content requests are pending in the native
        /// scheme handler. The current contract is strict user-interest
        /// reservation: any selected/visible request pauses background fill.
        package static let contentBackgroundFillUserInterestYieldThreshold: Int = 1
        /// Interactive background fill starts with a tiny burst, then admits
        /// one background content request per interval until recent user
        /// interest cools down. The debug-observability-oq4s-1783162673-24877
        /// session saw 2408 background-interest loads in a few minutes while
        /// scrolling; one sustained refill per second keeps active-use fill
        /// near 60/minute, an order-of-magnitude calmer than that session,
        /// while the idle path remains unpaced for startup pre-warm.
        package static let contentBackgroundFillInteractiveBurstBudget: Int = 12
        package static let contentBackgroundFillInteractiveRefillInterval: Duration = .seconds(1)
        package static let contentBackgroundFillInteractiveRefillBudget: Int = 1
        package static let contentBackgroundFillInteractiveCooldown: Duration = .seconds(2)
        /// Per-lane queued-job cap for the metadata lane scheduler. A pane
        /// whose gate never reopens (wedged or dead WebView) must not grow
        /// its queues without bound from watch-driven producers; on overflow
        /// the scheduler drops the lane's oldest job and emits an overflow
        /// drop so the loss is observable, never silent. Recovery is the
        /// normal reset/reopen path, which rebuilds from the manifest.
        package static let metadataSchedulerMaxQueuedJobsPerLane: Int = 256
        /// R46 execution budget for BridgeWeb's main-thread apply pump. The
        /// BridgeWeb mirror is source-scanned by AppPoliciesBridgeTests because
        /// this app cannot import TypeScript constants.
        package static let applyPumpFrameBudgetMilliseconds: Int = 8
        package static let applyPumpMaxUnitsPerFrame: Int = 4
        package static let applyPumpStaleScanLimit: Int = 64
        package static let applyPumpNoStarvationSelectedBatchLimit: Int = 3
        package static let selectedApplyInitialWindowLineCount: Int = 1500
    }

    package enum WorkspacePersistence {
        package static let debouncedAutosaveFailureDampingThreshold: Int = 3
    }

    package enum TerminalActivation {
        package static let maximumConcurrentAdmissions: Int = 4
    }

    package enum TerminalLocalAction {
        package static let titleMainActorAdmissionSlackNanoseconds: UInt64 = 100_000_000
    }

    package enum NonterminalContentMount {
        package static let maximumMountsPerMainActorTurn: Int = 4
    }

    package enum GitRefresh {
        package static let defaultPolicy = Policy()
        package static let defaultStatusReadTimeout: Duration = .seconds(1)
        package static let defaultDiscoveryReadTimeout: Duration = .seconds(2)
        package static let defaultDetachedStatusReadLimit: Int = 4
        package static let filesystemDebounceWindow: Duration = .milliseconds(500)
        package static let filesystemMaxFlushLatency: Duration = .seconds(10)
        package static let filesystemDerivedCoalescingWindow: Duration = .milliseconds(500)

        package struct Policy: Equatable, Sendable {
            package let activeCadence: Duration
            package let backgroundStripeCount: Int
            package let maxConcurrentStatusComputes: Int
            package let oldestStaleReservedSlots: Int
            package let suppressedWorktreeTombstoneLimit: Int
            package let maxNilStatusRetries: Int
            package let nilStatusRetryDelay: Duration
            /// First backoff step applied when a worktree's status compute times
            /// out. The per-worktree circuit breaker doubles this per consecutive
            /// failure up to `statusFailureBackoffMaxDelay`, coalescing file-change
            /// events that arrive during the open window into one deferred refresh.
            package let statusFailureBackoffBaseDelay: Duration
            package let statusFailureBackoffMultiplier: Int
            package let statusFailureBackoffMaxDelay: Duration
            /// Short bounded retry window for shared read-capacity contention. This
            /// is deliberately separate from the failure breaker because a busy
            /// global pool is not evidence that a worktree is unhealthy.
            package let capacityRetryBaseDelay: Duration
            package let capacityRetryJitterMaxDelay: Duration
            /// Maximum changed-path count a file-change batch may carry and still
            /// be refreshed with a pathspec-scoped status. Beyond this the
            /// projector falls back to a full-worktree status, since a very large
            /// pathspec set approaches full-tree walk cost anyway.
            package let maxScopedStatusPathspecCount: Int

            package init(
                activeCadence: Duration = .seconds(15),
                backgroundStripeCount: Int = 16,
                maxConcurrentStatusComputes: Int = 4,
                oldestStaleReservedSlots: Int = 1,
                suppressedWorktreeTombstoneLimit: Int = 1024,
                maxNilStatusRetries: Int = 1,
                nilStatusRetryDelay: Duration = .seconds(5),
                statusFailureBackoffBaseDelay: Duration = .seconds(5),
                statusFailureBackoffMultiplier: Int = 2,
                statusFailureBackoffMaxDelay: Duration = .seconds(60),
                capacityRetryBaseDelay: Duration = .milliseconds(500),
                capacityRetryJitterMaxDelay: Duration = .milliseconds(100),
                maxScopedStatusPathspecCount: Int = 128
            ) {
                precondition(backgroundStripeCount > 0)
                precondition(maxConcurrentStatusComputes > 0)
                precondition(oldestStaleReservedSlots >= 0)
                precondition(suppressedWorktreeTombstoneLimit > 0)
                precondition(maxNilStatusRetries >= 0)
                precondition(statusFailureBackoffBaseDelay > .zero)
                precondition(statusFailureBackoffMultiplier >= 1)
                precondition(statusFailureBackoffMaxDelay >= statusFailureBackoffBaseDelay)
                precondition(capacityRetryBaseDelay > .zero)
                precondition(capacityRetryJitterMaxDelay >= .zero)
                precondition(maxScopedStatusPathspecCount > 0)

                self.activeCadence = activeCadence
                self.backgroundStripeCount = backgroundStripeCount
                self.maxConcurrentStatusComputes = maxConcurrentStatusComputes
                self.oldestStaleReservedSlots = oldestStaleReservedSlots
                self.suppressedWorktreeTombstoneLimit = suppressedWorktreeTombstoneLimit
                self.maxNilStatusRetries = maxNilStatusRetries
                self.nilStatusRetryDelay = nilStatusRetryDelay
                self.statusFailureBackoffBaseDelay = statusFailureBackoffBaseDelay
                self.statusFailureBackoffMultiplier = statusFailureBackoffMultiplier
                self.statusFailureBackoffMaxDelay = statusFailureBackoffMaxDelay
                self.capacityRetryBaseDelay = capacityRetryBaseDelay
                self.capacityRetryJitterMaxDelay = capacityRetryJitterMaxDelay
                self.maxScopedStatusPathspecCount = maxScopedStatusPathspecCount
            }

            /// Exponential per-worktree backoff for status computes that time out
            /// `failureCount` is the number of consecutive failures (1 for the
            /// first). Each step multiplies by `statusFailureBackoffMultiplier`,
            /// clamped to `statusFailureBackoffMaxDelay`.
            package func statusFailureBackoffDelay(forConsecutiveFailureCount failureCount: Int) -> Duration {
                guard failureCount > 1 else {
                    return min(statusFailureBackoffBaseDelay, statusFailureBackoffMaxDelay)
                }
                var delay = statusFailureBackoffBaseDelay
                for _ in 1..<failureCount {
                    delay = Self.scaled(delay, by: statusFailureBackoffMultiplier)
                    if delay >= statusFailureBackoffMaxDelay {
                        return statusFailureBackoffMaxDelay
                    }
                }
                return min(delay, statusFailureBackoffMaxDelay)
            }

            package func capacityRetryDelay(for worktreeId: UUID) -> Duration {
                capacityRetryBaseDelay
                    + Self.jitterDelay(
                        maxDelay: capacityRetryJitterMaxDelay,
                        worktreeId: worktreeId
                    )
            }

            package var backgroundCadence: Duration {
                Self.scaled(activeCadence, by: backgroundStripeCount)
            }

            package func backgroundStripe(for worktreeId: UUID) -> Int {
                Int(Self.stableHash(for: worktreeId) % UInt64(backgroundStripeCount))
            }

            package func isBackgroundWorktreeDue(_ worktreeId: UUID, tick: UInt64) -> Bool {
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

            private static func jitterDelay(maxDelay: Duration, worktreeId: UUID) -> Duration {
                let maxNanoseconds = nanoseconds(from: maxDelay)
                guard maxNanoseconds > 0 else { return .zero }
                let jitterNanoseconds = Int64(stableHash(for: worktreeId) % UInt64(maxNanoseconds + 1))
                return .nanoseconds(jitterNanoseconds)
            }

            private static func nanoseconds(from duration: Duration) -> Int64 {
                let components = duration.components
                let seconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
                guard seconds.overflow == false else { return seconds.partialValue }
                return seconds.partialValue + components.attoseconds / 1_000_000_000
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

    package enum WatchedFolderScanning {
        package static let maximumConcurrentTraversalQuanta: Int = 2
        package static let fallbackCadence: Duration = .seconds(300)
    }

    package enum ZmxStartup {
        package static let reconciliationTimeout: Duration = .seconds(3)
    }

    package enum StartupDiagnostic {
        package static let appActivationTimeout: Duration = .seconds(2)
        package static let launchRestoreBoundsTimeout: Duration = .seconds(3)
        package static let ipcTerminalSmokeReadinessTimeout: Duration = .seconds(10)
        package static let bridgeFileViewSmokeReadinessTimeout: Duration = .seconds(15)
        /// Review startup smoke covers pane mount, BridgeWeb intake-ready,
        /// native package load, metadata apply, projection, selected content,
        /// worker-pool readiness, and tree/click convergence. It is a heavier
        /// proof path than the IPC terminal and File View smokes.
        package static let bridgeReviewSmokeReadinessTimeout: Duration = .seconds(20)
    }

    package enum SelectablePopover {
        package static let maxNumberedShortcuts: Int = 9
    }

    package enum PaneInbox {
        package static let maxVisibleNotifications: Int = 25
        package static let unreadBadgeDisplayLimit: Int = 9
    }

    package enum WorkspaceFocus {
        package enum Terminal {
            package static let stickyBottomBufferPx: CGFloat = 48
        }
    }

    package enum InboxNotification {
        /// Maximum number of notifications retained in the inbox per workspace.
        /// When `append` would exceed this cap, the oldest entry is evicted.
        package static let maxRetained: Int = 1000
        package static let maxTitleCharacters: Int = 200
        package static let maxBodyCharacters: Int = 8000
        package static let maxRPCPostsPerWindow: Int = 20
        package static let rpcPostRateLimitWindowSeconds: TimeInterval = 60

        /// Minimum command duration before a command-finished event
        /// is promoted into inbox history.
        package static let commandFinishedMinDurationNanoseconds: UInt64 = 10_000_000_000
        /// Durations beyond one week are treated as corrupt runtime payloads.
        package static let commandFinishedMaxTrustedDurationNanoseconds: UInt64 = 604_800_000_000_000
        package static let terminalActivityOutputBurstThresholdRows: Int = 30
        package static let terminalActivityQuietDebounceDuration: Duration = .milliseconds(750)
        package static let agentSettledMinimumRows: Int = 100
        package static let agentSettledHighConfidenceRows: Int = 500
        package static let agentSettledMinimumCandidateDuration: Duration = .seconds(60)
        package static let agentSettledMinimumActiveDuration: Duration = .seconds(360)
        package static let agentSettledQuietDuration: Duration = .seconds(180)
        package static let terminalActivitySessionIdleTimeoutDuration: Duration = .seconds(300)
    }

    /// Drag-and-drop behavioral rules. These are decisions about HOW the
    /// drag system works, not how it looks. Visual constants (marker
    /// width, opacity, animation) live in `AppStyles`.
    package enum DragAndDrop {
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
        package static let paneRowSideZoneFraction: CGFloat = 0.25

        /// Side-zone hittability floor in points. On narrow panes the
        /// natural side fraction collapses below this; the side zones
        /// grow to this floor and the center zone shrinks (or
        /// disappears when the pane can't host all three zones).
        package static let paneRowSideZoneFloor: CGFloat = 24

        /// Drawer new-row creation band — fraction of drawer panel
        /// height for the top/bottom drop zones that create a new row.
        /// Only applies to single-row drawers (two-row is at max).
        package static let drawerNewRowBandRatio: CGFloat = 0.2

        /// Floor for the drawer new-row creation band height. On short
        /// drawers the ratio drops below this; the band stays at this
        /// minimum height.
        package static let drawerNewRowBandMinHeight: CGFloat = 28

        /// Drawer hard cap on number of stacked rows. The drawer never
        /// exceeds this; new-row band targets are unavailable when the
        /// drawer is at this row count.
        package static let drawerMaxRows: Int = 2

        /// Minimum pane size after a split or resize. Splits that would
        /// produce a child smaller than this are forbidden.
        package static let splitMinimumPaneSize: CGFloat = 10
    }
}
