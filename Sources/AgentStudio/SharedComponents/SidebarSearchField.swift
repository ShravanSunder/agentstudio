import SwiftUI

struct SidebarSearchField<FocusValue: Hashable>: View {
    @Binding var text: String

    let placeholder: String
    let focusedField: FocusState<FocusValue?>.Binding
    let focusValue: FocusValue
    let clearHelp: String?
    let onSubmit: () -> Void
    let onExit: () -> Void
    let onDownArrow: (() -> KeyPress.Result)?

    init(
        placeholder: String,
        text: Binding<String>,
        focusedField: FocusState<FocusValue?>.Binding,
        focusValue: FocusValue,
        clearHelp: String? = nil,
        onSubmit: @escaping () -> Void = {},
        onExit: @escaping () -> Void = {},
        onDownArrow: (() -> KeyPress.Result)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.focusedField = focusedField
        self.focusValue = focusValue
        self.clearHelp = clearHelp
        self.onSubmit = onSubmit
        self.onExit = onExit
        self.onDownArrow = onDownArrow
    }

    var body: some View {
        HStack(spacing: AppStyles.Shell.Sidebar.SearchField.contentSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppStyles.Shell.Sidebar.SearchField.iconSize))
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: AppStyles.Shell.Sidebar.SearchField.textSize))
                .foregroundStyle(.primary)
                .focused(focusedField, equals: focusValue)
                .onSubmit {
                    onSubmit()
                }
                .onExitCommand {
                    onExit()
                }
                .onKeyPress(.downArrow) {
                    onDownArrow?() ?? .ignored
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppStyles.Shell.Sidebar.SearchField.textSize))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(clearHelp ?? "")
                .transition(
                    .opacity.animation(
                        .easeOut(duration: AppStyles.Shell.Sidebar.SearchField.clearTransitionDuration)
                    )
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppStyles.Shell.Sidebar.SearchField.horizontalPadding)
        .padding(.vertical, AppStyles.Shell.Sidebar.SearchField.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.SearchField.cornerRadius)
                .fill(Color.primary.opacity(AppStyles.Shell.Sidebar.SearchField.backgroundOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppStyles.Shell.Sidebar.SearchField.cornerRadius)
                .strokeBorder(
                    Color.primary.opacity(AppStyles.Shell.Sidebar.SearchField.borderOpacity),
                    lineWidth: AppStyles.Shell.Sidebar.SearchField.borderWidth
                )
        )
    }
}
