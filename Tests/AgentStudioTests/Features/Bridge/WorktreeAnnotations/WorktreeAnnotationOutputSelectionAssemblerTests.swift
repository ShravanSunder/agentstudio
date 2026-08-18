import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Worktree annotation output selection assembler")
struct WorktreeAnnotationOutputSelectionAssemblerTests {
    @Test("middle 65 of 130 and complementary exclusions survive bounded chunks in canonical order")
    func arbitraryFiniteSelectionsSurviveBoundedChunks() throws {
        let allIDs = (1...130).map(outputSelectionTestUUID)
        let middle = Array(allIDs[32..<97])
        let complement = allIDs.filter { !Set(middle).contains($0) }

        let explicit = try assemble(
            ids: middle,
            mode: .explicit,
            transferID: "explicit-middle"
        )
        let allEligible = try assemble(
            ids: complement,
            mode: .allEligible,
            transferID: "excluded-complement"
        )

        #expect(explicit.selection == .explicit(messageIds: middle))
        #expect(allEligible.selection == .allEligible(excludedMessageIds: complement))
    }

    @Test("duplicate, ordinal, size, identity, session, and mode failures retire the transfer")
    func invalidTransferInputRetiresTransfer() throws {
        let cases: [(String, (WorktreeAnnotationOutputSelectionAssembler) throws -> Void)] = [
            (
                "duplicate begin",
                { assembler in
                    try assembler.begin(beginBody(transferID: "duplicate"), productSessionID: "product-1")
                    try assembler.begin(beginBody(transferID: "duplicate"), productSessionID: "product-1")
                }
            ),
            (
                "skipped ordinal",
                { assembler in
                    try assembler.begin(beginBody(transferID: "skipped"), productSessionID: "product-1")
                    try assembler.append(
                        chunkBody(ids: [outputSelectionTestUUID(1)], ordinal: 1, transferID: "skipped"),
                        productSessionID: "product-1"
                    )
                }
            ),
            (
                "oversized chunk",
                { assembler in
                    try assembler.begin(beginBody(transferID: "oversized"), productSessionID: "product-1")
                    try assembler.append(
                        chunkBody(ids: (1...65).map(outputSelectionTestUUID), ordinal: 0, transferID: "oversized"),
                        productSessionID: "product-1"
                    )
                }
            ),
            (
                "cross chunk duplicate",
                { assembler in
                    try assembler.begin(beginBody(transferID: "cross-duplicate"), productSessionID: "product-1")
                    try assembler.append(
                        chunkBody(ids: [outputSelectionTestUUID(1)], ordinal: 0, transferID: "cross-duplicate"),
                        productSessionID: "product-1"
                    )
                    try assembler.append(
                        chunkBody(ids: [outputSelectionTestUUID(1)], ordinal: 1, transferID: "cross-duplicate"),
                        productSessionID: "product-1"
                    )
                }
            ),
            (
                "wrong product session",
                { assembler in
                    try assembler.begin(beginBody(transferID: "wrong-product"), productSessionID: "product-1")
                    try assembler.append(
                        chunkBody(ids: [outputSelectionTestUUID(1)], ordinal: 0, transferID: "wrong-product"),
                        productSessionID: "product-2"
                    )
                }
            ),
            (
                "wrong domain session",
                { assembler in
                    try assembler.begin(beginBody(transferID: "wrong-session"), productSessionID: "product-1")
                    try assembler.append(
                        chunkBody(
                            ids: [outputSelectionTestUUID(1)],
                            ordinal: 0,
                            sessionID: outputSelectionTestUUID(201),
                            transferID: "wrong-session"
                        ),
                        productSessionID: "product-1"
                    )
                }
            ),
            (
                "wrong mode",
                { assembler in
                    try assembler.begin(beginBody(transferID: "wrong-mode"), productSessionID: "product-1")
                    try assembler.append(
                        chunkBody(
                            ids: [outputSelectionTestUUID(1)],
                            mode: .allEligible,
                            ordinal: 0,
                            transferID: "wrong-mode"
                        ),
                        productSessionID: "product-1"
                    )
                }
            ),
        ]

        for (label, operation) in cases {
            let assembler = WorktreeAnnotationOutputSelectionAssembler()
            #expect(throws: (any Error).self) { try operation(assembler) }
            #expect(!assembler.contains(transferID: transferID(for: label)))
        }
    }

