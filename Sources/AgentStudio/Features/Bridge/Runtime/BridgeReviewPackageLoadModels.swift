struct BridgeReviewPackageLoadData {
    let package: BridgeReviewPackage
    let delta: BridgeReviewDelta?
}

struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
