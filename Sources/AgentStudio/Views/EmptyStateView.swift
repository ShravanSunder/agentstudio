import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Terminals Open")
                .font(.title2)
                .fontWeight(.medium)

            Text("Double-click a worktree in the sidebar to open a terminal,\nor add a project to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 12) {
                Button("Add Project...") {
                    NotificationCenter.default.post(name: .addProjectRequested, object: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
