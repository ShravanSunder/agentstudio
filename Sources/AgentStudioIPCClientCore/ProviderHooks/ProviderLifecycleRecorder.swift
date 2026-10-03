import AgentStudioCLIStore
import AgentStudioProgrammaticControl
import Darwin
import Foundation

/// Only lifecycle hooks persist. Failure leaves the original live envelope available for one send.
enum ProviderLifecycleRecorder {
    static func recording(_ params: IPCSessionEventParams, environment: [String: String]) -> IPCSessionEventParams {
        let event: CLILifecycleEvent
        switch params.event.name {
        case .sessionStart: event = .sessionStart
        case .sessionEnd: event = .sessionEnd(reason: params.event.endReason)
        default: return params
        }
        let reportID = params.event.occurrenceId
        guard
            let paneText = environment["AGENTSTUDIO_PANE_ID"], let paneID = UUID(uuidString: paneText),
            let path = environment["AGENTSTUDIO_CLI_STORE"], !path.isEmpty,
            let channelText = environment["AGENTSTUDIO_CLI_STORE_CHANNEL"],
            let channel = CLIStoreChannel(rawValue: channelText), let bootID = bootSessionID(),
            case .success(let writer) = CLIStore.openWriter(url: URL(fileURLWithPath: path), channel: channel),
            case .success(let report) = writer.appendLifecycleReport(
                .init(
                    reportID: reportID, paneID: paneID, providerIdentifier: params.provider.identifier,
                    providerVersion: params.provider.version, providerMode: params.provider.mode, event: event,
                    conversationID: params.event.conversationId, correlationID: params.correlationId,
                    recordedAt: Date(), bootSessionID: bootID))
        else { return params }
        return IPCSessionEventParams(
            handle: params.handle, provider: params.provider, event: params.event,
            correlationId: params.correlationId,
            lifecycleReport: .init(storeId: writer.identity.storeID, sequence: report.sequence))
    }

    /// The same platform boot identifier Core reads; the leaf target owns its platform read.
    private static func bootSessionID() -> String? {
        var bytes = [CChar](repeating: 0, count: MemoryLayout<uuid_string_t>.size)
        var count = bytes.count
        let result = bytes.withUnsafeMutableBytes {
            sysctlbyname("kern.bootsessionuuid", $0.baseAddress, &count, nil, 0)
        }
        guard result == 0, count > 1, count <= bytes.count, bytes[count - 1] == 0,
            let value = String(bytes: bytes.prefix(count - 1).map { UInt8(bitPattern: $0) }, encoding: .utf8),
            UUID(uuidString: value) != nil
        else { return nil }
        return value
    }
}
