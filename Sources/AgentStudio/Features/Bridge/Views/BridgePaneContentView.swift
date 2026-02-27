import SwiftUI
import WebKit

/// SwiftUI view wrapping the bridge pane's WebView.
///
/// Unlike `WebviewPaneContentView`, this has **no navigation bar** — bridge panes
/// display a fixed bundled React app and never navigate to external URLs.
/// The `WebView` renders the `WebPage` owned by `BridgePaneController`.
struct BridgePaneContentView: View {
    @Bindable var controller: BridgePaneController

    var body: some View {
        WebView(controller.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
