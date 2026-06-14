import Foundation

struct BridgeChangeCollationRequest: Equatable, Sendable {
    let descriptors: [BridgeReviewItemDescriptor]
    let pathScope: [String]
    let filter: BridgeViewFilter
    let grouping: BridgeChangeGrouping
    let checkpointIds: [String]
    let createdAtUnixMilliseconds: Int64
}

enum BridgeChangeCollator {
    static func collate(_ request: BridgeChangeCollationRequest) -> [BridgeReviewGroup] {
        let visibleDescriptors = visibleDescriptors(
            from: request.descriptors,
            pathScope: request.pathScope,
            filter: request.filter
        )
        let hiddenDescriptors = request.descriptors.filter {
            !isVisible($0, pathScope: request.pathScope, filter: request.filter)
        }

        return [
            BridgeReviewGroup(
                groupId: "group-\(request.grouping.kind.rawValue)",
                grouping: request.grouping,
                label: request.grouping.label ?? request.grouping.kind.rawValue,
                orderedItemIds: visibleDescriptors.map(\.itemId),
                summary: BridgeReviewGroupSummary(
                    filesChanged: visibleDescriptors.count,
                    additions: visibleDescriptors.reduce(0) { $0 + $1.additions },
                    deletions: visibleDescriptors.reduce(0) { $0 + $1.deletions }
                ),
                hiddenSummary: BridgeHiddenSummary(
                    hiddenFileCount: hiddenDescriptors.count,
                    hiddenAdditions: hiddenDescriptors.reduce(0) { $0 + $1.additions },
                    hiddenDeletions: hiddenDescriptors.reduce(0) { $0 + $1.deletions },
                    hiddenFileClasses: Array(Set(hiddenDescriptors.map(\.fileClass))).sorted {
                        $0.rawValue < $1.rawValue
                    }
                )
            )
        ]
    }

    static func visibleDescriptors(
        from descriptors: [BridgeReviewItemDescriptor],
        pathScope: [String] = [],
        filter: BridgeViewFilter
    ) -> [BridgeReviewItemDescriptor] {
        descriptors.filter { descriptor in
            isVisible(descriptor, pathScope: pathScope, filter: filter)
        }
    }

    static func summary(
        for descriptors: [BridgeReviewItemDescriptor],
        visibleDescriptors: [BridgeReviewItemDescriptor]
    ) -> BridgeReviewPackageSummary {
        BridgeReviewPackageSummary(
            filesChanged: descriptors.count,
            additions: descriptors.reduce(0) { $0 + $1.additions },
            deletions: descriptors.reduce(0) { $0 + $1.deletions },
            visibleFileCount: visibleDescriptors.count,
            hiddenFileCount: descriptors.count - visibleDescriptors.count
        )
    }

    private static func isVisible(
        _ descriptor: BridgeReviewItemDescriptor,
        pathScope: [String],
        filter: BridgeViewFilter
    ) -> Bool {
        let reviewPath = descriptor.headPath ?? descriptor.basePath ?? ""
        if !pathScope.isEmpty, !pathMatchesAnyGlob(reviewPath, globs: pathScope) {
            return false
        }
        if !filter.includedPathGlobs.isEmpty,
            !pathMatchesAnyGlob(reviewPath, globs: filter.includedPathGlobs)
        {
            return false
        }
        if pathMatchesAnyGlob(reviewPath, globs: filter.excludedPathGlobs) {
            return false
        }
        if !filter.includedFileClasses.isEmpty,
            !filter.includedFileClasses.contains(descriptor.fileClass)
        {
            return false
        }
        if filter.excludedFileClasses.contains(descriptor.fileClass) {
            return false
        }
        if !filter.includedExtensions.isEmpty {
            guard let ext = descriptor.extension, filter.includedExtensions.contains(ext) else {
                return false
            }
        }
        if let ext = descriptor.extension, filter.excludedExtensions.contains(ext) {
            return false
        }
        if !filter.changeKinds.isEmpty,
            !filter.changeKinds.contains(descriptor.changeKind)
        {
            return false
        }
        if !filter.reviewStates.isEmpty,
            !filter.reviewStates.contains(descriptor.reviewState)
        {
            return false
        }
        if descriptor.fileClass == .binary, !filter.showBinaryFiles {
            return false
        }
        if descriptor.fileClass == .large, !filter.showLargeFiles {
            return false
        }
        if descriptor.isHiddenByDefault, !filter.showHiddenFiles {
            return false
        }
        return true
    }

    private static func pathMatchesAnyGlob(_ path: String, globs: [String]) -> Bool {
        globs.contains { glob in
            path.range(
                of: regexPattern(for: glob),
                options: [.regularExpression]
            ) != nil
        }
    }

    private static func regexPattern(for glob: String) -> String {
        var pattern = "^"
        var index = glob.startIndex

        while index < glob.endIndex {
            let character = glob[index]
            if character == "*" {
                let nextIndex = glob.index(after: index)
                if nextIndex < glob.endIndex, glob[nextIndex] == "*" {
                    pattern += ".*"
                    index = glob.index(after: nextIndex)
                } else {
                    pattern += #"[^/]*"#
                    index = nextIndex
                }
            } else if character == "?" {
                pattern += #"[^/]"#
                index = glob.index(after: index)
            } else {
                pattern += NSRegularExpression.escapedPattern(for: String(character))
                index = glob.index(after: index)
            }
        }

        pattern += "$"
        return pattern
    }
}
