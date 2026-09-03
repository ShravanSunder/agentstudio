import AgentStudioTestSupport
import Foundation

@testable import AgentStudioBridge

func availabilityCommittedPublication(
    _ package: BridgeReviewPackage,
    operationCorrelationID: String? = nil
) -> BridgeReviewCommittedPublication {
    BridgeReviewCommittedPublication(
        publicationId: UUID(uuidString: "11111111-1111-7111-8111-111111111111")!,
        package: package,
        delta: nil,
        contentHandles: [],
        comparisonPresentationRevision: 1,
        reviewComparison: nil,
        operationCorrelationID: operationCorrelationID
    )
}

func availabilityCorrelatedCommittedPublication(
    _ package: BridgeReviewPackage
) -> BridgeReviewCommittedPublication {
    availabilityCommittedPublication(
        package,
        operationCorrelationID: String(repeating: "a", count: 64)
    )
}

func availabilityReservation(
    for package: BridgeReviewPackage,
    publicationId: UUID
) -> BridgeReviewMetadataPublicationReservation {
    BridgeReviewMetadataPublicationReservation(
        reservationId: UUID(uuidString: "22222222-2222-7222-8222-222222222222")!,
        packageId: package.packageId,
        publicationId: publicationId,
        reviewGeneration: package.reviewGeneration,
        revision: package.revision,
        projectionPlan: try! BridgeReviewMetadataPublicationProjectionPlan.prepare(
            package: package,
            publicationId: publicationId
        )
    )
}

func availabilityControlExecutionToken(
    _ admission: BridgeProductSessionControlAdmission
) -> BridgeProductControlAdmissionToken? {
    guard case .execute(let token, _) = admission else { return nil }
    return token
}

func availabilityReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}

func availabilityMetadataStreamRequest() throws -> BridgeProductMetadataStreamRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "kind": "metadataStream.open",
            "metadataStreamId": "metadata-stream-1",
            "paneSessionId": "pane-session-1",
            "resumeFromStreamSequence": NSNull(),
            "wireVersion": BridgeProductWireContract.version,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    return try BridgeProductStrictJSON.decode(BridgeProductMetadataStreamRequest.self, from: data)
}
