import Foundation

enum WorktreeAnnotationOutputSelectionAssemblerError: Error, Equatable, Sendable {
    case duplicateTransfer
    case emptyExplicitSelection
    case invalidChunk
    case transferNotFound
    case transferMismatch
}

struct WorktreeAnnotationAssembledOutputSelection: Equatable, Sendable {
    let outputKind: BridgeProductWorktreeAnnotationOperation.OutputKind
    let selection: BridgeProductWorktreeAnnotationOutputSelection
    let sessionID: UUID
}

@MainActor
final class WorktreeAnnotationOutputSelectionAssembler {
    private struct Transfer {
        let outputKind: BridgeProductWorktreeAnnotationOperation.OutputKind
        let productSessionID: String
        let selectionMode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode
        let sessionID: UUID
        var nextOrdinal: Int
        var orderedMessageIDs: [UUID]
        var messageIDs: Set<UUID>
    }

    private var transfersByID: [String: Transfer] = [:]

    func begin(
        _ body: BridgeProductWorktreeAnnotationOperation.OutputSelectionBeginBody,
        productSessionID: String
    ) throws {
        guard transfersByID[body.transferId] == nil else {
            transfersByID.removeValue(forKey: body.transferId)
            throw WorktreeAnnotationOutputSelectionAssemblerError.duplicateTransfer
        }
        transfersByID[body.transferId] = Transfer(
            outputKind: body.outputKind,
            productSessionID: productSessionID,
            selectionMode: body.selectionMode,
            sessionID: body.sessionId,
            nextOrdinal: 0,
            orderedMessageIDs: [],
            messageIDs: []
        )
    }

    func append(
        _ body: BridgeProductWorktreeAnnotationOperation.OutputSelectionChunkBody,
        productSessionID: String
    ) throws {
        guard var transfer = transfersByID[body.transferId] else {
            throw WorktreeAnnotationOutputSelectionAssemblerError.transferNotFound
        }
        do {
            try validate(
                transfer,
                sessionID: body.sessionId,
                selectionMode: body.selectionMode,
                productSessionID: productSessionID
            )
            guard body.ordinal == transfer.nextOrdinal,
                !body.messageIds.isEmpty,
                body.messageIds.count <= 64,
                Set(body.messageIds).count == body.messageIds.count,
                transfer.messageIDs.isDisjoint(with: body.messageIds)
            else {
                throw WorktreeAnnotationOutputSelectionAssemblerError.invalidChunk
            }
            transfer.orderedMessageIDs.append(contentsOf: body.messageIds)
            transfer.messageIDs.formUnion(body.messageIds)
            transfer.nextOrdinal += 1
            transfersByID[body.transferId] = transfer
        } catch {
            transfersByID.removeValue(forKey: body.transferId)
            throw error
        }
    }

    func commit(
        _ body: BridgeProductWorktreeAnnotationOperation.OutputSelectionTerminalBody,
        productSessionID: String
    ) throws -> WorktreeAnnotationAssembledOutputSelection {
        guard let transfer = transfersByID.removeValue(forKey: body.transferId) else {
            throw WorktreeAnnotationOutputSelectionAssemblerError.transferNotFound
        }
        try validate(
            transfer,
            sessionID: body.sessionId,
            selectionMode: body.selectionMode,
            productSessionID: productSessionID
        )
        let selection: BridgeProductWorktreeAnnotationOutputSelection
        switch transfer.selectionMode {
        case .explicit:
            guard !transfer.orderedMessageIDs.isEmpty else {
                throw WorktreeAnnotationOutputSelectionAssemblerError.emptyExplicitSelection
            }
            selection = .explicit(messageIds: transfer.orderedMessageIDs)
        case .allEligible:
            selection = .allEligible(excludedMessageIds: transfer.orderedMessageIDs)
        }
        return WorktreeAnnotationAssembledOutputSelection(
            outputKind: transfer.outputKind,
            selection: selection,
            sessionID: transfer.sessionID
        )
    }

    func cancel(
        _ body: BridgeProductWorktreeAnnotationOperation.OutputSelectionTerminalBody,
        productSessionID: String
    ) throws {
        guard let transfer = transfersByID.removeValue(forKey: body.transferId) else {
            throw WorktreeAnnotationOutputSelectionAssemblerError.transferNotFound
        }
        try validate(
            transfer,
            sessionID: body.sessionId,
            selectionMode: body.selectionMode,
            productSessionID: productSessionID
        )
    }

    func disconnect(productSessionID: String) {
        transfersByID = transfersByID.filter { $0.value.productSessionID != productSessionID }
    }

    func teardown() {
        transfersByID.removeAll()
    }

    func contains(transferID: String) -> Bool {
        transfersByID[transferID] != nil
    }

    private func validate(
        _ transfer: Transfer,
        sessionID: UUID,
        selectionMode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode,
        productSessionID: String
    ) throws {
        guard transfer.productSessionID == productSessionID,
            transfer.sessionID == sessionID,
            transfer.selectionMode == selectionMode
        else {
            throw WorktreeAnnotationOutputSelectionAssemblerError.transferMismatch
        }
    }
}
