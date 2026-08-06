import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge development product host")
struct BridgeDevelopmentProductHostTests {
    @Test("decodes a File target without inventing native source identity")
    func decodesFileTargetNavigationIntent() throws {
        // Arrange
        let requestData = Data(
            #"{"navigationIntent":{"commandId":"open-file-target","commandKind":"activateTarget","surface":"file","target":{"path":"Sources/App.swift","targetKind":"file","version":"current"}},"reason":"initial"}"#
                .utf8
        )

        // Act
        let request = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: requestData
        )

        // Assert
        #expect(
            request.navigationIntent
                == .activateFileTarget(
                    commandId: "open-file-target",
                    target: BridgeProductNavigationFileTarget(
                        path: "Sources/App.swift",
                        version: .current
                    )
                )
        )
    }

    @Test("decodes a Review path target without inventing package source identity")
    func decodesReviewPathTargetNavigationIntent() throws {
        // Arrange
        let requestData = Data(
            #"{"navigationIntent":{"commandId":"open-review-path","commandKind":"activateTarget","surface":"review","target":{"path":"Sources/App.swift","targetKind":"review","version":"head"}},"reason":"initial"}"#
                .utf8
        )

        // Act
        let request = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: requestData
        )

        // Assert
        #expect(
            request.navigationIntent
                == .activateReviewTarget(
                    commandId: "open-review-path",
                    target: BridgeProductNavigationReviewTarget(
                        path: "Sources/App.swift",
                        version: .head
                    )
                )
        )
    }

    @Test("decodes a Review item target without requiring a path")
    func decodesReviewItemTargetNavigationIntent() throws {
        // Arrange
        let requestData = Data(
            #"{"navigationIntent":{"commandId":"open-review-item","commandKind":"activateTarget","surface":"review","target":{"reviewItemId":"item-git-diff-123","targetKind":"review"}},"reason":"initial"}"#
                .utf8
        )

        // Act
        let request = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: requestData
        )

        // Assert
        #expect(
            request.navigationIntent
                == .activateReviewTarget(
                    commandId: "open-review-item",
                    target: BridgeProductNavigationReviewTarget(
                        reviewItemId: "item-git-diff-123"
                    )
                )
        )
    }

    @Test("rejects a Review target without a path or item identity")
    func rejectsEmptyReviewTargetNavigationIntent() {
        // Arrange
        let requestData = Data(
            #"{"navigationIntent":{"commandId":"open-empty-review","commandKind":"activateTarget","surface":"review","target":{"targetKind":"review"}},"reason":"initial"}"#
                .utf8
        )

        // Act / Assert
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(
                BridgeDevelopmentProductBootstrapRequest.self,
                from: requestData
            )
        }
    }

    @Test("binds a Review target to the committed native package source")
    func bindsReviewTargetToCommittedPackageSource() throws {
        // Arrange
        let target = BridgeProductNavigationReviewTarget(
            path: "Sources/Module00/File00000.swift",
            version: .head
        )
        let publication = BridgeReviewCommittedPublication(
            publicationId: try #require(
                UUID(uuidString: "11111111-1111-7111-8111-111111111111")
            ),
            package: makeReviewPackage(itemCount: 1),
            delta: nil,
            contentHandles: []
        )

        // Act
        let command = BridgeDevelopmentProductHost.bindReviewNavigationCommand(
            intent: .activateReviewTarget(
                commandId: "open-review-target",
                target: target
            ),
            publication: publication,
            bindingRevision: 3
        )

        // Assert
        #expect(
            command
                == .activateReviewTarget(
                    commandId: "open-review-target",
                    bindingRevision: 3,
                    source: BridgeProductNavigationReviewSource(
                        generation: 7,
                        metadataSourceId: "review-query-1",
                        packageId: "review-package-1"
                    ),
                    target: target
                )
        )
    }

    @Test("binds a File target to the exact accepted native source")
    func bindsFileTargetToAcceptedSource() throws {
        // Arrange
        let target = BridgeProductNavigationFileTarget(
            path: "Sources/App.swift",
            version: .current
        )
        let source = try BridgeProductFileSourceIdentity(
            repoId: "11111111-1111-7111-8111-111111111111",
            rootRevisionToken: "root-revision-7",
            sourceCursor: "file-cursor-7",
            sourceId: "file-source-7",
            subscriptionGeneration: 7,
            worktreeId: "22222222-2222-7222-8222-222222222222"
        )

        // Act
        let command = BridgeDevelopmentProductHost.bindFileNavigationCommand(
            intent: .activateFileTarget(
                commandId: "open-file-target",
                target: target
            ),
            source: source,
            bindingRevision: 3
        )

        // Assert
        #expect(
            command
                == .activateFileTarget(
                    commandId: "open-file-target",
                    bindingRevision: 3,
                    source: BridgeProductNavigationFileSource(
                        sourceId: "file-source-7",
                        subscriptionGeneration: 7
                    ),
                    target: target
                )
        )
    }

    @Test("rejects a source that is not a Git worktree")
    func rejectsNonGitWorktree() async throws {
        // Arrange
        let sourceURL = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-product-host-non-git"
        )

        // Act / Assert
        await #expect(throws: BridgeDevelopmentProductHostError.invalidWorktree) {
            _ = try await BridgeDevelopmentProductHost(
                source: BridgeDevelopmentProductSource(
                    worktreeRoot: sourceURL,
                    reviewBase: "HEAD"
                )
            )
        }
    }

    @Test("replacement bootstrap keeps pane identity and rotates worker authority")
    func replacementBootstrapRotatesWorkerAuthority() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-bootstrap"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )
        let navigationIntent = #"{"commandId":"open-file-view","commandKind":"activateContext","surface":"file"}"#
        let initialRequest = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: Data(#"{"navigationIntent":\#(navigationIntent),"reason":"initial"}"#.utf8)
        )

        // Act
        let initialDelivery = try await host.issueBootstrap(for: initialRequest)
        let initialEnvelope = try decodeDevelopmentBootstrapEnvelope(initialDelivery)
        let replacementRequest = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: Data(
                #"{"navigationIntent":\#(navigationIntent),"paneSessionId":"\#(initialEnvelope.bootstrap.paneSessionId)","reason":"workerReplacement"}"#
                    .utf8
            )
        )
        let replacementDelivery = try await host.issueBootstrap(for: replacementRequest)
        let replacementEnvelope = try decodeDevelopmentBootstrapEnvelope(replacementDelivery)

        // Assert
        #expect(replacementEnvelope.bootstrap.paneSessionId == initialEnvelope.bootstrap.paneSessionId)
        #expect(replacementEnvelope.bootstrap.workerInstanceId != initialEnvelope.bootstrap.workerInstanceId)
        #expect(replacementEnvelope.capabilityBytes != initialEnvelope.capabilityBytes)
        #expect(initialEnvelope.capabilityBytes.count == BridgeProductWireContract.capabilityByteLength)
        #expect(replacementEnvelope.capabilityBytes.count == BridgeProductWireContract.capabilityByteLength)
        await host.shutdown()
    }

    @Test("a reloaded development page can issue a fresh initial bootstrap")
    func repeatedInitialBootstrapRotatesWorkerAuthority() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-page-reload"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )
        let initialRequest = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: Data(
                #"{"navigationIntent":{"commandId":"open-file-view","commandKind":"activateContext","surface":"file"},"reason":"initial"}"#
                    .utf8
            )
        )
        let firstEnvelope = try decodeDevelopmentBootstrapEnvelope(
            await host.issueBootstrap(for: initialRequest)
        )

        // Act
        let reloadedEnvelope = try decodeDevelopmentBootstrapEnvelope(
            await host.issueBootstrap(for: initialRequest)
        )

        // Assert
        #expect(reloadedEnvelope.bootstrap.paneSessionId == firstEnvelope.bootstrap.paneSessionId)
        #expect(reloadedEnvelope.bootstrap.workerInstanceId != firstEnvelope.bootstrap.workerInstanceId)
        #expect(reloadedEnvelope.capabilityBytes != firstEnvelope.capabilityBytes)
        await host.shutdown()
    }

    @Test("routes worker admission through the existing product adapter")
    func routesWorkerAdmissionThroughExistingProductAdapter() async throws {
        // Arrange
        let repositoryURL = try FilesystemTestGitRepo.create(
            named: "bridge-development-product-host-route"
        )
        defer { FilesystemTestGitRepo.destroy(repositoryURL) }
        try FilesystemTestGitRepo.seedTrackedAndUntrackedChanges(at: repositoryURL)
        let host = try await BridgeDevelopmentProductHost(
            source: BridgeDevelopmentProductSource(
                worktreeRoot: repositoryURL,
                reviewBase: "HEAD"
            ),
            makeReviewProvider: { _, _ in BridgeObservabilitySmokeReviewSourceProvider() }
        )
        let bootstrapRequest = try JSONDecoder().decode(
            BridgeDevelopmentProductBootstrapRequest.self,
            from: Data(
                #"{"navigationIntent":{"commandId":"open-file-view","commandKind":"activateContext","surface":"file"},"reason":"initial"}"#
                    .utf8
            )
        )
        let delivery = try decodeDevelopmentBootstrapEnvelope(
            await host.issueBootstrap(for: bootstrapRequest)
        )
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(
            Array(delivery.capabilityBytes)
        )
        let requestBody = try JSONSerialization.data(
            withJSONObject: [
                "kind": "workerSession.open",
                "paneSessionId": delivery.bootstrap.paneSessionId,
                "request": NSNull(),
                "requestId": "request-open-development-host",
                "requestSequence": 1,
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": delivery.bootstrap.workerInstanceId,
            ],
            options: [.sortedKeys]
        )
        var request = URLRequest(url: try #require(URL(string: BridgeProductWireContract.commandRoute)))
        request.httpMethod = BridgeProductWireContract.requestMethod
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            capabilityHeader,
            forHTTPHeaderField: BridgeProductWireContract.capabilityHeaderName
        )

        // Act
        var response: HTTPURLResponse?
        var responseBody = Data()
        for try await result in await host.route(request) {
            switch result {
            case .response(let receivedResponse):
                response = receivedResponse as? HTTPURLResponse
            case .data(let data):
                responseBody.append(data)
            @unknown default:
                Issue.record("Unexpected URL scheme response event")
            }
        }
        let controlResponse = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: responseBody
        )

        // Assert
        #expect(response?.statusCode == 200)
        guard case .workerSessionAccepted(let accepted) = controlResponse else {
            Issue.record("Expected the existing adapter to accept the worker session")
            await host.shutdown()
            return
        }
        #expect(accepted.correlation.paneSessionId == delivery.bootstrap.paneSessionId)
        #expect(accepted.correlation.workerInstanceId == delivery.bootstrap.workerInstanceId)
        await host.shutdown()
    }
}

