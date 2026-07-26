import Testing

@testable import AgentStudio

actor BackgroundAtomMutator {
    func paneCount() async -> Int {
        await MainActor.run {
            CoreAtomScope.store.workspacePane.panes.count
        }
    }

    func addPane(_ pane: Pane) async {
        await MainActor.run {
            CoreAtomScope.store.workspacePane.addPane(pane)
        }
    }
}

@MainActor
struct CoreAtomScopeTests {
    @Test
    func overrideStore_winsWithinScopedBlock_only() async throws {
        installTestCoreAtomsIfNeeded()
        let production = CoreAtomScope.store
        let override = makeInstalledTestCoreAtoms()
        #expect(CoreAtomScope.store === production)

        CoreAtomScope.$override.withValue(override) {
            #expect(CoreAtomScope.store === override)
        }

        #expect(CoreAtomScope.store === production)
    }

    @Test
    func task_inheritsOverrideStore() async {
        installTestCoreAtomsIfNeeded()
        let override = makeInstalledTestCoreAtoms()

        let inherited = await CoreAtomScope.$override.withValue(override) {
            await Task { @MainActor in
                CoreAtomScope.store === override
            }.value
        }

        #expect(inherited)
    }

    @Test
    func asyncLet_inheritsOverrideStore() async {
        installTestCoreAtomsIfNeeded()
        let override = makeInstalledTestCoreAtoms()

        let inherited = await CoreAtomScope.$override.withValue(override) {
            async let child: Bool = MainActor.run {
                CoreAtomScope.store === override
            }
            return await child
        }

        #expect(inherited)
    }

    @Test
    func withTaskGroup_inheritsOverrideStore() async {
        installTestCoreAtomsIfNeeded()
        let override = makeInstalledTestCoreAtoms()

        let inherited = await CoreAtomScope.$override.withValue(override) {
            await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
                group.addTask { @MainActor in
                    CoreAtomScope.store === override
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
        installTestCoreAtomsIfNeeded()
        let production = CoreAtomScope.store
        let override = makeInstalledTestCoreAtoms()

        let inheritsOverride = await CoreAtomScope.$override.withValue(override) {
            // swiftlint:disable:next no_task_detached
            await Task.detached {
                await MainActor.run { CoreAtomScope.store === override }
            }.value
        }
        let seesProduction = await CoreAtomScope.$override.withValue(override) {
            // swiftlint:disable:next no_task_detached
            await Task.detached {
                await MainActor.run { CoreAtomScope.store === production }
            }.value
        }

        #expect(!inheritsOverride)
        #expect(seesProduction)
    }

    @Test
    func concurrentSiblingTask_doesNotSeeScopedOverride() async {
        installTestCoreAtomsIfNeeded()
        let production = CoreAtomScope.store
        let override = makeInstalledTestCoreAtoms()

        let result = await withTaskGroup(of: (String, Bool).self, returning: [String: Bool].self) { group in
            group.addTask {
                let seesOverride = await CoreAtomScope.$override.withValue(override) {
                    await Task { @MainActor in
                        CoreAtomScope.store === override
                    }.value
                }
                return ("override", seesOverride)
            }

            group.addTask { @MainActor in
                ("sibling", CoreAtomScope.store === production)
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
        installTestCoreAtomsIfNeeded()
        let production = CoreAtomScope.store
        let override = makeInstalledTestCoreAtoms()

        let closure = CoreAtomScope.$override.withValue(override) {
            { @MainActor in CoreAtomScope.store }
        }

        let resolved = closure()
        #expect(resolved === production)
    }

    @Test
    func freeAtomAccess_resolvesSameWorkspaceInstance() async {
        installTestCoreAtomsIfNeeded()
        let override = makeInstalledTestCoreAtoms()

        CoreAtomScope.$override.withValue(override) {
            #expect(CoreAtomScope.store.workspaceRepositoryTopology === override.workspaceRepositoryTopology)
            #expect(CoreAtomScope.store.workspacePane === override.workspacePane)
            #expect(atom(\.workspaceRepositoryTopology) === override.workspaceRepositoryTopology)
            #expect(atom(\.workspacePane) === override.workspacePane)
        }
    }

    @Test
    func backgroundActor_mutatesAtomsOnlyViaExplicitMainActorHop() async {
        installTestCoreAtomsIfNeeded()
        let override = makeInstalledTestCoreAtoms()

        await CoreAtomScope.$override.withValue(override) {
            let worker = BackgroundAtomMutator()
            let pane = Pane(
                content: .terminal(
                    TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())
                ),
                metadata: PaneMetadata(
                    title: "Background Hop"
                )
            )

            #expect(await worker.paneCount() == 0)
            await worker.addPane(pane)
            #expect(await worker.paneCount() == 1)
        }
    }
}
