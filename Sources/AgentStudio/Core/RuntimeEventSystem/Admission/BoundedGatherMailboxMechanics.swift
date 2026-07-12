import Foundation

extension BoundedGatherMailbox {
    static func isConfigurationValid(
        declaredKeyCount: Int,
        limits: GatherMailboxLimits
    ) -> Bool {
        let normalizedLimits = normalized(limits)
        guard declaredKeyCount >= 0,
            declaredKeyCount <= normalizedLimits.maximumDeclaredKeys,
            normalizedLimits.cleanupQuantum.isValid,
            let maximumCleanupBytes = normalizedLimits.cleanupQuantum.maximumBytes
        else {
            return false
        }
        let canRetainContribution =
            normalizedLimits.maximumRetainedContributions > 0
            && normalizedLimits.maximumRetainedContributionsPerKey > 0
            && normalizedLimits.maximumContributionsPerLease > 0
        guard canRetainContribution else { return true }
        let largestAdmissibleEntryBytes = min(
            normalizedLimits.maximumRetainedBytes,
            normalizedLimits.maximumRetainedBytesPerKey,
            normalizedLimits.maximumBytesPerLease
        )
        return maximumCleanupBytes >= largestAdmissibleEntryBytes
    }

    static func normalized(_ limits: GatherMailboxLimits) -> GatherMailboxLimits {
        GatherMailboxLimits(
            maximumDeclaredKeys: max(0, limits.maximumDeclaredKeys),
            maximumRetainedContributions: max(0, limits.maximumRetainedContributions),
            maximumRetainedItems: max(0, limits.maximumRetainedItems),
            maximumRetainedBytes: max(0, limits.maximumRetainedBytes),
            maximumRetainedContributionsPerKey: max(0, limits.maximumRetainedContributionsPerKey),
            maximumRetainedItemsPerKey: max(0, limits.maximumRetainedItemsPerKey),
            maximumRetainedBytesPerKey: max(0, limits.maximumRetainedBytesPerKey),
            maximumContributionsPerLease: max(0, limits.maximumContributionsPerLease),
            maximumItemsPerLease: max(0, limits.maximumItemsPerLease),
            maximumBytesPerLease: max(0, limits.maximumBytesPerLease),
            cleanupQuantum: limits.cleanupQuantum
        )
    }

    static func isValid(_ footprint: GatherFootprint) -> Bool {
        footprint.itemCount >= 0 && footprint.byteCount >= 0
    }

    static func checkedSum(_ values: Int...) -> Int? {
        values.reduce(0) { partial, value in
            guard let partial else { return nil }
            let result = partial.addingReportingOverflow(value)
            return result.overflow ? nil : result.partialValue
        }
    }

    static func addChecked(_ increment: Int, to value: inout Int) {
        let result = value.addingReportingOverflow(increment)
        precondition(result.overflow == false, "Gather mailbox counter overflow")
        value = result.partialValue
    }

    static func minimum(_ first: Duration?, _ second: Duration?) -> Duration? {
        switch (first, second) {
        case (.some(let first), .some(let second)): min(first, second)
        case (.some(let first), .none): first
        case (.none, .some(let second)): second
        case (.none, .none): nil
        }
    }
}