private struct DecodedDevelopmentBootstrapEnvelope {
    let bootstrap: BridgeProductSessionBootstrap
    let capabilityBytes: Data
}

private func decodeDevelopmentBootstrapEnvelope(
    _ data: Data
) throws -> DecodedDevelopmentBootstrapEnvelope {
    let envelopeVersionByteCount = 1
    let metadataLengthByteCount = 4
    let prefixByteCount = envelopeVersionByteCount + metadataLengthByteCount
    guard data.count >= prefixByteCount + BridgeProductWireContract.capabilityByteLength else {
        throw CocoaError(.fileReadCorruptFile)
    }
    #expect(data[0] == 1)
    let metadataByteCount = data[1..<prefixByteCount].reduce(0) { length, byte in
        (length << 8) | Int(byte)
    }
    let metadataRange = prefixByteCount..<(prefixByteCount + metadataByteCount)
    let capabilityRange = metadataRange.upperBound..<data.count
    guard metadataRange.upperBound <= data.count,
        capabilityRange.count == BridgeProductWireContract.capabilityByteLength
    else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return try DecodedDevelopmentBootstrapEnvelope(
        bootstrap: JSONDecoder().decode(
            BridgeProductSessionBootstrap.self,
            from: data.subdata(in: metadataRange)
        ),
        capabilityBytes: data.subdata(in: capabilityRange)
    )
}
