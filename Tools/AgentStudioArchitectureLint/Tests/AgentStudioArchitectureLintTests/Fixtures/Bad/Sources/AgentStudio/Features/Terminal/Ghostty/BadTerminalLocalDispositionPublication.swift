enum BadTerminalLocalDispositionPublication {
    static func route(_ event: GhosttyEvent) -> Bool {
        switch GhosttyActionDisposition.classify(event) {
        case .exactFactOrControl:
            return routeActionToTerminalRuntimeOnMainActor()
        case .latestPresentation:
            recordLocalPresentation()
            routeActionToTerminalRuntimeOnMainActor()
            return handledResult
        case .latestSemanticMetadata:
            routeActionToTerminalRuntimeOnMainActor()
            return handledResult
        case .activityEvidence:
            Self.routeActionToTerminalRuntimeOnMainActor()
            return handledResult
        case .exactLocalLifecycle:
            Ghostty.ActionRouter.routeActionToTerminalRuntimeOnMainActor()
            return handledResult
        case .diagnostic:
            routeActionToTerminalRuntimeOnMainActor()
            return handledResult
        }
    }
}
