import SwiftUI
import WebKit

/// Root SwiftUI view for a webview pane.
/// Shows either the new-tab page (favorites + recent) or the active WebView.
struct WebviewPaneContentView: View {
    @Bindable var controller: WebviewPaneController

    private var isNewTabPage: Bool {
        controller.url == nil || controller.url?.scheme == "about"
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.showNavigation {
                WebviewNavigationBar(controller: controller)
                Divider()
            }

            if isNewTabPage {
                WebviewNewTabView { url in
                    controller.navigate(to: url.absoluteString)
                }
            } else {
                WebView(controller.page)
            }
        }
        .onChange(of: controller.isLoading) { wasLoading, isLoading in
            if wasLoading && !isLoading {
                controller.recordCurrentPage()
            }
        }
    }
}
