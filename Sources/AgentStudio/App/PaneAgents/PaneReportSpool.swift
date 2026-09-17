import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Admits the notifications a pane CLI appended while the app was unreachable.
/// One owner-only file per pane is read under the writer's own lock, every line
/// is submitted as late evidence through the IPC sessions admission, and the
/// file is truncated only once nothing is left to retry.
actor PaneReportSpool {
    /// Counts only. No line text, explanation or message ever reaches a log or
    /// telemetry sink from this type.
    struct DrainReport: Equatable, Sendable {
        var admittedLineCount = 0
        var rejectedLineCount = 0
        var malformedLineCount = 0
        var truncatedFileCount = 0
        var retainedFileCount = 0

        var hasWork: Bool {
            admittedLineCount > 0 || rejectedLineCount > 0 || malformedLineCount > 0
                || retainedFileCount > 0
        }

        static func += (lhs: inout Self, rhs: Self) {
            lhs.admittedLineCount += rhs.admittedLineCount
            lhs.rejectedLineCount += rhs.rejectedLineCount
            lhs.malformedLineCount += rhs.malformedLineCount
            lhs.truncatedFileCount += rhs.truncatedFileCount
            lhs.retainedFileCount += rhs.retainedFileCount
        }
    }

    private enum LineOutcome: Equatable, Sendable {
        case admitted
        case rejected
        case malformed
        case retryable
    }

    private static let fileSuffix = ".notifications.ndjson"
    private static let reportMethodName = "session.report"
    private static let messageMethodName = "session.message"
    private static let selfHandle = "self"

    private let admission: any AppIPCSessionsPort
    private let descriptorsByMethodName: [String: IPCAnyMethodDescriptor]
    private let maximumLineBytes: Int

    init(
        admission: any AppIPCSessionsPort,
        maximumLineBytes: Int = AppPolicies.IPC.spoolDrainMaximumLineBytes
    ) throws {
        self.admission = admission
        self.maximumLineBytes = maximumLineBytes
        descriptorsByMethodName = Dictionary(
            uniqueKeysWithValues: try IPCBuiltInMethodCatalog.offlineNotificationDescriptors(
                examples: .init(illustrativeIdentifier: UUIDv7.generate())
            ).map { ($0.metadata.name, $0) }
        )
    }

    func drain(spoolDirectory: URL) async -> DrainReport {
        var report = DrainReport()
        guard
            let fileNames = try? FileManager.default.contentsOfDirectory(atPath: spoolDirectory.path)
        else {
            return report
        }
        for fileName in fileNames.sorted() where fileName.hasSuffix(Self.fileSuffix) {
            guard !Task.isCancelled else { return report }
            guard let paneId = UUID(uuidString: String(fileName.dropLast(Self.fileSuffix.count))) else {
                continue
            }
            let fileReport = await drainFile(
                at: spoolDirectory.appendingPathComponent(fileName),
                paneId: paneId
            )
            report += fileReport
        }
        return report
    }

    /// The exclusive lock is held across admission so a concurrent CLI append
    /// cannot land between reading the lines and truncating the file.
    private func drainFile(at url: URL, paneId: UUID) async -> DrainReport {
        #if canImport(Darwin)
            var report = DrainReport()
            let descriptor = open(url.path, O_RDWR)
            guard descriptor >= 0 else {
                report.retainedFileCount = 1
                return report
            }
            defer { close(descriptor) }
            guard flock(descriptor, LOCK_EX) == 0 else {
                report.retainedFileCount = 1
                return report
            }
            defer { flock(descriptor, LOCK_UN) }
            guard let decoded = readLines(from: descriptor) else {
                report.retainedFileCount = 1
                return report
            }
            report.malformedLineCount += decoded.incompleteTrailingLineCount
            var consumedEveryLine = true
            for line in decoded.lines {
                switch await admit(line: line, paneId: paneId) {
                case .admitted: report.admittedLineCount += 1
                case .rejected: report.rejectedLineCount += 1
                case .malformed: report.malformedLineCount += 1
                case .retryable: consumedEveryLine = false
                }
                guard consumedEveryLine else { break }
            }
            guard consumedEveryLine, ftruncate(descriptor, 0) == 0 else {
                report.retainedFileCount = 1
                return report
            }
            report.truncatedFileCount = 1
            return report
        #else
            return DrainReport(retainedFileCount: 1)
        #endif
    }

    #if canImport(Darwin)
        private struct DecodedSpoolFile {
            let lines: [String]
            let incompleteTrailingLineCount: Int
        }

        private func readLines(from descriptor: Int32) -> DecodedSpoolFile? {
            guard lseek(descriptor, 0, SEEK_SET) == 0 else { return nil }
            var frameDecoder = NDJSONFrameDecoder(maxFrameBytes: maximumLineBytes)
            var lines: [String] = []
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let readCount = buffer.withUnsafeMutableBytes { pointer in
                    read(descriptor, pointer.baseAddress, pointer.count)
                }
                if readCount < 0 {
                    if errno == EINTR { continue }
                    return nil
                }
                guard readCount > 0 else { break }
                guard let decoded = try? frameDecoder.append(Data(buffer[..<readCount])) else { return nil }
                lines.append(contentsOf: decoded)
            }
            return DecodedSpoolFile(
                lines: lines,
                incompleteTrailingLineCount: frameDecoder.pendingByteCount > 0 ? 1 : 0
            )
        }
    #endif

    /// Eligibility is re-checked against the compiled descriptors: a line that
    /// names an ineligible variant or another method never reaches admission,
    /// whatever wrote it.
    private func admit(line: String, paneId: UUID) async -> LineOutcome {
        guard let request = try? JSONRPCCodec.decodeRequest(line, maxBytes: maximumLineBytes),
            let descriptor = descriptorsByMethodName[request.method],
            let parameters = request.params,
            let rawParameters = try? JSONEncoder().encode(parameters),
            let normalizedParameters = try? descriptor.normalizeParameters(rawParameters)
        else {
            return .malformed
        }
        switch request.method {
        case Self.reportMethodName:
            guard
                let reportParameters = try? JSONDecoder().decode(
                    IPCSessionReportParams.self, from: normalizedParameters),
                Self.isOfflineEligible(Self.modelCallVariant(for: reportParameters.kind), in: descriptor),
                Self.resolvesToPane(handle: reportParameters.handle, paneId: paneId)
            else {
                return .malformed
            }
            do {
                _ = try await admission.recordDeliberateReport(paneId: paneId, params: reportParameters)
                return .admitted
            } catch {
                return Self.lineOutcome(for: error)
            }
        case Self.messageMethodName:
            guard
                let messageParameters = try? JSONDecoder().decode(
                    IPCSessionMessageParams.self, from: normalizedParameters),
                Self.isOfflineEligible(.message, in: descriptor),
                Self.resolvesToPane(handle: messageParameters.handle, paneId: paneId)
            else {
                return .malformed
            }
            do {
                _ = try await admission.recordAgentMessage(paneId: paneId, params: messageParameters)
                return .admitted
            } catch {
                return Self.lineOutcome(for: error)
            }
        default:
            return .malformed
        }
    }

    /// A duplicate correlation is already durable, so it consumes its line. A
    /// late deliberate report with no binding to attach to is a terminal
    /// rejection that also consumes its line. Only an unavailable ingestion or an
    /// unclassified failure retains the file for the next readiness.
    private static func lineOutcome(for error: any Error) -> LineOutcome {
        guard let sessionsError = error as? AppIPCSessionsError else { return .retryable }
        switch sessionsError.reason {
        case .correlationConflict:
            return .admitted
        case .bindingRequired, .targetNotFound, .validationRejected:
            return .rejected
        case .ingestionUnavailable:
            return .retryable
        }
    }

    private static func modelCallVariant(for kind: IPCSessionReportKind) -> IPCModelCallVariant {
        switch kind {
        case .needsYou: .needsYou
        case .clearNeedsYou: .needsYouClear
        case .done: .done
        }
    }

    private static func isOfflineEligible(
        _ variant: IPCModelCallVariant,
        in descriptor: IPCAnyMethodDescriptor
    ) -> Bool {
        guard case .modelCallVariants(let variants) = descriptor.metadata.offlineEligibility else {
            return false
        }
        return variants.contains(variant)
    }

    /// The file name is the durable pane identity. A line that targets another
    /// pane was not written by that pane's own CLI.
    private static func resolvesToPane(handle: String, paneId: UUID) -> Bool {
        handle == selfHandle || handle == paneId.uuidString
    }
}
