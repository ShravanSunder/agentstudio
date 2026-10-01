import AgentStudioCore
import Foundation

package enum ObservationAdmission: Equatable, Sendable {
    case admitted, retiredPane, bindingChanged, olderLook, invalidIdentity
}

package struct ForegroundPaneBinding: Equatable, Sendable {
    package let paneId: UUID
    package let sessionId: ZmxSessionID
    package let bindingGenerationId: UUID?
}

package protocol PaneForegroundObservationRepository: Sendable {
    func eligiblePanes() async throws -> [ForegroundPaneBinding]
    func admit(_ observation: PaneForegroundObservation) async throws -> ObservationAdmission
    func load(paneId: UUID) async throws -> PaneForegroundObservation?
    func retire(paneId: UUID) async throws
}

package struct ForegroundSnapshot: Equatable, Sendable {
    package let sessionIdentity: Data
    package let foregroundProcess: ProcessIncarnation?
    package let program: ForegroundProgram
}

package protocol TerminalForegroundProbing: Sendable {
    func probeForeground(of sessions: [ZmxSessionID]) async throws -> [ZmxSessionID: ForegroundSnapshot]
}

package enum ForegroundLookTrigger: Sendable {
    case bindingChanged, agentMessage, appQuitting, relaunched
    case outputBegan(burstWindowId: UUID)
    case outputSettled(burstWindowId: UUID)
}

package struct CurrentExitWatch: Equatable, Sendable {
    package let watchId: UUID
    package let incarnation: ProcessIncarnation
    package let bindingGenerationId: UUID?
}

package struct ForegroundObserverPolicy: Sendable {
    package let lookSettleDelay: Duration
    package let lookMaxDelay: Duration
    package let quitLookDeadline: Duration
}

package struct ForegroundObserverFactScope: Hashable, Sendable {
    package let paneId: UUID
    package let operationId: UUID
}

package enum ForegroundObserverFact: Equatable, Sendable {
    case scheduled
    case snapshotStarted(sequence: UInt64)
    case observation(ObservationAdmission)
    case watchRegistered(watchId: UUID)
    case watchUnavailable(ProcessExitWatchFailure)
    case staleWatchDropped(watchId: UUID)
    case closed(ForegroundObserverClose)
}

package enum ForegroundObserverClose: Equatable, Sendable {
    case scheduled, looked, retired, quit, quitDeadline, implementationMissing
}

package typealias ForegroundObserverFactSink = @Sendable (ForegroundObserverFactScope, ForegroundObserverFact) -> Void

package enum ForegroundImplementationMissing: Error {
    case s2
}
