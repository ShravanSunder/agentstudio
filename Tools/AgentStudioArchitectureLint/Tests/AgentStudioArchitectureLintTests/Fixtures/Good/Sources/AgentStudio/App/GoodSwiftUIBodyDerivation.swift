import SwiftUI

struct GoodSwiftUIBodyDerivation: View {
    let dispatcher: CommandDispatcher
    let capability: CommandCapabilitySet
    let session: ResultSession
    let selectedRow: Int?
    let rowIds: [Int?]
    let sortedRows: [Int]

    var body: some View {
        VStack {
            Text(selectedRow.map { "\($0)" } ?? "")
            ForEach(rowIds.compactMap { $0 }, id: \.self) { row in
                Text("\(row)")
            }
            ForEach(sortedRows, id: \.self) { row in
                Text("\(row)")
            }
            Button("Run") {
                _ = dispatcher.canDispatch(1)
            }
            Button(action: { _ = session.snapshot(state: 1) }) {
                Text("Open")
            }
            SearchField(onEnter: { _ = session.snapshot(state: 1) })
            ToolbarButton(canDispatchCommand: { dispatcher.canDispatch($0) })
            Text("\(capability.canDispatch(1))")
                .onTapGesture {
                    _ = sortedRows.sorted()
                }
                .onChange(of: selectedRow) {
                    _ = sortedRows.filter { $0 > 0 }
                }
                .task {
                    _ = sortedRows.reduce(0, +)
                }
        }
    }
}