    @Test("empty explicit commit, cancel, disconnect, and teardown leave no live transfer")
    func terminalPathsRetireTransfer() throws {
        let assembler = WorktreeAnnotationOutputSelectionAssembler()
        try assembler.begin(beginBody(transferID: "empty"), productSessionID: "product-1")
        #expect(throws: WorktreeAnnotationOutputSelectionAssemblerError.emptyExplicitSelection) {
            try assembler.commit(terminalBody(transferID: "empty"), productSessionID: "product-1")
        }
        #expect(!assembler.contains(transferID: "empty"))

        try assembler.begin(beginBody(transferID: "cancel"), productSessionID: "product-1")
        try assembler.cancel(terminalBody(transferID: "cancel"), productSessionID: "product-1")
        #expect(!assembler.contains(transferID: "cancel"))

        try assembler.begin(beginBody(transferID: "disconnect"), productSessionID: "product-1")
        assembler.disconnect(productSessionID: "product-1")
        #expect(!assembler.contains(transferID: "disconnect"))

        try assembler.begin(beginBody(transferID: "teardown"), productSessionID: "product-2")
        assembler.teardown()
        #expect(!assembler.contains(transferID: "teardown"))
    }
}

@MainActor
private func assemble(
    ids: [UUID],
    mode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode,
    transferID: String
) throws -> WorktreeAnnotationAssembledOutputSelection {
    let assembler = WorktreeAnnotationOutputSelectionAssembler()
    try assembler.begin(beginBody(mode: mode, transferID: transferID), productSessionID: "product-1")
    for (ordinal, offset) in stride(from: 0, to: ids.count, by: 64).enumerated() {
        try assembler.append(
            chunkBody(
                ids: Array(ids[offset..<min(offset + 64, ids.count)]),
                mode: mode,
                ordinal: ordinal,
                transferID: transferID
            ),
            productSessionID: "product-1"
        )
    }
    return try assembler.commit(
        terminalBody(mode: mode, transferID: transferID),
        productSessionID: "product-1"
    )
}

private func beginBody(
    mode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode = .explicit,
    transferID: String
) -> BridgeProductWorktreeAnnotationOperation.OutputSelectionBeginBody {
    .init(
        outputKind: .clipboardMarkdown,
        selectionMode: mode,
        sessionId: outputSelectionTestUUID(200),
        transferId: transferID
    )
}

private func chunkBody(
    ids: [UUID],
    mode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode = .explicit,
    ordinal: Int,
    sessionID: UUID = outputSelectionTestUUID(200),
    transferID: String
) -> BridgeProductWorktreeAnnotationOperation.OutputSelectionChunkBody {
    .init(
        messageIds: ids,
        ordinal: ordinal,
        selectionMode: mode,
        sessionId: sessionID,
        transferId: transferID
    )
}

private func terminalBody(
    mode: BridgeProductWorktreeAnnotationOperation.OutputSelectionMode = .explicit,
    transferID: String
) -> BridgeProductWorktreeAnnotationOperation.OutputSelectionTerminalBody {
    .init(
        selectionMode: mode,
        sessionId: outputSelectionTestUUID(200),
        transferId: transferID
    )
}

private func outputSelectionTestUUID(_ suffix: Int) -> UUID {
    UUID(uuidString: "00000000-0000-7000-8000-\(String(format: "%012d", suffix))")!
}

private func transferID(for label: String) -> String {
    switch label {
    case "duplicate begin": "duplicate"
    case "skipped ordinal": "skipped"
    case "oversized chunk": "oversized"
    case "cross chunk duplicate": "cross-duplicate"
    case "wrong product session": "wrong-product"
    case "wrong domain session": "wrong-session"
    case "wrong mode": "wrong-mode"
    default: label
    }
}
