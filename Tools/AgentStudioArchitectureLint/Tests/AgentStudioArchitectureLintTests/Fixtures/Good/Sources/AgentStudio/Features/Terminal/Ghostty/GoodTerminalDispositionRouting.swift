enum GoodTerminalDispositionRouting {
    static func route(_ event: GhosttyEvent) -> Bool {
        switch GhosttyActionDisposition.classify(event) {
        case .exactFactOrControl:
            break
        case .latestPresentation(let presentation):
            offerLocalPresentation(presentation)
            return handledResult
        case .latestSemanticMetadata(let metadata):
            offerLocalSemanticMetadata(metadata)
            return handledResult
        case .activityEvidence(let evidence):
            offerLocalActivityEvidence(evidence)
            return handledResult
        case .exactLocalLifecycle(let lifecycle):
            offerLocalLifecycle(lifecycle)
            return handledResult
        case .diagnostic(let diagnostic):
            recordDiagnostic(diagnostic)
            return handledResult
        }

        routeActionToTerminalRuntimeOnMainActor()

        let unrelatedDispositionResult = unrelatedDisposition(event)
        switch unrelatedDispositionResult {
        case .latestPresentation:
            routeActionToTerminalRuntimeOnMainActor()
        default:
            break
        }
        return handledResult
    }
}
