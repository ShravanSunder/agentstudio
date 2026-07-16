protocol BridgeProductSchemeProvider: Sendable {
    func response(
        for request: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) async

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool

    func applyCommittedControlEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        for request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async
}

extension BridgeProductSchemeProvider {
    func applyCommittedControlEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        for request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        _ = (effect, request, productAdmission)
    }
}
