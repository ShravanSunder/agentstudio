import Testing

/// R1 gate (Lead 2026-10-01, Fix 3): the shared parent for every suite that
/// binds or drives `Ghostty.ActionRouter`'s one process-wide
/// `ghosttyTerminalActivityInputBinding` singleton
/// (GhosttyActionRouter+TerminalActivityInput.swift) or its sibling
/// process-wide `localActionAccumulator`/`localActionDrainScheduler`
/// globals (GhosttyActionRouter+LocalActions.swift) -- `bind()` has no
/// guard against being overwritten, so two such suites running concurrently
/// in the same process can route one suite's own facts (a drain step, a
/// restore-phase-ended control) to the other's bound sink instead, and the
/// first suite then waits on a fact that will never arrive.
///
/// Same shape as `E2ESerializedTests`/`WebKitSerializedTests`
/// (Tests/AgentStudioTests/Integration/E2ESerializedTests.swift,
/// Tests/AgentStudioTests/App/WebKit/WebKitSerializedTests.swift):
/// Swift Testing's `.serialized` trait on a parent suite serializes every
/// nested suite against every other nested suite, not only each one's own
/// tests against itself. Deliberately NOT named or nested like
/// `E2ESerializedTests`/`ZmxE2ETests` -- `scripts/swift-test-helpers.sh`'s
/// `is_dedicated_e2e_or_zmx_lane_suite` routes suites matching that exact
/// name or `extension E2ESerializedTests` into the dedicated e2e/zmx lane,
/// which these fast, MainActor-only suites must not join.
@Suite(.serialized)
struct GhosttyActionRouterSerializedTests {}
