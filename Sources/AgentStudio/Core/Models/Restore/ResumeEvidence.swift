import Foundation

package enum ResumeUnknownReason: Equatable, Sendable {
    case noObservation, observationMismatch, programNotAgent, startedFromHistoricalReport
    case evidenceUnordered, invalidSessionId, unknownProvider, reportsNotTakenIn
}

package enum ResumeEvidence: Equatable, Sendable {
    case knownExited(ProviderEndReason)
    case interruptedCandidate(ResumeInvocation)
    case unknown(ResumeUnknownReason)
}

package struct ResumeEvidenceInput: Sendable {
    package let paneId: UUID
    package let zmxSessionId: ZmxSessionID
    package let observation: PaneForegroundObservation?
    package let launchBootId: String
    package let inventory: ZmxSessionInventory

    package init(
        paneId: UUID, zmxSessionId: ZmxSessionID, observation: PaneForegroundObservation?,
        launchBootId: String, inventory: ZmxSessionInventory
    ) {
        self.paneId = paneId
        self.zmxSessionId = zmxSessionId
        self.observation = observation
        self.launchBootId = launchBootId
        self.inventory = inventory
    }
}
