import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioCore

@MainActor
@Suite("Bridge development product host display lifecycle")
struct BridgeDevelopmentProductHostDisplayLifecycleTests {
    @Test("fresh and replacement workers preserve bounded Review display installation")
    func freshAndReplacementWorkersPreserveBoundedReviewDisplayInstallation() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-display-lifecycle"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: makeDevelopmentProductSource(worktreeRoot: repositoryURL),
            contributionTargetCommit: developmentContributionTargetCommit(
                worktreeRoot: repositoryURL
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )

        try await withMainActorShutdownDevelopmentProductHost(host) {
            let established = try await establishInitialAndFreshDocumentDisplay(in: host)
            let successor = try await establishReplacementWorkerAndAdmitB(
                established: established,
                host: host
            )
            try await commitAndApplyC(established: established, host: host, successor: successor)
        }
    }
}

@MainActor
private func establishInitialAndFreshDocumentDisplay(
    in host: BridgeDevelopmentProductHost
) async throws -> DevelopmentDisplayEstablishedContext {
    let initialBootstrapRequest = try developmentDisplayBootstrapRequest(reason: "initial")
    let workerOne = try DevelopmentDisplayWorkerClient(
        host: host,
        delivery: await host.issueBootstrap(for: initialBootstrapRequest)
    )
    try await workerOne.openSession()
    let publicationA = try #require(await host.diagnosticCommittedReviewPublication())
    let coordinator = await host.reviewPublicationCoordinator

    #expect(
        try await workerOne.admitReviewPublication(
            candidatePublicationId: publicationA.publicationId,
            expectedDisplayedPublicationId: nil
        )
    )
    try await workerOne.applyReviewPublication(publicationA.publicationId)
    #expect(coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId == publicationA.publicationId)
    #expect(coordinator.diagnosticSnapshot.admitted == nil)

    let workerTwo = try DevelopmentDisplayWorkerClient(
        host: host,
        delivery: await host.issueBootstrap(for: initialBootstrapRequest)
    )
    try await workerTwo.openSession()
    #expect(workerTwo.paneSessionId == workerOne.paneSessionId)
    #expect(workerTwo.workerInstanceId != workerOne.workerInstanceId)
    #expect(
        try await workerTwo.admitReviewPublication(
            candidatePublicationId: publicationA.publicationId,
            expectedDisplayedPublicationId: nil
        )
    )
    try await workerTwo.applyReviewPublication(publicationA.publicationId)
    #expect(coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId == publicationA.publicationId)
    #expect(coordinator.diagnosticSnapshot.admitted == nil)
    return DevelopmentDisplayEstablishedContext(
        coordinator: coordinator,
        publicationA: publicationA,
        workerTwo: workerTwo
    )
}

@MainActor
private func establishReplacementWorkerAndAdmitB(
    established: DevelopmentDisplayEstablishedContext,
    host: BridgeDevelopmentProductHost
) async throws -> DevelopmentDisplaySuccessorContext {
    let replacementBootstrapRequest = try developmentDisplayBootstrapRequest(
        paneSessionId: established.workerTwo.paneSessionId,
        reason: "workerReplacement"
    )
    let workerThree = try DevelopmentDisplayWorkerClient(
        host: host,
        delivery: await host.issueBootstrap(for: replacementBootstrapRequest)
    )
    try await workerThree.openSession()
    #expect(workerThree.paneSessionId == established.workerTwo.paneSessionId)
    #expect(workerThree.workerInstanceId != established.workerTwo.workerInstanceId)
    try await workerThree.applyReviewPublication(established.publicationA.publicationId)

    let preparedB = try await makeReviewPreparedPublication(
        suffix: "development-display-b",
        reviewGeneration: 2
    )
    let publicationB = try commitObserved(
        preparedB,
        in: established.coordinator,
        productAdmission: await host.productAdmission
    )
    #expect(
        !(try await workerThree.admitReviewPublication(
            candidatePublicationId: publicationB.publicationId,
            expectedDisplayedPublicationId: nil
        ))
    )
    #expect(
        try await workerThree.admitReviewPublication(
            candidatePublicationId: publicationB.publicationId,
            expectedDisplayedPublicationId: established.publicationA.publicationId
        )
    )
    return DevelopmentDisplaySuccessorContext(publicationB: publicationB, workerThree: workerThree)
}

