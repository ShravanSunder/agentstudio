import SwiftUI

struct GoodValueView: View {
    let value: Int

    var body: some View {
        Text("\(value)")
    }
}

struct GoodSortedValueModel {
    let items: [Int]

    var value: [Int] {
        items.sorted()
    }
}
