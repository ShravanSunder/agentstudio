import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import Foundation
import SwiftUI

enum RepoExplorerFocus: Hashable {
    case filter
}

final class RepoExplorerFocusableView: NSView {
    var onFocusChange: @MainActor (Bool) -> Void = { _ in }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange(false)
        }
        return didResignFirstResponder
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
    }
}

struct RepoExplorerFocusBridge: NSViewRepresentable {
    let uiState: WorkspaceSidebarState

    func makeNSView(context: Context) -> RepoExplorerFocusableView {
        let view = RepoExplorerFocusableView()
        view.identifier = RepoExplorerView.focusTargetIdentifier
        view.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
        return view
    }

    func updateNSView(_ nsView: RepoExplorerFocusableView, context: Context) {
        nsView.onFocusChange = { hasFocus in
            uiState.setSidebarHasFocus(hasFocus)
        }
    }

    static func dismantleNSView(_ nsView: RepoExplorerFocusableView, coordinator: ()) {
        MainActor.assumeIsolated {
            nsView.onFocusChange(false)
        }
    }
}

enum RepoExplorerFocusPublisher {
    @MainActor
    static func publish(
        focusedField: RepoExplorerFocus?,
        into uiState: WorkspaceSidebarState
    ) {
        uiState.setSidebarHasFocus(focusedField != nil)
    }
}

struct RepoExplorerVisibleRowsBridge: NSViewRepresentable {
    let entries: [RepoExplorerListEntry]
    let scrollInstrumentationState: RepoExplorerScrollInstrumentationState
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    let onVisibleWorktreeIdsChange: @MainActor @Sendable (Set<UUID>) -> Void

    func makeNSView(context: Context) -> RepoExplorerVisibleRowsObserverView {
        let view = RepoExplorerVisibleRowsObserverView()
        view.entries = entries
        view.scrollInstrumentationState = scrollInstrumentationState
        view.performanceTraceRecorder = performanceTraceRecorder
        view.onVisibleWorktreeIdsChange = onVisibleWorktreeIdsChange
        return view
    }

    func updateNSView(_ nsView: RepoExplorerVisibleRowsObserverView, context: Context) {
        nsView.entries = entries
        nsView.scrollInstrumentationState = scrollInstrumentationState
        nsView.performanceTraceRecorder = performanceTraceRecorder
        nsView.onVisibleWorktreeIdsChange = onVisibleWorktreeIdsChange
        nsView.scheduleVisibleRowsReport()
    }

    static func dismantleNSView(_ nsView: RepoExplorerVisibleRowsObserverView, coordinator: ()) {
        nsView.stopObservingTable()
    }
}

@MainActor
final class RepoExplorerVisibleRowsObserverView: NSView {
    var entries: [RepoExplorerListEntry] = []
    var onVisibleWorktreeIdsChange: @MainActor @Sendable (Set<UUID>) -> Void = { _ in }
    var scrollInstrumentationState = RepoExplorerScrollInstrumentationState()
    var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?

    private weak var observedTableView: NSTableView?
    private var boundsObserver: NSObjectProtocol?
    private var reportTask: Task<Void, Never>?
    private var lastReportedWorktreeIds: Set<UUID> = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopObservingTable()
            return
        }
        scheduleTableResolution()
    }

    func scheduleVisibleRowsReport() {
        guard reportTask == nil else { return }
        reportTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            reportTask = nil
            reportVisibleWorktrees()
        }
    }

    func stopObservingTable() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        reportTask?.cancel()
        reportTask = nil
        observedTableView = nil
    }

    private func scheduleTableResolution() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.resolveTableViewIfNeeded()
            self?.scheduleVisibleRowsReport()
        }
    }

    private func resolveTableViewIfNeeded() {
        guard window != nil else { return }
        let tableView = nearestTableView()
        guard observedTableView !== tableView else { return }
        stopObservingTable()
        observedTableView = tableView
        guard let clipView = tableView?.enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordScrollBoundsChange()
                self?.scheduleVisibleRowsReport()
            }
        }
    }

    private func nearestTableView() -> NSTableView? {
        var candidate: NSView? = self
        while let current = candidate {
            if let tableView = current as? NSTableView {
                return tableView
            }
            candidate = current.superview
        }
        return window?.contentView?.firstDescendant(ofType: NSTableView.self)
    }

    private func reportVisibleWorktrees() {
        resolveTableViewIfNeeded()
        guard let tableView = observedTableView else { return }
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        let visibleWorktreeIds = RepoExplorerVisibleRows.worktreeIds(
            in: entries,
            rowRange: visibleRows
        )
        guard visibleWorktreeIds != lastReportedWorktreeIds else { return }
        lastReportedWorktreeIds = visibleWorktreeIds
        onVisibleWorktreeIdsChange(visibleWorktreeIds)
    }

    private func recordScrollBoundsChange() {
        guard let tableView = observedTableView else { return }
        let sample = scrollInstrumentationState.recordBoundsChange(
            visibleRowCount: tableView.rows(in: tableView.visibleRect).length
        )
        if let gapDuration = sample.gapDuration {
            performanceTraceRecorder?.recordDuration(
                .repoExplorerScrollFrameGap,
                duration: gapDuration,
                attributes: sample.traceAttributes
            )
        } else {
            performanceTraceRecorder?.record(.repoExplorerScrollFrameGap, attributes: sample.traceAttributes)
        }
    }
}

