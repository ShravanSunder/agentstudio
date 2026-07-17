import SwiftUI

struct BadSharedComponent {
    @Atom(\.repoCache) private var repoCache
    @StateObject private var ownedStore = BadSharedComponentStore()
    @EnvironmentObject private var environmentStore: BadSharedComponentStore
    @Environment(\.workspaceStore) private var workspaceStore
    @Environment(\.atomScope) private var atomScope
    let injectedStore: WorkspaceStore
    let registry: AtomRegistry

    func readAtom() {
        _ = atom(\.repoCache)
        _ = AtomReader.self
    }
}

final class BadSharedComponentStore {}
