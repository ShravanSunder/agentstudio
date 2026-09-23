# Pinned navigation native proof

Debug igj3 PID 6831, marker `debug-observability-igj3-1789336509-3379`; standard launch and observability verification exit 0. Current binary contains queued pinned navigation and exact current-target guards. Latest focused App/IPC proof: 9 tests/2 suites, exit 0; lint and diff exit 0 (`pinned-native-build-*`). Separate raw capture, App sequence and regression tests passed earlier.

Through CUA on this exact isolated bundle:

- Existing sidebar pinned terminal was retained; pinned the existing Files pane with its toolbar action and the existing drawer child with its context-menu Pin Pane action.
- Actual unfiltered Panes order showed pinned Files, pinned terminal, then pinned drawer (No Repository group). These are existing test panes; no replacement session was created by this proof.
- Activated the terminal using displayed result 2, then Command-S hid sidebar.
- Option-Shift-Down moved to pinned drawer, expanded its parent drawer in Layout 2, and AX reported focus on the drawer terminal scroll area.
- Another Option-Shift-Down wrapped to Files, switched to Layout 1 and displayed the real Bridge canvas with sidebar hidden.
- Another Option-Shift-Down continued after Bridge to the pinned terminal in Layout 2; native terminal focus was reported.
- Option-Shift-Up returned to Files in Layout 1, still with sidebar hidden.

The initial pin click's tool result reported noWindowsAvailable. Process inspection showed the same PID remained alive; reconnecting showed Unpin Pane and the Files row in Pinned Panes, proving the action had succeeded. No blind repeat pin or process restart was performed.

Screenshots and AX observations are in the current session tool trace. No standalone screenshot files are claimed. Bridge content reveal does not establish inner DOM focus or override the separately deferred DOM-focus work.

## Performance observation gap

New capture/worker duration calls used phase/trigger strings absent from the existing closed OTLP taxonomy; queries returned zero matching measurements. No timing pass is claimed. Current source needs a narrow taxonomy/complete-dimension correction after the aggregate input freeze ends, then fresh marker proof. Capture and worker measurement regions are separate synchronous regions, not await elapsed time labeled MainActor occupancy.

## Remaining

Full aggregate is running. Independent review and final committed IPC handoff remain. Preview's attach-only requirement remains pending owner scope decision. This record is feature-specific proof, not a PR-ready or full-goal completion claim.

## Telemetry correction validation

Closed-taxonomy regression failed for both pinned phases and trigger (25 tests/2 suites, 6 issues; architecture correction passed). Exact allowlist/metric-enum cases and complete existing dimensions were added. GREEN: 29 tests/3 suites, then lint/diff exit 0. New standard debug launch PID 86213, marker `debug-observability-igj3-1789337839-85171`, launch and observability verifier exit 0. CUA returns `cgWindowNotFound` for both exact bundle path and identifier, including a clean tool reconnection; process remains alive. No live timing proof on this marker is claimed. The preceding native effect proof remains separate. Aggregate rerun is in progress on corrected source.
