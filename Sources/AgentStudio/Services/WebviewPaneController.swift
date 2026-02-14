import Foundation
import WebKit
import Observation

/// Per-pane browser tab manager. Each WebviewPaneView owns one controller
/// that manages an array of WebPage instances (tabs) and exposes observable
/// navigation state for SwiftUI views.
@Observable
@MainActor
final class WebviewPaneController {

    // MARK: - State

    let paneId: UUID
    private(set) var pages: [WebPage] = []
    var activeTabIndex: Int = 0
    var showNavigation: Bool
    var isFindPresented: Bool = false

    // MARK: - Shared Configuration

    /// All webview panes share the same persistent data store (cookies, local storage).
    static let sharedConfiguration: WebPage.Configuration = {
        var config = WebPage.Configuration()
        config.websiteDataStore = .default()
        return config
    }()

    // MARK: - Derived State

    var activePage: WebPage? {
        guard activeTabIndex >= 0, activeTabIndex < pages.count else { return nil }
        return pages[activeTabIndex]
    }

    var activeURL: URL? { activePage?.url }
    var activeTitle: String { activePage?.title ?? "" }
    var isLoading: Bool { activePage?.isLoading ?? false }
    var estimatedProgress: Double { activePage?.estimatedProgress ?? 0 }

    var canGoBack: Bool {
        guard let page = activePage else { return false }
        return !page.backForwardList.backList.isEmpty
    }

    var canGoForward: Bool {
        guard let page = activePage else { return false }
        return !page.backForwardList.forwardList.isEmpty
    }

    // MARK: - Init

    init(paneId: UUID, state: WebviewState) {
        self.paneId = paneId
        self.showNavigation = state.showNavigation
        // Pages are created after init so `self` is available for the new-tab callback
        self.activeTabIndex = 0
        self.pages = []

        self.pages = state.tabs.map { tab in
            let page = self.makePage()
            _ = page.load(tab.url)
            return page
        }
        self.activeTabIndex = min(state.activeTabIndex, max(pages.count - 1, 0))
    }

    // MARK: - Tab Operations

    @discardableResult
    func newTab(url: URL) -> WebPage {
        let page = makePage()
        _ = page.load(url)
        pages.append(page)
        activeTabIndex = pages.count - 1
        return page
    }

    func closeTab(at index: Int) {
        guard pages.count > 1, index >= 0, index < pages.count else { return }
        pages.remove(at: index)
        if activeTabIndex >= pages.count {
            activeTabIndex = pages.count - 1
        } else if activeTabIndex > index {
            activeTabIndex -= 1
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < pages.count else { return }
        activeTabIndex = index
    }

    // MARK: - Navigation

    func goBack() {
        guard let page = activePage,
              let backItem = page.backForwardList.backList.last else { return }
        _ = page.load(backItem)
    }

    func goForward() {
        guard let page = activePage,
              let forwardItem = page.backForwardList.forwardList.first else { return }
        _ = page.load(forwardItem)
    }

    func reload() {
        guard let page = activePage else { return }
        _ = page.reload()
    }

    func stopLoading() {
        activePage?.stopLoading()
    }

    /// Navigate the active tab to a URL string. Auto-prepends https:// for scheme-less input.
    func navigate(to urlString: String) {
        guard let page = activePage else { return }
        let normalized = Self.normalizeURLString(urlString)
        guard let url = URL(string: normalized) else { return }
        _ = page.load(url)
    }

    // MARK: - Persistence

    /// Capture current tab state back to serializable model.
    /// During active loads, `page.url` reflects the URL being loaded (the target),
    /// not the previous page. This ensures tabs restore to the correct URL on relaunch.
    func snapshot() -> WebviewState {
        let tabs = pages.map { page in
            WebviewTabState(
                url: page.url ?? URL(string: "about:blank")!,
                title: page.title
            )
        }
        return WebviewState(
            tabs: tabs,
            activeTabIndex: activeTabIndex,
            showNavigation: showNavigation
        )
    }

    // MARK: - URL Normalization

    static func normalizeURLString(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "about:blank" }
        if trimmed.contains("://") { return trimmed }
        if trimmed.hasPrefix("about:") || trimmed.hasPrefix("data:") { return trimmed }
        return "https://\(trimmed)"
    }

    // MARK: - Page Factory

    private func makePage() -> WebPage {
        let decider = WebviewNavigationDecider()
        decider.onNewTabRequested = { [weak self] url in
            self?.newTab(url: url)
        }
        let handler = WebviewDialogHandler()
        return WebPage(
            configuration: Self.sharedConfiguration,
            navigationDecider: decider,
            dialogPresenter: handler
        )
    }
}
