import AgentStudioProgrammaticControl
import Foundation

struct BridgeIPCResponseBudget: Sendable {
    static func validate(_ value: IPCBridgeReviewPackageResult) throws {
        try validate(byteCount: estimatedPayloadBytes(value))
    }

    static func validate(_ value: IPCBridgeContentGetResult) throws {
        try validate(byteCount: estimatedPayloadBytes(value))
    }

    private static func validate(byteCount: Int) throws {
        guard byteCount <= AppPolicies.Bridge.ipcMaxResponsePayloadBytes else {
            throw BridgeIPCProjectionError(reason: .payloadTooLarge)
        }
    }

    private static func estimatedPayloadBytes(_ value: IPCBridgeReviewPackageResult) -> Int {
        var byteCount = 512
        byteCount += estimatedJSONStringBytes(value.paneId.uuidString)
        byteCount += estimatedJSONStringBytes(value.status)
        byteCount += estimatedOptionalJSONStringBytes(value.selectedItemId)
        byteCount += estimatedOptionalJSONStringBytes(value.packageId)
        if let reviewGeneration = value.reviewGeneration {
            byteCount += estimatedJSONIntegerBytes(reviewGeneration)
        }
        if let revision = value.revision {
            byteCount += estimatedJSONIntegerBytes(revision)
        }
        if let summary = value.summary {
            byteCount += 80
            byteCount += estimatedJSONIntegerBytes(summary.filesChanged)
            byteCount += estimatedJSONIntegerBytes(summary.additions)
            byteCount += estimatedJSONIntegerBytes(summary.deletions)
            byteCount += estimatedJSONIntegerBytes(summary.visibleFileCount)
            byteCount += estimatedJSONIntegerBytes(summary.hiddenFileCount)
        }
        return byteCount
    }

    private static func estimatedPayloadBytes(_ value: IPCBridgeContentGetResult) -> Int {
        512
            + estimatedJSONStringBytes(value.paneId.uuidString)
            + estimatedPayloadBytes(value.handle)
            + estimatedJSONStringBytes(value.mimeType)
            + estimatedJSONIntegerBytes(value.byteCount)
            + 8
    }

    private static func estimatedPayloadBytes(_ handle: IPCBridgeContentHandleSummary) -> Int {
        256
            + estimatedJSONStringBytes(handle.handleId)
            + estimatedJSONStringBytes(handle.itemId)
            + estimatedJSONStringBytes(handle.role)
            + estimatedJSONIntegerBytes(handle.reviewGeneration)
            + estimatedJSONStringBytes(handle.resourceUrl)
            + estimatedJSONStringBytes(handle.mimeType)
            + estimatedOptionalJSONStringBytes(handle.language)
            + estimatedJSONIntegerBytes(handle.sizeBytes)
    }

    private static func estimatedOptionalJSONStringBytes(_ value: String?) -> Int {
        guard let value else {
            return 4
        }
        return estimatedJSONStringBytes(value)
    }

    private static func estimatedJSONStringBytes(_ value: String) -> Int {
        var byteCount = 2
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0...0x1F:
                byteCount += 6
            case 0x22, 0x5C:
                byteCount += 2
            case 0...0x7F:
                byteCount += 1
            case 0...0x7FF:
                byteCount += 2
            case 0...0xFFFF:
                byteCount += 3
            default:
                byteCount += 4
            }
        }
        return byteCount
    }

    private static func estimatedJSONIntegerBytes(_ value: Int) -> Int {
        String(value).utf8.count
    }
}
