enum BadTerminalLocalDispositionFallthrough {
    static func route(_ event: GhosttyEvent) -> Bool {
        switch GhosttyActionDisposition.classify(event) {
        case .exactFactOrControl:
            break
        case .latestPresentation(let presentation):
            offerLocalPresentation(presentation)
            return handledResult
        case .activityEvidence(let evidence):
            offerLocalActivityEvidence(evidence)
        case .exactLocalLifecycle(let lifecycle):
            offerLocalLifecycle(lifecycle)
            return handledResult
        case .diagnostic(let diagnostic):
            recordDiagnostic(diagnostic)
            return handledResult
        }

        routeActionToTerminalRuntimeOnMainActor()
        return handledResult
    }
}
