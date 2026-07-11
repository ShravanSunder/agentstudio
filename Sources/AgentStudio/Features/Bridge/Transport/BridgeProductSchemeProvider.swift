protocol BridgeProductSchemeProvider: Sendable {
    func response(
        for request: BridgeProductControlRequest
    ) async -> BridgeProductControlResponse

    func runMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async

    func runContentProducer(
        request: BridgeProductContentRequest,
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async

    func acknowledgeLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) async -> Bool
}
