import AgentStudioInfrastructure
import CryptoKit
import Foundation

enum BridgeWorktreeAnnotationOutputSourceError: Error, Equatable, Sendable {
    case descriptorMismatch
    case unavailable
}

struct BridgePaneProductWorktreeAnnotationOutputBody: Equatable, Sendable {
    let data: Data
    let sha256: String
}

/// Re-reads immutable output attempts from SQLite for every descriptor and body
/// request. Exact output bytes stay on the content-stream path and are never
/// retained by the projection Atom.
actor BridgePaneProductWorktreeAnnotationOutputSource {
    static let unavailable = BridgePaneProductWorktreeAnnotationOutputSource(store: nil)

    private let store: WorktreeAnnotationStore?
    private var issuedDescriptorIDs: [String] = []
    private var issuedDescriptorsByID: [String: BridgeProductAnnotationOutputContentDescriptor] = [:]

    init(store: WorktreeAnnotationStore?) {
        self.store = store
    }

    func descriptor(
        attemptID: WorktreeAnnotationOutputAttemptID,
        surface: BridgeProductSurface
    ) async throws -> BridgeProductAnnotationOutputContentDescriptor {
        guard let store else {
            throw BridgeWorktreeAnnotationOutputSourceError.unavailable
        }
        let preparedOutput = try await store.inspectOutputAttempt(attemptID: attemptID)
        let descriptor = try await Self.makeDescriptor(
            for: preparedOutput.attempt,
            descriptorID: UUIDv7.generate().uuidString.lowercased(),
            surface: surface
        )
        retainIssuedDescriptor(descriptor)
        return descriptor
    }

    func body(
        for descriptor: BridgeProductAnnotationOutputContentDescriptor
    ) async throws -> BridgePaneProductWorktreeAnnotationOutputBody {
        guard let store else {
            throw BridgeWorktreeAnnotationOutputSourceError.unavailable
        }
        guard issuedDescriptorsByID[descriptor.descriptorID] == descriptor else {
            throw BridgeWorktreeAnnotationOutputSourceError.descriptorMismatch
        }
        issuedDescriptorsByID[descriptor.descriptorID] = nil
        issuedDescriptorIDs.removeAll { $0 == descriptor.descriptorID }
        let preparedOutput = try await store.inspectOutputAttempt(
            attemptID: .init(rawValue: descriptor.attemptID)
        )
        let expectedDescriptor = try await Self.makeDescriptor(
            for: preparedOutput.attempt,
            descriptorID: descriptor.descriptorID,
            surface: descriptor.surface
        )
        guard expectedDescriptor == descriptor else {
            throw BridgeWorktreeAnnotationOutputSourceError.descriptorMismatch
        }
        return BridgePaneProductWorktreeAnnotationOutputBody(
            data: preparedOutput.attempt.exactBytes,
            sha256: descriptor.expectedSHA256
        )
    }

    private func retainIssuedDescriptor(
        _ descriptor: BridgeProductAnnotationOutputContentDescriptor
    ) {
        issuedDescriptorsByID[descriptor.descriptorID] = descriptor
        issuedDescriptorIDs.append(descriptor.descriptorID)
        while issuedDescriptorIDs.count
            > AppPolicies.Bridge.worktreeAnnotationMaximumIssuedOutputDescriptors
        {
            let expiredDescriptorID = issuedDescriptorIDs.removeFirst()
            issuedDescriptorsByID[expiredDescriptorID] = nil
        }
    }

    private static func makeDescriptor(
        for attempt: WorktreeAnnotationOutputAttempt,
        descriptorID: String,
        surface: BridgeProductSurface
    ) async throws -> BridgeProductAnnotationOutputContentDescriptor {
        let exactBytes = attempt.exactBytes
        let digest = await sha256Hex(exactBytes)
        return try BridgeProductAnnotationOutputContentDescriptor(
            attemptID: attempt.id.rawValue,
            contentType: attempt.contentType,
            declaredByteLength: exactBytes.count,
            descriptorID: descriptorID,
            expectedSHA256: digest,
            formatVersion: attempt.formatVersion,
            maximumBytes: exactBytes.count,
            outputKind: attempt.outputKind,
            surface: surface
        )
    }

    @concurrent nonisolated private static func sha256Hex(_ data: Data) async -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
