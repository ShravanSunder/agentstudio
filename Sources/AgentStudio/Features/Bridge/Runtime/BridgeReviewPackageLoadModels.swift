struct BridgeReviewPackageConstructionResult {
    let result: BridgeReviewPipelineResult
    let artifactPin: BridgeReviewPublicationArtifactPin?

    func releaseArtifactPin() async {
        await artifactPin?.releaseAndWait()
    }
}

struct BridgeReviewPackageLoadData {
    let preparedPublication: BridgeReviewPreparedPublication
    let changeIndexLoad: BridgeChangeIndexPreparedLoad

    var package: BridgeReviewPackage { preparedPublication.package }
    var delta: BridgeReviewDelta? { preparedPublication.delta }

    func releaseArtifactPin() async {
        await preparedPublication.artifactPin?.releaseAndWait()
    }

    func classified(with refreshImpact: BridgeReviewRefreshImpact) -> Self {
        Self(
            preparedPublication: preparedPublication.classified(with: refreshImpact),
            changeIndexLoad: changeIndexLoad
        )
    }
}

struct ReviewEndpointSelection {
    let base: BridgeSourceEndpoint
    let head: BridgeSourceEndpoint
    let comparisonSemantics: BridgeReviewQuery.ComparisonSemantics
    let pathScope: [String]
}
