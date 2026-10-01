import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal

/// Compile-only S3 first-frame boundary; no startup work is installed yet.
@MainActor
func startScrollbackAfterFirstFrame(
    windowLifecycleStore: WindowLifecycleAtom, snapshotter: ScrollbackSnapshotter
) async -> StartupDeferralOutcome {
    .cancelled
}

/// Compile-only S3 quit boundary; neither capture nor shutdown is called yet.
@MainActor
func captureScrollbackBeforeSurfaceShutdown(
    snapshotter: ScrollbackSnapshotter, budget: Duration, shutdown: () async -> Void
) async {}
