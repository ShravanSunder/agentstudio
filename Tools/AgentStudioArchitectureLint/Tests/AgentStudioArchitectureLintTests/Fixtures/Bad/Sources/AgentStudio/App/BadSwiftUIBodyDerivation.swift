import SwiftUI

struct BadSwiftUIBodyDerivation: View {
    let dispatcher: CommandDispatcher
    let session: ResultSession
    let rows: [Int]
    let query: String

    var body: some View {
        let snapshot = session.snapshot(state: 1)
        return VStack {
            Text("\(dispatcher.canDispatch(1))")
            ForEach(rows.sorted(), id: \.self) { row in
                Text("\(row)")
            }
            Text("\(Dictionary(grouping: rows) { $0 % 2 }.count)")
            Text("\(BadCommandPresentation.resolve(command: 1, dispatcher: dispatcher))")
            content
                .padding()
            Text("\(snapshot)")
        }
    }

    private var content: some View {
        titleRow
    }

    private var titleRow: some View {
        Text("\(FuzzySearch.fuzzyMatch(pattern: query, in: "title") != nil)")
    }
}
