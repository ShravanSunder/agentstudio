import SwiftUI

@Observable
final class SharedComponentInteractionModel {
    var isExpanded = false
}

struct GoodSharedComponent: View {
    let title: String
    @Binding var isSelected: Bool
    @ObservedObject var legacyObservableModel: SharedLegacyObservableModel
    let interactionModel: SharedComponentInteractionModel
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
    }
}

final class SharedLegacyObservableModel: ObservableObject {
    @Published var isHovered = false
}
