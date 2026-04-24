import Foundation
import Observation

struct TerminalURLRequest: Equatable, Sendable {
    let url: String
    let kind: OpenURLKind
    let sequence: UInt64
}

enum TerminalProgressActivity: Equatable, Sendable {
    case notReported
    case reported(ProgressState)
    case removed
}

struct TerminalOutputBurst: Equatable, Sendable {
    let baselineTotal: Int
    let latestTotal: Int
    let addedRows: Int
    let threshold: Int

    var thresholdReached: Bool {
        addedRows >= threshold
    }
}

enum TerminalOutputBurstState: Equatable, Sendable {
    case unknown
    case quiet(lastTotal: Int)
    case accumulating(TerminalOutputBurst)

    var thresholdReached: Bool {
        guard case .accumulating(let burst) = self else { return false }
        return burst.thresholdReached
    }
}

struct TerminalActivitySnapshot: Equatable, Sendable {
    let paneId: UUID
    var progress: TerminalProgressActivity
    var cwd: URL?
    var secureInputActive: Bool
    var recentURLRequests: [TerminalURLRequest]
    var outputBurst: TerminalOutputBurstState

    init(paneId: UUID) {
        self.paneId = paneId
        self.progress = .notReported
        self.cwd = nil
        self.secureInputActive = false
        self.recentURLRequests = []
        self.outputBurst = .unknown
    }
}

@Observable
@MainActor
final class TerminalActivityAtom {
    private(set) var snapshotsByPaneId: [UUID: TerminalActivitySnapshot] = [:]

    private let outputBurstThreshold: Int
    private let recentURLLimit: Int

    init(
        outputBurstThreshold: Int = 30,
        recentURLLimit: Int = 10
    ) {
        self.outputBurstThreshold = max(1, outputBurstThreshold)
        self.recentURLLimit = max(0, recentURLLimit)
    }

    func snapshot(for paneId: UUID) -> TerminalActivitySnapshot? {
        snapshotsByPaneId[paneId]
    }

    func consume(_ envelope: PaneEnvelope) {
        guard case .terminal(let event) = envelope.event else { return }
        let paneId = envelope.paneId.uuid
        var snapshot = snapshotsByPaneId[paneId] ?? TerminalActivitySnapshot(paneId: paneId)

        switch event {
        case .progressReportUpdated(let progress):
            snapshot.progress = progress.map(TerminalProgressActivity.reported) ?? .removed
        case .cwdChanged(let cwdPath):
            snapshot.cwd = URL(fileURLWithPath: cwdPath)
        case .secureInputChanged(let isActive):
            snapshot.secureInputActive = isActive
        case .openURLRequested(let url, let kind):
            appendURLRequest(
                TerminalURLRequest(
                    url: url,
                    kind: kind,
                    sequence: envelope.seq
                ),
                to: &snapshot
            )
        case .scrollbarChanged(let state):
            snapshot.outputBurst = nextOutputBurstState(
                current: snapshot.outputBurst,
                newTotal: state.total
            )
        default:
            break
        }

        snapshotsByPaneId[paneId] = snapshot
    }

    func clear(paneId: UUID) {
        snapshotsByPaneId.removeValue(forKey: paneId)
    }

    func reset() {
        snapshotsByPaneId.removeAll()
    }

    private func appendURLRequest(
        _ request: TerminalURLRequest,
        to snapshot: inout TerminalActivitySnapshot
    ) {
        guard recentURLLimit > 0 else { return }
        snapshot.recentURLRequests.append(request)
        if snapshot.recentURLRequests.count > recentURLLimit {
            snapshot.recentURLRequests.removeFirst(snapshot.recentURLRequests.count - recentURLLimit)
        }
    }

    private func nextOutputBurstState(
        current: TerminalOutputBurstState,
        newTotal: Int
    ) -> TerminalOutputBurstState {
        let baselineTotal: Int
        switch current {
        case .unknown:
            return .quiet(lastTotal: newTotal)
        case .quiet(let lastTotal):
            baselineTotal = lastTotal
        case .accumulating(let burst):
            baselineTotal = burst.baselineTotal
        }

        guard newTotal > baselineTotal else {
            return .quiet(lastTotal: newTotal)
        }

        return .accumulating(
            TerminalOutputBurst(
                baselineTotal: baselineTotal,
                latestTotal: newTotal,
                addedRows: newTotal - baselineTotal,
                threshold: outputBurstThreshold
            )
        )
    }
}
