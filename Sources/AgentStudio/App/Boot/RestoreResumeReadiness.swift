import Foundation

// S3 RED stand-in: declare the two readiness outcomes without publication.
enum RestoreResumeReadinessResult: Equatable, Sendable { case ready, unavailable }

// S3 RED stand-in: the typed facts are declared but never emitted.
enum RestoreResumeReadinessFact: Equatable, Sendable {
    case listenerReady
    case boundaryRead(LifecycleReportBoundary)
    case launchPrepared
    case reportsTakenIn(LifecycleReportBoundary)
    case published(RestoreResumeReadinessResult)
    case waiting
    case decided(RestoreResumeReadinessResult)
}

// S3 RED stand-in: no clock task, publication or waiting; readiness is unavailable.
actor RestoreResumeReadiness<ReadinessClock: Clock> where ReadinessClock.Duration == Duration {
    init(
        clock: ReadinessClock, deadline: Duration, launchId: UUID,
        factSink: @escaping @Sendable (UUID, RestoreResumeReadinessFact) -> Void
    ) {}

    func wait(paneId: UUID) -> RestoreResumeReadinessResult { .unavailable }
    func shutdown() {}
}

extension AppIPCDeferredInitialization {
    // S3 RED stand-in: perform no listener/S0 capture, launch sweep, intake or publication.
    @concurrent nonisolated static func prepareResumeReadiness<ReadinessClock: Clock>(
        readiness: RestoreResumeReadiness<ReadinessClock>,
        intake: any LifecycleReportIntaking = NoStoreLifecycleReportIntake(),
        prepareForLaunch: @escaping @Sendable () async throws -> Void
    ) async where ReadinessClock.Duration == Duration {}
}
