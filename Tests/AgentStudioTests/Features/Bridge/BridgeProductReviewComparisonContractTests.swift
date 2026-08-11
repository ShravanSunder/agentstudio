import AgentStudioCore
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product Review comparison contract")
struct BridgeProductReviewComparisonContractTests {
    @Test("comparison update acknowledges only after the committed target effect")
    func comparisonUpdateAcknowledgesAfterCommittedTargetEffect() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let recorder = await MainActor.run { BridgeProductComparisonTargetRecorder() }
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            applyReviewComparisonUpdate: { request, _ in
                recorder.record(request.target)
            },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let productAdmission = try BridgeProductAdmissionTestContext.make().context
        let dispatcher = makeBridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider,
            productAdmission: productAdmission
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let result = try await dispatcher.dispatch(
            exactRequestBytes: reviewComparisonUpdateBody(),
            presentedCapability: capabilityHeader
        )

        // Assert
        guard case .response(let responseBytes) = result,
            case .callCompleted(let response) = try BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: responseBytes
            )
        else {
            Issue.record("Expected a committed comparison-update completion")
            return
        }
        #expect(response.call == .reviewComparisonUpdate)
        #expect(await recorder.targets == [.branch(name: "stack/base")])
    }

    @Test("failed comparison target effect suppresses successful acknowledgement")
    func failedComparisonTargetEffectSuppressesAcknowledgement() async throws {
        // Arrange
        let capabilityBytes = (0..<BridgeProductWireContract.capabilityByteLength).map(UInt8.init)
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        let session = try BridgeProductSession(
            paneSessionId: bridgeProductTestPaneSessionId,
            workerInstanceId: bridgeProductTestWorkerInstanceId,
            capabilityBytes: capabilityBytes
        )
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let productAdmissionGate = BridgeProductAdmissionGate()
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            applyReviewComparisonUpdate: { _, _ in
                productAdmissionGate.close()
            },
            refreshWorkAdmissionSource: refreshWorkAdmission.source
        )
        let productAdmission = try #require(productAdmissionGate.acquire())
        let dispatcher = makeBridgeProductSchemeControlDispatcher(
            session: session,
            provider: provider,
            productAdmission: productAdmission
        )
        _ = try await dispatcher.dispatch(
            exactRequestBytes: bridgeProductSchemeWorkerOpenBody(),
            presentedCapability: capabilityHeader
        )

        // Act
        let result = try await dispatcher.dispatch(
            exactRequestBytes: reviewComparisonUpdateBody(),
            presentedCapability: capabilityHeader
        )

        // Assert
        #expect(result == .admissionClosed)
    }

    @Test("target-only comparison update request and null result round trip")
    func targetOnlyComparisonUpdateRoundTrips() throws {
        // Arrange
        let requestJSON = Data(
            #"{"method":"review.comparison.update","request":{"target":{"basis":"commonCommit","kind":"branch","name":"stack/base"}}}"#
                .utf8
        )
        let resultJSON = Data(
            #"{"method":"review.comparison.update","result":null}"#.utf8
        )

        // Act
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductCallRequest.self,
            from: requestJSON
        )
        let result = try BridgeProductStrictJSON.decode(
            BridgeProductCallResult.self,
            from: resultJSON
        )
        let encodedRequest = try sortedJSONObject(request)
        let canonicalRequest = try sortedJSONObject(from: requestJSON)
        let encodedResult = try sortedJSONObject(result)
        let canonicalResult = try sortedJSONObject(from: resultJSON)

        // Assert
        #expect(
            request
                == .reviewComparisonUpdate(
                    BridgeProductReviewComparisonUpdateRequest(
                        target: .branch(name: "stack/base")
                    )
                )
        )
        #expect(result == .reviewComparisonUpdate)
        #expect(encodedRequest == canonicalRequest)
        #expect(encodedResult == canonicalResult)
    }

    @Test("exact commit comparison update round trips without ref ambiguity")
    func exactCommitComparisonUpdateRoundTrips() throws {
        let oid = "0123456789abcdef0123456789abcdef01234567"
        let requestJSON = Data(
            #"{"method":"review.comparison.update","request":{"target":{"kind":"commit","oid":"0123456789abcdef0123456789abcdef01234567"}}}"#
                .utf8
        )

        let request = try BridgeProductStrictJSON.decode(
            BridgeProductCallRequest.self,
            from: requestJSON
        )
        let encodedRequest = try sortedJSONObject(request)
        let canonicalRequest = try sortedJSONObject(from: requestJSON)

        #expect(
            request
                == .reviewComparisonUpdate(
                    BridgeProductReviewComparisonUpdateRequest(
                        target: .commit(oid: oid)
                    )
                )
        )
        #expect(encodedRequest == canonicalRequest)

        for invalidOID in ["abc123", String(repeating: "g", count: 40)] {
            let invalidRequestJSON = Data(
                """
                {"method":"review.comparison.update","request":{"target":{"kind":"commit","oid":"\(invalidOID)"}}}
                """.utf8
            )
            #expect(throws: Error.self) {
                _ = try BridgeProductStrictJSON.decode(
                    BridgeProductCallRequest.self,
                    from: invalidRequestJSON
                )
            }
        }
    }

    @Test("comparison update rejects transport-invalid target variants")
    func comparisonUpdateRejectsTransportInvalidTargetVariants() {
        let invalidTargets = [
            #"{"basis":"commonCommit","kind":"commit","oid":"0123456789abcdef0123456789abcdef01234567"}"#,
            #"{"kind":"branch","name":"stack/base"}"#,
            #"{"basis":"commonCommit","kind":"branch","name":"stack/base","oid":"0123456789abcdef0123456789abcdef01234567"}"#,
            #"{"basis":"commonCommit","branchName":"main","kind":"originDefaultBranch","name":"main","remoteName":"origin"}"#,
            #"{"basis":"commonCommit","kind":"branch","name":""}"#,
        ]

        for invalidTarget in invalidTargets {
            let requestJSON = Data(
                """
                {"method":"review.comparison.update","request":{"target":\(invalidTarget)}}
                """.utf8
            )

            #expect(throws: Error.self) {
                _ = try BridgeProductStrictJSON.decode(
                    BridgeProductCallRequest.self,
                    from: requestJSON
                )
            }
        }
    }

    @Test("strict transport target decodes every canonical variant")
    func strictTransportTargetDecodesEveryCanonicalVariant() throws {
        let targetCases: [(json: String, expected: WorkspaceReviewContributionTarget)] = [
            (
                #"{"basis":"commonCommit","branchName":"main","kind":"localDefaultBranch"}"#,
                .localDefaultBranch(branchName: "main")
            ),
            (
                #"{"basis":"branchTip","branchName":"main","kind":"originDefaultBranch","remoteName":"origin"}"#,
                .originDefaultBranch(
                    remoteName: "origin",
                    branchName: "main",
                    basis: .branchTip
                )
            ),
            (
                #"{"basis":"commonCommit","kind":"branch","name":"stack/base"}"#,
                .branch(name: "stack/base")
            ),
            (
                #"{"kind":"commit","oid":"0123456789abcdef0123456789abcdef01234567"}"#,
                .commit(oid: "0123456789abcdef0123456789abcdef01234567")
            ),
            (
                #"{"basis":"branchTip","kind":"ref","name":"refs/tags/release"}"#,
                .ref(name: "refs/tags/release", basis: .branchTip)
            ),
        ]

        for targetCase in targetCases {
            let decoded = try JSONDecoder().decode(
                BridgeProductReviewComparisonTransportTarget.self,
                from: Data(targetCase.json.utf8)
            )
            #expect(decoded.workspaceTarget == targetCase.expected)
        }
    }

    @Test("strict target admission is shared by presentation and immutable origin")
    func strictTargetAdmissionIsSharedByPresentationAndOrigin() {
        let presentationJSON = Data(
            #"{"kind":"pane.presentation","wireVersion":2,"paneSessionId":"pane-session-1","workerInstanceId":"worker-instance-1","metadataStreamId":"metadata-stream-1","streamSequence":3,"presentationRevision":9,"nativeActivity":"foreground","refreshingLanes":[],"reviewComparison":{"activeTarget":{"kind":"branch","name":"stack/base"},"attempt":{"status":"selectionRequired"},"displayedSnapshot":{"status":"none"},"repositoryDefaultTarget":null}}"#
                .utf8
        )
        let originJSON = Data(
            #"{"baseOID":"aaaaaaaa","baseRole":"commonCommit","comparedRole":"capturedWorkingTree","kind":"contribution","resolvedTargetOID":"bbbbbbbb","reviewedHeadOID":"cccccccc","symbolicTarget":{"kind":"branch","name":"stack/base"}}"#
                .utf8
        )

        #expect(throws: Error.self) {
            _ = try BridgeProductStrictJSON.decode(
                BridgeProductMetadataFrame.self,
                from: presentationJSON
            )
        }
        #expect(throws: Error.self) {
            _ = try JSONDecoder().decode(BridgeReviewComparisonOrigin.self, from: originJSON)
        }
    }

    @Test("pane presentation carries canonical target attempt and snapshot identity")
    func panePresentationCarriesComparisonState() throws {
        // Arrange
        let presentationJSON = Data(
            #"{"kind":"pane.presentation","wireVersion":2,"paneSessionId":"pane-session-1","workerInstanceId":"worker-instance-1","metadataStreamId":"metadata-stream-1","streamSequence":3,"presentationRevision":9,"nativeActivity":"foreground","refreshingLanes":["review"],"reviewComparison":{"activeTarget":{"basis":"commonCommit","kind":"branch","name":"stack/base"},"attempt":{"status":"pending","reviewGeneration":8},"displayedSnapshot":{"status":"stale","packageId":"package-7","reviewGeneration":7,"revision":11},"repositoryDefaultTarget":{"branchName":"main","remoteName":"origin"}}}"#
                .utf8
        )

        // Act
        let frame = try BridgeProductStrictJSON.decode(
            BridgeProductMetadataFrame.self,
            from: presentationJSON
        )
        let encodedFrame = try sortedJSONObject(frame)
        let canonicalFrame = try sortedJSONObject(from: presentationJSON)

        // Assert
        guard case .panePresentation(let presentation) = frame else {
            Issue.record("Expected pane presentation frame")
            return
        }
        #expect(presentation.presentationRevision == 9)
        #expect(
            presentation.reviewComparison
                == BridgePaneReviewComparisonPresentation(
                    activeTarget: .branch(name: "stack/base"),
                    attempt: .pending(reviewGeneration: 8),
                    displayedSnapshot: .stale(
                        BridgePaneReviewDisplayedSnapshotIdentity(
                            packageId: "package-7",
                            reviewGeneration: 7,
                            revision: 11
                        )
                    ),
                    repositoryDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity(
                        remoteName: "origin",
                        branchName: "main"
                    )
                )
        )
        #expect(encodedFrame == canonicalFrame)
    }

    @Test("comparison target content encodes capture facts and an absent default as explicit null")
    func comparisonTargetContentEncodesCaptureFactsAndAbsentDefaultAsExplicitNull() throws {
        // Arrange
        let catalog = BridgeReviewComparisonTargetCatalog(
            capturedAtUnixMilliseconds: 2000,
            cutoffUnixMilliseconds: 1000,
            isTruncated: false,
            defaultTarget: nil,
            currentTarget: nil,
            branches: [
                .local(
                    branchName: "stack/base",
                    oid: "af70f11324247e802366a8f6ab1f4ea0ec5ae55f"
                )
            ]
        )

        // Act
        let encodedCatalog = try sortedJSONObject(catalog)

        // Assert
        #expect(
            encodedCatalog
                == #"{"branches":[{"branchName":"stack\/base","kind":"local","oid":"af70f11324247e802366a8f6ab1f4ea0ec5ae55f"}],"capturedAtUnixMilliseconds":2000,"currentTarget":null,"cutoffUnixMilliseconds":1000,"defaultTarget":null,"isTruncated":false}"#
        )
    }

    @Test("comparison target query response is admitted by strict JSON vocabulary")
    func comparisonTargetQueryResponseUsesRegisteredCaptureKeys() throws {
        let responseJSON = Data(
            #"{"call":{"method":"review.comparisonTargets.query","result":{"descriptor":{"capturedAtUnixMilliseconds":2000,"contentKind":"review.comparisonTargets","cutoffUnixMilliseconds":1000,"declaredByteLength":7,"descriptorId":"019FEEC5-A29D-7858-A3BD-AB969E228484","encoding":"utf-8","expectedSha256":"b4515e15c59bb425429f6a53644cb0c6b5696ceedfb5230e73ace9ee7cbae33e","maximumBytes":7}}},"kind":"call.completed","paneSessionId":"pane-session-1","requestId":"request-1","requestSequence":1,"wireVersion":2,"workerInstanceId":"worker-instance-1"}"#
                .utf8
        )

        let response = try BridgeProductStrictJSON.decode(
            BridgeProductControlResponse.self,
            from: responseJSON
        )

        guard case .callCompleted(let completed) = response else {
            Issue.record("Expected a completed comparison-target query response")
            return
        }
        #expect(completed.call.method == "review.comparisonTargets.query")
    }

    @Test("comparison target query creates a descriptor for a catalog below the byte ceiling")
    func comparisonTargetQueryCreatesDescriptorBelowByteCeiling() async throws {
        // Arrange
        let capture = BridgeReviewComparisonTargetsCapture(
            capturedAtUnixMilliseconds: 2000,
            cutoffUnixMilliseconds: 1000,
            isTruncated: false,
            defaultTarget: nil,
            currentTarget: nil,
            branches: [
                .local(
                    branchName: "stack/base",
                    oid: "af70f11324247e802366a8f6ab1f4ea0ec5ae55f"
                )
            ]
        )

        // Act
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let result = BridgePaneProductComparisonTargetQuerySource.makeCapture(
            capture,
            maximumEncodedBytes: 1024 * 1024,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        let queryCapture = try #require(result)
        #expect(queryCapture.descriptor.declaredByteLength == queryCapture.body.count)
        #expect(queryCapture.descriptor.maximumBytes == queryCapture.body.count)
    }

    @Test("comparison target byte truncation is exact deterministic and preserves role rows")
    func comparisonTargetByteTruncationPreservesRoleRows() async throws {
        // Arrange
        let defaultTarget = BridgeReviewComparisonBranchTarget.local(
            branchName: "default-\(String(repeating: "d", count: 256))",
            oid: String(repeating: "a", count: 40)
        )
        let currentTarget = BridgeReviewComparisonBranchTarget.local(
            branchName: "current-\(String(repeating: "c", count: 256))",
            oid: String(repeating: "b", count: 40)
        )
        let ordinaryBranches = (0..<1998).map { index in
            BridgeReviewComparisonBranchTarget.local(
                branchName: "ordinary-\(index)-\(String(repeating: "x", count: 256))",
                oid: String(format: "%040x", index)
            )
        }
        let capture = BridgeReviewComparisonTargetsCapture(
            capturedAtUnixMilliseconds: 2000,
            cutoffUnixMilliseconds: 1000,
            isTruncated: false,
            defaultTarget: defaultTarget,
            currentTarget: currentTarget,
            branches: [defaultTarget, currentTarget] + ordinaryBranches
        )
        let maximumEncodedBytes = 32 * 1024
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()

        // Act
        let first = try #require(
            BridgePaneProductComparisonTargetQuerySource.makeCapture(
                capture,
                maximumEncodedBytes: maximumEncodedBytes,
                foregroundWorkAdmission: refreshWorkAdmission.admission
            )
        )
        let second = try #require(
            BridgePaneProductComparisonTargetQuerySource.makeCapture(
                capture,
                maximumEncodedBytes: maximumEncodedBytes,
                foregroundWorkAdmission: refreshWorkAdmission.admission
            )
        )
        let decodedCatalog = try JSONDecoder().decode(
            BridgeReviewComparisonTargetCatalog.self,
            from: first.body
        )

        // Assert
        #expect(first.body == second.body)
        #expect(first.body.count <= maximumEncodedBytes)
        #expect(decodedCatalog.isTruncated)
        #expect(decodedCatalog.defaultTarget == defaultTarget)
        #expect(decodedCatalog.currentTarget == currentTarget)
        #expect(decodedCatalog.branches.first == defaultTarget)
        #expect(decodedCatalog.branches.dropFirst().first == currentTarget)
        #expect(decodedCatalog.branches.count < capture.branches.count)

        let firstOmittedBranch = capture.branches[decodedCatalog.branches.count]
        let oneRowLargerCatalog = BridgeReviewComparisonTargetCatalog(
            capturedAtUnixMilliseconds: capture.capturedAtUnixMilliseconds,
            cutoffUnixMilliseconds: capture.cutoffUnixMilliseconds,
            isTruncated: true,
            defaultTarget: capture.defaultTarget,
            currentTarget: capture.currentTarget,
            branches: decodedCatalog.branches + [firstOmittedBranch]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(oneRowLargerCatalog).count > maximumEncodedBytes)
    }

    @Test("comparison target byte truncation removes a row at the exact flag boundary")
    func comparisonTargetByteTruncationRemovesRowAtExactFlagBoundary() async throws {
        // Arrange
        let defaultTarget = BridgeReviewComparisonBranchTarget.local(
            branchName: "main",
            oid: String(repeating: "a", count: 40)
        )
        let ordinaryTarget = BridgeReviewComparisonBranchTarget.local(
            branchName: "feature/review-comparison",
            oid: String(repeating: "b", count: 40)
        )
        let capture = BridgeReviewComparisonTargetsCapture(
            capturedAtUnixMilliseconds: 2000,
            cutoffUnixMilliseconds: 1000,
            isTruncated: false,
            defaultTarget: defaultTarget,
            currentTarget: nil,
            branches: [defaultTarget, ordinaryTarget]
        )
        let completeCatalog = BridgeReviewComparisonTargetCatalog(
            capturedAtUnixMilliseconds: capture.capturedAtUnixMilliseconds,
            cutoffUnixMilliseconds: capture.cutoffUnixMilliseconds,
            isTruncated: false,
            defaultTarget: capture.defaultTarget,
            currentTarget: capture.currentTarget,
            branches: capture.branches
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let maximumEncodedBytes = try encoder.encode(completeCatalog).count - 1
        let refreshWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()

        // Act
        let queryCapture = BridgePaneProductComparisonTargetQuerySource.makeCapture(
            capture,
            maximumEncodedBytes: maximumEncodedBytes,
            foregroundWorkAdmission: refreshWorkAdmission.admission
        )

        // Assert
        let admittedCapture = try #require(queryCapture)
        let decodedCatalog = try JSONDecoder().decode(
            BridgeReviewComparisonTargetCatalog.self,
            from: admittedCapture.body
        )
        #expect(decodedCatalog.isTruncated)
        #expect(decodedCatalog.defaultTarget == defaultTarget)
        #expect(decodedCatalog.branches == [defaultTarget])
        #expect(admittedCapture.body.count < maximumEncodedBytes)
    }

    @Test("foreground loss during target capture returns a query-local error")
    func foregroundLossDuringTargetCaptureReturnsQueryLocalError() async throws {
        // Arrange
        let captureGate = BridgeComparisonGate()
        let capture = BridgeReviewComparisonTargetsCapture(
            capturedAtUnixMilliseconds: 2000,
            cutoffUnixMilliseconds: 1000,
            isTruncated: false,
            defaultTarget: nil,
            currentTarget: nil,
            branches: [
                .local(
                    branchName: "stack/base",
                    oid: "af70f11324247e802366a8f6ab1f4ea0ec5ae55f"
                )
            ]
        )
        let sourceProvider = BridgeReviewSourceProviderFake(
            comparison: BridgeEndpointComparison(
                baseEndpoint: makeBridgeEndpoint(endpointId: "base", kind: .gitRef),
                headEndpoint: makeBridgeEndpoint(endpointId: "head", kind: .workingTree),
                changedFiles: []
            ),
            contentByHandleId: [:],
            comparisonTargetsCapture: capture,
            comparisonTargetsCaptureGate: captureGate
        )
        let refreshCoordinator = await MainActor.run {
            BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        }
        let refreshWorkAdmissionSource = await MainActor.run {
            refreshCoordinator.workAdmissionSource
        }
        let targetProjection = await MainActor.run {
            BridgeReviewComparisonTargetProjection(
                state: BridgePaneState(
                    panelKind: .diffViewer,
                    source: .workspace(
                        rootPath: "/tmp/worktree",
                        baseline: .branch(name: "stack/base")
                    )
                )
            )
        }
        let provider = BridgePaneProductSchemeProvider(
            fileMetadataSource: BridgeUnavailablePaneProductFileMetadataSource(),
            reviewMetadataSource: BridgeUnavailablePaneProductReviewMetadataSource(),
            reviewContentSource: BridgeUnavailablePaneProductReviewContentSource(),
            markReviewItemViewed: { _, _ in },
            queryReviewComparisonTargets: BridgePaneProductComparisonTargetQuerySource.makeQuery(
                reviewSourceProvider: sourceProvider,
                targetProjection: targetProjection,
                refreshWorkAdmissionSource: refreshWorkAdmissionSource
            ),
            refreshWorkAdmissionSource: refreshWorkAdmissionSource
        )
        let request = try BridgeProductStrictJSON.decode(
            BridgeProductControlRequest.self,
            from: reviewComparisonTargetsQueryBody()
        )
        let query = Task {
            await provider.response(for: request)
        }
        await captureGate.waitForStartedComparisonCount(1)

        // Act
        await MainActor.run {
            refreshCoordinator.applyActivity(.loadedHidden)
        }
        await captureGate.releaseAll()
        let response = await query.value

        // Assert
        guard case .requestError(let error) = response else {
            Issue.record("Expected foreground loss to cancel only the comparison-target query")
            return
        }
        #expect(error.code == .internal)
        #expect(error.retryable)
        #expect(error.safeMessage == "Comparison targets are unavailable")
    }

    private func sortedJSONObject<TValue: Encodable>(_ value: TValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(data: encoder.encode(value), encoding: .utf8))
    }

    private func sortedJSONObject(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        let sorted = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try #require(String(data: sorted, encoding: .utf8))
    }

    private func reviewComparisonUpdateBody() -> Data {
        Data(
            """
            {
              "call": {
                "method": "review.comparison.update",
                "request": { "target": { "basis": "commonCommit", "kind": "branch", "name": "stack/base" } }
              },
              "kind": "product.call",
              "paneSessionId": "\(bridgeProductTestPaneSessionId)",
              "requestId": "review-comparison-update-1",
              "requestSequence": 2,
              "wireVersion": 2,
              "workerDerivationEpoch": 0,
              "workerInstanceId": "\(bridgeProductTestWorkerInstanceId)"
            }
            """.utf8
        )
    }

    private func reviewComparisonTargetsQueryBody() -> Data {
        Data(
            """
            {
              "call": {
                "method": "review.comparisonTargets.query",
                "request": {}
              },
              "kind": "product.call",
              "paneSessionId": "\(bridgeProductTestPaneSessionId)",
              "requestId": "review-comparison-targets-query-1",
              "requestSequence": 2,
              "wireVersion": 2,
              "workerDerivationEpoch": 0,
              "workerInstanceId": "\(bridgeProductTestWorkerInstanceId)"
            }
            """.utf8
        )
    }
}

@MainActor
private final class BridgeProductComparisonTargetRecorder {
    private(set) var targets: [WorkspaceReviewContributionTarget] = []

    func record(_ target: WorkspaceReviewContributionTarget) {
        targets.append(target)
    }
}
