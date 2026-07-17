struct BridgeReviewPackageLoadData {
    let preparedPublication: BridgeReviewPreparedPublication
    let changeIndexLoad: BridgeChangeIndexPreparedLoad

    var package: BridgeReviewPackage { preparedPublication.package }
    var delta: BridgeReviewDelta? { preparedPublication.delta }
}

struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
