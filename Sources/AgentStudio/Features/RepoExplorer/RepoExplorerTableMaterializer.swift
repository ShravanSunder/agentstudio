import AppKit

struct RepoExplorerTableScrollAnchor: Equatable {
    let rowID: RepoExplorerRowID
    let offset: CGFloat
}

@MainActor
final class RepoExplorerTableMaterializer: NSObject,
    RepoExplorerMaterializationContentChild,
    RepoExplorerNativeTableTransactionTarget,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    typealias VisibleRowHeightMeasurer =
        @MainActor (
            RepoExplorerMaterializedRow,
            CGFloat
        ) -> CGFloat?

    let view: NSView
    private(set) var nativeTransactionApplyCount = 0

    var numberOfRows: Int { snapshot?.rows.count ?? 0 }

    var currentTopVisibleAnchor: RepoExplorerTableScrollAnchor? {
        guard let snapshot, !snapshot.rows.isEmpty else { return nil }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let visibleRange = tableView.rows(in: visibleRect)
        guard visibleRange.location != NSNotFound else { return nil }
        for rowIndex in visibleRange.location..<NSMaxRange(visibleRange) {
            guard snapshot.rows.indices.contains(rowIndex) else { continue }
            let rowRect = tableView.rect(ofRow: rowIndex)
            guard rowRect.minY >= visibleRect.minY, rowRect.maxY <= visibleRect.maxY else {
                continue
            }
            return RepoExplorerTableScrollAnchor(
                rowID: snapshot.rows[rowIndex].id,
                offset: rowRect.minY - visibleRect.minY
            )
        }
        return nil
    }

    private struct HeightCacheEntry {
        let contentRevision: RepoExplorerRowContentRevision
        let widthRevision: Int
        let height: CGFloat
    }

    private let tableView = NSTableView()
    private let scrollView: NSScrollView
    private let measureVisibleRowHeight: VisibleRowHeightMeasurer
    private let onVisibleWorktreeIDsChange: @MainActor (Set<UUID>) -> Void
    private var snapshot: RepoExplorerMaterializationSnapshot?
    private var visibleGeneration: UInt64?
    private var viewportTask: Task<Void, Never>?
    private var viewportSequence: UInt64 = 0
    private var lastPublishedVisibleWorktreeIDs: Set<UUID> = []
    private var heightByRowID: [RepoExplorerRowID: HeightCacheEntry] = [:]
    private var widthRevision = 0
    private var pendingReloadRows = IndexSet()
    private var pendingHeightRows = IndexSet()
    private var boundsObserver: NSObjectProtocol?
    private var isDetached = false

    init(
        onVisibleWorktreeIDsChange: @escaping @MainActor (Set<UUID>) -> Void,
        measureVisibleRowHeight: @escaping VisibleRowHeightMeasurer = { _, _ in nil }
    ) {
        self.onVisibleWorktreeIDsChange = onVisibleWorktreeIDsChange
        self.measureVisibleRowHeight = measureVisibleRowHeight
        scrollView = NSScrollView(frame: .zero)
        view = scrollView
        super.init()

        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.usesAutomaticRowHeights = false
        tableView.addTableColumn(
            NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repo-explorer-content"))
        )
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.boundsDidChange()
            }
        }
        updateTableFrame()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        numberOfRows
    }

    func tableView(
        _ tableView: NSTableView,
        objectValueFor tableColumn: NSTableColumn?,
        row: Int
    ) -> Any? {
        row
    }

    func tableView(_ tableView: NSTableView, heightOfRow rowIndex: Int) -> CGFloat {
        resolvedHeight(forRowAt: rowIndex)
    }

    func resolvedHeight(forRowAt rowIndex: Int) -> CGFloat {
        guard let row = snapshot?.rows[safe: rowIndex] else { return tableView.rowHeight }
        let fallbackHeight = max(row.layout.metrics.minimumHeight, row.layout.metrics.fallbackHeight)
        guard row.layout.requiresVisibleWidthMeasurement,
            representedRowIndexes().contains(rowIndex)
        else {
            return fallbackHeight
        }

        let currentWidthRevision = normalizedWidthRevision()
        if let cached = heightByRowID[row.id],
            cached.contentRevision == row.contentRevision,
            cached.widthRevision == currentWidthRevision
        {
            return cached.height
        }
        guard let measured = measureVisibleRowHeight(row, availableContentWidth(for: row)) else {
            return fallbackHeight
        }
        let height = max(row.layout.metrics.minimumHeight, measured)
        heightByRowID[row.id] = HeightCacheEntry(
            contentRevision: row.contentRevision,
            widthRevision: currentWidthRevision,
            height: height
        )
        return height
    }

    func apply(
        _ candidate: RepoExplorerMaterializationContentCandidate,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        guard !isDetached else {
            completion(.rejected)
            return
        }
        let priorSnapshot = snapshot
        let anchor = currentTopVisibleAnchor
        snapshot = candidate.snapshot
        visibleGeneration = candidate.visibleGeneration
        heightByRowID = heightByRowID.filter { candidate.snapshot.rowIndexByID[$0.key] != nil }
        updateWidthRevisionIfNeeded()
        updateTableFrame()

        nativeTransactionApplyCount += 1
        let didApply = RepoExplorerNativeTransactionApplier.apply(
            tablePlan: candidate.tableUpdatePlan,
            to: self
        )
        guard didApply, tableView.numberOfRows == candidate.snapshot.rows.count else {
            snapshot = priorSnapshot
            updateTableFrame()
            completion(.rejected)
            return
        }
        restore(
            anchor: anchor,
            tablePlan: candidate.tableUpdatePlan,
            priorSnapshot: priorSnapshot
        )
        scheduleViewportPublication()
        completion(.accepted)
    }

    func prepareForRemoval(
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        clearViewportDemand()
        completion(.accepted)
    }

    func detach() {
        guard !isDetached else { return }
        isDetached = true
        viewportTask?.cancel()
        viewportTask = nil
        clearViewportDemand()
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        tableView.dataSource = nil
        tableView.delegate = nil
        scrollView.documentView = nil
        snapshot = nil
        heightByRowID.removeAll(keepingCapacity: false)
    }

    func scroll(to rowID: RepoExplorerRowID, offset: CGFloat) {
        guard let rowIndex = snapshot?.rowIndexByID[rowID] else { return }
        scroll(toRowAt: rowIndex, offset: offset)
        scheduleViewportPublication()
    }

    func drainViewportPublication() async {
        await viewportTask?.value
    }

    func beginUpdates() {
        pendingReloadRows.removeAll()
        pendingHeightRows.removeAll()
        tableView.beginUpdates()
    }

    func removeRows(_ indexes: IndexSet) {
        tableView.removeRows(at: indexes, withAnimation: [])
    }

    func moveRow(from oldIndex: Int, to newIndex: Int) {
        tableView.moveRow(at: oldIndex, to: newIndex)
    }

    func insertRows(_ indexes: IndexSet) {
        tableView.insertRows(at: indexes, withAnimation: [])
    }

    func reloadRows(_ indexes: IndexSet) {
        pendingReloadRows.formUnion(indexes)
    }

    func noteHeightChanges(_ indexes: IndexSet) {
        pendingHeightRows.formUnion(indexes)
    }

    func endUpdates() {
        tableView.endUpdates()
        updateTableFrame()
        scrollView.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
        let represented = representedRowIndexes()
        let visibleReloadRows = pendingReloadRows.intersection(represented)
        let visibleHeightRows = pendingHeightRows.intersection(represented)
        if !visibleReloadRows.isEmpty {
            tableView.reloadData(
                forRowIndexes: visibleReloadRows,
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }
        if !visibleHeightRows.isEmpty {
            tableView.noteHeightOfRows(withIndexesChanged: visibleHeightRows)
        }
        pendingReloadRows.removeAll()
        pendingHeightRows.removeAll()
    }

    private func restore(
        anchor: RepoExplorerTableScrollAnchor?,
        tablePlan: RepoExplorerNativeTableUpdatePlan,
        priorSnapshot: RepoExplorerMaterializationSnapshot?
    ) {
        guard let anchor else { return }
        let targetRowID: RepoExplorerRowID?
        if snapshot?.rowIndexByID[anchor.rowID] != nil {
            targetRowID = anchor.rowID
        } else if case .membership(let membership) = tablePlan,
            priorSnapshot?.rowIndexByID[anchor.rowID] != nil
        {
            targetRowID = membership.anchorFallbacks.targetRowID(
                forRemovedRowID: anchor.rowID
            )
        } else {
            targetRowID = nil
        }
        guard let targetRowID else { return }
        scroll(to: targetRowID, offset: anchor.offset)
    }

    private func scroll(toRowAt rowIndex: Int, offset: CGFloat) {
        guard tableView.numberOfRows > rowIndex else { return }
        let rowRect = tableView.rect(ofRow: rowIndex)
        let documentVisibleRect = scrollView.contentView.documentVisibleRect
        let maximumOriginY = max(0, tableView.bounds.height - documentVisibleRect.height)
        let requestedOriginY = rowRect.minY - max(0, offset)
        scrollView.contentView.scroll(
            to: NSPoint(
                x: documentVisibleRect.minX,
                y: min(maximumOriginY, max(0, requestedOriginY))
            )
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.layoutSubtreeIfNeeded()
        tableView.layoutSubtreeIfNeeded()
    }

    private func boundsDidChange() {
        guard !isDetached else { return }
        let previousWidthRevision = widthRevision
        updateWidthRevisionIfNeeded()
        if widthRevision != previousWidthRevision {
            heightByRowID.removeAll(keepingCapacity: true)
            let visibleWrappingRows = IndexSet(
                representedRowIndexes().filter { rowIndex in
                    snapshot?.rows[safe: rowIndex]?.layout.requiresVisibleWidthMeasurement == true
                }
            )
            if !visibleWrappingRows.isEmpty {
                tableView.noteHeightOfRows(withIndexesChanged: visibleWrappingRows)
            }
        }
        scheduleViewportPublication()
    }

    private func scheduleViewportPublication() {
        guard !isDetached, let visibleGeneration else { return }
        viewportSequence &+= 1
        let scheduledSequence = viewportSequence
        viewportTask?.cancel()
        viewportTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled,
                self.viewportSequence == scheduledSequence,
                self.visibleGeneration == visibleGeneration
            else { return }
            self.publishVisibleWorktreeIDs()
        }
    }

    private func publishVisibleWorktreeIDs() {
        guard let snapshot else {
            clearViewportDemand()
            return
        }
        let worktreeIDs = Set(
            representedRowIndexes().compactMap { rowIndex in
                snapshot.rows[safe: rowIndex]?.representedWorktreeID
            }
        )
        guard worktreeIDs != lastPublishedVisibleWorktreeIDs else { return }
        lastPublishedVisibleWorktreeIDs = worktreeIDs
        onVisibleWorktreeIDsChange(worktreeIDs)
    }

    private func clearViewportDemand() {
        guard !lastPublishedVisibleWorktreeIDs.isEmpty else { return }
        lastPublishedVisibleWorktreeIDs = []
        onVisibleWorktreeIDsChange([])
    }

    private func representedRowIndexes() -> IndexSet {
        let range = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        guard range.location != NSNotFound, range.length > 0 else { return [] }
        let upperBound = min(NSMaxRange(range), numberOfRows)
        guard range.location < upperBound else { return [] }
        return IndexSet(integersIn: range.location..<upperBound)
    }

    private func updateTableFrame() {
        let documentHeight = max(
            scrollView.contentView.bounds.height,
            CGFloat(numberOfRows) * tableView.rowHeight
        )
        tableView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(scrollView.contentView.bounds.width, tableView.frame.width),
            height: documentHeight
        )
    }

    private func updateWidthRevisionIfNeeded() {
        widthRevision = normalizedWidthRevision()
    }

    private func normalizedWidthRevision() -> Int {
        let backingScale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        return Int((scrollView.contentView.bounds.width * backingScale).rounded())
    }

    private func availableContentWidth(for row: RepoExplorerMaterializedRow) -> CGFloat {
        max(
            0,
            scrollView.contentView.bounds.width
                - row.layout.metrics.leadingInset
                - row.layout.metrics.trailingInset
        )
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
