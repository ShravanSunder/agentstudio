import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite("RepoScanner completeness")
struct RepoScannerCompletenessTests {
    @Test("depth-zero scan validates only the exact root as authoritative clone evidence")
    func depthZeroScanValidatesExactRoot() async throws {
        // Arrange
        let scanRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-depth-zero-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: scanRoot.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scanRoot) }
        let canonicalRoot = RepoScanner.canonicalURL(scanRoot)
        let expectedEntry = RepoScanner.ResolvedGitEntry(
            path: canonicalRoot,
            kind: .cloneRoot,
            repositoryKey: "depth-zero-root"
        )
        let discoveryProvider = StubGitRepositoryDiscoveryProvider(
            outcomesByCanonicalPath: [canonicalPath(canonicalRoot): .validated(expectedEntry)]
        )

        // Act
        let result = await RepoScanner().scan(
            in: scanRoot,
            maxDepth: 0,
            discoveryProvider: discoveryProvider
        )

        // Assert
        guard case .completeAuthoritative(let completeScan) = result else {
            Issue.record("expected exact-root authoritative scanner evidence, got \(result)")
            return
        }
        #expect(completeScan.verifiedEntries == [expectedEntry])
        #expect(completeScan.counts.gitCandidateCount == 1)
        #expect(completeScan.counts.validationSuccessCount == 1)
    }

    @Test("validation failure produces partial evidence while retaining verified positives")
    func validationFailureRetainsVerifiedPositiveWithoutAuthorizingAbsence() async throws {
        // Arrange
        let scanRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-completeness-\(UUID().uuidString)")
        let validatedRepositoryPath = scanRoot.appending(path: "validated")
        let failedRepositoryPath = scanRoot.appending(path: "failed")
        try FileManager.default.createDirectory(
            at: validatedRepositoryPath.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: failedRepositoryPath.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scanRoot) }

        let validatedEntry = RepoScanner.ResolvedGitEntry(
            path: validatedRepositoryPath,
            kind: .cloneRoot,
            repositoryKey: "validated-repository"
        )
        let discoveryProvider = StubGitRepositoryDiscoveryProvider(
            outcomesByCanonicalPath: [
                canonicalPath(validatedRepositoryPath): .validated(validatedEntry),
                canonicalPath(failedRepositoryPath): .failure(
                    .validationFailed(detail: "injected validation failure")
                ),
            ]
        )

        // Act
        let result = await RepoScanner().scan(
            in: scanRoot,
            maxDepth: 1,
            discoveryProvider: discoveryProvider
        )

        // Assert
        guard case .partial(let partialScan) = result else {
            Issue.record("expected partial scanner evidence, got \(result)")
            return
        }

        #expect(partialScan.verifiedEntries == [validatedEntry])
        #expect(partialScan.counts.gitCandidateCount == 2)
        #expect(partialScan.counts.validationSuccessCount == 1)
        #expect(partialScan.counts.validationFailureCount == 1)
        #expect(partialScan.counts.validationAuthoritativeNegativeCount == 0)
        #expect(partialScan.counts.validationTimeoutCount == 0)
        #expect(partialScan.counts.validationCancellationCount == 0)
        let minimumServiceInvocationCount =
            partialScan.counts.validationSuccessCount
            + partialScan.counts.validationFailureCount + 1
        let maximumServiceInvocationCount =
            partialScan.counts.directoryVisitCount
            + partialScan.counts.gitCandidateCount + 1
        #expect(
            (minimumServiceInvocationCount...maximumServiceInvocationCount).contains(
                partialScan.counts.scannerServiceInvocationCount
            )
        )
        guard
            case .gitRepositoryDiscoveryFailed(let failedCandidatePath, let discoveryFailure) =
                partialScan.failures.first
        else {
            Issue.record("expected a Git repository discovery failure")
            return
        }
        #expect(failedCandidatePath.lastPathComponent == failedRepositoryPath.lastPathComponent)
        #expect(discoveryFailure == .validationFailed(detail: "injected validation failure"))
    }

    @Test("authoritative negative preserves complete authoritative classification")
    func authoritativeNegativeRemainsComplete() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: ["invalid"])
        defer { fixture.remove() }
        let discoveryProvider = StubGitRepositoryDiscoveryProvider(
            outcomesByCanonicalPath: [
                canonicalPath(fixture.candidatePaths[0]): .authoritativeNegative(.notAValidWorktree)
            ]
        )

        // Act
        let result = await RepoScanner().scan(
            in: fixture.root,
            maxDepth: 1,
            discoveryProvider: discoveryProvider
        )

        // Assert
        guard case .completeAuthoritative(let completeScan) = result else {
            Issue.record("expected complete authoritative scanner evidence, got \(result)")
            return
        }
        #expect(completeScan.verifiedEntries.isEmpty)
        #expect(completeScan.counts.gitCandidateCount == 1)
        #expect(completeScan.counts.validationAuthoritativeNegativeCount == 1)
        #expect(completeScan.counts.validationFailureCount == 0)
    }

    @Test("validation timeout is partial rather than an authoritative negative")
    func validationTimeoutIsPartial() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: ["timed-out"])
        defer { fixture.remove() }
        let discoveryProvider = StubGitRepositoryDiscoveryProvider(
            outcomesByCanonicalPath: [canonicalPath(fixture.candidatePaths[0]): .timeout]
        )

        // Act
        let result = await RepoScanner().scan(
            in: fixture.root,
            maxDepth: 1,
            discoveryProvider: discoveryProvider
        )

        // Assert
        guard case .partial(let partialScan) = result else {
            Issue.record("expected partial scanner evidence, got \(result)")
            return
        }
        #expect(partialScan.verifiedEntries.isEmpty)
        #expect(partialScan.counts.validationTimeoutCount == 1)
        #expect(partialScan.counts.validationAuthoritativeNegativeCount == 0)
        guard case .gitValidationTimedOut(let timedOutCandidatePath) = partialScan.failures.first else {
            Issue.record("expected a Git validation timeout")
            return
        }
        #expect(timedOutCandidatePath.lastPathComponent == fixture.candidatePaths[0].lastPathComponent)
    }

    @Test("validation cancellation remains cancellation")
    func validationCancellationRemainsCancellation() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: ["cancelled"])
        defer { fixture.remove() }
        let discoveryProvider = StubGitRepositoryDiscoveryProvider(
            outcomesByCanonicalPath: [canonicalPath(fixture.candidatePaths[0]): .cancelled]
        )

        // Act
        let result = await RepoScanner().scan(
            in: fixture.root,
            maxDepth: 1,
            discoveryProvider: discoveryProvider
        )

        // Assert
        guard case .cancelled(let cancelledScan) = result else {
            Issue.record("expected cancelled scanner evidence, got \(result)")
            return
        }
        #expect(cancelledScan.counts.validationCancellationCount == 1)
        #expect(cancelledScan.counts.validationFailureCount == 0)
    }

    @Test("missing root is unavailable rather than an empty complete scan")
    func missingRootIsUnavailable() async {
        // Arrange
        let missingRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-missing-\(UUID().uuidString)")

        // Act
        let result = await RepoScanner().scan(
            in: missingRoot,
            discoveryProvider: StubGitRepositoryDiscoveryProvider(outcomesByCanonicalPath: [:])
        )

        // Assert
        guard case .unavailable(let unavailableScan) = result else {
            Issue.record("expected unavailable scanner evidence, got \(result)")
            return
        }
        #expect(unavailableScan.reason == .rootDoesNotExist)
        #expect(unavailableScan.counts.scannerServiceInvocationCount == 1)
    }

    @Test("retained checkout beyond ordinary depth is validated before exhaustion")
    func retainedCheckoutBeyondMaximumDepthIsValidated() async throws {
        // Arrange
        let scanRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-retained-depth-\(UUIDv7.generate().uuidString)")
        let retainedCheckoutPath = scanRoot.appending(path: "organization/team/retained")
        try FileManager.default.createDirectory(
            at: retainedCheckoutPath.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scanRoot) }
        let canonicalRetainedCheckoutPath = RepoScanner.canonicalURL(retainedCheckoutPath)
        let expectedEntry = RepoScanner.ResolvedGitEntry(
            path: canonicalRetainedCheckoutPath,
            kind: .cloneRoot,
            repositoryKey: "retained-depth"
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: scanRoot,
                maxDepth: 1,
                retainedCheckoutPaths: [retainedCheckoutPath]
            ),
            outcomesByCanonicalPath: [canonicalPath(retainedCheckoutPath): .validated(expectedEntry)]
        )

        // Assert
        guard case .completeAuthoritative(let completeScan) = result else {
            Issue.record("expected retained checkout validation to remain authoritative, got \(result)")
            return
        }
        #expect(completeScan.verifiedEntries == [expectedEntry])
        #expect(completeScan.counts.validationSuccessCount == 1)
    }

    @Test("ordinary traversal and retained input validate one canonical target once")
    func retainedCheckoutAlreadyExaminedByTraversalIsNotValidatedAgain() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: ["ordinary"])
        defer { fixture.remove() }
        let canonicalCandidatePath = RepoScanner.canonicalURL(fixture.candidatePaths[0])
        let expectedEntry = RepoScanner.ResolvedGitEntry(
            path: canonicalCandidatePath,
            kind: .cloneRoot,
            repositoryKey: "ordinary"
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                retainedCheckoutPaths: [fixture.candidatePaths[0], canonicalCandidatePath]
            ),
            outcomesByCanonicalPath: [canonicalPath(canonicalCandidatePath): .validated(expectedEntry)]
        )

        // Assert
        guard case .completeAuthoritative(let completeScan) = result else {
            Issue.record("expected complete scanner evidence, got \(result)")
            return
        }
        #expect(completeScan.verifiedEntries == [expectedEntry])
        #expect(completeScan.counts.gitCandidateCount == 1)
        #expect(completeScan.counts.validationSuccessCount == 1)
    }

    @Test("failed ordinary candidate is not retried by retained continuation")
    func retainedCheckoutDoesNotRetryFailedOrdinaryValidation() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: ["failed"])
        defer { fixture.remove() }
        let failureReason = GitRepositoryDiscoveryFailureReason.validationFailed(
            detail: "injected ordinary validation failure"
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                retainedCheckoutPaths: [fixture.candidatePaths[0]]
            ),
            outcomesByCanonicalPath: [canonicalPath(fixture.candidatePaths[0]): .failure(failureReason)]
        )

        // Assert
        guard case .partial(let partialScan) = result else {
            Issue.record("expected one failed validation to keep the scan partial, got \(result)")
            return
        }
        #expect(partialScan.counts.gitCandidateCount == 1)
        #expect(partialScan.counts.validationFailureCount == 1)
        #expect(partialScan.failures.all.count == 1)
    }

    @Test("missing and noncandidate retained checkouts are negative space without validation")
    func missingAndNoncandidateRetainedCheckoutsDoNotEnterValidation() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: [])
        defer { fixture.remove() }
        let missingRetainedCheckoutPath = fixture.root.appending(path: "missing/checkout")
        let noncandidateRetainedCheckoutPath = fixture.root.appending(path: "plain/folder")
        try FileManager.default.createDirectory(
            at: noncandidateRetainedCheckoutPath,
            withIntermediateDirectories: true
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 1,
                retainedCheckoutPaths: [
                    missingRetainedCheckoutPath,
                    noncandidateRetainedCheckoutPath,
                ]
            ),
            outcomesByCanonicalPath: [:]
        )

        // Assert
        guard case .completeAuthoritative(let completeScan) = result else {
            Issue.record("expected missing retained checkout to be authoritative negative space, got \(result)")
            return
        }
        #expect(completeScan.verifiedEntries.isEmpty)
        #expect(completeScan.counts.gitCandidateCount == 0)
        #expect(completeScan.counts.validationFailureCount == 0)
        #expect(completeScan.counts.validationAuthoritativeNegativeCount == 0)
    }

    @Test("retained continuation remains within the scanner session capacity")
    func retainedCheckoutCapacityExhaustionRemainsPartial() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: ["retained"])
        defer { fixture.remove() }
        let capacity = try RepoScannerSessionCapacity(
            maximumEnumeratedItems: 1,
            maximumPathBytes: 1_048_576,
            maximumRetainedVerifiedEntries: 10,
            maximumRetainedVerifiedEntryBytes: 1_048_576,
            maximumRetainedFailures: 10
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 0,
                retainedCheckoutPaths: [fixture.candidatePaths[0]],
                capacity: capacity
            ),
            outcomesByCanonicalPath: [:]
        )

        // Assert
        guard case .partial(let partialScan) = result else {
            Issue.record("expected retained continuation capacity failure to remain partial, got \(result)")
            return
        }
        #expect(
            partialScan.failures.all.contains(
                .sessionCapacityExceeded(.enumeratedItemCount(maximum: 1))
            )
        )
        #expect(partialScan.counts.gitCandidateCount == 0)
    }

    @Test("retained continuation ignores targets outside the canonical scan root")
    func retainedCheckoutOutsideRootIsNotExamined() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: [])
        defer { fixture.remove() }
        let outsideRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-retained-outside-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(
            at: outsideRoot.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outsideRoot) }

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 0,
                retainedCheckoutPaths: [outsideRoot]
            ),
            outcomesByCanonicalPath: [:]
        )

        // Assert
        guard case .completeAuthoritative(let completeScan) = result else {
            Issue.record("expected outside retained target to be ignored, got \(result)")
            return
        }
        #expect(completeScan.verifiedEntries.isEmpty)
        #expect(completeScan.counts.gitCandidateCount == 0)
        #expect(completeScan.counts.validationFailureCount == 0)
    }

    @Test("lexically contained retained target that escapes by symlink keeps scan partial")
    func escapingRetainedCheckoutSymlinkDoesNotAuthorizeAbsence() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: [])
        defer { fixture.remove() }
        let outsideRepositoryPath = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-retained-escape-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(
            at: outsideRepositoryPath.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outsideRepositoryPath) }
        let retainedCheckoutPath = fixture.root.appending(path: "retained-link")
        try FileManager.default.createSymbolicLink(
            at: retainedCheckoutPath,
            withDestinationURL: outsideRepositoryPath
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: fixture.root,
                maxDepth: 0,
                retainedCheckoutPaths: [retainedCheckoutPath]
            ),
            outcomesByCanonicalPath: [:]
        )

        // Assert
        guard case .partial(let partialScan) = result else {
            Issue.record("expected escaping retained target to keep scan partial, got \(result)")
            return
        }
        #expect(partialScan.verifiedEntries.isEmpty)
        #expect(partialScan.counts.validationFailureCount == 1)
        #expect(
            partialScan.failures.all.contains(
                .gitRepositoryDiscoveryFailed(
                    candidatePath: RepoScanner.canonicalURL(fixture.root)
                        .appending(path: "retained-link"),
                    reason: .candidateAdmissionRejected(.outsideRegisteredRoot)
                )
            )
        )
    }

    @Test("retained checkout validation failure keeps the scan partial")
    func retainedCheckoutValidationFailureDoesNotAuthorizeAbsence() async throws {
        // Arrange
        let scanRoot = FileManager.default.temporaryDirectory
            .appending(path: "repo-scanner-retained-failure-\(UUIDv7.generate().uuidString)")
        let retainedCheckoutPath = scanRoot.appending(path: "organization/team/retained")
        try FileManager.default.createDirectory(
            at: retainedCheckoutPath.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: scanRoot) }
        let failureReason = GitRepositoryDiscoveryFailureReason.validationFailed(
            detail: "injected retained validation failure"
        )

        // Act
        let result = await finish(
            session: RepoScanner().makeSession(
                in: scanRoot,
                maxDepth: 1,
                retainedCheckoutPaths: [retainedCheckoutPath]
            ),
            outcomesByCanonicalPath: [canonicalPath(retainedCheckoutPath): .failure(failureReason)]
        )

        // Assert
        guard case .partial(let partialScan) = result else {
            Issue.record("expected retained validation failure to remain partial, got \(result)")
            return
        }
        #expect(partialScan.verifiedEntries.isEmpty)
        #expect(partialScan.counts.validationFailureCount == 1)
        #expect(
            partialScan.failures.all.contains { failure in
                guard case .gitRepositoryDiscoveryFailed(let candidatePath, let reason) = failure else { return false }
                return canonicalPath(candidatePath) == canonicalPath(retainedCheckoutPath) && reason == failureReason
            }
        )
    }

    @Test("invalid maximum depth is a scanner failure")
    func invalidMaximumDepthIsFailure() async throws {
        // Arrange
        let fixture = try ScanFixture(candidateNames: [])
        defer { fixture.remove() }

        // Act
        let result = await RepoScanner().scan(
            in: fixture.root,
            maxDepth: -1,
            discoveryProvider: StubGitRepositoryDiscoveryProvider(outcomesByCanonicalPath: [:])
        )

        // Assert
        guard case .failed(let failedScan) = result else {
            Issue.record("expected failed scanner evidence, got \(result)")
            return
        }
        #expect(failedScan.reason == .invalidMaximumDepth(-1))
    }

    private struct StubGitRepositoryDiscoveryProvider: RepoScanner.GitRepositoryDiscoveryProvider {
        let outcomesByCanonicalPath: [String: GitRepositoryDiscoveryOutcome]

        func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome {
            outcomesByCanonicalPath[canonicalPath(url)]
                ?? .authoritativeNegative(.notAValidWorktree)
        }
    }

    private func finish(
        session: RepoScannerSessionPort,
        outcomesByCanonicalPath: [String: GitRepositoryDiscoveryOutcome]
    ) async -> RepoScannerResult {
        while true {
            switch await session.advanceOneQuantum() {
            case .suspended:
                continue
            case .validationRequired(let request):
                let outcome =
                    outcomesByCanonicalPath[canonicalPath(request.candidateURL)]
                    ?? .authoritativeNegative(.notAValidWorktree)
                #expect(
                    session.consumeValidationCompletion(
                        .init(
                            request: request,
                            outcome: outcome,
                            validationServiceDuration: .zero
                        )
                    ) == .consumed
                )
            case .finished(let result):
                return result
            }
        }
    }

    private struct ScanFixture {
        let root: URL
        let candidatePaths: [URL]

        init(candidateNames: [String]) throws {
            let fixtureRoot = FileManager.default.temporaryDirectory
                .appending(path: "repo-scanner-outcomes-\(UUID().uuidString)")
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
}

private func canonicalPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
}
