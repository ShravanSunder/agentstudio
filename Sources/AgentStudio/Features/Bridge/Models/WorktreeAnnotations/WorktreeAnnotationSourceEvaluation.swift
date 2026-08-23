import Foundation

struct WorktreeAnnotationCurrentSourceFile: Equatable, Sendable {
    let path: String
    let sourceRole: WorktreeAnnotationSourceRole
    let sourceIdentity: String
    let body: String
}

enum WorktreeAnnotationSourceMaterial: Equatable, Sendable {
    case available([WorktreeAnnotationCurrentSourceFile])
    case unavailable
}

struct WorktreeAnnotationThreadPlacementProjection: Equatable, Sendable {
    let placement: WorktreeAnnotationPlacement
    let currentPath: String?
    let currentStartLine: Int?
    let currentEndLine: Int?
    let currentSourceIdentity: String?
}

struct WorktreeAnnotationSourceEvaluationInput: Sendable {
    let session: WorktreeAnnotationSession
    let threads: [WorktreeAnnotationThread]
    let surface: BridgeProductSurface
    let sourceEpoch: String
    let currentFingerprint: WorktreeAnnotationSourceFingerprint
    let material: WorktreeAnnotationSourceMaterial
}

struct WorktreeAnnotationSourceEvaluationResult: Equatable, Sendable {
    let sourceEpoch: String
    let sourceRelationship: WorktreeAnnotationSourceRelationship
    let acceptedSourceFingerprint: WorktreeAnnotationSourceFingerprint?
    let placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
}

enum WorktreeAnnotationSourceEvaluationError: Error, Equatable, Sendable {
    case invalidSourceEpoch
}

enum WorktreeAnnotationSourceEvaluator {
    static func evaluate(
        _ input: WorktreeAnnotationSourceEvaluationInput
    ) throws -> WorktreeAnnotationSourceEvaluationResult {
        guard !input.sourceEpoch.isEmpty else {
            throw WorktreeAnnotationSourceEvaluationError.invalidSourceEpoch
        }
        let relationship = sourceRelationship(for: input)
        guard relationship == .applicable else {
            return WorktreeAnnotationSourceEvaluationResult(
                sourceEpoch: input.sourceEpoch,
                sourceRelationship: relationship,
                acceptedSourceFingerprint: nil,
                placements: [:]
            )
        }
        return WorktreeAnnotationSourceEvaluationResult(
            sourceEpoch: input.sourceEpoch,
            sourceRelationship: .applicable,
            acceptedSourceFingerprint: mergedFingerprint(for: input),
            placements: Dictionary(
                uniqueKeysWithValues: input.threads.map { thread in
                    (
                        thread.id,
                        placement(
                            for: thread.origin,
                            surface: input.surface,
                            material: input.material
                        )
                    )
                }
            )
        )
    }

    private static func mergedFingerprint(
        for input: WorktreeAnnotationSourceEvaluationInput
    ) -> WorktreeAnnotationSourceFingerprint {
        let accepted = input.session.acceptedSourceFingerprint
        let current = input.currentFingerprint
        return switch input.surface {
        case .file:
            WorktreeAnnotationSourceFingerprint(
                repositoryID: current.repositoryID,
                worktreeID: current.worktreeID,
                fileSourceIdentity: current.fileSourceIdentity,
                reviewComparisonOrigin: accepted.reviewComparisonOrigin
            )
        case .review:
            WorktreeAnnotationSourceFingerprint(
                repositoryID: current.repositoryID,
                worktreeID: current.worktreeID,
                fileSourceIdentity: accepted.fileSourceIdentity,
                reviewComparisonOrigin: current.reviewComparisonOrigin
            )
        }
    }

    private static func sourceRelationship(
        for input: WorktreeAnnotationSourceEvaluationInput
    ) -> WorktreeAnnotationSourceRelationship {
        let accepted = input.session.acceptedSourceFingerprint
        let current = input.currentFingerprint
        guard accepted.repositoryID == current.repositoryID,
            accepted.worktreeID == current.worktreeID
        else {
            return .detached
        }
        switch input.surface {
        case .file:
            return current.fileSourceIdentity == nil ? .uncertain : .applicable
        case .review:
            return current.reviewComparisonOrigin == nil ? .uncertain : .applicable
        }
    }

