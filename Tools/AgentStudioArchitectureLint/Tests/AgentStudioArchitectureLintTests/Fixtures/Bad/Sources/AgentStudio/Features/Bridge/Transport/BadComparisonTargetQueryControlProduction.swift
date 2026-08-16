actor BridgePaneProductSchemeProvider {
    static func response(for request: Request) {
        switch request {
        case .productCall(let callRequest):
            switch callRequest.call {
            case .reviewComparisonTargetsQuery:
                queryReviewComparisonTargets()
                captureReviewComparisonTargets()
                produceComparisonTargetCatalog()
                BridgeReviewComparisonTargetCatalog()
                JSONEncoder()
                SHA256()
                BridgeReviewComparisonTargetCatalogProducer.produceCatalog(
                    capture,
                    maximumEncodedBytes: 1024
                )
            default:
                break
            }
        default:
            break
        }
    }
}
