import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    var pendingBridgePaneRetirementCount: Int {
        bridgePaneRetirementTasksByPaneId.count
    }

    func drainBridgePaneRetirements() async {
        while !bridgePaneRetirementTasksByPaneId.isEmpty {
            let retirementTasks = Array(bridgePaneRetirementTasksByPaneId.values)
            for retirementTask in retirementTasks {
                await retirementTask.value
            }
        }
    }

    func startTrackedBridgePaneRetirement(
        paneId: UUID,
        controller: BridgePaneController,
        shouldUnregisterRuntime: Bool
    ) {
        recordBridgePaneRetirementDisposition(
            paneId: paneId,
            shouldUnregisterRuntime: shouldUnregisterRuntime
        )
        guard bridgePaneRetirementTasksByPaneId[paneId] == nil else { return }
        let initialRetirementAttempt = controller.teardown()
        let retirementTask = Task { @MainActor [self, controller] in
            var retirementAttempt = initialRetirementAttempt
            while !(await retirementAttempt.value) {
                await Task.yield()
                retirementAttempt = controller.teardown()
            }
            let shouldUnregisterRuntime =
                bridgePaneRetirementsRequiringRuntimeUnregister.contains(paneId)
            finishViewTeardown(
                paneId: paneId,
                shouldUnregisterRuntime: shouldUnregisterRuntime,
                retiringBridgeController: controller,
                replayEvictionPolicy: shouldUnregisterRuntime ? .callerManaged : .schedule
            )
            if shouldUnregisterRuntime, UUIDv7.isV7(paneId) {
                let runtimePaneId = PaneId(uuid: paneId)
                await paneEventBus.evictReplay(sourceKey: EventSource.pane(runtimePaneId).description)
            }
            bridgePaneRetirementTasksByPaneId.removeValue(forKey: paneId)
            bridgePaneRetirementsRequiringRuntimeUnregister.remove(paneId)
            let shouldRestore = bridgePaneRetirementsRequiringRestore.remove(paneId) != nil
            if shouldRestore {
                restoreBridgePaneAfterRetirementIfNeeded(paneId: paneId)
            }
        }
        bridgePaneRetirementTasksByPaneId[paneId] = retirementTask
        refreshBridgePaneActivities()
    }

    func recordBridgePaneRetirementDisposition(
        paneId: UUID,
        shouldUnregisterRuntime: Bool
    ) {
        if shouldUnregisterRuntime {
            bridgePaneRetirementsRequiringRuntimeUnregister.insert(paneId)
            bridgePaneRetirementsRequiringRestore.remove(paneId)
        } else if !bridgePaneRetirementsRequiringRuntimeUnregister.contains(paneId) {
            bridgePaneRetirementsRequiringRestore.insert(paneId)
        }
    }

    private func restoreBridgePaneAfterRetirementIfNeeded(paneId: UUID) {
        guard let pane = store.paneAtom.pane(paneId),
            case .bridgePanel = pane.content,
            store.tabLayoutAtom.tabContaining(paneId: pane.parentPaneId ?? pane.id) != nil,
            viewRegistry.view(for: paneId) == nil
        else { return }
        _ = createViewForContent(pane: pane)
    }
}
