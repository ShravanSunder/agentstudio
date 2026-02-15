import Foundation
import WebKit
import Observation

/// Per-pane browser controller. Each webview pane owns one controller
/// that manages a single WebPage and exposes observable navigation state
/// for SwiftUI views.
@Observable
@MainActor
final class WebviewPaneController {

    // MARK: - State

    let paneId: UUID
    private(set) var page: WebPage
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

    var url: URL? { page.url }
    var title: String { page.title }
    var isLoading: Bool { page.isLoading }
    var estimatedProgress: Double { page.estimatedProgress }

    var canGoBack: Bool {
        !page.backForwardList.backList.isEmpty
    }

    var canGoForward: Bool {
        !page.backForwardList.forwardList.isEmpty
    }

    // MARK: - Init

    init(paneId: UUID, state: WebviewState) {
        self.paneId = paneId
        self.showNavigation = state.showNavigation
        self.page = WebPage(
            configuration: Self.sharedConfiguration,
            navigationDecider: WebviewNavigationDecider(),
            dialogPresenter: WebviewDialogHandler()
        )
        if state.url.scheme != "about" {
            _ = page.load(state.url)
        }
    }

    // MARK: - Navigation

    func goBack() {
        guard let backItem = page.backForwardList.backList.last else { return }
        _ = page.load(backItem)
    }

    func goForward() {
        guard let forwardItem = page.backForwardList.forwardList.first else { return }
        _ = page.load(forwardItem)
    }

    func reload() {
        _ = page.reload()
    }

    func stopLoading() {
        page.stopLoading()
    }

    /// Navigate to a URL string. Auto-prepends https:// for scheme-less input.
    func navigate(to urlString: String) {
        let normalized = Self.normalizeURLString(urlString)
        guard let url = URL(string: normalized) else { return }
        _ = page.load(url)
    }

    // MARK: - Persistence

    /// Capture current state back to serializable model.
    func snapshot() -> WebviewState {
        WebviewState(
            url: page.url ?? URL(string: "about:blank")!,
            title: page.title,
            showNavigation: showNavigation
        )
    }

    // MARK: - History

    /// Record the current page's URL and title in the URL history service.
    func recordCurrentPage() {
        guard let url = page.url,
              !page.isLoading else { return }
        URLHistoryService.shared.record(url: url, title: page.title)
    }

    // MARK: - URL Normalization

    static func normalizeURLString(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "about:blank" }
        if trimmed.contains("://") { return trimmed }
        if trimmed.hasPrefix("about:") || trimmed.hasPrefix("data:") { return trimmed }
        return "https://\(trimmed)"
    }
}
