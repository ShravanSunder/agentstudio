import AgentStudioCore

@MainActor
protocol TopologyEffectHandler: AnyObject {
    func topologyDidChange(_ delta: WorktreeTopologyDelta)
    func topologyDidChange(_ deltas: [WorktreeTopologyDelta])
}

extension TopologyEffectHandler {
    func topologyDidChange(_ deltas: [WorktreeTopologyDelta]) {
        for delta in deltas {
            topologyDidChange(delta)
        }
    }
}
