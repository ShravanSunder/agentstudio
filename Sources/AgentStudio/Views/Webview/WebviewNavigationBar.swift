import SwiftUI
import WebKit

/// Mini browser toolbar with back/forward/reload and URL bar.
struct WebviewNavigationBar: View {
    @Bindable var controller: WebviewPaneController
    @State private var urlFieldText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            navigationButtons
            urlField
            progressIndicator
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .onChange(of: controller.url) { _, newURL in
            urlFieldText = newURL?.absoluteString ?? ""
        }
        .onAppear {
            urlFieldText = controller.url?.absoluteString ?? ""
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button { controller.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .disabled(!controller.canGoBack)
            .buttonStyle(.plain)
            .foregroundStyle(controller.canGoBack ? .primary : .quaternary)
            .keyboardShortcut("[", modifiers: .command)

            Button { controller.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .disabled(!controller.canGoForward)
            .buttonStyle(.plain)
            .foregroundStyle(controller.canGoForward ? .primary : .quaternary)
            .keyboardShortcut("]", modifiers: .command)

            if controller.isLoading {
                Button { controller.stopLoading() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
            } else {
                Button { controller.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    // MARK: - URL Field

    private var urlField: some View {
        HStack(spacing: 4) {
            SelectAllTextField(
                placeholder: "Enter URL",
                text: $urlFieldText,
                onSubmit: {
                    controller.navigate(to: urlFieldText)
                }
            )

            Button {
                controller.navigate(to: urlFieldText)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressIndicator: some View {
        if controller.isLoading {
            ProgressView(value: controller.estimatedProgress)
                .progressViewStyle(.linear)
                .frame(width: 60)
        }
    }
}
