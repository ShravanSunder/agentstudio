extension BridgePaneProductSchemeProvider {
    func consumeComparisonTargetCapture(
        _ descriptor: BridgeProductReviewComparisonTargetsContentDescriptor
    ) -> BridgeProductReviewComparisonTargetsQueryCapture? {
        guard let capture = pendingComparisonTargetQuery,
            capture.descriptor == descriptor
        else { return nil }
        pendingComparisonTargetQuery = nil
        guard capture.foregroundWorkAdmission.withValidAdmission({ true }) == true else {
            return nil
        }
        return capture
    }
}
