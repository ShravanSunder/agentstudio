import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ViewRegistryTests {
    @Test("renderTree with nil layout root returns empty tree")
    func renderTree_withNilLayoutRoot_returnsEmptyTree() {
        let registry = ViewRegistry()
        let tree = registry.renderTree(for: Layout())

        #expect(tree != nil)
        #expect(tree?.root == nil)
        #expect(tree?.isEmpty == true)
    }

    @Test("renderTree with single leaf returns leaf node")
    func renderTree_withSingleLeafLayout_returnsLeaf() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let view = PaneView(paneId: paneId)
        registry.register(view, for: paneId)

        let tree = registry.renderTree(for: Layout(paneId: paneId))

        #expect(tree != nil)
        #expect(tree?.isSplit == false)
        guard let tree else {
            Issue.record("Expected a rendered leaf tree")
            return
        }
        guard case .leaf(let rendered) = tree.root else {
            Issue.record("Expected leaf root node")
            return
        }
        #expect(rendered === view)
        #expect(rendered.paneId == paneId)
    }

    @Test("renderTree with missing leaf returns nil")
    func renderTree_withMissingLeafInSimpleLayout_returnsNil() {
        let registry = ViewRegistry()
        let layout = Layout(root: .leaf(paneId: UUID()))

        #expect(registry.renderTree(for: layout) == nil)
    }

    @Test("renderTree split preserves split id and ratio")
    func renderTree_withSplitPreservesSplitId() {
        let registry = ViewRegistry()
        let leftPaneId = UUID()
        let rightPaneId = UUID()
        let splitId = UUID()

        registry.register(PaneView(paneId: leftPaneId), for: leftPaneId)
        registry.register(PaneView(paneId: rightPaneId), for: rightPaneId)

        let layout = Layout(
            root: .split(
                Layout.Split(
                    id: splitId,
                    direction: .horizontal,
                    ratio: 0.66,
                    left: .leaf(paneId: leftPaneId),
                    right: .leaf(paneId: rightPaneId)
                )))

        let tree = registry.renderTree(for: layout)

        #expect(tree != nil)
        guard case .split(let renderedSplit) = tree?.root else {
            Issue.record("Expected split root node")
            return
        }
        #expect(renderedSplit.id == splitId)
        #expect(renderedSplit.ratio == 0.66)
    }

    @Test("unregister removes pane from registry")
    func unregister_existingPane_removesFromRegistry() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let view = PaneView(paneId: paneId)

        registry.register(view, for: paneId)
        #expect(registry.registeredPaneIds.contains(paneId))
        #expect(registry.view(for: paneId) != nil)

        registry.unregister(paneId)

        #expect(!registry.registeredPaneIds.contains(paneId))
        #expect(registry.view(for: paneId) == nil)
    }

    @Test("register replaces an existing pane view for the same id")
    func register_replacesExistingPaneViewForSamePaneId() {
        let registry = ViewRegistry()
        let paneId = UUID()
        let original = PaneView(paneId: paneId)
        let replacement = PaneView(paneId: paneId)

        registry.register(original, for: paneId)
        #expect(registry.view(for: paneId) === original)
        registry.register(replacement, for: paneId)

        #expect(registry.view(for: paneId) === replacement)
        #expect(registry.view(for: paneId) !== original)
    }

    @Test("renderTree returns split tree when all branches registered")
    func renderTree_withAllViewsRegistered_returnsSplitTree() {
        let registry = ViewRegistry()
        let leftPaneId = UUID()
        let rightPaneId = UUID()

        let leftView = PaneView(paneId: leftPaneId)
        let rightView = PaneView(paneId: rightPaneId)
        registry.register(leftView, for: leftPaneId)
        registry.register(rightView, for: rightPaneId)

        let layout = Layout(
            root: .split(
                Layout.Split(
                    direction: .horizontal,
                    ratio: 0.5,
                    left: .leaf(paneId: leftPaneId),
                    right: .leaf(paneId: rightPaneId)
                )))

        let tree = registry.renderTree(for: layout)
        #expect(tree != nil)

        guard let tree else {
            Issue.record("Expected a rendered PaneSplitTree")
            return
        }
        guard case .split(let rootSplit) = tree.root else {
            Issue.record("Expected split root node")
            return
        }

        #expect(rootSplit.direction == .horizontal)
        #expect(rootSplit.ratio == 0.5)

        let orderedViews = tree.allViews.compactMap { $0.paneId }
        #expect(orderedViews.count == 2)
        #expect(orderedViews == [leftPaneId, rightPaneId])
    }

    @Test("renderTree promotes non-missing branch when one side is missing")
    func renderTree_withMissingChild_promotesRemainingBranch() {
        let registry = ViewRegistry()
        let presentPaneId = UUID()
        let missingPaneId = UUID()
        let presentView = PaneView(paneId: presentPaneId)
        registry.register(presentView, for: presentPaneId)

        let layout = Layout(
            root: .split(
                Layout.Split(
                    direction: .horizontal,
                    ratio: 0.5,
                    left: .leaf(paneId: missingPaneId),
                    right: .leaf(paneId: presentPaneId)
                )))

        let tree = registry.renderTree(for: layout)

        #expect(tree != nil)
        guard let tree else {
            Issue.record("Expected a rendered tree after promotion")
            return
        }
        guard case .leaf(let view) = tree.root else {
            Issue.record("Expected promoted leaf root node")
            return
        }
        #expect(view === presentView)
    }

    @Test("renderTree returns nil when all split children are missing")
    func renderTree_withAllMissingChildren_returnsNil() {
        let registry = ViewRegistry()
        let missingLeft = UUID()
        let missingRight = UUID()
        let layout = Layout(
            root: .split(
                Layout.Split(
                    direction: .vertical,
                    ratio: 0.5,
                    left: .leaf(paneId: missingLeft),
                    right: .leaf(paneId: missingRight)
                )))

        #expect(registry.renderTree(for: layout) == nil)
    }

    @Test("renderTree deep missing branches promote a surviving leaf")
    func renderTree_deepPromotion_whenNestedChildrenMissing() {
        let registry = ViewRegistry()
        let leafId = UUID()
        let missingId = UUID()

        let presentView = PaneView(paneId: leafId)
        registry.register(presentView, for: leafId)

        let layout = Layout(
            root: .split(
                Layout.Split(
                    direction: .horizontal,
                    ratio: 0.5,
                    left: .split(
                        Layout.Split(
                            direction: .vertical,
                            ratio: 0.7,
                            left: .leaf(paneId: missingId),
                            right: .leaf(paneId: missingId)
                        )),
                    right: .leaf(paneId: leafId)
                )))

        let tree = registry.renderTree(for: layout)

        #expect(tree != nil)
        guard let tree else {
            Issue.record("Expected deep promotion to preserve registered leaf")
            return
        }
        guard case .leaf(let view) = tree.root else {
            Issue.record("Expected nested-missing branch to promote surviving leaf")
            return
        }
        #expect(view === presentView)
    }

    @Test("allWebviewViews returns only webview panes")
    func allWebviewViews_returnsOnlyWebviewViewsInRegistry() {
        let registry = ViewRegistry()
        let terminalPaneId = UUID()
        let webviewPaneId = UUID()
        let normalPaneId = UUID()

        registry.register(PaneView(paneId: terminalPaneId), for: terminalPaneId)
        registry.register(
            WebviewPaneView(
                paneId: webviewPaneId,
                state: WebviewState(url: URL(string: "https://example.com")!)
            ),
            for: webviewPaneId
        )
        registry.register(PaneView(paneId: normalPaneId), for: normalPaneId)

        let allWebviews = registry.allWebviewViews

        #expect(allWebviews.count == 1)
        #expect(allWebviews[webviewPaneId] != nil)
        #expect(allWebviews[terminalPaneId] == nil)
    }
}
