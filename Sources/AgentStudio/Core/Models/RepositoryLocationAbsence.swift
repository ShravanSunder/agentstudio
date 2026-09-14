import AgentStudioInfrastructure
import Foundation

/// Durable absence knowledge. A legacy unavailable marker has no invented age.
package enum RepositoryLocationAbsence: Equatable, Codable, Sendable {
    case unconfirmed
    case confirmed(RepositoryAbsenceTiming)
}

package struct RepositoryAbsenceTiming: Equatable, Codable, Sendable {
    package let firstAbsentAt: Date
    package let anchorUTC: Date
    package let anchorBootID: String
    package let anchorUptimeNanoseconds: Int64
    package let elapsedBeforeAnchor: TimeInterval
}

/// Captured off MainActor; policy evaluation never reads the system clock.
package struct RepositoryRetentionTime: Equatable, Sendable {
    package let utc: Date
    package let bootID: String
    package let uptimeNanoseconds: Int64

    @concurrent nonisolated package static func current() async throws -> Self {
        let time = try await WorkspaceUndoJournalClock.current()
        return Self(utc: time.utc, bootID: time.bootID, uptimeNanoseconds: time.uptimeNanoseconds)
    }

    package init(utc: Date, bootID: String, uptimeNanoseconds: Int64) {
        // SQLite stores Unix-epoch doubles; normalize once so exact commit preconditions survive that round trip.
        self.utc = Date(timeIntervalSince1970: utc.timeIntervalSince1970)
        self.bootID = bootID
        self.uptimeNanoseconds = uptimeNanoseconds
    }
}

package enum RepositoryRetentionPolicy {
    package static let retentionSeconds: TimeInterval = AppPolicies.RepositoryRetention.durationSeconds

    package static func confirmedAbsence(
        retaining existing: RepositoryLocationAbsence?,
        at time: RepositoryRetentionTime
    ) -> RepositoryLocationAbsence? {
        guard valid(time) else { return nil }
        if case .confirmed(let timing) = existing {
            guard timing.anchorBootID != time.bootID else { return existing }
            guard let existing, let elapsed = elapsedSeconds(for: existing, at: time) else { return existing }
            return .confirmed(
                RepositoryAbsenceTiming(
                    firstAbsentAt: timing.firstAbsentAt, anchorUTC: time.utc, anchorBootID: time.bootID,
                    anchorUptimeNanoseconds: time.uptimeNanoseconds, elapsedBeforeAnchor: elapsed
                ))
        }
        return .confirmed(
            RepositoryAbsenceTiming(
                firstAbsentAt: time.utc,
                anchorUTC: time.utc,
                anchorBootID: time.bootID,
                anchorUptimeNanoseconds: time.uptimeNanoseconds,
                elapsedBeforeAnchor: 0
            )
        )
    }

    package static func elapsedSeconds(
        for absence: RepositoryLocationAbsence,
        at time: RepositoryRetentionTime
    ) -> TimeInterval? {
        guard valid(time), case .confirmed(let timing) = absence,
            timing.elapsedBeforeAnchor.isFinite, timing.elapsedBeforeAnchor >= 0,
            timing.anchorUTC.timeIntervalSince1970.isFinite, !timing.anchorBootID.isEmpty,
            timing.anchorUptimeNanoseconds >= 0
        else { return nil }
        let elapsed: TimeInterval
        if timing.anchorBootID == time.bootID {
            guard time.uptimeNanoseconds >= timing.anchorUptimeNanoseconds else { return nil }
            elapsed = Double(time.uptimeNanoseconds - timing.anchorUptimeNanoseconds) / 1_000_000_000
        } else {
            elapsed = time.utc.timeIntervalSince(timing.anchorUTC)
            guard elapsed.isFinite, elapsed >= 0 else { return nil }
        }
        let total = timing.elapsedBeforeAnchor + elapsed
        return total.isFinite ? total : nil
    }

    package static func isDue(
        _ absence: RepositoryLocationAbsence,
        at time: RepositoryRetentionTime
    ) -> Bool {
        guard let elapsed = elapsedSeconds(for: absence, at: time) else { return false }
        return elapsed >= retentionSeconds
    }

    private static func valid(_ time: RepositoryRetentionTime) -> Bool {
        !time.bootID.isEmpty && time.uptimeNanoseconds >= 0 && time.utc.timeIntervalSince1970.isFinite
    }
}
