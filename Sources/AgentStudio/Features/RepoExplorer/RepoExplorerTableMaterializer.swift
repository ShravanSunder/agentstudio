import AgentStudioInfrastructure
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
    private(set) var hostedCellCreationCount = 0

    var numberOfRows: Int { snapshot?.rows.count ?? 0 }

    var currentTopVisibleAnchor: RepoExplorerTableScrollAnchor? {
        guard let snapshot, !snapshot.rows.isEmpty else { return nil }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let visibleRange = tableView.rows(in: visibleRect)
        guard visibleRange.location != NSNotFound else { return nil }
        var firstIntersectingAnchor: RepoExplorerTableScrollAnchor?
        for rowIndex in visibleRange.location..<NSMaxRange(visibleRange) {
            guard snapshot.rows.indices.contains(rowIndex) else { continue }
            let rowRect = tableView.rect(ofRow: rowIndex)
            guard rowRect.intersects(visibleRect) else { continue }
            let anchor = RepoExplorerTableScrollAnchor(
                rowID: snapshot.rows[rowIndex].id,
                offset: rowRect.minY - visibleRect.minY
            )
            if rowRect.minY >= visibleRect.minY, rowRect.maxY <= visibleRect.maxY {
                return anchor
            }
            if firstIntersectingAnchor == nil {
                firstIntersectingAnchor = anchor
            }
        }
        return firstIntersectingAnchor
    }

    private struct HeightCacheEntry {
        let contentRevision: RepoExplorerRowContentRevision
        let widthRevision: Int
        let height: CGFloat
    }

    private let tableView = NSTableView()
    private let scrollView: NSScrollView
    private let materializationHostLifetimeID: RepoExplorerMaterializationHostLifetimeID
    private let octiconLoader: OcticonLoader
    private let interactions: RepoExplorerTableInteractions
    private let measureVisibleRowHeight: VisibleRowHeightMeasurer
    private let onVisibleWorktreeSnapshotChange: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
    private let observeCurrentVisibleTarget: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
    private var snapshot: RepoExplorerMaterializationSnapshot?
    private var visibleGeneration: UInt64?
    private var viewportTask: Task<Void, Never>?
    private var viewportSequence: UInt64 = 0
    private var visibleRevision: UInt64 = 0
    private var currentVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot
    private var lastPublishedVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot?
    private var acceptedCommandPresentationSnapshot = RepoExplorerCommandPresentationSnapshot.empty
    private var acceptedCommandGeneration: UInt64 = 0
    private var heightByRowID: [RepoExplorerRowID: HeightCacheEntry] = [:]
    private var widthRevision = 0
    private var pendingReloadRows = IndexSet()
    private var pendingHeightRows = IndexSet()
    private var boundsObserver: NSObjectProtocol?
    private var menuTrackingObservers: [NSObjectProtocol] = []
    private weak var contextMenuSessionCell: RepoExplorerTableRowCell?
    private var contextMenuSessionBindingIdentity: RepoExplorerTableRowBindingIdentity?
    private var trackedContextMenuIdentities: Set<ObjectIdentifier> = []
    private var contextMenuSessionReleaseTask: Task<Void, Never>?
    private var contextMenuSessionSequence: UInt64 = 0
    private var isDetached = false
    private var isDemandActive = true

    init(
        materializationHostLifetimeID: RepoExplorerMaterializationHostLifetimeID =
            RepoExplorerMaterializationHostLifetimeID(
                rawValue: UUIDv7.generate()
            ),
        octiconLoader: OcticonLoader,
        interactions: RepoExplorerTableInteractions = .inert,
        onVisibleWorktreeSnapshotChange: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
        observeCurrentVisibleTarget: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void = { _ in },
        measureVisibleRowHeight: @escaping VisibleRowHeightMeasurer = { _, _ in nil }
    ) {
        self.materializationHostLifetimeID = materializationHostLifetimeID
        self.octiconLoader = octiconLoader
        self.interactions = interactions
        self.onVisibleWorktreeSnapshotChange = onVisibleWorktreeSnapshotChange
        self.observeCurrentVisibleTarget = observeCurrentVisibleTarget
        self.measureVisibleRowHeight = measureVisibleRowHeight
        currentVisibleSnapshot = RepoExplorerVisibleWorktreeSnapshot(
            target: RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: materializationHostLifetimeID,
                materializationGeneration: 0,
                visibleRevision: 0
            ),
            worktreeIDs: []
        )
        scrollView = NSScrollView(frame: .zero)
        view = scrollView
        super.init()

        scrollView.drawsBackground = false
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
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
        observeMenuTracking()
        updateTableFrame()
    }

    isolated deinit {
        menuTrackingObservers.forEach(NotificationCenter.default.removeObserver)
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

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row rowIndex: Int
    ) -> NSView? {
        guard let row = snapshot?.rows[safe: rowIndex], let visibleGeneration else {
            return nil
        }
        let cell: RepoExplorerTableRowCell
        if let reused = tableView.makeView(
            withIdentifier: RepoExplorerTableRowCell.reuseIdentifier,
            owner: self
        ) as? RepoExplorerTableRowCell {
            cell = reused
        } else {
            cell = RepoExplorerTableRowCell(
                octiconLoader: octiconLoader,
                interactions: interactions
            )
            hostedCellCreationCount += 1
        }
        if contextMenuSessionCell === cell,
            contextMenuSessionBindingIdentity?.rowID != row.id
        {
            cancelContextMenuSession()
        }
        cell.bind(
            row: row,
            visibleGeneration: visibleGeneration,
            commandPresentationSnapshot: acceptedCommandPresentationSnapshot
        )
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        tableView.deselectAll(nil)
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
        let priorVisibleGeneration = visibleGeneration
        let priorVisibleSnapshot = currentVisibleSnapshot
        let priorCommandSnapshot = acceptedCommandPresentationSnapshot
        let priorCommandGeneration = acceptedCommandGeneration
        let anchor = currentTopVisibleAnchor
        snapshot = candidate.snapshot
        visibleGeneration = candidate.visibleGeneration
        if priorVisibleGeneration != candidate.visibleGeneration {
            advanceVisibleTarget(
                materializationGeneration: candidate.visibleGeneration,
                worktreeIDs: priorVisibleSnapshot.worktreeIDs,
                repositoryIDs: priorVisibleSnapshot.repositoryIDs
            )
            acceptedCommandPresentationSnapshot = .empty
            acceptedCommandGeneration = 0
        }
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
            visibleGeneration = priorVisibleGeneration
            currentVisibleSnapshot = priorVisibleSnapshot
            acceptedCommandPresentationSnapshot = priorCommandSnapshot
            acceptedCommandGeneration = priorCommandGeneration
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
        invalidateScheduledViewportPublication()
        self.visibleGeneration = visibleGeneration
        advanceVisibleTarget(
            materializationGeneration: visibleGeneration,
            worktreeIDs: []
        )
        acceptedCommandPresentationSnapshot = .empty
        acceptedCommandGeneration = 0
        lastPublishedVisibleSnapshot = currentVisibleSnapshot
        onVisibleWorktreeSnapshotChange(currentVisibleSnapshot)
        clearRepresentedCellsForReuse()
        completion(.accepted)
    }

    func suspendDemand() {
        guard !isDetached, isDemandActive else { return }
        isDemandActive = false
        invalidateScheduledViewportPublication()
        clearRepresentedCellsForReuse()
        publishClearedViewportDemand()
    }

    func resumeDemand(visibleGeneration: UInt64) {
        guard !isDetached, !isDemandActive, self.visibleGeneration == visibleGeneration else { return }
        isDemandActive = true
        advanceVisibleTarget(
            materializationGeneration: visibleGeneration,
            worktreeIDs: currentVisibleSnapshot.worktreeIDs,
            repositoryIDs: currentVisibleSnapshot.repositoryIDs
        )
        acceptedCommandPresentationSnapshot = .empty
        acceptedCommandGeneration = 0
        rebindRepresentedCells()
        scheduleViewportPublication()
    }

    func detach() {
        guard !isDetached else { return }
        isDetached = true
        cancelContextMenuSession()
        invalidateScheduledViewportPublication()
        clearRepresentedCellsForReuse()
        clearViewportDemand()
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        menuTrackingObservers.forEach(NotificationCenter.default.removeObserver)
        menuTrackingObservers.removeAll(keepingCapacity: false)
        tableView.dataSource = nil
        tableView.delegate = nil
        scrollView.documentView = nil
        snapshot = nil
        heightByRowID.removeAll(keepingCapacity: false)
    }

    func menuDidBeginTracking(_ menuIdentity: ObjectIdentifier, clickedRow: Int) {
        guard !isDetached else { return }
        if let contextMenuSessionCell, let contextMenuSessionBindingIdentity {
            guard contextMenuSessionCell.currentBindingIdentity == contextMenuSessionBindingIdentity
            else {
                cancelContextMenuSession()
                return
            }
            contextMenuSessionSequence &+= 1
            contextMenuSessionReleaseTask?.cancel()
            contextMenuSessionReleaseTask = nil
            trackedContextMenuIdentities.insert(menuIdentity)
            contextMenuSessionCell.beginContextMenuTracking(menuIdentity)
            return
        }
        guard clickedRow >= 0, clickedRow < tableView.numberOfRows,
            let cell = tableView.view(
                atColumn: 0,
                row: clickedRow,
                makeIfNecessary: false
            ) as? RepoExplorerTableRowCell,
            let bindingIdentity = cell.currentBindingIdentity
        else { return }

        contextMenuSessionCell = cell
        contextMenuSessionBindingIdentity = bindingIdentity
        trackedContextMenuIdentities = [menuIdentity]
        contextMenuSessionSequence &+= 1
        cell.beginContextMenuTracking(menuIdentity)
    }

    func menuDidEndTracking(_ menuIdentity: ObjectIdentifier) {
        guard !isDetached, let contextMenuSessionCell,
            let contextMenuSessionBindingIdentity,
            contextMenuSessionCell.currentBindingIdentity == contextMenuSessionBindingIdentity
        else {
            cancelContextMenuSession()
            return
        }
        guard trackedContextMenuIdentities.remove(menuIdentity) != nil else { return }
        contextMenuSessionCell.endContextMenuTracking(menuIdentity)
        guard trackedContextMenuIdentities.isEmpty else { return }

        contextMenuSessionReleaseTask?.cancel()
        let scheduledSequence = contextMenuSessionSequence
        contextMenuSessionReleaseTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled,
                self.contextMenuSessionSequence == scheduledSequence,
                self.trackedContextMenuIdentities.isEmpty
            else { return }
            self.releaseContextMenuSession()
        }
    }

    func scroll(to rowID: RepoExplorerRowID, offset: CGFloat) {
        guard let rowIndex = snapshot?.rowIndexByID[rowID] else { return }
        scroll(toRowAt: rowIndex, offset: offset)
        scheduleViewportPublication()
    }

    func drainViewportPublication() async {
        await viewportTask?.value
    }

    func applyCommandPresentationDelta(
        _ delta: RepoExplorerCommandPresentationDelta
    ) -> RepoExplorerCommandPresentationDeltaDisposition {
        guard !isDetached, delta.target == currentVisibleSnapshot.target else {
            observeCurrentVisibleTarget(currentVisibleSnapshot)
            return .stale(currentVisibleSnapshot: currentVisibleSnapshot)
        }
        guard delta.commandGeneration > acceptedCommandGeneration else {
            return .duplicateOrOlderCommandGeneration
        }

        acceptedCommandPresentationSnapshot = delta.snapshot
        acceptedCommandGeneration = delta.commandGeneration
        var affectedRowIDs: Set<RepoExplorerRowID> = []
        if let snapshot {
            for worktreeID in delta.affectedWorktreeIDs {
                affectedRowIDs.formUnion(snapshot.rowIDsByWorktreeID[worktreeID] ?? [])
            }
            for repositoryID in delta.affectedRepositoryIDs {
                affectedRowIDs.formUnion(snapshot.rowIDsByRepoID[repositoryID] ?? [])
            }
        }
        let represented = representedRowIndexes()
        var reboundRowCount = 0
        for rowID in affectedRowIDs {
            guard let rowIndex = snapshot?.rowIndexByID[rowID], represented.contains(rowIndex),
                let cell = tableView.view(
                    atColumn: 0,
                    row: rowIndex,
                    makeIfNecessary: false
                ) as? RepoExplorerTableRowCell,
                let row = snapshot?.rows[safe: rowIndex],
                let visibleGeneration
            else { continue }
            cell.bind(
                row: row,
                visibleGeneration: visibleGeneration,
                commandPresentationSnapshot: acceptedCommandPresentationSnapshot
            )
            reboundRowCount += 1
        }
        return .accepted(reboundRowCount: reboundRowCount)
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
        if !visibleReloadRows.isEmpty {
            tableView.reloadData(
                forRowIndexes: visibleReloadRows,
                columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
            )
        }
        if !pendingHeightRows.isEmpty {
            tableView.noteHeightOfRows(withIndexesChanged: pendingHeightRows)
        }
        rebindRepresentedCells()
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

    private func observeMenuTracking() {
        menuTrackingObservers = [
            NotificationCenter.default.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                let menuIdentity = ObjectIdentifier(menu)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.menuDidBeginTracking(
                        menuIdentity,
                        clickedRow: self.tableView.clickedRow
                    )
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                let menuIdentity = ObjectIdentifier(menu)
                MainActor.assumeIsolated {
                    self?.menuDidEndTracking(menuIdentity)
                }
            },
        ]
    }

    private func cancelContextMenuSession() {
        contextMenuSessionSequence &+= 1
        contextMenuSessionReleaseTask?.cancel()
        contextMenuSessionReleaseTask = nil
        contextMenuSessionCell?.cancelContextMenuTracking()
        releaseContextMenuSession()
    }

    private func releaseContextMenuSession() {
        contextMenuSessionCell = nil
        contextMenuSessionBindingIdentity = nil
        trackedContextMenuIdentities.removeAll(keepingCapacity: false)
        contextMenuSessionReleaseTask = nil
    }

    private func scroll(toRowAt rowIndex: Int, offset: CGFloat) {
        guard tableView.numberOfRows > rowIndex else { return }
        let rowRect = tableView.rect(ofRow: rowIndex)
        let documentVisibleRect = scrollView.contentView.documentVisibleRect
        let maximumOriginY = max(0, tableView.bounds.height - documentVisibleRect.height)
        let requestedOriginY = rowRect.minY - offset
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

    private func invalidateScheduledViewportPublication() {
        viewportSequence &+= 1
        viewportTask?.cancel()
        viewportTask = nil
    }

    private func publishVisibleWorktreeIDs() {
        guard let snapshot else {
            clearViewportDemand()
            return
        }
        if let visibleGeneration {
            RepoExplorerNativeVisibleProjectionReadback.stampExpectedVisibleProjection(
                in: tableView,
                snapshot: snapshot,
                materializationGeneration: visibleGeneration
            )
        }
        let worktreeIDs = Set(
            representedRowIndexes().compactMap { rowIndex in
                snapshot.rows[safe: rowIndex]?.representedWorktreeID
            }
        )
        let repositoryIDs = Set(
            representedRowIndexes().compactMap { rowIndex -> UUID? in
                guard let row = snapshot.rows[safe: rowIndex],
                    case .groupHeader(let group) = row.presentation,
                    group.presentsRepositoryActivity,
                    group.repoIDs.count == 1
                else { return nil }
                return group.repoIDs[0]
            }
        )
        let settledUpdateAttemptByRepositoryID = Dictionary(
            uniqueKeysWithValues: representedRowIndexes().compactMap { rowIndex -> (UUID, UUID)? in
                guard let row = snapshot.rows[safe: rowIndex],
                    case .groupHeader(let group) = row.presentation,
                    group.presentsRepositoryActivity,
                    let progress = group.repositoryFactUpdateProgress,
                    progress.phase == .settled,
                    group.repoIDs == [progress.repoId]
                else { return nil }
                return (progress.repoId, progress.attemptId)
            }
        )
        if worktreeIDs != currentVisibleSnapshot.worktreeIDs
            || repositoryIDs != currentVisibleSnapshot.repositoryIDs
            || settledUpdateAttemptByRepositoryID
                != currentVisibleSnapshot.settledUpdateAttemptByRepositoryID
        {
            advanceVisibleTarget(
                materializationGeneration: visibleGeneration ?? 0,
                worktreeIDs: worktreeIDs,
                repositoryIDs: repositoryIDs,
                settledUpdateAttemptByRepositoryID: settledUpdateAttemptByRepositoryID
            )
        }
        guard lastPublishedVisibleSnapshot != currentVisibleSnapshot else { return }
        lastPublishedVisibleSnapshot = currentVisibleSnapshot
        onVisibleWorktreeSnapshotChange(currentVisibleSnapshot)
    }

    private func clearViewportDemand() {
        guard
            !currentVisibleSnapshot.worktreeIDs.isEmpty
                || !currentVisibleSnapshot.repositoryIDs.isEmpty
                || !currentVisibleSnapshot.settledUpdateAttemptByRepositoryID.isEmpty
        else {
            return
        }
        publishClearedViewportDemand()
    }

    private func publishClearedViewportDemand() {
        advanceVisibleTarget(
            materializationGeneration: visibleGeneration ?? 0,
            worktreeIDs: [],
            repositoryIDs: [],
            settledUpdateAttemptByRepositoryID: [:]
        )
        lastPublishedVisibleSnapshot = currentVisibleSnapshot
        onVisibleWorktreeSnapshotChange(currentVisibleSnapshot)
    }

    private func advanceVisibleTarget(
        materializationGeneration: UInt64,
        worktreeIDs: Set<UUID>,
        repositoryIDs: Set<UUID> = [],
        settledUpdateAttemptByRepositoryID: [UUID: UUID] = [:]
    ) {
        visibleRevision &+= 1
        currentVisibleSnapshot = RepoExplorerVisibleWorktreeSnapshot(
            target: RepoExplorerCommandPresentationTarget(
                materializationHostLifetimeID: materializationHostLifetimeID,
                materializationGeneration: materializationGeneration,
                visibleRevision: visibleRevision
            ),
            worktreeIDs: worktreeIDs,
            repositoryIDs: repositoryIDs,
            settledUpdateAttemptByRepositoryID: settledUpdateAttemptByRepositoryID
        )
    }

    private func representedRowIndexes() -> IndexSet {
        let range = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        guard range.location != NSNotFound, range.length > 0 else { return [] }
        let upperBound = min(NSMaxRange(range), numberOfRows)
        guard range.location < upperBound else { return [] }
        return IndexSet(integersIn: range.location..<upperBound)
    }

    private func rebindRepresentedCells() {
        guard let snapshot, let visibleGeneration else { return }
        for rowIndex in representedRowIndexes() {
            guard
                let cell = tableView.view(
                    atColumn: 0,
                    row: rowIndex,
                    makeIfNecessary: false
                ) as? RepoExplorerTableRowCell
            else {
                continue
            }
            cell.bind(
                row: snapshot.rows[rowIndex],
                visibleGeneration: visibleGeneration,
                commandPresentationSnapshot: acceptedCommandPresentationSnapshot
            )
        }
        RepoExplorerNativeVisibleProjectionReadback.stampExpectedVisibleProjection(
            in: tableView,
            snapshot: snapshot,
            materializationGeneration: visibleGeneration
        )
    }

    private func clearRepresentedCellsForReuse() {
        for rowIndex in representedRowIndexes() {
            guard
                let cell = tableView.view(
                    atColumn: 0,
                    row: rowIndex,
                    makeIfNecessary: false
                ) as? RepoExplorerTableRowCell
            else {
                continue
            }
            cell.clearBindingForReuse()
        }
    }

    private func updateTableFrame() {
        let fallbackContentHeight = snapshot?.fallbackContentHeight ?? 0
        let visibleMeasurementDelta = heightByRowID.reduce(into: CGFloat.zero) { delta, entry in
            guard let row = snapshot?.row(id: entry.key) else { return }
            delta += max(0, entry.value.height - row.layout.metrics.fallbackHeight)
        }
        let documentHeight = max(
            scrollView.contentView.bounds.height,
            fallbackContentHeight + visibleMeasurementDelta
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