enum RepoExplorerVisibleRowCountBucket: String, Equatable, Sendable {
    case zero
    case oneToEight = "1_8"
    case nineToSixteen = "9_16"
    case seventeenToThirtyTwo = "17_32"
    case thirtyThreePlus = "33_plus"

    init(rowCount: Int) {
        switch rowCount {
        case ...0: self = .zero
        case 1...8: self = .oneToEight
        case 9...16: self = .nineToSixteen
        case 17...32: self = .seventeenToThirtyTwo
        default: self = .thirtyThreePlus
        }
    }
}

enum RepoExplorerScrollGapOutcome: String, Equatable, Sendable {
    case sampled
    case incomplete
}

struct RepoExplorerScrollGapSample: Equatable, Sendable {
    let gapDuration: Duration?
    let scrollBurstSequence: UInt64
    let frameSampleSequence: UInt64
    let visibleRowCountBucket: RepoExplorerVisibleRowCountBucket
    let outcome: RepoExplorerScrollGapOutcome

    var traceAttributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.repo_explorer.surface": .string("repo"),
            "agentstudio.performance.repo_explorer.scroll_frame_gap.outcome": .string(outcome.rawValue),
            "agentstudio.performance.repo_explorer.visible_row_count_bucket": .string(
                visibleRowCountBucket.rawValue),
            "agentstudio.performance.repo_explorer.scroll_burst.sequence": .int(
                Int(clamping: scrollBurstSequence)),
            "agentstudio.performance.repo_explorer.frame_sample.sequence": .int(
                Int(clamping: frameSampleSequence)),
            "agentstudio.performance.repo_explorer.scroll_active": .bool(true),
        ]
    }
}

struct RepoExplorerScrollGapState: Sendable {
    private var previousSampleNanoseconds: UInt64?
    private(set) var scrollBurstSequence: UInt64 = 0
    private var frameSampleSequence: UInt64 = 0

    mutating func sample(atNanoseconds: UInt64, visibleRowCount: Int) -> RepoExplorerScrollGapSample {
        let gapNanoseconds = previousSampleNanoseconds.map {
            atNanoseconds - min(atNanoseconds, $0)
        }
        let startsBurst =
            gapNanoseconds.map {
                $0 > AppPolicies.Diagnostics.repoExplorerScrollBurstSeparationNanoseconds
            } ?? true
        if startsBurst {
            scrollBurstSequence &+= 1
            frameSampleSequence = 0
        }
        frameSampleSequence &+= 1
        previousSampleNanoseconds = atNanoseconds
        return RepoExplorerScrollGapSample(
            gapDuration: startsBurst ? nil : gapNanoseconds.map { .nanoseconds(Int64(clamping: $0)) },
            scrollBurstSequence: scrollBurstSequence,
            frameSampleSequence: frameSampleSequence,
            visibleRowCountBucket: RepoExplorerVisibleRowCountBucket(rowCount: visibleRowCount),
            outcome: startsBurst ? .incomplete : .sampled
        )
    }
}

@MainActor
final class RepoExplorerScrollInstrumentationState {
    private var gapState = RepoExplorerScrollGapState()
    private(set) var latestSample: RepoExplorerScrollGapSample?
    private var latestSampleNanoseconds: UInt64?

    var latestVisibleRowCountBucket: RepoExplorerVisibleRowCountBucket? {
        latestSample?.visibleRowCountBucket
    }

