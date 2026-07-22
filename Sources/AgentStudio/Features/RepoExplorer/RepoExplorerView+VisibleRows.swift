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
    let onVisibleWorktreeIdsChange: @MainActor @Sendable (Set<UUID>) -> Void

    func makeNSView(context: Context) -> RepoExplorerVisibleRowsObserverView {
        let view = RepoExplorerVisibleRowsObserverView()
        view.entries = entries
        view.onVisibleWorktreeIdsChange = onVisibleWorktreeIdsChange
        return view
    }

    func updateNSView(_ nsView: RepoExplorerVisibleRowsObserverView, context: Context) {
        nsView.entries = entries
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
            guard case .resolvedWorktreeRow(_, _, let worktreeId, _) = entry else { return }
            result.insert(worktreeId)
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
    static let focusTargetIdentifier = NSUserInterfaceItemIdentifier("repoExplorerFocusTarget")
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
