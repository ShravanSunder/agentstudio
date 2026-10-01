import Foundation

// S3 RED stand-in: declaration-only verdict vocabulary, without a decision implementation.
package enum ResumeUnknownReason: Equatable, Sendable {
    case noObservation, observationMismatch, programNotAgent, startedFromHistoricalReport
    case evidenceUnordered, invalidSessionId, unknownProvider, reportsNotTakenIn
}

// S3 RED stand-in: declare only the PD's three verdict outcomes.
package enum ResumeEvidence: Equatable, Sendable {
    case knownExited(ProviderEndReason)
    case interruptedCandidate(ResumeInvocation)
    case unknown(ResumeUnknownReason)
}

// S3 RED stand-in: carry the named inputs without reading or deciding from them.
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
