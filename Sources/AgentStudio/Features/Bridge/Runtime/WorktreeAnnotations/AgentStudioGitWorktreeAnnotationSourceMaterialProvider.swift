import AgentStudioGit
import AgentStudioInfrastructure
import CryptoKit
import Foundation

enum WorktreeAnnotationSourceMaterialIdentity: Equatable, Sendable {
    case provided(String)
    case currentFileDescriptor
}

struct WorktreeAnnotationSourceMaterialCandidate: Sendable {
    let path: String
    let sourceRole: WorktreeAnnotationSourceRole
    let sourceIdentity: WorktreeAnnotationSourceMaterialIdentity
    let target: GitDiffTarget
}

struct WorktreeAnnotationSourceMaterialRequest: Sendable {
    let repositoryPath: URL
    let candidates: [WorktreeAnnotationSourceMaterialCandidate]
}

struct GitWorktreeAnnotationSourceMaterialProvider<LocalClient: AgentStudioGitLocalClient>:
    Sendable
{
    private let client: LocalClient
    private let maximumCandidateCount: Int
    private let maximumFileByteCount: Int

    init(
        client: LocalClient,
        maximumCandidateCount: Int = AppPolicies.Bridge.worktreeAnnotationMaximumSourceCandidateCount,
        maximumFileByteCount: Int = AppPolicies.Bridge.worktreeAnnotationMaximumSourceFileByteCount
    ) {
        precondition(maximumCandidateCount > 0)
        precondition(maximumFileByteCount > 0)
        self.client = client
        self.maximumCandidateCount = maximumCandidateCount
        self.maximumFileByteCount = maximumFileByteCount
    }

    func material(
        _ request: WorktreeAnnotationSourceMaterialRequest
    ) async -> WorktreeAnnotationSourceMaterial {
        guard !request.candidates.isEmpty,
            request.candidates.count <= maximumCandidateCount,
            !containsDuplicateCandidate(request.candidates)
        else {
            return .unavailable
        }

        var files: [WorktreeAnnotationCurrentSourceFile] = []
        var hadReadFailure = false
        files.reserveCapacity(request.candidates.count)
        for candidate in request.candidates {
            if let file = await readSourceFile(candidate, repositoryPath: request.repositoryPath) {
                files.append(file)
            } else {
                hadReadFailure = true
            }
        }
        guard !files.isEmpty else { return .unavailable }
        return hadReadFailure ? .availableWithReadFailures(files) : .available(files)
    }

    private func readSourceFile(
        _ candidate: WorktreeAnnotationSourceMaterialCandidate,
        repositoryPath: URL
    ) async -> WorktreeAnnotationCurrentSourceFile? {
        guard !candidate.path.isEmpty else { return nil }
        let payload: GitContentPayload
        do {
            payload = try await client.content(
                GitContentRequest(
                    repositoryPath: repositoryPath,
                    target: candidate.target,
                    path: candidate.path,
                    maxSizeBytes: Int64(maximumFileByteCount)
                )
            )
        } catch {
            return nil
        }
        guard !payload.isBinary,
            payload.data.count <= maximumFileByteCount,
            let body = String(data: payload.data, encoding: .utf8)
        else { return nil }
        let sourceIdentity: String
        switch candidate.sourceIdentity {
        case .provided(let providedIdentity):
            guard !providedIdentity.isEmpty else { return nil }
            sourceIdentity = providedIdentity
        case .currentFileDescriptor:
            guard candidate.target == .workingTree else { return nil }
            let sourceSHA256 = SHA256.hash(data: payload.data)
                .map { String(format: "%02x", $0) }
                .joined()
            sourceIdentity = BridgePaneProductFileContentSource.stableDescriptorId(
                relativePath: candidate.path,
                sourceSHA256: sourceSHA256
            )
        }
        return WorktreeAnnotationCurrentSourceFile(
            path: candidate.path,
            sourceRole: candidate.sourceRole,
            sourceIdentity: sourceIdentity,
            body: body
        )
    }

    private func containsDuplicateCandidate(
        _ candidates: [WorktreeAnnotationSourceMaterialCandidate]
    ) -> Bool {
        for index in candidates.indices {
            for comparisonIndex in candidates.indices where comparisonIndex > index {
                let candidate = candidates[index]
                let comparison = candidates[comparisonIndex]
                if candidate.path == comparison.path,
                    candidate.sourceRole == comparison.sourceRole,
                    candidate.sourceIdentity == comparison.sourceIdentity,
                    candidate.target == comparison.target
                {
                    return true
                }
            }
        }
        return false
    }
}
