import SwiftUI

@Observable
final class SharedComponentInteractionModel {
    var isExpanded = false
}

struct GoodSharedComponent: View {
    @Environment(\.storefront) private var storefront
    let title: String
    @Binding var isSelected: Bool
    let interactionModel: SharedComponentInteractionModel
    let action: () -> Void

    var body: some View {
        Button("\(storefront): \(title)", action: action)
    }
}
