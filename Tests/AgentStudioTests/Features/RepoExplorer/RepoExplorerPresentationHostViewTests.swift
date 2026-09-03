import AppKit
import SwiftUI
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer production presentation host", .serialized)
struct RepoExplorerPresentationHostViewTests {
    @Test("isolated production mount registers one host and drives the real table acknowledgment")
    func productionMountDrivesRealTableAcknowledgment() async throws {
        let adapter = RepoExplorerProjectionAdapter()
        let visibleSnapshotRecorder = PresentationHostVisibleSnapshotRecorder()
        let hostingView = NSHostingView(
            rootView: AnyView(
                RepoExplorerPresentationHostView(
                    projectionAdapter: adapter,
                    octiconLoader: makeRepoExplorerTestOcticonLoader(),
                    onVisibleWorktreeSnapshotChange: visibleSnapshotRecorder.record
                )
                .frame(width: 320, height: 180)
            )
        )
        let window = makePresentationHostWindow(hostingView)
        defer {
            adapter.stop()
            window.close()
        }
        let host = try await registeredPresentationHost(adapter: adapter)
        let initialBaseline = try #require(host.acceptedBaseline)

        #expect(initialBaseline.presentation == .rowless(.noRepositories))
        #expect(initialBaseline.revision == 0)
        #expect(host.isPresentationReady)

        let request = makeProjectionIntentRequest(generation: 1)
        adapter.admit(request)
        let publishedResult = try await presentationHostPublishedResult(
            generation: 1,
            adapter: adapter
        )
        let contentBaseline = try #require(host.acceptedBaseline)
        let scrollView = try #require(host.presentedChildView as? NSScrollView)
        let tableView = try #require(scrollView.documentView as? NSTableView)

        #expect(contentBaseline.revision == 1)
        #expect(contentBaseline.presentation.rowCount == publishedResult.rowIndex.entries.count)
        #expect(tableView.numberOfRows == contentBaseline.rowCount)
        #expect(adapter.acknowledgedMaterializationBaseline == contentBaseline)

        for _ in 0..<10_000
        where visibleSnapshotRecorder.latest?.target.materializationGeneration
            != contentBaseline.visibleGeneration
        {
            await Task.yield()
        }
        let visibleSnapshot = try #require(visibleSnapshotRecorder.latest)
        let materializationSnapshot = try #require(contentBaseline.presentation.contentSnapshot)
        let repositoryID = try #require(materializationSnapshot.rowIDsByRepoID.keys.first)
        let repositoryRowID = try #require(materializationSnapshot.rowIDsByRepoID[repositoryID]?.first)
        let repositoryRowIndex = try #require(materializationSnapshot.rowIndexByID[repositoryRowID])
        let commandSnapshot = RepoExplorerCommandPresentationSnapshot(generation: 1, results: [:])
        hostingView.rootView = AnyView(
            RepoExplorerPresentationHostView(
                projectionAdapter: adapter,
                octiconLoader: makeRepoExplorerTestOcticonLoader(),
                commandPresentationDelta: RepoExplorerCommandPresentationDelta(
                    commandGeneration: 1,
                    target: visibleSnapshot.target,
                    snapshot: commandSnapshot,
                    affectedWorktreeIDs: [],
                    affectedRepositoryIDs: [repositoryID],
                    affectedRequestIdentities: [],
                    toolbarChanged: false
                ),
                onVisibleWorktreeSnapshotChange: visibleSnapshotRecorder.record
            )
            .frame(width: 320, height: 180)
        )
        hostingView.layoutSubtreeIfNeeded()
        for _ in 0..<20 { await Task.yield() }
        let commandBoundCell = try #require(
            tableView.view(
                atColumn: 0,
                row: repositoryRowIndex,
                makeIfNecessary: true
            ) as? RepoExplorerTableRowCell
        )
        #expect(commandBoundCell.currentCommandGeneration == 1)

        adapter.updateDemand(isVisible: false, query: "")
        let retainedRevision = host.acceptedBaseline?.revision
        #expect(!host.isPresentationReady)
        #expect(adapter.acknowledgedMaterializationBaseline == nil)

        adapter.updateDemand(isVisible: true, query: "")

        #expect(adapter.materializationHost === host)
        #expect(host.acceptedBaseline?.revision == retainedRevision)
        #expect(host.isPresentationReady)
        #expect(adapter.acknowledgedMaterializationBaseline == host.acceptedBaseline)
    }

    @Test("dismantle unregisters the matching lifetime before detaching the host")
    func dismantleUnregistersBeforeDetach() async throws {
        let adapter = RepoExplorerProjectionAdapter()
        let hostingView = NSHostingView(
            rootView: AnyView(
                RepoExplorerPresentationHostView(
                    projectionAdapter: adapter,
                    octiconLoader: makeRepoExplorerTestOcticonLoader(),
                    onVisibleWorktreeSnapshotChange: { _ in }
                )
                .frame(width: 320, height: 180)
            )
        )
        let window = makePresentationHostWindow(hostingView)
        defer {
            adapter.stop()
            window.close()
        }
        let host = try await registeredPresentationHost(adapter: adapter)
        let lifetimeID = host.lifetimeID

        hostingView.rootView = AnyView(EmptyView())
        hostingView.layoutSubtreeIfNeeded()
        for _ in 0..<10_000 where adapter.materializationHost != nil {
            await Task.yield()
        }

        #expect(adapter.materializationHost == nil)
        #expect(adapter.acknowledgedMaterializationBaseline == nil)
        adapter.unregisterMaterializationHost(lifetimeID: lifetimeID)
        #expect(adapter.materializationHost == nil)
    }
}

@MainActor
private final class PresentationHostVisibleSnapshotRecorder {
    private(set) var latest: RepoExplorerVisibleWorktreeSnapshot?

    func record(_ snapshot: RepoExplorerVisibleWorktreeSnapshot) {
        latest = snapshot
    }
}

extension RepoExplorerMaterializationPresentation {
    fileprivate var contentSnapshot: RepoExplorerMaterializationSnapshot? {
        guard case .content(let snapshot, _) = self else { return nil }
        return snapshot
    }
}

@MainActor
private func makePresentationHostWindow(_ hostingView: NSView) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.layoutIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    return window
}

@MainActor
private func registeredPresentationHost(
    adapter: RepoExplorerProjectionAdapter
) async throws -> RepoExplorerMaterializationHost {
    for _ in 0..<10_000 where adapter.materializationHost == nil {
        await Task.yield()
    }
    return try #require(adapter.materializationHost)
}

@MainActor
private func presentationHostPublishedResult(
    generation: Int,
    adapter: RepoExplorerProjectionAdapter
) async throws -> RepoExplorerProjectionResult {
    for _ in 0..<10_000 where adapter.publishedResult?.generation != generation {
        await Task.yield()
    }
    return try #require(adapter.publishedResult)
}
