import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoScanner resumable sessions")
struct RepoScannerSessionTests {
    @Test("one-item quanta suspend without inventory and finish exhaustively")
    func oneItemQuantaResumeToOneExhaustiveResult() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha", "beta", "gamma"])
        defer { fixture.remove() }
        let budget = try oneItemQuantumBudget()
        let expectedEntries = fixture.candidatePaths.map { candidatePath in
            RepoScanner.ResolvedGitEntry(
                path: candidatePath,
                kind: .cloneRoot,
                repositoryKey: candidatePath.lastPathComponent
            )
        }
        let session = RepoScanner().makeSession(
            in: fixture.root,
            maxDepth: 1,
            quantumBudget: budget
        )

        // Act
        var suspendedUsages: [RepoScannerQuantumUsage] = []
        let finalResult = await finish(
            session: session,
            outcomesByCanonicalPath: Dictionary(
                uniqueKeysWithValues: expectedEntries.map { entry in
                    (canonicalSessionPath(entry.path), .validated(entry))
                }
            ),
            suspendedUsages: &suspendedUsages
        )

        // Assert
        #expect(!suspendedUsages.isEmpty)
        #expect(suspendedUsages.allSatisfy { $0.enumeratedItemCount <= 1 })
        guard case .completeAuthoritative(let completeScan) = finalResult else {
            Issue.record("expected complete scanner evidence, got \(finalResult)")
            return
        }
        #expect(Set(completeScan.verifiedEntries.map(\.repositoryKey)) == Set(["alpha", "beta", "gamma"]))
        #expect(completeScan.counts.validationSuccessCount == expectedEntries.count)
        #expect(
            completeScan.counts.scannerServiceInvocationCount
                == suspendedUsages.count + completeScan.counts.validationSuccessCount + 1
        )
        #expect(completeScan.serviceMetrics.traversalServiceDuration > .zero)
        #expect(completeScan.serviceMetrics.validationServiceDuration == .zero)
    }

    @Test("cancellation between quanta finishes with typed cancellation evidence")
    func cancellationBetweenQuantaFinishesSession() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha"])
        defer { fixture.remove() }
        let session = RepoScanner().makeSession(
            in: fixture.root,
            maxDepth: 1,
            quantumBudget: try oneItemQuantumBudget()
        )
        guard case .suspended = await session.advanceOneQuantum() else {
            Issue.record("expected the first one-item quantum to suspend")
            return
        }

        // Act
        let cancellation = session.cancel()
        let outcome = await session.advanceOneQuantum()

        // Assert
        #expect(cancellation == .cancelled)
        guard case .finished(.cancelled(let cancelledScan)) = outcome else {
            Issue.record("expected cancelled scanner evidence, got \(outcome)")
            return
        }
        #expect(cancelledScan.counts.scannerServiceInvocationCount == 1)
        #expect(session.cancel() == .alreadyFinished)
    }

    @Test("cancellation awaiting validation returns exact executor cancellation custody")
    func cancellationAwaitingValidationFinishesSession() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha"])
        defer { fixture.remove() }
        let session = RepoScanner().makeSession(in: fixture.root, maxDepth: 1)

        // Act
        let validationOutcome = await session.advanceOneQuantum()
        guard case .validationRequired(let request) = validationOutcome else {
            Issue.record("expected validation request, got \(validationOutcome)")
            return
        }
        let cancellation = session.cancel()
        let outcome = await session.advanceOneQuantum()

        // Assert
        #expect(cancellation == .cancelledAwaitingValidation(request))
        guard case .finished(.cancelled(let cancelledScan)) = outcome else {
            Issue.record("expected cancelled scanner evidence, got \(outcome)")
            return
        }
        #expect(cancelledScan.counts.validationCancellationCount == 1)
        #expect(cancelledScan.counts.scannerServiceInvocationCount == 1)
    }

    @Test("validation completion consumes only the exact current request")
    func validationCompletionRejectsForeignStaleDuplicateAndCandidateMismatch() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha", "beta"])
        defer { fixture.remove() }
        let session = RepoScanner().makeSession(in: fixture.root, maxDepth: 1)
        guard case .validationRequired(let alphaRequest) = await nextValidationRequest(session) else {
            Issue.record("expected first validation request")
            return
        }
        let foreignSessionRequest = RepoScannerValidationRequest(
            requestID: alphaRequest.requestID,
            scannerSessionID: RepoScannerSessionID(rawValue: UUIDv7.generate()),
            scanRootURL: alphaRequest.scanRootURL,
            candidateURL: alphaRequest.candidateURL
        )
        let foreignRequest = RepoScannerValidationRequest(
            requestID: .make(),
            scannerSessionID: alphaRequest.scannerSessionID,
            scanRootURL: alphaRequest.scanRootURL,
            candidateURL: alphaRequest.candidateURL
        )
        let foreignCandidateRequest = RepoScannerValidationRequest(
            requestID: alphaRequest.requestID,
            scannerSessionID: alphaRequest.scannerSessionID,
            scanRootURL: alphaRequest.scanRootURL,
            candidateURL: fixture.candidatePaths[1]
        )
        let foreignRootRequest = RepoScannerValidationRequest(
            requestID: alphaRequest.requestID,
            scannerSessionID: alphaRequest.scannerSessionID,
            scanRootURL: fixture.root.appending(path: "foreign-root"),
            candidateURL: alphaRequest.candidateURL
        )

        // Act / Assert
        #expect(
            session.consumeValidationCompletion(
                .init(
                    request: foreignRootRequest,
                    outcome: .authoritativeNegative(.notAValidWorktree),
                    validationServiceDuration: .zero
                )
            ) == .rejected(.foreignRoot(foreignRootRequest.scanRootURL))
        )
        #expect(
            session.consumeValidationCompletion(
                .init(
                    request: foreignSessionRequest,
                    outcome: .authoritativeNegative(.notAValidWorktree),
                    validationServiceDuration: .zero
                )
            ) == .rejected(.foreignSession(foreignSessionRequest.scannerSessionID))
        )
        #expect(
            session.consumeValidationCompletion(
                .init(
                    request: foreignRequest,
                    outcome: .authoritativeNegative(.notAValidWorktree),
                    validationServiceDuration: .zero
                )
            ) == .rejected(.foreignRequest(foreignRequest.requestID))
        )
        #expect(
            session.consumeValidationCompletion(
                .init(
                    request: foreignCandidateRequest,
                    outcome: .authoritativeNegative(.notAValidWorktree),
                    validationServiceDuration: .zero
                )
            ) == .rejected(.foreignCandidate(foreignCandidateRequest.candidateURL))
        )
        let exactCompletion = RepoScannerValidationCompletion(
            request: alphaRequest,
            outcome: .authoritativeNegative(.notAValidWorktree),
            validationServiceDuration: .milliseconds(7)
        )
        #expect(session.consumeValidationCompletion(exactCompletion) == .consumed)
        #expect(
            session.consumeValidationCompletion(exactCompletion)
                == .rejected(.duplicateCompletion(alphaRequest.requestID))
        )

        guard case .validationRequired(let betaRequest) = await nextValidationRequest(session) else {
            Issue.record("expected second validation request")
            return
        }
        #expect(
            session.consumeValidationCompletion(exactCompletion)
                == .rejected(.staleRequest(alphaRequest.requestID))
        )
        #expect(betaRequest.scannerSessionID == session.id)
        #expect(betaRequest.requestID.isUUIDv7)
    }

    @Test("validation wait is outside traversal service by construction")
    func validationWaitDoesNotAcquireAnotherTraversalLease() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha"])
        defer { fixture.remove() }
        let session = RepoScanner().makeSession(in: fixture.root, maxDepth: 1)
        guard case .validationRequired(let request) = await session.advanceOneQuantum() else {
            Issue.record("expected validation request")
            return
        }

        // Act
        let repeatedOutcome = await session.advanceOneQuantum()

        // Assert
        #expect(repeatedOutcome == .validationRequired(request))
        #expect(
            session.consumeValidationCompletion(
                .init(
                    request: request,
                    outcome: .authoritativeNegative(.notAValidWorktree),
                    validationServiceDuration: .milliseconds(7)
                )
            ) == .consumed
        )
        guard case .finished(.completeAuthoritative(let completed)) = await session.advanceOneQuantum()
        else {
            Issue.record("expected completed scanner evidence")
            return
        }
        #expect(completed.serviceMetrics.validationServiceDuration == .milliseconds(7))
        #expect(completed.serviceMetrics.traversalServiceDuration > .zero)
        guard case .finished(.completeAuthoritative(let result)) = await session.advanceOneQuantum() else {
            Issue.record("expected complete result")
            return
        }
        #expect(result.counts.scannerServiceInvocationCount == 2)
        #expect(result.counts.validationAuthoritativeNegativeCount == 1)
    }

    @Test("recent consumed validation requests remain stale while a later request is pending")
    func earlierConsumedValidationRequestDoesNotAdvanceLaterPendingRequest() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(
            candidateNames: ["alpha", "beta", "gamma", "delta"]
        )
        defer { fixture.remove() }
        let session = RepoScanner().makeSession(in: fixture.root, maxDepth: 1)
        var consumedRequests: [RepoScannerValidationRequest] = []
        for _ in 0..<3 {
            guard case .validationRequired(let request) = await nextValidationRequest(session) else {
                Issue.record("expected validation request")
                return
            }
            #expect(
                session.consumeValidationCompletion(
                    .init(
                        request: request,
                        outcome: .authoritativeNegative(.notAValidWorktree),
                        validationServiceDuration: .zero
                    )
                ) == .consumed
            )
            consumedRequests.append(request)
        }
        guard case .validationRequired(let pendingRequest) = await nextValidationRequest(session) else {
            Issue.record("expected later pending validation request")
            return
        }

        // Act
        let staleCompletionResult = session.consumeValidationCompletion(
            .init(
                request: consumedRequests[0],
                outcome: .authoritativeNegative(.notAValidWorktree),
                validationServiceDuration: .zero
            )
        )
        let outcomeAfterStaleCompletion = await session.advanceOneQuantum()

        // Assert
        #expect(
            staleCompletionResult
                == .rejected(.staleRequest(consumedRequests[0].requestID))
        )
        #expect(outcomeAfterStaleCompletion == .validationRequired(pendingRequest))
    }

    @Test("enumeration capacity exhaustion cannot authorize absence")
    func enumerationCapacityProducesPartialEvidence() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha", "beta"])
        defer { fixture.remove() }
        let capacity = try RepoScannerSessionCapacity(
            maximumEnumeratedItems: 2,
            maximumPathBytes: 1_048_576,
            maximumRetainedVerifiedEntries: 10,
            maximumRetainedVerifiedEntryBytes: 1_048_576,
            maximumRetainedFailures: 10
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                capacity: capacity
            ),
            outcomesByCanonicalPath: [:]
        )

        // Assert
        assertPartialCapacityResult(
            result,
            expectedDimension: .enumeratedItemCount(maximum: 2)
        )
    }

    @Test("retained entry count exhaustion cannot produce a complete result")
    func retainedEntryCapacityProducesPartialEvidence() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha", "beta"])
        defer { fixture.remove() }
        let entries = fixture.candidatePaths.map { candidatePath in
            RepoScanner.ResolvedGitEntry(
                path: candidatePath,
                kind: .cloneRoot,
                repositoryKey: candidatePath.lastPathComponent
            )
        }
        let capacity = try RepoScannerSessionCapacity(
            maximumEnumeratedItems: 100,
            maximumPathBytes: 1_048_576,
            maximumRetainedVerifiedEntries: 1,
            maximumRetainedVerifiedEntryBytes: 1_048_576,
            maximumRetainedFailures: 10
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                capacity: capacity
            ),
            outcomesByCanonicalPath: Dictionary(
                uniqueKeysWithValues: entries.map { entry in
                    (canonicalSessionPath(entry.path), .validated(entry))
                }
            )
        )

        // Assert
        assertPartialCapacityResult(
            result,
            expectedDimension: .retainedVerifiedEntryCount(maximum: 1)
        )
    }

    @Test("enumerated path byte exhaustion cannot authorize absence")
    func enumeratedPathByteCapacityProducesPartialEvidence() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha"])
        defer { fixture.remove() }
        let maximumPathBytes = fixture.root.path.utf8.count
        let capacity = try RepoScannerSessionCapacity(
            maximumEnumeratedItems: 100,
            maximumPathBytes: maximumPathBytes,
            maximumRetainedVerifiedEntries: 10,
            maximumRetainedVerifiedEntryBytes: 1_048_576,
            maximumRetainedFailures: 10
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                capacity: capacity
            ),
            outcomesByCanonicalPath: [:]
        )

        // Assert
        assertPartialCapacityResult(
            result,
            expectedDimension: .enumeratedPathBytes(maximum: maximumPathBytes)
        )
    }

    @Test("retained entry byte exhaustion cannot produce a complete result")
    func retainedEntryByteCapacityProducesPartialEvidence() async throws {
        // Arrange
        let fixture = try ScannerSessionFixture(candidateNames: ["alpha"])
        defer { fixture.remove() }
        let entry = RepoScanner.ResolvedGitEntry(
            path: fixture.candidatePaths[0],
            kind: .cloneRoot,
            repositoryKey: "alpha"
        )
        let capacity = try RepoScannerSessionCapacity(
            maximumEnumeratedItems: 100,
            maximumPathBytes: 1_048_576,
            maximumRetainedVerifiedEntries: 10,
            maximumRetainedVerifiedEntryBytes: 1,
            maximumRetainedFailures: 10
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                capacity: capacity
            ),
            outcomesByCanonicalPath: [canonicalSessionPath(entry.path): .validated(entry)]
        )

        // Assert
        assertPartialCapacityResult(
            result,
            expectedDimension: .retainedVerifiedEntryBytes(maximum: 1)
        )
    }

    private func oneItemQuantumBudget() throws -> RepoScannerQuantumBudget {
        try RepoScannerQuantumBudget(
            maximumEnumeratedItems: 1,
            maximumPathBytes: 1_048_576,
            maximumCandidateValidations: 1,
            maximumFailures: 10,
            maximumActiveServiceDuration: .seconds(60)
        )
    }

    private func finish(
        session: RepoScannerSessionPort,
        outcomesByCanonicalPath: [String: GitRepositoryDiscoveryOutcome],
        suspendedUsages: inout [RepoScannerQuantumUsage]
    ) async -> RepoScannerResult {
        while true {
            switch await session.advanceOneQuantum() {
            case .suspended(let usage):
                suspendedUsages.append(usage)
            case .validationRequired(let request):
                let outcome =
                    outcomesByCanonicalPath[canonicalSessionPath(request.candidateURL)]
                    ?? .authoritativeNegative(.notAValidWorktree)
                #expect(
                    session.consumeValidationCompletion(
                        .init(
                            request: request,
                            outcome: outcome,
                            validationServiceDuration: .zero
                        )
                    )
                        == .consumed
                )
            case .finished(let result):
                return result
            }
        }
    }

    private func finish(
        session: RepoScannerSessionPort,
        outcomesByCanonicalPath: [String: GitRepositoryDiscoveryOutcome]
    ) async -> RepoScannerResult {
        var suspendedUsages: [RepoScannerQuantumUsage] = []
        return await finish(
            session: session,
            outcomesByCanonicalPath: outcomesByCanonicalPath,
            suspendedUsages: &suspendedUsages
        )
    }

    private func nextValidationRequest(
        _ session: RepoScannerSessionPort
    ) async -> RepoScannerQuantumOutcome {
        while true {
            let outcome = await session.advanceOneQuantum()
            if case .suspended = outcome { continue }
            return outcome
        }
    }

    private func assertPartialCapacityResult(
        _ result: RepoScannerResult,
        expectedDimension: RepoScannerSessionCapacityDimension,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard case .partial(let partialScan) = result else {
            Issue.record("expected partial scanner evidence, got \(result)", sourceLocation: sourceLocation)
            return
        }
        #expect(
            partialScan.failures.all.contains(.sessionCapacityExceeded(expectedDimension)),
            sourceLocation: sourceLocation
        )
    }
}

private struct ScannerSessionFixture {
    let root: URL
    let candidatePaths: [URL]

    init(candidateNames: [String]) throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-session-\(UUID().uuidString)")
        root = fixtureRoot
        candidatePaths = candidateNames.map { fixtureRoot.appending(path: $0) }
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        for candidatePath in candidatePaths {
            try FileManager.default.createDirectory(
                at: candidatePath.appending(path: ".git"),
                withIntermediateDirectories: true
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func canonicalSessionPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
}
