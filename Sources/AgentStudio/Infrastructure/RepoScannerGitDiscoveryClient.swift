import AgentStudioGit
import Foundation

/// Capability adapter from the package's discovery-only read contract into scanner evidence.
/// It intentionally cannot retain status, remote, writer-registry, or mutation capabilities.
struct RepoScannerGitDiscoveryClient: RepoScanner.GitRepositoryDiscoveryProvider,
    RepoDiscoveryReadClient
{
    /// Retained only as the operation-class policy source; this adapter owns no deadline.
    static let defaultTimeout: Duration = AppPolicies.GitRefresh.defaultDiscoveryReadTimeout

    private let discoveryReadClient: any AgentStudioGitDiscoveryReadClient

    init(
        discoveryReadClient: any AgentStudioGitDiscoveryReadClient =
            LibGit2AgentStudioGitDiscoveryReadClient()
    ) {
        self.discoveryReadClient = discoveryReadClient
    }

    func discoveryOutcome(for url: URL) async -> GitRepositoryDiscoveryOutcome {
        let outcome = await discoveryReadClient.readDiscoveryCandidate(
            GitDiscoveryReadRequest(candidatePath: url)
        )
        switch outcome {
        case .validated(let evidence):
            return Self.validatedOutcome(scannedPath: url, evidence: evidence)
        case .notRepository(.exactCandidateIsNotRepository):
            return .authoritativeNegative(.exactCandidateIsNotRepository)
        case .notRepository(.invalidRepository):
            return .authoritativeNegative(.invalidRepository)
        case .notRepository(.invalidWorktreeRegistration):
            return .authoritativeNegative(.invalidWorktreeRegistration)
        case .notRepository(.bareRepository):
            return .authoritativeNegative(.bareRepository)
        case .failed(let failure):
            return .failure(
                .serviceFailed(
                    detail:
                        "libgit2 code=\(failure.code) class=\(failure.errorClass): \(failure.message)"
                )
            )
        }
    }

    func validateDiscoveryCandidate(at candidateURL: URL) async -> GitRepositoryDiscoveryOutcome {
        await discoveryOutcome(for: candidateURL)
    }
}

extension RepoScannerGitDiscoveryClient {
    private static func validatedOutcome(
        scannedPath: URL,
        evidence: GitDiscoveryReadEvidence
    ) -> GitRepositoryDiscoveryOutcome {
        let scannedCanonicalPath = canonicalPath(scannedPath)
        guard samePath(evidence.canonicalCandidatePath, scannedCanonicalPath),
            samePath(evidence.canonicalWorktreePath, scannedCanonicalPath)
        else {
            return .authoritativeNegative(.canonicalPathMismatch)
        }
        guard !isSubmoduleGitDirectory(evidence.canonicalGitDirectory) else {
            return .authoritativeNegative(.submoduleWorktree)
        }

        let repositoryKey = evidence.repositoryIdentity.id.rawValue
        switch evidence.registration {
        case .main:
            if let mainWorktreePath = evidence.repositoryIdentity.mainWorktreePath,
                !samePath(mainWorktreePath, scannedCanonicalPath)
            {
                return .authoritativeNegative(.mainWorktreeMismatch)
            }
            return .validated(
                RepoScanner.ResolvedGitEntry(
                    path: canonicalPath(evidence.canonicalWorktreePath),
                    kind: .cloneRoot,
                    repositoryKey: repositoryKey
                )
            )
        case .linked:
            let parentClonePath =
                evidence.repositoryIdentity.mainWorktreePath
                ?? fallbackParentClonePath(repositoryID: evidence.repositoryIdentity.id)
                ?? evidence.canonicalCommonDirectory
            return .validated(
                RepoScanner.ResolvedGitEntry(
                    path: canonicalPath(evidence.canonicalWorktreePath),
                    kind: .linkedWorktree(parentClonePath: canonicalPath(parentClonePath)),
                    repositoryKey: repositoryKey
                )
            )
        }
    }

    private static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        canonicalPath(lhs).path == canonicalPath(rhs).path
    }

    private static func canonicalPath(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isSubmoduleGitDirectory(_ gitDirectory: URL) -> Bool {
        canonicalPath(gitDirectory).path.contains("/.git/modules/")
    }

    private static func fallbackParentClonePath(repositoryID: GitRepositoryID) -> URL? {
        let commonPrefix = "common:"
        guard repositoryID.rawValue.hasPrefix(commonPrefix) else { return nil }
        let commonPath = String(repositoryID.rawValue.dropFirst(commonPrefix.count))
        guard !commonPath.isEmpty else { return nil }
        return URL(fileURLWithPath: commonPath)
    }
}

extension RepoScanner {
    typealias AgentStudioGitRepositoryDiscoveryProvider = RepoScannerGitDiscoveryClient
}
