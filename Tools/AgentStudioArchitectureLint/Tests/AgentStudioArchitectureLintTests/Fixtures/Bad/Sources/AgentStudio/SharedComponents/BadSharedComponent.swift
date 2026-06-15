import SwiftUI

@Observable
final class BadSharedComponentModel {}

struct BadSharedComponent {
    @State private var isExpanded = false
    @Atom(\.repoCache) private var repoCache

    func readAtom() {
        _ = atom(\.repoCache)
    }
}
