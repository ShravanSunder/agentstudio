import AgentStudioCore

// S3 RED stand-in: the Sessions read port is declared without real evidence resolution.
package protocol SessionResumeResolving: Sendable {
    func resumeEvidence(for input: ResumeEvidenceInput) async -> ResumeEvidence
}

// S3 RED stand-in: no repository read or verdict; return the existing absent-observation outcome.
package struct SessionsResumeResolver: SessionResumeResolving {
    package init(repository: SessionsRepository) {}

    package func resumeEvidence(for input: ResumeEvidenceInput) async -> ResumeEvidence {
        .unknown(.noObservation)
    }
}
