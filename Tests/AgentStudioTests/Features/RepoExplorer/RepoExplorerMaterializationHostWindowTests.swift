import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
private final class RowlessWindowContentChild: RepoExplorerMaterializationContentChild {
    let view = NSView()

    func apply(
        snapshot: RepoExplorerMaterializationSnapshot,
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        completion(.accepted)
    }

    func prepareForRemoval(
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    ) {
        completion(.accepted)
    }

    func detach() {}
}

@MainActor
@Suite("Repo Explorer materialization host window", .serialized)
struct RepoExplorerMaterializationHostWindowTests {
    @Test(
        "rowless presentation fills a real window and exposes its accessibility label",
        arguments: RepoExplorerRowlessPresentation.allCases
    )
    func rowlessPresentationLayoutAndAccessibility(
        presentation: RepoExplorerRowlessPresentation
    ) throws {
        let expectedSize = NSSize(width: 320, height: 480)
        let host = RepoExplorerMaterializationHost(
            lifetimeID: RepoExplorerMaterializationHostLifetimeID(
                rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            ),
            initialDemandEpoch: 1,
            initialPresentation: presentation,
            makeContentChild: { RowlessWindowContentChild() },
            onFeedback: { _ in }
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: expectedSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
        defer { window.close() }

        let rowlessView = try #require(host.presentedChildView)
        #expect(host.frame.size == expectedSize)
        #expect(rowlessView.frame == host.bounds)
        #expect(rowlessView.isAccessibilityElement())
        #expect(rowlessView.accessibilityRole() == .group)
        #expect(rowlessView.accessibilityLabel() == presentation.accessibilityLabel)
        #expect(host.visibleGeneration == 0)
        #expect(host.isPresentationReady)
    }

    @Test("rowless updates preserve an existing first responder")
    func rowlessUpdatePreservesFirstResponder() {
        let host = RepoExplorerMaterializationHost(
            lifetimeID: RepoExplorerMaterializationHostLifetimeID(
                rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
            ),
            initialDemandEpoch: 1,
            initialPresentation: .noRepositories,
            makeContentChild: { RowlessWindowContentChild() },
            onFeedback: { _ in }
        )
        let focusView = RepoExplorerFocusableView()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 480))
        container.addSubview(host)
        container.addSubview(focusView)
        host.frame = container.bounds
        focusView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        let window = NSWindow(
            contentRect: container.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        #expect(window.makeFirstResponder(focusView))

        let candidate = RepoExplorerMaterializationCandidate(
            id: RepoExplorerMaterializationCandidateID(rawValue: 1),
            lifetimeID: host.lifetimeID,
            demandEpoch: 1,
            visibleGeneration: 1,
            expectedRevision: 0,
            proposedRevision: 1,
            presentation: .rowless(.noTabs)
        )
        guard case .accepted = host.apply(candidate) else { return }

        #expect(window.firstResponder === focusView)
        #expect(host.presentedChildView?.accessibilityLabel() == "No tabs")
    }
}
