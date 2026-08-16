actor BridgePaneProductSchemeProvider {
    static func response(for request: Request) {
        switch request {
        case .productCall(let callRequest):
            switch callRequest.call {
            case .reviewComparisonTargetsQuery:
                authorizeComparisonTargetQuery()
            default:
                break
            }
        default:
            break
        }
    }
}

actor GoodComparisonTargetCatalogProducer {
    func produceComparisonTargetCatalog() {
        captureReviewComparisonTargets()
        BridgeReviewComparisonTargetCatalog()
        JSONEncoder()
        SHA256()
    }
}
