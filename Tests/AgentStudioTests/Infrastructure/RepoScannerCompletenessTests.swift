import Foundation
import Testing

@testable import AgentStudio

@Suite("RepoScanner completeness")
struct RepoScannerCompletenessTests {
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