    func recordBoundsChange(
        atNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
        visibleRowCount: Int
    ) -> RepoExplorerScrollGapSample {
        let sample = gapState.sample(atNanoseconds: atNanoseconds, visibleRowCount: visibleRowCount)
        latestSample = sample
        latestSampleNanoseconds = atNanoseconds
        return sample
    }

    func isScrollActive(atNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        guard let latestSampleNanoseconds else { return false }
        let elapsedNanoseconds = atNanoseconds - min(atNanoseconds, latestSampleNanoseconds)
        return elapsedNanoseconds <= AppPolicies.Diagnostics.repoExplorerScrollBurstSeparationNanoseconds
    }
}

struct RepoExplorerRowBodyEvaluationProxy<Content: View>: View {
    let entry: RepoExplorerListEntry
    let scrollInstrumentationState: RepoExplorerScrollInstrumentationState
    let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let measurement = RepoExplorerView.measureRowBodyEvaluationProxy(
            rowKind: entry.rowKind,
            resolve: content
        )
        if RepoExplorerPerformanceTelemetry.shared.admitExactRowBodyRecord() {
            var attributes: [String: AgentStudioTraceValue] = [
                "agentstudio.performance.repo_explorer.row_body_evaluation.outcome": .string(
                    measurement.outcome.rawValue),
                "agentstudio.performance.repo_explorer.row_kind": .string(measurement.rowKind.rawValue),
                "agentstudio.performance.repo_explorer.surface": .string("repo"),
                "agentstudio.performance.repo_explorer.scroll_active": .bool(
                    scrollInstrumentationState.isScrollActive()),
            ]
            if let visibleRowCountBucket = scrollInstrumentationState.latestVisibleRowCountBucket {
                attributes["agentstudio.performance.repo_explorer.visible_row_count_bucket"] = .string(
                    visibleRowCountBucket.rawValue)
            }
            performanceTraceRecorder?.recordDuration(
                .repoExplorerRowBodyEvaluation,
                duration: measurement.duration,
                attributes: attributes
            )
        }
        return measurement.content
    }
}

extension RepoExplorerListEntry {
    fileprivate var rowKind: RepoExplorerRowKind {
        switch self {
        case .sectionHeader: .sectionHeader
        case .loadingSectionHeader: .loadingSectionHeader
        case .loadingRepoRow: .loadingRepo
        case .resolvedGroupHeader: .resolvedGroupHeader
        case .resolvedWorktreeRow: .resolvedWorktree
        case .resolvedPaneRow: .resolvedPane
        case .unassociatedPaneRow: .resolvedPane
        case .topologyFault: .topologyFault
        }
    }
}

@MainActor
enum RepoExplorerVisibleRows {
    static func worktreeIds(
        in entries: [RepoExplorerListEntry],
        rowRange: NSRange
    ) -> Set<UUID> {
        guard rowRange.location != NSNotFound else { return [] }
        let lowerBound = max(0, rowRange.location)
        let upperBound = min(entries.count, rowRange.location + rowRange.length)
        guard lowerBound < upperBound else { return [] }

        return entries[lowerBound..<upperBound].reduce(into: Set<UUID>()) { result, entry in
            switch entry {
            case .resolvedWorktreeRow(_, _, let worktreeId, _):
                result.insert(worktreeId)
            case .sectionHeader, .loadingSectionHeader, .loadingRepoRow, .resolvedPaneRow,
                .unassociatedPaneRow,
                .resolvedGroupHeader,
                .topologyFault:
                break
            }
        }
    }

    static func publish(
        _ worktreeIds: Set<UUID>,
        into atom: SidebarVisibleWorktreesRuntimeAtom,
        onChange: @MainActor @Sendable () -> Void
    ) {
        atom.setVisibleWorktreeIds(worktreeIds)
        onChange()
    }
}

extension RepoExplorerView {
    package static let focusTargetIdentifier = NSUserInterfaceItemIdentifier("repoExplorerFocusTarget")
    static let surfaceListPolicy = SidebarSurfaceListPolicy.nativeSidebarList
    static let surfaceBackground = SidebarSurfaceBackground.shellChrome

    func updateSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) {
        RepoExplorerVisibleRows.publish(
            worktreeIds,
            into: atom(\.sidebarVisibleWorktreesRuntime),
            onChange: onSidebarVisibleWorktreesChanged
        )
    }
}

extension NSView {
    fileprivate func firstDescendant<T>(ofType type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstDescendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}