    private static func placement(
        for origin: WorktreeAnnotationThreadOrigin,
        surface: BridgeProductSurface,
        material: WorktreeAnnotationSourceMaterial
    ) -> WorktreeAnnotationThreadPlacementProjection {
        switch origin {
        case .session:
            return projection(placement: .exact)
        case .wholeFile(let originalPath, let sourceRole):
            guard case .available(let files) = material else {
                return projection(placement: .unavailable)
            }
            guard
                let currentFile = files.first(where: {
                    $0.path == originalPath && $0.sourceRole == sourceRole
                })
            else {
                return projection(placement: .outdated)
            }
            return projection(
                placement: .exact,
                currentPath: currentFile.path,
                currentSourceIdentity: currentFile.sourceIdentity
            )
        case .located(let locatedOrigin):
            return locatedPlacement(for: locatedOrigin, surface: surface, material: material)
        }
    }

    private static func locatedPlacement(
        for origin: WorktreeAnnotationLocatedOrigin,
        surface: BridgeProductSurface,
        material: WorktreeAnnotationSourceMaterial
    ) -> WorktreeAnnotationThreadPlacementProjection {
        guard case .available(let files) = material else {
            return projection(placement: .unavailable)
        }
        let roleFiles = files.filter {
            currentSourceRoleIsCompatible($0.sourceRole, with: origin.sourceRole, on: surface)
        }
        if let exactFile = roleFiles.first(where: { $0.path == origin.repositoryRelativePath }),
            excerpt(
                in: sourceLines(exactFile.body),
                startLine: origin.startLine,
                endLine: origin.endLine
            ) == origin.selectedExcerpt
        {
            return projection(
                placement: .exact,
                currentPath: exactFile.path,
                currentStartLine: origin.startLine,
                currentEndLine: origin.endLine,
                currentSourceIdentity: exactFile.sourceIdentity
            )
        }
        let matches = roleFiles.flatMap { file in
            contextMatches(origin: origin, file: file)
        }
        guard matches.count == 1, let match = matches.first else {
            return projection(placement: .outdated)
        }
        return projection(
            placement: .relocated,
            currentPath: match.file.path,
            currentStartLine: match.startLine,
            currentEndLine: match.endLine,
            currentSourceIdentity: match.file.sourceIdentity
        )
    }

    private static func currentSourceRoleIsCompatible(
        _ currentSourceRole: WorktreeAnnotationSourceRole,
        with originSourceRole: WorktreeAnnotationSourceRole,
        on surface: BridgeProductSurface
    ) -> Bool {
        switch surface {
        case .file:
            return currentSourceRole == .file
                && (originSourceRole == .file || originSourceRole == .reviewHead)
        case .review:
            return currentSourceRole == originSourceRole
        }
    }

    private struct ContextMatch {
        let file: WorktreeAnnotationCurrentSourceFile
        let startLine: Int
        let endLine: Int
    }

    private static func contextMatches(
        origin: WorktreeAnnotationLocatedOrigin,
        file: WorktreeAnnotationCurrentSourceFile
    ) -> [ContextMatch] {
        let lines = sourceLines(file.body)
        let excerptLines = sourceLines(origin.selectedExcerpt)
        guard !excerptLines.isEmpty, excerptLines.count <= lines.count else { return [] }
        return (0...(lines.count - excerptLines.count)).compactMap { startIndex in
            let endIndex = startIndex + excerptLines.count - 1
            guard Array(lines[startIndex...endIndex]) == excerptLines else { return nil }
            if let contextBefore = origin.contextBefore {
                guard startIndex > 0, lines[startIndex - 1] == contextBefore else { return nil }
            }
            if let contextAfter = origin.contextAfter {
                guard endIndex + 1 < lines.count, lines[endIndex + 1] == contextAfter else { return nil }
            }
            return ContextMatch(
                file: file,
                startLine: startIndex + 1,
                endLine: endIndex + 1
            )
        }
    }

    private static func sourceLines(_ source: String) -> [String] {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if source.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private static func excerpt(
        in lines: [String],
        startLine: Int,
        endLine: Int
    ) -> String? {
        guard startLine > 0, endLine >= startLine, endLine <= lines.count else { return nil }
        return lines[(startLine - 1)...(endLine - 1)].joined(separator: "\n")
    }

    private static func projection(
        placement: WorktreeAnnotationPlacement,
        currentPath: String? = nil,
        currentStartLine: Int? = nil,
        currentEndLine: Int? = nil,
        currentSourceIdentity: String? = nil
    ) -> WorktreeAnnotationThreadPlacementProjection {
        WorktreeAnnotationThreadPlacementProjection(
            placement: placement,
            currentPath: currentPath,
            currentStartLine: currentStartLine,
            currentEndLine: currentEndLine,
            currentSourceIdentity: currentSourceIdentity
        )
    }
}
