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

    nonisolated func makeContentProducerOperation(
        request: BridgeProductContentRequest,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) -> BridgeProductProducerRegistry.ProducerOperation

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
    nonisolated func makeContentProducerOperation(
        request: BridgeProductContentRequest,
        productAdmission: BridgeProductAdmissionContext,
        session: BridgeProductSession
    ) -> BridgeProductProducerRegistry.ProducerOperation {
        { lease in
            await self.runContentProducer(
                request: request,
                lease: lease,
                productAdmission: productAdmission,
                session: session
            )
        }
    }

    func applyCommittedControlEffect(
        _ effect: BridgeProductSessionCompletionEffect,
        for request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        _ = (effect, request, productAdmission)
    }
}