@MainActor
private func commitAndApplyC(
    established: DevelopmentDisplayEstablishedContext,
    host: BridgeDevelopmentProductHost,
    successor: DevelopmentDisplaySuccessorContext
) async throws {
    let preparedC = try await makeReviewPreparedPublication(
        suffix: "development-display-c",
        reviewGeneration: 3
    )
    let publicationC = try commitObserved(
        preparedC,
        in: established.coordinator,
        productAdmission: await host.productAdmission
    )
    #expect(
        await host.diagnosticCommittedReviewPublication()?.publicationId
            == publicationC.publicationId
    )

    try await successor.workerThree.applyReviewPublication(successor.publicationB.publicationId)
    #expect(
        established.coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId
            == successor.publicationB.publicationId
    )
    #expect(established.coordinator.diagnosticSnapshot.active?.publicationId == publicationC.publicationId)
    #expect(established.coordinator.diagnosticSnapshot.admitted == nil)
    #expect(
        try await successor.workerThree.admitReviewPublication(
            candidatePublicationId: publicationC.publicationId,
            expectedDisplayedPublicationId: successor.publicationB.publicationId
        )
    )
    try await successor.workerThree.applyReviewPublication(publicationC.publicationId)
    #expect(
        established.coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId
            == publicationC.publicationId
    )
    #expect(established.coordinator.diagnosticSnapshot.active?.publicationId == publicationC.publicationId)
    #expect(established.coordinator.diagnosticSnapshot.admitted == nil)
}

private struct DevelopmentDisplayEstablishedContext {
    let coordinator: BridgeReviewPublicationCoordinator
    let publicationA: BridgeReviewCommittedPublication
    let workerTwo: DevelopmentDisplayWorkerClient
}

private struct DevelopmentDisplaySuccessorContext {
    let publicationB: BridgeReviewCommittedPublication
    let workerThree: DevelopmentDisplayWorkerClient
}

@MainActor
private final class DevelopmentDisplayWorkerClient {
    private let capabilityHeader: String
    private let host: BridgeDevelopmentProductHost
    private var nextRequestSequence = 1
    let paneSessionId: String
    let workerInstanceId: String

