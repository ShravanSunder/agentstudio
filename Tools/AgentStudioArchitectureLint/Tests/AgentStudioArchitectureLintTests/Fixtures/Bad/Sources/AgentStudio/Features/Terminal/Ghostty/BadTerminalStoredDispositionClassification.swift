enum BadTerminalStoredDispositionClassification {
    static func route(_ event: GhosttyEvent) -> Bool {
        let disposition = GhosttyActionDisposition.classify(event)

        switch disposition {
        case .exactFactOrControl:
            return routeActionToTerminalRuntimeOnMainActor()
        case .latestPresentation:
            recordLocalPresentation()
            routeActionToTerminalRuntimeOnMainActor()
            return handledResult
        default:
            return handledResult
        }
    }
}
