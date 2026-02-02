import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if sessionManager.openTabs.isEmpty {
                EmptyStateView()
            } else {
                TerminalTabsView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
