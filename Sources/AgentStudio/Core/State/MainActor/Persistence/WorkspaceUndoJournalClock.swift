import Darwin
import Foundation

/// Boot identity and sleep-inclusive uptime are the deadline authority; UTC is diagnostic context.
package enum WorkspaceUndoJournalClock {
    @concurrent nonisolated package static func current() async throws -> WorkspaceUndoJournalTime {
        var bootBytes = [CChar](repeating: 0, count: MemoryLayout<uuid_string_t>.size)
        var byteCount = bootBytes.count
        let result = bootBytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &byteCount, nil, 0)
        }
        guard result == 0, byteCount > 1, byteCount <= bootBytes.count, bootBytes[byteCount - 1] == 0 else {
            throw WorkspaceUndoJournalFailure.invalidClock
        }
        guard
            let bootID = String(bytes: bootBytes.prefix(byteCount - 1).map { UInt8(bitPattern: $0) }, encoding: .utf8),
            UUID(uuidString: bootID) != nil
        else { throw WorkspaceUndoJournalFailure.invalidClock }
        var timebase = mach_timebase_info_data_t(numer: 0, denom: 0)
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else { throw WorkspaceUndoJournalFailure.invalidClock }
        let uptime = try nanoseconds(
            ticks: mach_continuous_time(), numerator: timebase.numer, denominator: timebase.denom)
        return .init(utc: Date(), bootID: bootID, uptimeNanoseconds: uptime)
    }

    static func nanoseconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) throws -> Int64 {
        guard numerator > 0, denominator > 0 else { throw WorkspaceUndoJournalFailure.invalidClock }
        let (scaledTicks, overflow) = ticks.multipliedReportingOverflow(by: UInt64(numerator))
        guard !overflow, let nanoseconds = Int64(exactly: scaledTicks / UInt64(denominator)) else {
            throw WorkspaceUndoJournalFailure.invalidClock
        }
        return nanoseconds
    }
}
