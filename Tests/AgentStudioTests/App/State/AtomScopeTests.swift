import Testing

@testable import AgentStudio

@MainActor
private struct WorkspaceAtomFixture {
    @Atom(\.workspaceRepositoryTopology) var workspaceRepositoryTopology
    @Atom(\.workspacePane) var workspacePane
}

actor BackgroundAtomMutator {
    func paneCount() async -> Int {
        await MainActor.run {
            AtomScope.store.workspacePane.panes.count
        }
    }

    func addPane(_ pane: Pane) async {
        await MainActor.run {
            AtomScope.store.workspacePane.addPane(pane)
        }
    }
}

@MainActor
struct AtomScopeTests {
    @Test
    func overrideStore_winsWithinScopedBlock_only() async throws {
        installTestAtomScopeIfNeeded()
        let production = AtomScope.store
        let override = AtomStore()
        #expect(AtomScope.store === production)

        AtomScope.$override.withValue(override) {
            #expect(AtomScope.store === override)
        }

        #expect(AtomScope.store === production)
    }

    @Test
    func task_inheritsOverrideStore() async {
        installTestAtomScopeIfNeeded()
        let override = AtomStore()

        let inherited = await AtomScope.$override.withValue(override) {
            await Task { @MainActor in
                AtomScope.store === override
            }.value
        }

        #expect(inherited)
    }

    @Test
    func asyncLet_inheritsOverrideStore() async {
        installTestAtomScopeIfNeeded()
        let override = AtomStore()

        let inherited = await AtomScope.$override.withValue(override) {
            async let child: Bool = MainActor.run {
                AtomScope.store === override
            }
            return await child
        }

        #expect(inherited)
    }

    @Test
    func withTaskGroup_inheritsOverrideStore() async {
        installTestAtomScopeIfNeeded()
        let override = AtomStore()

        let inherited = await AtomScope.$override.withValue(override) {
            await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                group.addTask { @MainActor in
                    AtomScope.store === override
                }
                var allInherited = true
                while let next = await group.next() {
                    allInherited = allInherited && next
                }
                return allInherited
            }
        }

        #expect(inherited)
    }

    @Test
    func detachedTask_doesNotInheritOverrideStore() async {
        installTestAtomScopeIfNeeded()
        let production = AtomScope.store
        let override = AtomStore()

        let inheritsOverride = await AtomScope.$override.withValue(override) {
            // swiftlint:disable:next no_task_detached
            await Task.detached {
                await MainActor.run { AtomScope.store === override }
            }.value
        }
        let seesProduction = await AtomScope.$override.withValue(override) {
            // swiftlint:disable:next no_task_detached
            await Task.detached {
                await MainActor.run { AtomScope.store === production }
            }.value
        }

        #expect(!inheritsOverride)
        #expect(seesProduction)
    }

    @Test
    func concurrentSiblingTask_doesNotSeeScopedOverride() async {
        installTestAtomScopeIfNeeded()
        let production = AtomScope.store
        let override = AtomStore()

        let result = await withTaskGroup(of: (String, Bool).self, returning: [String: Bool].self) { group in
            group.addTask {
                let seesOverride = await AtomScope.$override.withValue(override) {
                    await Task { @MainActor in
                        AtomScope.store === override
                    }.value
                }
                return ("override", seesOverride)
            }

            group.addTask { @MainActor in
                ("sibling", AtomScope.store === production)
            }

            var results: [String: Bool] = [:]
            while let next = await group.next() {
                results[next.0] = next.1
            }
            return results
        }

        #expect(result["override"] == true)
        #expect(result["sibling"] == true)
    }

    @Test
    func escapedClosure_usesCurrentScopeWhenInvoked() async {
        installTestAtomScopeIfNeeded()
        let production = AtomScope.store
        let override = AtomStore()

        let closure = AtomScope.$override.withValue(override) {
            { @MainActor in AtomScope.store }
        }

        let resolved = closure()
        #expect(resolved === production)
    }

    @Test
    func atomPropertyWrapper_resolvesSameWorkspaceInstance() async {
        installTestAtomScopeIfNeeded()
        let override = AtomStore()

        AtomScope.$override.withValue(override) {
            let fixture = WorkspaceAtomFixture()
            #expect(AtomScope.store.workspaceRepositoryTopology === override.workspaceRepositoryTopology)
            #expect(AtomScope.store.workspacePane === override.workspacePane)
            #expect(fixture.workspaceRepositoryTopology === override.workspaceRepositoryTopology)
            #expect(fixture.workspacePane === override.workspacePane)
        }
    }

    @Test
    func backgroundActor_mutatesAtomsOnlyViaExplicitMainActorHop() async {
        installTestAtomScopeIfNeeded()
        let override = AtomStore()

        await AtomScope.$override.withValue(override) {
            let worker = BackgroundAtomMutator()
            let pane = Pane(
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: PaneMetadata(
                    source: .floating(launchDirectory: nil, title: nil),
                    title: "Background Hop"
                )
            )

            #expect(await worker.paneCount() == 0)
            await worker.addPane(pane)
            #expect(await worker.paneCount() == 1)
        }
    }
}
