import Foundation

extension WorktreeAnnotationStore {
    func fetchOutputCandidates(
        sessionID: WorktreeAnnotationSessionID,
        expectedSessionRevision: Int,
        cursor: WorktreeAnnotationOutputCandidateCursor?,
        limit: Int,
        contextID: String,
        surface: BridgeProductSurface
    ) async throws -> WorktreeAnnotationOutputCandidatePage {
        try requireAvailableForReads()
        let repositoryPage = try await repositoryAccess.fetchOutputCandidates(
            sessionID: sessionID,
            expectedSessionRevision: expectedSessionRevision,
            cursor: cursor,
            limit: limit
        )
        let detail = try await repositoryAccess.fetchSessionDetail(sessionID: sessionID)
        guard detail.session.semanticRevision == repositoryPage.sessionRevision else {
            throw WorktreeAnnotationRepositoryError.conflict(
                currentRevision: detail.session.semanticRevision
            )
        }
        let placements = projection.placements(
            contextID: contextID,
            surface: surface,
            sessionID: sessionID
        )
        let eligibleWithoutInlinePlacementCount = detail.threads.reduce(into: 0) { count, thread in
            let eligibleCount = thread.messages.filter(Self.isOutputEligible).count
            guard eligibleCount > 0 else { return }
            let placement = placements[thread.thread.id]
            if placement?.placement != .exact && placement?.placement != .relocated {
                count += eligibleCount
            }
        }
        let candidates = repositoryPage.candidates.map { candidate in
            let currentPlacement = placements[candidate.threadID]
            let hasCurrentLocation =
                (currentPlacement?.placement == .exact || currentPlacement?.placement == .relocated)
                && currentPlacement?.currentPath != nil
                && currentPlacement?.currentStartLine != nil
                && currentPlacement?.currentEndLine != nil
            return WorktreeAnnotationOutputCandidate(
                messageID: candidate.messageID,
                threadID: candidate.threadID,
                flatOrdinal: candidate.flatOrdinal,
                path: hasCurrentLocation
                    ? currentPlacement?.currentPath ?? candidate.originalPath : candidate.originalPath,
                startLine: hasCurrentLocation
                    ? currentPlacement?.currentStartLine ?? candidate.originalStartLine
                    : candidate.originalStartLine,
                endLine: hasCurrentLocation
                    ? currentPlacement?.currentEndLine ?? candidate.originalEndLine
                    : candidate.originalEndLine,
                location: hasCurrentLocation ? .current : .original,
                placement: currentPlacement?.placement ?? .unavailable,
                authoredAt: candidate.authoredAt,
                state: .eligible,
                excerpt: Self.outputCandidatePlainTextExcerpt(candidate.savedBodyPrefix)
            )
        }
        return WorktreeAnnotationOutputCandidatePage(
            sessionID: sessionID,
            sessionRevision: repositoryPage.sessionRevision,
            candidates: candidates,
            nextCursor: repositoryPage.nextCursor,
            eligibleMessageCount: repositoryPage.eligibleMessageCount,
            eligibleWithoutInlinePlacementCount: eligibleWithoutInlinePlacementCount
        )
    }

    private static func isOutputEligible(_ message: WorktreeAnnotationMessage) -> Bool {
        message.status == .editable
            && message.savedBody != nil
            && message.savedRevision != nil
            && message.draft == nil
    }

    private static func outputCandidatePlainTextExcerpt(_ markdownPrefix: String) -> String {
        let markdownPunctuation = CharacterSet(charactersIn: "#*_`>|[]()~-+")
        let normalizedWords =
            markdownPrefix
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: markdownPunctuation) }
            .filter { !$0.isEmpty }
        var excerpt = ""
        for character in normalizedWords.joined(separator: " ") {
            let candidate = excerpt + String(character)
            guard candidate.utf8.count <= 240 else { break }
            excerpt = candidate
        }
        return excerpt
    }
}
