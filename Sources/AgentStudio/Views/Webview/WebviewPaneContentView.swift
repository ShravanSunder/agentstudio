import SwiftUI
import WebKit

/// Root SwiftUI view for a webview pane.
/// Composes the tab bar, navigation toolbar, and the active WebView.
struct WebviewPaneContentView: View {
    @Bindable var controller: WebviewPaneController

    var body: some View {
        VStack(spacing: 0) {
            if controller.pages.count > 1 {
                WebviewTabBar(controller: controller)
                Divider()
            }

            if controller.showNavigation {
                WebviewNavigationBar(controller: controller)
                Divider()
            }

            if let activePage = controller.activePage {
                WebView(activePage)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Color.clear
            .overlay {
                Text("No page loaded")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
    }
}
