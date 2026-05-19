import SwiftUI

struct PaneOrdinalBadge: View {
    let ordinal: Int

    var body: some View {
        Text("\(ordinal)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(minWidth: 18, minHeight: 18)
            .background(.thinMaterial, in: Circle())
            .overlay(Circle().stroke(.separator.opacity(0.55), lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
