extension BridgePaneController {
    // MARK: - Push Plan Factories

    func makeDiffPushPlan() -> PushPlan<DiffState> {
        PushPlan(
            state: paneState.diff,
            transport: self,
            revisions: revisionClock,
            epoch: { [paneState] in paneState.diff.epoch },
            slices: {
                Slice("diffStatus", telemetrySlice: .diffStatus, store: .diff, level: .hot) { state in
                    DiffStatusSlice(status: state.status, error: state.error, epoch: state.epoch)
                }
                EntitySlice(
                    "diffFiles", telemetrySlice: .diffFiles, store: .diff, level: .cold,
                    capture: { state in state.files },
                    version: { file in file.version },
                    keyToString: { $0 }
                )
            }
        )
    }

    func makeReviewPushPlan() -> PushPlan<ReviewState> {
        PushPlan(
            state: paneState.review,
            transport: self,
            revisions: revisionClock,
            // Review epoch tracks diff epoch until review data has its own
            // version timeline separate from diffs.
            epoch: { [paneState] in paneState.diff.epoch },
            slices: {
                EntitySlice(
                    "reviewThreads", telemetrySlice: .reviewThreads, store: .review, level: .warm,
                    capture: { state in state.threads },
                    version: { thread in thread.version },
                    keyToString: { $0.uuidString }
                )
                Slice(
                    "reviewViewedFiles",
                    telemetrySlice: .reviewViewedFiles,
                    store: .review,
                    level: .warm
                ) { state in
                    state.viewedFiles.sorted()
                }
            }
        )
    }

    func makeConnectionPushPlan() -> PushPlan<PaneDomainState> {
        PushPlan(
            state: paneState,
            transport: self,
            revisions: revisionClock,
            epoch: { 0 },
            slices: {
                Slice("connectionHealth", telemetrySlice: .connectionHealth, store: .connection, level: .hot) { state in
                    ConnectionSlice(health: state.connection.health, latencyMs: state.connection.latencyMs)
                }
            }
        )
    }

    func makeAgentPushPlan() -> PushPlan<PaneDomainState> {
        PushPlan(
            state: paneState,
            transport: self,
            revisions: revisionClock,
            epoch: { 0 },
            slices: {
                Slice("commandAcks", telemetrySlice: .commandAcks, store: .agent, level: .warm) { state in
                    state.commandAcks
                }
            }
        )
    }

    func handleRuntimeCommandAck(_ ack: CommandAck) {
        onRuntimeCommandAck?(ack)
    }
}
