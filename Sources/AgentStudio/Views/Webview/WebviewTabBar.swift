import SwiftUI
import WebKit

/// Horizontal scrolling tab bar for webview panes.
/// Shown only when more than one tab is open.
struct WebviewTabBar: View {
    @Bindable var controller: WebviewPaneController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(controller.pages.enumerated()), id: \.offset) { index, page in
                    tabItem(index: index, page: page)
                }
                addButton
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func tabItem(index: Int, page: WebPage) -> some View {
        let isActive = index == controller.activeTabIndex

        Button {
            controller.selectTab(at: index)
        } label: {
            HStack(spacing: 4) {
                Text(tabTitle(for: page))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140)

                if controller.pages.count > 1 {
                    Button {
                        controller.closeTab(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : .secondary)
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button {
            controller.newTab(url: URL(string: "about:blank")!)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func tabTitle(for page: WebPage) -> String {
        let title = page.title
        if !title.isEmpty { return title }
        if let host = page.url?.host() { return host }
        return "New Tab"
    }
}
