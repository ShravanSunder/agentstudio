import AgentStudioAppIPC
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
            throw AppIPCBridgeError(reason: .payloadTooLarge)
        }
    }

    private static func estimatedPayloadBytes(_ value: IPCBridgeReviewPackageResult) -> Int {
        var byteCount = 512
        byteCount += estimatedJSONStringBytes(value.paneId.uuidString)
        byteCount += estimatedJSONStringBytes(value.status)
        byteCount += estimatedOptionalJSONStringBytes(value.selectedItemId)
        guard let package = value.package else {
            return byteCount + 4
        }

        byteCount += 512
        byteCount += estimatedJSONStringBytes(package.packageId)
        byteCount += estimatedJSONIntegerBytes(package.reviewGeneration)
        byteCount += estimatedJSONIntegerBytes(package.revision)
        byteCount += package.orderedItemIds.reduce(2) { partialResult, itemId in
            partialResult + estimatedJSONStringBytes(itemId) + 1
        }
        byteCount += 80
        byteCount += estimatedJSONIntegerBytes(package.summary.filesChanged)
        byteCount += estimatedJSONIntegerBytes(package.summary.additions)
        byteCount += estimatedJSONIntegerBytes(package.summary.deletions)
        byteCount += estimatedJSONIntegerBytes(package.summary.visibleFileCount)
        byteCount += estimatedJSONIntegerBytes(package.summary.hiddenFileCount)
        byteCount += package.items.reduce(2) { partialResult, item in
            partialResult + estimatedPayloadBytes(item) + 1
        }
        return byteCount
    }

    private static func estimatedPayloadBytes(_ value: IPCBridgeContentGetResult) -> Int {
        512
            + estimatedJSONStringBytes(value.paneId.uuidString)
            + estimatedPayloadBytes(value.handle)
            + estimatedJSONStringBytes(value.mimeType)
            + estimatedJSONIntegerBytes(value.byteCount)
            + estimatedOptionalJSONStringBytes(value.contentText)
            + estimatedOptionalJSONStringBytes(value.contentBase64)
    }

    private static func estimatedPayloadBytes(_ item: IPCBridgeReviewItem) -> Int {
        384
            + estimatedJSONStringBytes(item.itemId)
            + estimatedJSONStringBytes(item.itemKind)
            + estimatedOptionalJSONStringBytes(item.basePath)
            + estimatedOptionalJSONStringBytes(item.headPath)
            + estimatedJSONStringBytes(item.changeKind)
            + estimatedJSONStringBytes(item.fileClass)
            + estimatedOptionalJSONStringBytes(item.language)
            + estimatedJSONIntegerBytes(item.additions)
            + estimatedJSONIntegerBytes(item.deletions)
            + estimatedJSONStringBytes(item.reviewPriority)
            + estimatedPayloadBytes(item.contentRoles)
    }

    private static func estimatedPayloadBytes(_ roles: IPCBridgeContentRoles) -> Int {
        64
            + estimatedOptionalPayloadBytes(roles.base)
            + estimatedOptionalPayloadBytes(roles.head)
            + estimatedOptionalPayloadBytes(roles.diff)
            + estimatedOptionalPayloadBytes(roles.file)
    }

    private static func estimatedOptionalPayloadBytes(
        _ handle: IPCBridgeContentHandleSummary?
    ) -> Int {
        guard let handle else {
            return 4
        }
        return estimatedPayloadBytes(handle)
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
