import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

/// S2 RED compile-level stand-in. Deliberately closes every request as missing
/// implementation so its red facts fail immediately instead of hanging a lane.
package actor PaneForegroundObserver<ObserverClock: Clock> where ObserverClock.Duration == Duration {
    private let factSink: ForegroundObserverFactSink

    package init(
        clock: ObserverClock,
        policy: ForegroundObserverPolicy,
        repository: any PaneForegroundObservationRepository,
        probe: any TerminalForegroundProbing,
        exitWatcher: any ProcessExitWatching,
        observerLaunchId: UUID,
        factSink: @escaping ForegroundObserverFactSink
    ) {
        self.factSink = factSink
    }

    package func note(_ trigger: ForegroundLookTrigger, pane: UUID) {
        factSink(.init(paneId: pane, operationId: UUIDv7.generate()), .closed(.implementationMissing))
    }

    package func retire(paneId: UUID) {
        factSink(.init(paneId: paneId, operationId: UUIDv7.generate()), .closed(.implementationMissing))
    }

    package func takePreRestoreObservation(paneId: UUID) async throws -> PaneForegroundObservation? {
        throw ForegroundImplementationMissing.s2
    }

    package func currentWatch(paneId: UUID) -> CurrentExitWatch? { nil }

    package func shutdown() {}
}
