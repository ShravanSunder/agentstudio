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
        let hostingView = NSHostingView(
            rootView: AnyView(
                RepoExplorerPresentationHostView(
                    projectionAdapter: adapter,
                    onVisibleWorktreeIDsChange: { _ in }
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
                    onVisibleWorktreeIDsChange: { _ in }
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
