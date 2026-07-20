extension BridgePaneProductFileMetadataSource {
    func authoritativePath(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) -> String? {
        productAdmission.withValidAdmission { () -> String? in
            let descriptor = request.descriptor
            for subscriptionId in contextBySubscriptionId.keys.sorted() {
                guard let context = contextBySubscriptionId[subscriptionId],
                    context.productSource == descriptor.source,
                    context.productAdmission.matches(productAdmission)
                else { continue }
                return context.descriptorByPath.values.first(where: {
                    if case .available(let issuedDescriptor) = $0.availability {
                        issuedDescriptor == descriptor
                    } else {
                        false
                    }
                })?.path
            }
            return nil
        }.flatMap({ $0 })
    }

    func contentReadPlan(
        for request: BridgeProductFileContentRequest,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgePaneProductFileContentReadPlan? {
        productAdmission.withValidAdmission { () -> BridgePaneProductFileContentReadPlan? in
            let descriptor = request.descriptor
            for subscriptionId in contextBySubscriptionId.keys.sorted() {
                guard let context = contextBySubscriptionId[subscriptionId],
                    context.productSource == descriptor.source,
                    context.productAdmission.matches(productAdmission)
                else { continue }
                guard
                    let issuedPayload = context.descriptorByPath.values.first(where: {
                        if case .available(let issuedDescriptor) = $0.availability {
                            issuedDescriptor == descriptor
                        } else {
                            false
                        }
                    })
                else { return nil }
                return BridgePaneProductFileContentReadPlan(
                    descriptor: descriptor,
                    relativePath: issuedPayload.path,
                    rootURL: authority.worktree.path
                )
            }
            return nil
        }.flatMap({ $0 })
    }
}