    init(host: BridgeDevelopmentProductHost, delivery: Data) throws {
        let envelope = try decodeDevelopmentDisplayBootstrapEnvelope(delivery)
        capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            Array(envelope.capabilityBytes)
        )
        self.host = host
        paneSessionId = envelope.bootstrap.paneSessionId
        workerInstanceId = envelope.bootstrap.workerInstanceId
    }

    func openSession() async throws {
        let response = try await sendControl(
            body: [
                "kind": "workerSession.open",
                "paneSessionId": paneSessionId,
                "request": NSNull(),
                "requestId": requestId("open"),
                "requestSequence": takeRequestSequence(),
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": workerInstanceId,
            ]
        )
        guard case .workerSessionAccepted(let accepted) = response else {
            Issue.record("Expected the development-host worker session to open")
            return
        }
        #expect(accepted.correlation.paneSessionId == paneSessionId)
        #expect(accepted.correlation.workerInstanceId == workerInstanceId)
    }

    func admitReviewPublication(
        candidatePublicationId: UUID,
        expectedDisplayedPublicationId: UUID?
    ) async throws -> Bool {
        let expectedDisplayedPublicationValue: Any =
            if let expectedDisplayedPublicationId {
                expectedDisplayedPublicationId.uuidString.lowercased()
            } else {
                NSNull()
            }
        let response = try await sendProductCall(
            method: "review.publication.install.admit",
            request: [
                "candidatePublicationId": candidatePublicationId.uuidString.lowercased(),
                "expectedDisplayedPublicationId": expectedDisplayedPublicationValue,
            ]
        )
        guard case .callCompleted(let completed) = response,
            case .reviewPublicationInstallAdmission(let result) = completed.call
        else {
            Issue.record("Expected a typed Review publication install-admission result")
            return false
        }
        return result.status == .admitted
    }

    func applyReviewPublication(_ publicationId: UUID) async throws {
        let response = try await sendProductCall(
            method: "review.publication.applied",
            request: ["publicationId": publicationId.uuidString.lowercased()]
        )
        guard case .callCompleted(let completed) = response,
            completed.call == .reviewPublicationApplied
        else {
            Issue.record("Expected a typed Review publication applied result")
            return
        }
    }

    private func sendProductCall(
        method: String,
        request: [String: Any]
    ) async throws -> BridgeProductControlResponse {
        try await sendControl(
            body: [
                "call": ["method": method, "request": request],
                "kind": "product.call",
                "paneSessionId": paneSessionId,
                "requestId": requestId(method),
                "requestSequence": takeRequestSequence(),
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": 0,
                "workerInstanceId": workerInstanceId,
            ]
        )
    }

    private func sendControl(body: [String: Any]) async throws -> BridgeProductControlResponse {
        let requestBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        var request = URLRequest(url: try #require(URL(string: BridgeProductWireContract.commandRoute)))
        request.httpMethod = BridgeProductWireContract.requestMethod
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            capabilityHeader,
            forHTTPHeaderField: BridgeProductWireContract.capabilityHeaderName
        )
        var response: HTTPURLResponse?
        var responseBody = Data()
        for try await result in await host.route(request) {
            switch result {
            case .response(let receivedResponse):
                response = receivedResponse as? HTTPURLResponse
            case .data(let data):
                responseBody.append(data)
            @unknown default:
                Issue.record("Unexpected development-host scheme response event")
            }
        }
        #expect(response?.statusCode == 200)
        return try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: responseBody
        )
    }

    private func takeRequestSequence() -> Int {
        defer { nextRequestSequence += 1 }
        return nextRequestSequence
    }

    private func requestId(_ operation: String) -> String {
        "development-display-\(workerInstanceId)-\(nextRequestSequence)-\(operation)"
    }
}

@MainActor
private func withMainActorShutdownDevelopmentProductHost<Result>(
    _ host: BridgeDevelopmentProductHost,
    operation: () async throws -> Result
) async throws -> Result {
    do {
        let result = try await operation()
        await host.shutdown()
        return result
    } catch {
        await host.shutdown()
        throw error
    }
}

private struct DecodedDevelopmentDisplayBootstrapEnvelope {
    let bootstrap: BridgeProductSessionBootstrap
    let capabilityBytes: Data
}

private func decodeDevelopmentDisplayBootstrapEnvelope(
    _ data: Data
) throws -> DecodedDevelopmentDisplayBootstrapEnvelope {
    let prefixByteCount = 5
    guard data.count >= prefixByteCount + BridgeProductWireContract.capabilityByteLength else {
        throw CocoaError(.fileReadCorruptFile)
    }
    #expect(data[0] == 1)
    let metadataByteCount = data[1..<prefixByteCount].reduce(0) { length, byte in
        (length << 8) | Int(byte)
    }
    let metadataRange = prefixByteCount..<(prefixByteCount + metadataByteCount)
    guard metadataRange.upperBound <= data.count else {
        throw CocoaError(.fileReadCorruptFile)
    }
    let capabilityRange = metadataRange.upperBound..<data.count
    guard capabilityRange.count == BridgeProductWireContract.capabilityByteLength else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return try DecodedDevelopmentDisplayBootstrapEnvelope(
        bootstrap: JSONDecoder().decode(
            BridgeProductSessionBootstrap.self,
            from: data.subdata(in: metadataRange)
        ),
        capabilityBytes: data.subdata(in: capabilityRange)
    )
}

private func developmentDisplayBootstrapRequest(
    paneSessionId: String? = nil,
    reason: String
) throws -> BridgeDevelopmentProductBootstrapRequest {
    var request: [String: Any] = [
        "navigationIntent": [
            "commandId": "open-review-view",
            "commandKind": "activateContext",
            "surface": "review",
        ],
        "reason": reason,
    ]
    if let paneSessionId {
        request["paneSessionId"] = paneSessionId
    }
    return try JSONDecoder().decode(
        BridgeDevelopmentProductBootstrapRequest.self,
        from: JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
    )
}
