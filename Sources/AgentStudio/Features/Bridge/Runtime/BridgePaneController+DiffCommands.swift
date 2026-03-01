import Foundation

@MainActor
extension BridgePaneController: BridgeRuntimeCommandHandling {
    func handleDiffCommand(
        _ command: DiffCommand,
        commandId: UUID,
        correlationId: UUID?
    ) -> ActionResult {
        switch command {
        case .loadDiff(let artifact):
            paneState.diff.setStatus(.loading)
            paneState.diff.advanceEpoch()
            let stats = Self.deriveDiffStats(from: artifact.patchData)
            paneState.diff.setStatus(.ready)
            ingestRuntimeEvent(
                .diff(.diffLoaded(stats: stats)),
                commandId: commandId,
                correlationId: correlationId
            )
            return .success(commandId: commandId)
        case .approveHunk(let hunkId):
            ingestRuntimeEvent(
                .diff(.hunkApproved(hunkId: hunkId)),
                commandId: commandId,
                correlationId: correlationId
            )
            return .success(commandId: commandId)
        case .rejectHunk:
            return .success(commandId: commandId)
        }
    }

    private static func deriveDiffStats(from patchData: Data) -> DiffStats {
        guard let patchText = String(data: patchData, encoding: .utf8) else {
            return DiffStats(filesChanged: 0, insertions: 0, deletions: 0)
        }

        var filesChanged = 0
        var insertions = 0
        var deletions = 0

        for line in patchText.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("diff --git ") {
                filesChanged += 1
                continue
            }
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                continue
            }
            if line.hasPrefix("+") {
                insertions += 1
                continue
            }
            if line.hasPrefix("-") {
                deletions += 1
            }
        }

        return DiffStats(
            filesChanged: filesChanged,
            insertions: insertions,
            deletions: deletions
        )
    }
}
