# Polling-wait survey — Tests tree

Scope: every `.swift` file under `Tests/` (targets `AgentStudioTests`, `AgentStudioBridgeDevelopmentServerTests`, and the rest). Read-only survey, no edits, no builds.

## Method / grep patterns

Derivation was scripted, not eyeballed. Exact steps:

1. **Helper discovery** — walked every `Tests/**/*.swift`, brace-matched every `func` body, and kept the ones whose body contains BOTH a loop keyword (`while`/`for`) AND one of `Task.yield()`, `Task.sleep`, `ContinuousClock`, `SuspendingClock`. 305 hits; split into 129 wait-helpers (closure-taking or named `wait*`/`eventually*`/`poll*`) vs 176 `@Test` bodies with inline loops.
2. **Six false positives removed by reading them**: 4 in `AgentStudioOTLPBootstrapSmokeTests.swift` and 2 WebKit-carrier helpers race a `for await`/continuation against `clock.sleep` in a `TaskGroup` — event-driven, not polling. Final helper count **123**.
3. **Call sites** — regex `\b(<helper names>)\s*\(` over the whole tree, definition lines excluded, then brace-matched forward to capture the full call incl. trailing closure.
4. **Name disambiguation** — 39 distinct `waitUntilStarted` definitions exist; only one polls. For any helper name that also has a non-polling definition, a call site was kept only if it sits in a file that defines the polling variant. 259 sites dropped this way (231 of them `waitUntilStarted`, 25 `waitForStartedComparisonCount` — all confirmed to resolve to continuation-based actor gates).
5. **Category** — for the 20 closure-taking helpers (`eventually`, `waitUntil`, `assertEventually*`, …) the captured closure text was classified; for the other ~103 single-purpose helpers the helper's own predicate line (first `if`/`guard`/`where` inside the loop) was classified and inherited by its call sites. A/B was decided by: `await` in the predicate → B; otherwise, if the predicate leads with one of the helper's own parameters the state belongs to the object handed in and is read synchronously → A; only a predicate reading bare `self` state inside an `actor` type falls to B. Buckets were sampled (10-12 per bucket) three times and mis-hits corrected by reading the source; the last pass moved 72 sites.
6. Raw counts: `grep -rn 'await Task.yield()' Tests --include='*.swift'` → **398**; `grep -rn 'for _ in 0..<' Tests` → **296**; `grep -rn 'Task.sleep' Tests` → **9, and all nine are source-text assertions** (`#expect(!source.contains("Task.sleep"))`), not waits. No test body sleeps.

## (a) Summary

### Helpers by budget kind

| Budget kind | Helpers |
| --- | ---: |
| turn-count | 87 |
| clock-deadline | 29 |
| dual (turn floor + clock deadline) | 4 |
| unbounded | 3 |
| **total** | **123** |

`turn-count` = `for _ in 0..<N { ... await Task.yield() }`. `clock-deadline` = `while ContinuousClock.now < deadline { ... await Task.yield() }` (still a yield spin, just bounded by time). `dual` = the EventBusHarness shape: give up only when BOTH a turn floor and a wall-clock deadline are exhausted. `unbounded` = loop with no budget at all.

### Call sites by category

| Cat | What the condition reads | Call sites |
| --- | --- | ---: |
| A | MainActor `@Observable` atom / store / controller / view-model property (sync read) | 327 |
| B | `actor` or actor-isolated test-double state read with `await` | 177 |
| C | EventBus / AsyncStream delivery (subscriber counts, posted facts, recorded envelopes) | 71 |
| D | real OS / external asynchrony (FSEvents, filesystem, git, WebKit/JS, sockets, child processes) | 51 |
| E | AppKit / SwiftUI view or window state (first responder, layout, hosted tree, a11y elements) | 27 |
| F | NEGATIVE wait — budget must expire to prove something does *not* happen | 3 |
| G | other / unclear (see ambiguities) | 22 |
| | **total** | **678** |

Plus **162** inline polling loops in test bodies that are not wrapped in any helper (same `for _ in 0..<N` + `Task.yield()` shape), and **77** call sites that pass an explicit non-default budget.

### Top helpers by call volume

Note that a name like `eventually` is not one helper: it is 12 independent file-private copies with different budgets.

| Helper name | Call sites | Distinct definitions | Default budgets across those definitions |
| --- | ---: | ---: | --- |
| `eventually` | 152 | 12 | `maxTurns=100`, `maxTurns=200`, `maxTurns=50_000`, `maxYields=300_000`, `maximumTurns=10_000`, `timeout=.seconds(5)` |
| `assertEventuallyMain` | 146 | 1 | `minimumTurns=200` + `timeout=.seconds(10)` (dual) |
| `assertEventuallyAsync` | 79 | 1 | `minimumTurns=200` + `timeout=.seconds(10)` (dual) |
| `waitUntil` | 40 | 9 | `attempts=10_000`, `iterations=20_000`, `maxTurns=10_000`, `timeout=.seconds(2)`, caller-supplied deadline |
| `waitForActiveReviewRefreshTaskToFinish` | 31 | 2 | `maxTurns=2000` |
| `expectBridgePaneActivity` | 24 | 1 | `maxTurns=200` |
| `waitUntilNotificationState` | 14 | 1 | `maximumTurns=20_000` |
| `waitForRefreshDriverFileIdle` | 10 | 1 | `maximumTurns=200` |
| `waitForPageLoad` | 8 | 3 | `timeout=.seconds(2)`, `timeout=.seconds(5)` |
| `waitForMessageCount` | 7 | 2 | literal `200_000` turns, `timeout=.seconds(2)` |
| `waitForActiveFileRefreshTaskToFinish` | 7 | 1 | `maxTurns=2000` |
| `waitForActivityContentProducerToFinish` | 7 | 1 | `maxTurns=2000` |

`assertEventuallyMain` + `assertEventuallyAsync` (the two shared `package` helpers in `Tests/AgentStudioTests/TestSupport/EventBusHarness.swift`) alone cover **225** of the 678 call sites, and every locally-defined `eventually`/`waitUntil` is a copy of the same shape.

## (b) Helper table

| file:line | name | budget kind | default budget | on expiry | scope |
| --- | --- | --- | --- | --- | --- |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:268` | `waitForCancellation` | clock-deadline | deadline .seconds(1) | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:277` | `waitForBodyWrite` | clock-deadline | deadline .seconds(5) | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:216` | `waitForCancellation` | clock-deadline | deadline .seconds(1) | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:225` | `waitForBodyWrite` | clock-deadline | deadline .seconds(5) | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:234` | `waitForConnectionClose` | clock-deadline | deadline .seconds(1) | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:420` | `waitForUnregisteredWorktreeCount` | clock-deadline | timeout=.seconds(5 | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:465` | `waitForFileChangesetCount` | clock-deadline | timeout=.seconds(5 | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:477` | `waitForFileChangeset` | clock-deadline | deadline timeout | returns/void | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:491` | `waitForStatusCount` | clock-deadline | timeout=.seconds(5 | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:511` | `waitForTerminalCount` | clock-deadline | timeout=.seconds(5 | returns Bool | target-internal |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:524` | `waitForReviewRefreshSettlement` | clock-deadline | deadline timeout | returns Bool | file-private |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:536` | `waitForCommittedReviewDeletion` | clock-deadline | deadline timeout | returns Bool | file-private |
| `AgentStudioTests/App/AppDelegateRepositoryFactUpdateTests.swift:420` | `repositoryFactUpdateEventually` | turn-count | maxTurns=20_000 | returns Bool | file-private |
| `AgentStudioTests/App/PaneTabViewControllerBridgeCommandTests.swift:665` | `waitForBridgeCommandCondition` | clock-deadline | timeout=.seconds(5 | returns Bool | file-private |
| `AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift:402` | `waitUntil` | turn-count | iterations=20_000 | returns Bool | file-private |
| `AgentStudioTests/App/Panes/TabBarAdapterMaterializationTests.swift:803` | `waitUntil` | turn-count | attempts=10_000 | returns Bool | file-private |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:729` | `eventually` | turn-count | maxTurns=100 | Issue.record | file-private |
| `AgentStudioTests/App/RecordingCommandPaneRuntime.swift:7` | `waitForRecordedCommands` | turn-count | maxTurns=50 | returns/void | target-internal |
| `AgentStudioTests/App/RepositoryBootBaselineTests.swift:154` | `waitForRepositoryBootReplaySuspension` | dual (turn floor + clock deadline) | minimumTurns=200; timeout=.seconds(10 | returns Bool | file-private |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:106` | `waitForAppEventBusSubscriberCount` | turn-count | literal 1000 | Issue.record | file-private |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:125` | `waitForAppEventBusSubscriber` | turn-count | literal 1000 | Issue.record | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeContentWorldIsolationTests.swift:112` | `waitForMessageCount` | turn-count | literal 200_000 | returns Bool | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeContentWorldIsolationTests.swift:125` | `waitForPageLoad` | clock-deadline | timeout=.seconds(2 | returns/void | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeSchemeHandlerSpikeTests.swift:94` | `waitForTitle` | turn-count | timeout=.seconds(2 | returns Bool | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:206` | `waitForTitle` | clock-deadline | timeout=.seconds(2 | returns Bool | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:222` | `waitForPageLoad` | dual (turn floor + clock deadline) | timeout=.seconds(2 | returns/void | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:237` | `waitUntil` | clock-deadline | timeout=.seconds(2 | returns Bool | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:363` | `waitForPageLoad` | turn-count | timeout=.seconds(5 | returns/void | file-private |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:372` | `waitForMessageCount` | turn-count | timeout=.seconds(2 | returns Bool | file-private |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:24` | `waitForRefreshAdmissionQueuedMetadataFrame` | turn-count | maxTurns=200 | returns Bool | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:37` | `waitForStartedComparisonCount` | turn-count | maxTurns=2000 | returns Bool | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:52` | `waitForRetiringReviewRefreshTasksToDrain` | turn-count | maxTurns=2000 | returns Bool | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:74` | `waitForRefreshAdmissionIdle` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:89` | `waitForActiveReviewRefreshTaskToFinish` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:103` | `waitForActiveFileRefreshTaskToFinish` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:115` | `waitForRefreshAdmissionSettledWhileHidden` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionRequestTestSupport.swift:67` | `waitForRefreshAdmissionMetadataStream` | turn-count | maxTurns=200 | throws | file-private |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitCarrierTestSupport.swift:715` | `waitUntil` | clock-deadline | deadline timeout | returns Bool | shared support |
| `AgentStudioTests/App/Windows/SidebarSurfaceHostSwitchGuardTests.swift:281` | `waitForEngagement` | unbounded | — | returns Bool | file-private |
| `AgentStudioTests/App/Windows/SidebarSurfaceHostSwitchGuardTests.swift:456` | `waitForTableView` | unbounded | — | returns/void | file-private |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:821` | `eventually` | turn-count | maxTurns=100 | Issue.record | file-private |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift:920` | `eventually` | turn-count | maxTurns=100 | Issue.record | file-private |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift:935` | `waitUntilYielding` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneActivityTestSupport.swift:156` | `expectBridgePaneActivity` | turn-count | maxTurns=200 | #expect | shared support |
| `AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneRefreshIntegrationTests.swift:582` | `expectControllerRefreshActivity` | turn-count | maxTurns=200 | #expect | file-private |
| `AgentStudioTests/App/WorkspaceSurfaceCoordinatorGeometryReevaluationIntegrationTests.swift:101` | `waitUntil` | turn-count | iterations=20_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:305` | `waitForRenewedAuthority` | turn-count | literal 1000 | returns/void | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:318` | `waitForSharedActivitySettlement` | clock-deadline | deadline .seconds(2 | returns/void | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverFailureTests.swift:500` | `waitForLogicalRegistrationCount` | clock-deadline | — | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverTests.swift:527` | `waitForLogicalRegistrationCount` | clock-deadline | — | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorActivityTests.swift:652` | `waitUntil` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift:81` | `waitUntil` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift:765` | `waitUntilFilesystemLogicalDebt` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift:786` | `waitForStartedQuantumCount` | turn-count | literal 10_000 | Issue.record | target-internal |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift:800` | `waitUntilRecordedLogicalDebtEquals` | turn-count | literal 10_000 | returns Bool | target-internal |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift:810` | `waitUntilAdmittedWatchedScanCount` | turn-count | literal 10_000 | returns Bool | target-internal |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorWatchedFolderTests.swift:946` | `waitUntilWatchedFolderLogicalDebt` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorAdmissionTests.swift:872` | `admissionWaitUntil` | turn-count | maxTurns=20_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorAutomaticPacingTests.swift:357` | `automaticPacingWaitUntil` | turn-count | maxTurns=20_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorContinuityTests.swift:301` | `eventually` | turn-count | maximumTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorExplicitUpdateTests.swift:344` | `explicitUpdateWaitUntil` | turn-count | maxTurns=20_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift:4283` | `waitUntil` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift:4296` | `waitUntilYielding` | turn-count | maxTurns=10_000 | returns Bool | file-private |
| `AgentStudioTests/Core/PaneRuntime/Sources/WatchedFolderScanSchedulerTests.swift:783` | `waitForState` | turn-count | literal 10_000 | Issue.record | target-internal |
| `AgentStudioTests/Core/PaneRuntime/Sources/WatchedFolderScanSchedulerTests.swift:796` | `waitForPendingResultCount` | turn-count | literal 10_000 | Issue.record | target-internal |
| `AgentStudioTests/Core/PaneRuntime/Sources/WatchedFolderScanSchedulerValidationTests.swift:286` | `waitForState` | turn-count | literal 10_000 | Issue.record | target-internal |
| `AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift:1146` | `waitForDirtyObservation` | turn-count | literal 20 | returns/void | file-private |
| `AgentStudioTests/Features/Bridge/BridgeContentDemandAdmissionTests.swift:398` | `waitForBackgroundWaiterCount` | turn-count | literal 1000 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/BridgeContentDemandAdmissionTests.swift:411` | `waitForClosedAdmission` | turn-count | literal 1000 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/BridgeDevelopmentProductHostDisplayLifecycleTestSupport.swift:402` | `waitForMetadataProducerRetirementToBegin` | clock-deadline | timeout=.seconds(10 | Issue.record | shared support |
| `AgentStudioTests/Features/Bridge/BridgeDevelopmentProductHostDisplayLifecycleTests.swift:75` | `initialReviewPublicationArrives` | clock-deadline | deadline .seconds(5) | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift:760` | `waitForRefreshAdmissionMetadataStream` | turn-count | maxTurns=200 | throws | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift:870` | `waitForRefreshAdmissionQueuedMetadataFrame` | turn-count | maxTurns=200 | returns Bool | shared support |
| `AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift:884` | `waitForRefreshAdmissionIdle` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift:899` | `waitForActiveReviewRefreshTaskToFinish` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/Features/Bridge/BridgePaneControllerRefreshTestSupport.swift:913` | `waitForRefreshAdmissionSettledWhileHidden` | turn-count | maxTurns=2000 | Issue.record | shared support |
| `AgentStudioTests/Features/Bridge/BridgePaneProductComparisonTargetContentLifecycleTests.swift:929` | `waitUntilSessionRevoked` | turn-count | literal 512 | Issue.record | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneProductContentActivityAdmissionTests.swift:829` | `waitForActivityContentProducerToFinish` | turn-count | maxTurns=2000 | Issue.record | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneProductContentActivityAdmissionTests.swift:843` | `waitForActivityContentState` | turn-count | maxTurns=2000 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneProductMetadataActivityAdmissionTests.swift:576` | `waitForActivityMetadataSourceScheduling` | turn-count | maxTurns=2000 | returns/void | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneProductMetadataActivityAdmissionTests.swift:596` | `waitForActivityMetadataState` | turn-count | maxTurns=2000 | returns Bool | target-internal |
| `AgentStudioTests/Features/Bridge/BridgePaneProductMetadataReconnectSubscriptionTestSupport.swift:331` | `waitForReconnectSourceActivity` | turn-count | maximumTurns=2000 | returns Bool | shared support |
| `AgentStudioTests/Features/Bridge/BridgePaneProductMetadataReconnectSubscriptionTestSupport.swift:342` | `waitForReconnectSourceUpdate` | turn-count | maximumTurns=2000 | returns Bool | shared support |
| `AgentStudioTests/Features/Bridge/BridgePaneProductSessionOwnerTests.swift:560` | `waitForActiveWorkerInstance` | turn-count | literal 512 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneProductSessionOwnerTests.swift:732` | `waitUntilProductRouterIsFenced` | turn-count | literal 512 | Issue.record | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneReviewSharedConstructionTests.swift:853` | `waitUntilConstructionEntryIsRemoved` | turn-count | literal 100 | Issue.record | target-internal |
| `AgentStudioTests/Features/Bridge/BridgePaneWorktreeRefreshDriverSessionIntegrationTests.swift:270` | `waitForSessionIntegrationDriverIdle` | turn-count | maximumTurns=200 | throws | file-private |
| `AgentStudioTests/Features/Bridge/BridgePaneWorktreeRefreshDriverTests.swift:441` | `waitForRefreshDriverFileIdle` | turn-count | maximumTurns=200 | throws | file-private |
| `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:573` | `waitForProducerPacingWaiterCount` | turn-count | literal 1000 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:608` | `waitUntilRecorded` | turn-count | literal 1000 | returns Bool | target-internal |
| `AgentStudioTests/Features/Bridge/BridgeProductSessionReentrancyTests.swift:378` | `waitForProducerCount` | turn-count | literal 512 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/ObservationSpikeTests.swift:251` | `waitForCondition` | turn-count | maxYields=200 | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/ObservationSpikeTests.swift:264` | `advanceClock` | turn-count | — | returns Bool | file-private |
| `AgentStudioTests/Features/Bridge/WorktreeAnnotations/WorktreeAnnotationNotificationSourceTests.swift:480` | `waitUntilNotificationState` | turn-count | maximumTurns=20_000 | Issue.record | file-private |
| `AgentStudioTests/Features/CommandBar/CommandBarProductionProbeWiringTests.swift:68` | `eventuallyTraceContains` | turn-count | maxTurns=200 | #expect | file-private |
| `AgentStudioTests/Features/CommandBar/TestSupport/CommandBarTestHelpers.swift:59` | `eventually` | turn-count | maxTurns=200 | #expect | shared support |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift:860` | `waitForEnvelopeTrace` | clock-deadline | deadline .seconds(2 | returns Bool | file-private |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterPayloadTests.swift:220` | `waitForNotificationState` | clock-deadline | deadline .seconds(2 | returns Bool | file-private |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionActivityDemandTests.swift:234` | `waitForStableKey` | turn-count | literal 2000 | returns/void | target-internal |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift:63` | `waitUntilStarted` | turn-count | literal 10_000 | returns Bool | target-internal |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift:290` | `waitForBrokerPublishedResult` | turn-count | literal 10_000 | returns/void | file-private |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift:301` | `waitForBrokerSemanticSequence` | turn-count | literal 10_000 | returns Bool | file-private |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift:313` | `waitForAnyBrokerPublishedResult` | turn-count | literal 10_000 | returns/void | file-private |
| `AgentStudioTests/Features/Terminal/Restore/TerminalActivationSchedulerSettlementRaceTests.swift:98` | `waitUntilMemberIsReady` | turn-count | iterations=20_000 | Issue.record | file-private |
| `AgentStudioTests/Helpers/TestPushClockTests.swift:32` | `cancelledBeforeSleepRegistrationTerminatesImmediately` | unbounded | deadline .seconds(1 | #expect | shared support |
| `AgentStudioTests/Helpers/WorkspaceSurfaceCoordinatorTestHelpers.swift:43` | `eventually` | clock-deadline | timeout=.seconds(5 | #expect | shared support |
| `AgentStudioTests/Helpers/ZmxTestHarness.swift:366` | `fallbackWaitForSessionSocket` | clock-deadline | deadline timeout | returns Bool | file-private |
| `AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceEventQueueTests.swift:141` | `waitUntil` | turn-count | attempts=10_000 | returns Bool | file-private |
| `AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceRuntimeTests.swift:438` | `waitForBodyByYielding` | turn-count | literal 100 | returns Bool | file-private |
| `AgentStudioTests/Infrastructure/ProcessExecutorTests.swift:373` | `waitForProcessIdentifier` | clock-deadline | deadline .seconds(3 | throws | file-private |
| `AgentStudioTests/Infrastructure/ProcessExecutorTests.swift:406` | `waitUntilPaused` | clock-deadline | deadline .seconds(3 | throws | target-internal |
| `AgentStudioTests/Integration/FilesystemFetchHeadGitPipelineIntegrationTests.swift:78` | `eventually` | turn-count | maxTurns=50_000 | Issue.record | file-private |
| `AgentStudioTests/Integration/FilesystemGitPipelineDemandIntegrationTests.swift:434` | `eventually` | turn-count | maxTurns=50_000 | Issue.record | file-private |
| `AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift:622` | `eventually` | turn-count | maxTurns=50_000 | Issue.record | file-private |
| `AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift:678` | `waitUntilYielding` | turn-count | maxTurns=2000 | returns Bool | file-private |
| `AgentStudioTests/Integration/FilesystemGitPipelineRegistrationTests.swift:175` | `eventually` | turn-count | maxTurns=50_000 | Issue.record | file-private |
| `AgentStudioTests/Integration/FilesystemGitPipelineRegistrationTests.swift:193` | `neverArrives` | turn-count | maxTurns=2000 | Issue.record | file-private |
| `AgentStudioTests/Integration/FilesystemSourceE2ETests.swift:122` | `eventually` | turn-count | maxYields=300_000 | #expect | file-private |
| `AgentStudioTests/Integration/FilesystemToPrimarySidebarIntegrationTests.swift:376` | `eventually` | turn-count | maxTurns=50_000 | Issue.record | file-private |
| `AgentStudioTests/Integration/ZmxE2ETests.swift:143` | `waitForObservedSessionIdentity` | clock-deadline | deadline .seconds(5 | throws | file-private |
| `AgentStudioTests/SharedComponents/SidebarGroupingPopoverTests.swift:76` | `waitForGroupingPopoverState` | turn-count | maxTurns=1000 | returns Bool | file-private |
| `AgentStudioTests/TestSupport/EventBusHarness.swift:150` | `assertEventuallyAsync` | dual (turn floor + clock deadline) | minimumTurns=200; timeout=.seconds(10 | #expect | shared support |
| `AgentStudioTests/TestSupport/EventBusHarness.swift:173` | `assertEventuallyMain` | dual (turn floor + clock deadline) | minimumTurns=200; timeout=.seconds(10 | #expect | shared support |
## (c) Call sites by category

`condition reads` is the closure body for closure-taking helpers, or the helper's own predicate line for single-purpose helpers (truncated to 100 chars).

### A — MainActor `@Observable` atom / store / controller property (sync read) — 327 call sites

Exact total: **327**. First 60 listed (sorted by path).

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:77` | `eventually` | `clock.pendingSleepCount == 1 && coordinator.pendingRepositoryProjectionSupersessionCount == 1 }` |  |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:84` | `eventually` | `repoCache.pullRequestFacts(for: branchKey) == facts }` |  |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:178` | `eventually` | `repoCache.repoEnrichmentByRepoId[repo.id] != nil }` |  |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:237` | `eventually` | `clock.pendingSleepCount == 1 }` |  |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:242` | `eventually` | `repoCache.worktreeEnrichment(for: worktreeId)?.snapshot == snapshot }` |  |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:263` | `eventually` | `clock.pendingSleepCount == 1 }` |  |
| `AgentStudioTests/App/Coordination/WorkspaceCacheCoordinatorApplyGovernorTests.swift:268` | `eventually` | `repoCache.worktreeEnrichment(for: worktreeId)?.branch == "feature/new" }` |  |
| `AgentStudioTests/App/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift:120` | `assertEventuallyMain` | `inboxSidebarState.peekPendingFilter() == nil }` |  |
| `AgentStudioTests/App/ManagementLayerTests.swift:33` | `eventually` | `recorder.records.count == 1 }` |  |
| `AgentStudioTests/App/PaneTabViewControllerBridgeCommandTests.swift:561` | `eventually` | `atoms.core.workspaceEntityRecency.recentEntities.contains { $0.entity == .pane(paneID: openedPane.id` |  |
| `AgentStudioTests/App/Panes/Hosting/DrawerPanelOverlayStateTests.swift:393` | `assertEventuallyMain` | `publishedViewBox.view != nil }` |  |
| `AgentStudioTests/App/Panes/Hosting/PaneLeafContainerPaneInboxTests.swift:114` | `eventually` | `pendingRequest == nil && presentedScopes.contains { $0.parentPaneId == pane.id && $0.paneIds == [pan` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:91` | `eventually` | `guard case .some(.resolvedRemote(_, _, let identityA, _)) = repoCache.repoEnrichmentByRepoId[repoA.i` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:133` | `eventually` | `guard let repo = workspaceStore.repos.first(where: { $0.repoPath == repoPath }) else { return false ` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:167` | `eventually` | `guard case .some(.resolvedRemote(_, let raw, let identity, _)) = repoCache.repoEnrichmentByRepoId[ r` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:380` | `eventually` | `guard !fixture.financeRepositoryIDs.isEmpty else { return false } for repoId in fixture.financeRepos` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:393` | `eventually` | `guard let primaryBranchId = fixture.financeWorktreeIDByBranch["master"], let transactionTableId = fi` |  |
| `AgentStudioTests/App/RepositoryBridgeObservationLifetimeTests.swift:107` | `assertEventuallyMain` | `setup.controller.refreshAdmissionCoordinator.diagnosticSnapshot.activity == .loadedHidden }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:311` | `eventually` | `harness.store.tabs.isEmpty }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:341` | `eventually` | `harness.store.pane(drawerPane.id) == nil }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:384` | `eventually` | `harness.store.pane(minimizedPane.id) == nil }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:460` | `eventually` | `weakController.value == nil }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:52` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:114` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:208` | `waitForRetiringReviewRefreshTasksToDrain` | `if controller.retiringReviewRefreshTaskById.isEmpty { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:217` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:244` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:265` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:280` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerDiffLoadTests.swift:334` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerInitialLoadSupersessionTests.swift:42` | `waitUntil` | `fixture.controller.retiringReviewRefreshTaskById.isEmpty }` | timeout: .seconds(2 |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerInitialLoadSupersessionTests.swift:47` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:50` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:77` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:145` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:186` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:253` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:268` | `waitForRefreshAdmissionIdle` | `if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:269` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:296` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:370` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:427` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:499` | `waitForRefreshAdmissionIdle` | `if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:563` | `waitForRefreshAdmissionIdle` | `if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:600` | `waitForRefreshAdmissionIdle` | `if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:649` | `waitForRetiringReviewRefreshTasksToDrain` | `if controller.retiringReviewRefreshTaskById.isEmpty { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:659` | `waitForRefreshAdmissionIdle` | `if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:693` | `waitForRefreshAdmissionSettledWhileHidden` | `if snapshot.activity == .loadedHidden, snapshot.activeRefreshPass == nil, snapshot.dirtyFact != nil,` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:733` | `waitForRefreshAdmissionIdle` | `if snapshot.activeRefreshPass == nil, snapshot.dirtyFact == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:779` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:815` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerReviewComparisonPresentationTests.swift:171` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerReviewComparisonPresentationTests.swift:221` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerReviewComparisonPresentationTests.swift:273` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerReviewComparisonPresentationTests.swift:337` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitEmptyReviewWebKitTests.swift:32` | `waitUntil` | `guard let package = try? hostedController.ipcReviewPackageSnapshot() else { return false } return pa` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:83` | `waitUntil` | `guard let package = try? controller.ipcReviewPackageSnapshot() else { return false } return package.` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitTests.swift:449` | `waitUntil` | `harness.controllerTarget.applicationReceipts.count == 1 && harness.controllerTarget.applicationRecei` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeContributionRefreshTestSupport.swift:199` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionFixtureTestSupport.swift:25` | `waitForActiveReviewRefreshTaskToFinish` | `if controller.activeReviewRefreshTask == nil { return }` |  |

### B — `actor` / actor-isolated test-double state read with `await` — 177 call sites

Exact total: **177**. First 60 listed (sorted by path).

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:49` | `waitForFileChangesetCount` | `if fileChangesets.count >= expectedCount { return true } await Task.yield() }` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:50` | `waitForStatusCount` | `if statuses.count >= expectedCount { return true } await Task.yield() }` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:72` | `waitForStatusCount` | `if statuses.count >= expectedCount { return true } await Task.yield() }` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:146` | `waitForStatusCount` | `if statuses.count >= expectedCount { return true } await Task.yield() }` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:151` | `waitForUnregisteredWorktreeCount` | `if fseventClient.unregisteredWorktreeIds.count >= expectedCount { return true } await Task.yield() }` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:152` | `waitForTerminalCount` | `if terminals.count >= expectedCount { return true } await Task.yield() }` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:221` | `waitForStatusCount` | `if statuses.count >= expectedCount { return true } await Task.yield() }` | timeout: .seconds(5 |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:227` | `waitForFileChangeset` | `if let matchingChangeset = fileChangesets.last(where: { $0.paths == expectedPaths }) { return matchi` | timeout: .seconds(5 |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:233` | `waitForStatusCount` | `if statuses.count >= expectedCount { return true } await Task.yield() }` | timeout: .seconds(5 |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:296` | `waitForStatusCount` | `if statuses.count >= expectedCount { return true } await Task.yield() }` | timeout: .seconds(5 |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:298` | `waitForReviewRefreshSettlement` | `if await !host.diagnosticPanePresentation().refreshingLanes.contains(.review) { return true } await ` | timeout: .seconds(5 |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:316` | `waitForFileChangeset` | `if let matchingChangeset = fileChangesets.last(where: { $0.paths == expectedPaths }) { return matchi` | timeout: .seconds(5 |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentSeededWorktreeObservationTests.swift:323` | `waitForCommittedReviewDeletion` | `if let publication = await host.diagnosticCommittedReviewPublication(), publication.package.itemsByI` | timeout: .seconds(5 |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:104` | `eventually` | `let pullRequestCountsConverged = await eventually("forge pull request counts should map to both work` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:260` | `eventually` | `await callCounter.value() == 1 }` |  |
| `AgentStudioTests/App/RepositoryBootBaselineTests.swift:70` | `waitForRepositoryBootReplaySuspension` | `if await replayGate.isReplaySuspended() { return true }` |  |
| `AgentStudioTests/App/Terminal/GhosttyActionRouterMixedPressureTests.swift:187` | `assertEventuallyAsync` | `let runtimeEventCount = await fixture.runtimeSubscriber.snapshot().count let eventBusEventCount = aw` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerInitialLoadSupersessionTests.swift:15` | `waitUntil` | `await comparisonGate.hasStartedComparisonCount(1) }` | timeout: .seconds(2 |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerInitialLoadSupersessionTests.swift:37` | `waitUntil` | `await comparisonGate.hasStartedComparisonCount(2) }` | timeout: .seconds(2 |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:86` | `waitForRefreshAdmissionQueuedMetadataFrame` | `if await fixture.productInstallation.session.producerSnapshot().queuedFrameCount > 0 { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:728` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:847` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:872` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:895` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:906` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:930` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:934` | `waitForActiveFileRefreshTaskToFinish` | `if !controller.worktreeRefreshDriver.hasActiveFileOperation { return } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerReviewComparisonPresentationTests.swift:218` | `waitForRefreshAdmissionQueuedMetadataFrame` | `if await fixture.productInstallation.session.producerSnapshot().queuedFrameCount > 0 { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerReviewComparisonPresentationTests.swift:222` | `waitForRefreshAdmissionQueuedMetadataFrame` | `if await fixture.productInstallation.session.producerSnapshot().queuedFrameCount > 0 { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductPackagedShareJourneyTestSupport.swift:414` | `waitUntil` | `observed = try? await shareSnapshot(page) return observed.map(predicate) == true }` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:72` | `waitUntil` | `let trace = await traceRecorder.scrubbedTrace() return trace.hasCanonicalEagerSubscriptions && trace` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:114` | `waitUntil` | `guard let metadata = await reviewMetadataDOMSnapshot(controller), metadata.itemCount >= 128, metadat` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitTests.swift:431` | `waitUntil` | `let fileSnapshot = await harness.fileMetadataSource.snapshot() let reviewSnapshot = await harness.re` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:140` | `waitUntil` | `(try? await controller.renderStateForIPC().summary.hasReviewShell) == true }` | timeout: .seconds(1 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:190` | `waitUntil` | `(try? await controller.renderStateForIPC().summary.hasReviewShell) == true }` | timeout: .seconds(1 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionRequestTestSupport.swift:60` | `waitForRefreshAdmissionMetadataStream` | `if case .resyncAccepted = await provider.response(for: request) { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitSurfaceSelectionJourneyTestSupport.swift:251` | `waitUntil` | `(try? await state(page))?.activeMode == expectedMode }` | timeout: .seconds(10 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitSurfaceSelectionJourneyTestSupport.swift:287` | `waitUntil` | `guard let snapshot = try? await state(page) else { return false } observed = snapshot guard let proj` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitSurfaceSelectionJourneyTestSupport.swift:316` | `waitUntil` | `guard let snapshot = try? await state(page) else { return false } observed = snapshot return snapsho` | timeout: .seconds(10 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitSurfaceSelectionJourneyTestSupport.swift:340` | `waitUntil` | `guard let snapshot = try? await state(page) else { return false } observed = snapshot return snapsho` | timeout: .seconds(10 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift:678` | `waitUntil` | `await provider.snapshot().blockedComparisonCount == expectedCount }` | timeout: .seconds(10 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift:745` | `waitUntil` | `observed = try? await positionSnapshot(page) guard let observed else { return false } let activeText` | timeout: .seconds(10 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift:773` | `waitUntil` | `observed = try? await positionSnapshot(page) return observed?.fileStatusText == nil && observed?.rev` | timeout: .seconds(10 |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:117` | `eventually` | `let changes = await recordedScopeChanges.values return changes.isEmpty }` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:193` | `eventually` | `let changes = await recordedScopeChanges.values return changes.isEmpty }` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:243` | `eventually` | `let changes = await recordedScopeChanges.values return changes.contains { if case .unregisterForgeRe` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:346` | `eventually` | `let changes = await recordedScopeChanges.values return changes.contains { if case .unregisterForgeRe` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift:843` | `eventually` | `let count = await recordedScopeChanges.count return count >= 1 }` |  |
| `AgentStudioTests/App/WorkspaceSurfaceCoordinatorTests+Filesystem.swift:311` | `assertEventuallyAsync` | `condition(await source.snapshot()) }` | minimumTurns: 200 |
| `AgentStudioTests/App/WorkspaceSurfaceCoordinatorTests+Filesystem.swift:321` | `assertEventuallyAsync` | `condition(await source.snapshot()) }` | minimumTurns: 200 |
| `AgentStudioTests/App/WorkspaceTerminalSessionCleanupTests.swift:149` | `assertEventuallyAsync` | `await backend.observed == [fixture.sessionID] }` |  |
| `AgentStudioTests/App/WorkspaceTerminalSessionCleanupTests.swift:157` | `assertEventuallyAsync` | `await fixture.coordinator.terminalSessionCleanupStopped }` |  |
| `AgentStudioTests/App/WorkspaceTerminalSessionCleanupTests.swift:197` | `assertEventuallyAsync` | `await backend.retryRequested }` |  |
| `AgentStudioTests/App/WorkspaceTerminalSessionCleanupTests.swift:241` | `assertEventuallyAsync` | `(try? await store.terminalSessionCleanupBatch(after: nil))?.isEmpty == true }` |  |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusHarnessTests.swift:135` | `assertEventuallyAsync` | `await counter.incrementAndCheck(threshold: 150) }` | timeout: .zero |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:23` | `waitForRenewedAuthority` | `if case .authoritative(let renewedAuthority) = await client.renew(authority) { return renewedAuthori` |  |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:54` | `waitForSharedActivitySettlement` | `if let barrier = await fixture.client.captureActivityBarrier(), fixture.sharedDeliveredEventID(in: b` |  |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:77` | `waitForSharedActivitySettlement` | `if let barrier = await fixture.client.captureActivityBarrier(), fixture.sharedDeliveredEventID(in: b` |  |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:105` | `waitForSharedActivitySettlement` | `if let barrier = await fixture.client.captureActivityBarrier(), fixture.sharedDeliveredEventID(in: b` |  |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:132` | `waitForSharedActivitySettlement` | `if let barrier = await fixture.client.captureActivityBarrier(), fixture.sharedDeliveredEventID(in: b` |  |

### C — EventBus / AsyncStream delivery — 71 call sites

Exact total: **71**. First 60 listed (sorted by path).

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorFilesystemSourceTests.swift:457` | `assertEventuallyAsync` | `let paneEvents = RuntimeEnvelopeHarness.paneEvents(from: await subscriber.snapshot()) return paneEve` | minimumTurns: 200_000 |
| `AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorFilesystemSourceTests.swift:530` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 1 }` |  |
| `AgentStudioTests/App/PaneTabViewControllerTerminalCommandTests.swift:46` | `waitForRecordedCommands` | `runtime.receivedCommands.count < count` |  |
| `AgentStudioTests/App/PaneTabViewControllerTerminalShortcutCommandTests.swift:60` | `waitForRecordedCommands` | `runtime.receivedCommands.count < count` |  |
| `AgentStudioTests/App/PaneTabViewControllerTerminalShortcutCommandTests.swift:136` | `waitForRecordedCommands` | `runtime.receivedCommands.count < count` | maxTurns: 5 |
| `AgentStudioTests/App/PaneTabViewControllerTerminalShortcutCommandTests.swift:182` | `waitForRecordedCommands` | `runtime.receivedCommands.count < count` | maxTurns: 5 |
| `AgentStudioTests/App/PaneTabViewControllerTerminalShortcutCommandTests.swift:218` | `waitForRecordedCommands` | `runtime.receivedCommands.count < count` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:759` | `eventually` | `await bus.subscriberCount == 0 }` |  |
| `AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift:783` | `eventually` | `await bus.subscriberCount == 0 }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:121` | `waitForAppEventBusSubscriberCount` | `if await appEventBus.subscriberCount == expectedCount { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:239` | `waitForAppEventBusSubscriber` | `if activeSubscriberNames.contains(subscriberName) == isPresent { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:255` | `waitForAppEventBusSubscriber` | `if activeSubscriberNames.contains(subscriberName) == isPresent { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:308` | `waitForAppEventBusSubscriberCount` | `if await appEventBus.subscriberCount == expectedCount { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:338` | `waitForAppEventBusSubscriberCount` | `if await appEventBus.subscriberCount == expectedCount { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:381` | `waitForAppEventBusSubscriberCount` | `if await appEventBus.subscriberCount == expectedCount { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:439` | `waitForAppEventBusSubscriber` | `if activeSubscriberNames.contains(subscriberName) == isPresent { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:454` | `waitForAppEventBusSubscriberCount` | `if await appEventBus.subscriberCount == expectedCount { return }` |  |
| `AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift:464` | `waitForAppEventBusSubscriberCount` | `if await appEventBus.subscriberCount == expectedCount { return }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeContentWorldIsolationTests.swift:55` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeContentWorldIsolationTests.swift:103` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:164` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:172` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:239` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:247` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:296` | `waitForMessageCount` | `if handler.receivedMessages.count >= expectedCount { return true }` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:591` | `eventually` | `let diagnostics = await bus.diagnosticsSnapshot() let subscriber = diagnostics.activeSubscribers.fir` | maxTurns: burstCount * 4 |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:845` | `eventually` | `await bus.subscriberCount == 0 }` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift:867` | `eventually` | `await bus.subscriberCount == 0 }` |  |
| `AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift:464` | `assertEventuallyAsync` | `let diagnostics = await bus.diagnosticsSnapshot() return diagnostics.activeSubscribers.contains { $0` |  |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusHarnessTests.swift:36` | `assertEventuallyAsync` | `await subscriberA.snapshot() == [42] }` |  |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusHarnessTests.swift:39` | `assertEventuallyAsync` | `await subscriberB.snapshot() == [42] }` |  |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusHarnessTests.swift:55` | `assertEventuallyAsync` | `await subscriber.snapshot() == ["a", "b", "c"] }` |  |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift:58` | `assertEventuallyAsync` | `await harness.bus.subscriberCount > 0 }` | minimumTurns: 50 |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift:83` | `assertEventuallyAsync` | `await harness.bus.subscriberCount > 0 }` | minimumTurns: 50 |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift:107` | `assertEventuallyAsync` | `await harness.bus.subscriberCount > 0 }` | minimumTurns: 50 |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift:134` | `assertEventuallyAsync` | `await harness.bus.subscriberCount > 0 }` | minimumTurns: 50 |
| `AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift:158` | `assertEventuallyAsync` | `await harness.bus.subscriberCount > 0 }` | minimumTurns: 50 |
| `AgentStudioTests/Core/PaneRuntime/Events/RuntimeEnvelopeHarnessTests.swift:35` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 2 }` |  |
| `AgentStudioTests/Core/PaneRuntime/Runtime/PaneRuntimeEventChannelTests.swift:33` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 10 }` | minimumTurns: 5000 |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitObservationLifetimeTests.swift:27` | `assertEventuallyAsync` | `await events.count { guard case .worktree(let envelope) = $0, case .gitWorkingDirectory(.originChang` |  |
| `AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift:295` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 2 }` | minimumTurns: 5000 |
| `AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift:411` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 4 }` | minimumTurns: 5000 |
| `AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift:474` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 1 }` | minimumTurns: 5000 |
| `AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift:529` | `assertEventuallyAsync` | `await subscriber.snapshot().count == 1 }` | minimumTurns: 5000 |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:65` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .unseenActivitySettled = $0 {` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:116` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .agentSettledActivityPromoted` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:125` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .agentSettledActivityRevoked ` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:171` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .agentSettledActivityPromoted` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:238` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .agentSettledActivityPromoted` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:247` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .agentSettledActivityRevoked ` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:287` | `assertEventuallyAsync` | `await Self.agentSettledPromotionCount(from: subscriber) == 1 }` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:293` | `assertEventuallyAsync` | `await Self.terminalActivityEvents(from: subscriber).contains { if case .agentSettledActivityRevoked ` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityAgentSettledHeuristicTests.swift:318` | `assertEventuallyAsync` | `await Self.agentSettledPromotionCount(from: subscriber) == 2 }` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityDerivedEventTests.swift:126` | `assertEventuallyAsync` | `await derivedActivities(from: subscriber).count == 1 }` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityDerivedEventTests.swift:214` | `assertEventuallyAsync` | `await derivedPaneEvents(from: subscriber).count == 1 }` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityDerivedEventTests.swift:236` | `assertEventuallyAsync` | `await derivedPaneEvents(from: subscriber).count == 2 }` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityRouterTests.swift:484` | `assertEventuallyAsync` | `await subscriber.count { envelope in RuntimeEnvelopeHarness.paneEvents(from: [envelope]).contains { ` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityRouterTests.swift:507` | `assertEventuallyAsync` | `await subscriber.count { envelope in RuntimeEnvelopeHarness.paneEvents(from: [envelope]).contains { ` |  |
| `AgentStudioTests/Helpers/GitEventPipelineHarness.swift:513` | `assertEventuallyAsync` | `let diagnostics = await bus.diagnosticsSnapshot() return diagnostics.activeSubscribers.contains { su` |  |
| `AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift:752` | `eventually` | `await bus.subscriberCount >= expectedCount }` | maxTurns: maxTurns |

### D — real OS / external asynchrony — 51 call sites

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioTests/App/WebKit/Bridge/BridgeContentWorldIsolationTests.swift:45` | `waitForPageLoad` | `if !page.isLoading { break }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductPackagedShareJourneyTestSupport.swift:216` | `waitUntil` | `guard await BridgeProductWebKitCarrierTestSupport.selectFilePath( controller.page, path: "alternate.` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductPackagedShareJourneyTestSupport.swift:252` | `waitUntil` | `let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page) guard let product` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductPackagedShareJourneyTestSupport.swift:344` | `waitUntil` | `(try? await page.callJavaScript( """ const buttonLabel = String(label); const activeHost = document.` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductPackagedShareJourneyTestSupport.swift:466` | `waitUntil` | `FileManager.default.fileExists(atPath: url.path) }` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitEmptyReviewWebKitTests.swift:49` | `waitUntil` | `guard let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot( hostedController.page ) els` | timeout: .seconds(10 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitEmptyReviewWebKitTests.swift:61` | `waitUntil` | `guard let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot( hostedController.page ) els` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:42` | `waitUntil` | `nativeCompletionSnapshot = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot( hostedControl` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:67` | `waitUntil` | `let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page) let native = awai` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:124` | `waitUntil` | `let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page) guard let dom els` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:154` | `waitUntil` | `await BridgeProductWebKitCarrierTestSupport.selectFilePath( controller.page, path: sourceOracle.path` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductRealGitFileAndReviewWebKitLiveProof.swift:165` | `waitUntil` | `let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page) return dom?.fileR` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeSchemeHandlerSpikeTests.swift:70` | `waitForTitle` | `if page.title == expectedTitle { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:78` | `waitForPageLoad` | `if !page.isLoading { break }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:79` | `waitForTitle` | `if page.title == expectedTitle { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:96` | `waitForTitle` | `if page.title == expectedTitle { return true }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:117` | `waitForPageLoad` | `if !page.isLoading { break }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeTransportIntegrationTests.swift:184` | `waitForPageLoad` | `if !page.isLoading { break }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeURLSchemeEnvelopeCapacityTests.swift:33` | `waitUntil` | `page.title.hasPrefix("capacity:") }` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:150` | `waitForPageLoad` | `if !page.isLoading { break } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:232` | `waitForPageLoad` | `if !page.isLoading { break } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:289` | `waitForPageLoad` | `if !page.isLoading { break } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/BridgeWebKitSpikeTests.swift:329` | `waitForPageLoad` | `if !page.isLoading { break } await Task.yield() }` |  |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitSurfaceSelectionJourneyTestSupport.swift:222` | `waitUntil` | `do { return try await page.callJavaScript( """ const fileHost = document.querySelector('[data-testid` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitSurfaceSelectionJourneyTestSupport.swift:265` | `waitUntil` | `let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller) guard native.lif` | timeout: .seconds(25 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift:641` | `waitUntil` | `let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page) let native = awai` | timeout: .seconds(15 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift:655` | `waitUntil` | `let dom = await BridgeProductWebKitCarrierTestSupport.domSnapshot(controller.page) let trace = await` | timeout: .seconds(20 |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitTwoPaneJourneyTestSupport.swift:688` | `waitUntil` | `let native = await BridgeProductWebKitCarrierTestSupport.nativeSnapshot(controller) return native.ne` | timeout: .seconds(10 |
| `AgentStudioTests/App/WorkspaceSurfaceCoordinatorRuntimeDispatchTests.swift:436` | `eventually` | `store.pane(sourcePane.id)?.metadata.title == "Updated Title" && store.pane(sourcePane.id)?.metadata.` |  |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverFailureTests.swift:487` | `waitForLogicalRegistrationCount` | `while client.sharedLocalObservationSnapshot().logicalRegistrationCount != expectedCount {` | timeout: .seconds(1 |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedLocalFSEventObserverTests.swift:139` | `waitForLogicalRegistrationCount` | `while client.sharedLocalObservationSnapshot().logicalRegistrationCount != expectedCount {` | timeout: .seconds(1 |
| `AgentStudioTests/Features/CommandBar/CommandBarProductionProbeWiringTests.swift:50` | `eventuallyTraceContains` | `guard turn.isMultiple(of: 10) else { continue } try await recorder.flush() let contents = try String` |  |
| `AgentStudioTests/Features/CommandBar/CommandBarProductionProbeWiringTests.swift:56` | `eventuallyTraceContains` | `guard turn.isMultiple(of: 10) else { continue } try await recorder.flush() let contents = try String` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift:454` | `assertEventuallyMain` | `(try? String(contentsOf: outputFileURL, encoding: .utf8))? .contains("\"body\":\"inbox.observedPaneC` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift:459` | `assertEventuallyMain` | `(try? String(contentsOf: outputFileURL, encoding: .utf8))? .contains("\"body\":\"inbox.focusGainedOb` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift:482` | `waitForEnvelopeTrace` | `if (try? String(contentsOf: outputFileURL, encoding: .utf8))? .contains(expectedSequence) == true {` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift:521` | `assertEventuallyMain` | `(try? String(contentsOf: outputFileURL, encoding: .utf8))? .contains("\"body\":\"inbox.observedPaneC` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift:690` | `assertEventuallyMain` | `fixture.inboxAtom.notifications.contains { $0.title == "Overflow" } }` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift:314` | `assertEventuallyAsync` | `await fixture.router.flushTraceRecords() return (try? String(contentsOf: outputFileURL, encoding: .u` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift:358` | `assertEventuallyAsync` | `await fixture.router.flushTraceRecords() return (try? String(contentsOf: outputFileURL, encoding: .u` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterTests.swift:430` | `assertEventuallyAsync` | `await fixture.router.flushTraceRecords() guard let outputFileURL = traceRuntime.outputFileURL else {` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/PaneFocusTrackerTests.swift:104` | `assertEventuallyMain` | `guard let contents = try? String(contentsOf: outputFileURL, encoding: .utf8) else { return false } r` |  |
| `AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPresenterTests.swift:146` | `assertEventuallyMain` | `(try? String(contentsOf: outputFileURL, encoding: .utf8))? .contains("\"body\":\"paneInbox.presentat` |  |
| `AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPresenterTests.swift:199` | `assertEventuallyMain` | `(try? String(contentsOf: outputFileURL, encoding: .utf8))? .contains("\"body\":\"paneInbox.rowActiva` |  |
| `AgentStudioTests/Helpers/ZmxTestHarness.swift:231` | `fallbackWaitForSessionSocket` | `if FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists { return true }` | timeout: timeout |
| `AgentStudioTests/Infrastructure/ProcessExecutorTests.swift:333` | `waitForProcessIdentifier` | `if let contents = try? String(contentsOf: url, encoding: .utf8), let processIdentifier = pid_t(conte` |  |
| `AgentStudioTests/Integration/ZmxE2ETests.swift:30` | `waitForObservedSessionIdentity` | `if let identity = try await backend.observeSessionIdentity(sessionID) { return identity } } catch Zm` |  |
| `AgentStudioTests/Integration/ZmxE2ETests.swift:62` | `waitForObservedSessionIdentity` | `if let identity = try await backend.observeSessionIdentity(sessionID) { return identity } } catch Zm` |  |
| `AgentStudioTests/Integration/ZmxE2ETests.swift:98` | `waitForObservedSessionIdentity` | `if let identity = try await backend.observeSessionIdentity(sessionID) { return identity } } catch Zm` |  |
| `AgentStudioTests/Integration/ZmxE2ETests.swift:240` | `waitForObservedSessionIdentity` | `if let identity = try await backend.observeSessionIdentity(sessionID) { return identity } } catch Zm` |  |
| `AgentStudioTests/Integration/ZmxE2ETests.swift:263` | `waitForObservedSessionIdentity` | `if let identity = try await backend.observeSessionIdentity(sessionID) { return identity } } catch Zm` |  |

### E — AppKit / SwiftUI view or window state — 27 call sites

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioTests/App/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift:161` | `assertEventuallyMain` | `inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarActiveFilterChip") == 1` |  |
| `AgentStudioTests/App/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift:168` | `assertEventuallyMain` | `inboxSidebarAccessibleElementCount(in: hostingView, identifier: "inboxSidebarActiveFilterChip") == 0` |  |
| `AgentStudioTests/App/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift:812` | `assertEventuallyMain` | `inboxSidebarAccessibleElementLabels(in: hostingView, identifier: "inboxSourceGroupHeader") .contains` |  |
| `AgentStudioTests/App/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift:893` | `assertEventuallyMain` | `inboxSidebarAccessibleElementLabels(in: hostingView, identifier: "inboxSourceGroupHeader") .contains` |  |
| `AgentStudioTests/App/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift:916` | `assertEventuallyMain` | `inboxSidebarAccessibleElementLabels(in: hostingView, identifier: "inboxSourceGroupHeader") .contains` |  |
| `AgentStudioTests/App/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift:470` | `eventually` | `let actionRow = findAccessibleElement( in: hostingView, identifier: "paneInboxNotificationRow.\(acti` |  |
| `AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift:259` | `eventually` | `harness.window.firstResponder === secondHost }` |  |
| `AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift:297` | `eventually` | `harness.window.firstResponder === drawerHost }` |  |
| `AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift:306` | `eventually` | `harness.window.firstResponder === drawerHost }` |  |
| `AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift:348` | `eventually` | `harness.window.firstResponder === contentView }` |  |
| `AgentStudioTests/App/Panes/DraggableTabBarHostingViewTests.swift:39` | `eventually` | `hostingView.tabBarAdapter?.tabs.map(\.id) == [secondTab.id, firstTab.id] }` |  |
| `AgentStudioTests/App/Panes/Hosting/FlatTabStripContainerAllMinimizedTests.swift:72` | `eventually` | `findAllMinimizedAccessibilityElement( in: hostingView, identifier: "collapsed-pane-bar-arrangements"` |  |
| `AgentStudioTests/App/Panes/Hosting/PaneManagementTrailingControlTests.swift:138` | `eventually` | `hostingView.layoutSubtreeIfNeeded() return findAccessibilityView( in: hostingView, identifier: "pane` |  |
| `AgentStudioTests/App/Views/Panes/DraggableTabBarWindowDragTests.swift:208` | `eventually` | `fixture.hostingView.tabBarAdapter?.tabs.map(\.id) == fixture.tabIds }` |  |
| `AgentStudioTests/App/Views/Panes/DrawerPaneHostPublicationTests.swift:60` | `eventually` | `drainDrawerPresentationRunLoop() hosting.layoutSubtreeIfNeeded() return panelAppeared }` |  |
| `AgentStudioTests/App/Views/Panes/DrawerPaneHostPublicationTests.swift:71` | `eventually` | `drainDrawerPresentationRunLoop() hosting.layoutSubtreeIfNeeded() return host.window === window && !h` |  |
| `AgentStudioTests/App/Views/Panes/DrawerPaneHostPublicationTests.swift:87` | `eventually` | `drainDrawerPresentationRunLoop() hosting.layoutSubtreeIfNeeded() return replacement.window === windo` |  |
| `AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift:121` | `assertEventuallyMain` | `harness.window.contentView?.layoutSubtreeIfNeeded() return tabBarHostingView.tabFrameInView(for: tab` |  |
| `AgentStudioTests/App/Windows/SidebarSurfaceHostSwitchGuardTests.swift:56` | `waitForEngagement` | `if iteration.isMultiple(of: 100) { hostingView.layoutSubtreeIfNeeded() }` |  |
| `AgentStudioTests/App/Windows/SidebarSurfaceHostSwitchGuardTests.swift:75` | `waitForTableView` | `if iteration.isMultiple(of: 100) { hostingView.layoutSubtreeIfNeeded() if let tableView = firstDesce` | maxIterations: 2000 |
| `AgentStudioTests/Core/Views/ArrangementPanelMountTests.swift:243` | `assertEventuallyMain` | `mountedRenameField = findArrangementRenameField(in: hostingView) return mountedRenameField != nil }` |  |
| `AgentStudioTests/Core/Views/ArrangementPanelMountTests.swift:249` | `assertEventuallyMain` | `window.firstResponder === renameField.currentEditor() }` |  |
| `AgentStudioTests/Core/Views/ArrangementPanelMountTests.swift:255` | `assertEventuallyMain` | `renameField.currentEditor() == nil && window.firstResponder !== fieldEditor }` |  |
| `AgentStudioTests/Core/Views/Panes/CollapsedPaneBarArrangementPanelTests.swift:108` | `assertEventuallyMain` | `findAccessibilityElement( in: NSApp.windows.compactMap(\.contentView), identifier: visibilityIdentif` |  |
| `AgentStudioTests/Core/Views/Panes/CollapsedPaneBarArrangementPanelTests.swift:123` | `assertEventuallyMain` | `findAccessibilityElement( in: NSApp.windows.compactMap(\.contentView), identifier: visibilityIdentif` |  |
| `AgentStudioTests/Core/Views/Panes/CollapsedPaneBarArrangementPanelTests.swift:202` | `assertEventuallyMain` | `findAccessibilityElement( in: NSApp.windows.compactMap(\.contentView), identifier: zoomIdentifier ) ` |  |
| `AgentStudioTests/Core/Views/Panes/CollapsedPaneBarArrangementPanelTests.swift:217` | `assertEventuallyMain` | `findAccessibilityElement( in: NSApp.windows.compactMap(\.contentView), identifier: zoomIdentifier ) ` |  |

### F — NEGATIVE wait (budget must expire) — 3 call sites

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioTests/Features/Bridge/BridgePaneProductSessionOwnerTests.swift:196` | `waitForActiveWorkerInstance` | `if await owner.activeInstallation?.bootstrap.workerInstanceId == workerInstanceId { return true }` |  |
| `AgentStudioTests/Features/Bridge/BridgePaneProductSessionOwnerTests.swift:253` | `waitForActiveWorkerInstance` | `if await owner.activeInstallation?.bootstrap.workerInstanceId == workerInstanceId { return true }` |  |
| `AgentStudioTests/Integration/FilesystemGitPipelineRegistrationTests.swift:110` | `neverArrives` | `if await condition() { Issue.record("\(description), but it arrived") return false` |  |

### G — other / unclear — 22 call sites

| file:line | helper | condition reads | budget override |
| --- | --- | --- | --- |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:38` | `waitForBodyWrite` | `#expect(await probe.waitForBodyWrite())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:46` | `waitForCancellation` | `#expect(await probe.waitForCancellation())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:72` | `waitForBodyWrite` | `#expect(await probe.waitForBodyWrite())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:155` | `waitForBodyWrite` | `#expect(await probe.waitForBodyWrite())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:164` | `waitForCancellation` | `#expect(await probe.waitForCancellation())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:184` | `waitForCancellation` | `#expect(await probe.waitForCancellation())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:213` | `waitForBodyWrite` | `#expect(await probe.waitForBodyWrite())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPResponseCancellationTests.swift:221` | `waitForCancellation` | `#expect(await probe.waitForCancellation())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:63` | `waitForConnectionClose` | `#expect(await probe.waitForConnectionClose())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:108` | `waitForBodyWrite` | `#expect(await probe.waitForBodyWrite())` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:115` | `waitForCancellation` | `let upstreamWasCancelled = await probe.waitForCancellation()` |  |
| `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:182` | `waitForBodyWrite` | `#expect(await probe.waitForBodyWrite())` |  |
| `AgentStudioTests/App/WorkspaceCommandGestureOrderingTests.swift:31` | `eventually` | `predecessorStarted }` |  |
| `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:207` | `waitUntilRecorded` | `if lock.withLock({ registrations.contains(expectedRegistration) }) { return true }` |  |
| `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:216` | `waitUntilRecorded` | `if lock.withLock({ registrations.contains(expectedRegistration) }) { return true }` |  |
| `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:283` | `waitUntilRecorded` | `if lock.withLock({ registrations.contains(expectedRegistration) }) { return true }` |  |
| `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:289` | `waitUntilRecorded` | `if lock.withLock({ registrations.contains(expectedRegistration) }) { return true }` |  |
| `AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterZoomObservationTests.swift:84` | `assertEventuallyMain` | `observedPaneId != nil }` |  |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionActivityDemandTests.swift:460` | `waitForStableKey` | `) async { where adapter.cachedProjectionRequest?.snapshot.repos.first(where: { $0.id == repo.id \|\| a` |  |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionActivityDemandTests.swift:574` | `waitForStableKey` | `) async { where adapter.cachedProjectionRequest?.snapshot.repos.first(where: { $0.id == repo.id \|\| a` |  |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift:159` | `waitUntilStarted` | `return }` |  |
| `AgentStudioTests/Features/Terminal/State/TerminalActivityRouterAttentionTests.swift:155` | `assertEventuallyMain` | `restartRequested }` |  |
## (d) Event-driven exemplars already in the test tree

These do **not** poll. They are the shapes a replacement can copy. All paths relative to `Tests/`.

### Continuation-parked waiters (the dominant correct pattern)

| file:line | type / method | How it wakes |
| --- | --- | --- |
| `AgentStudioTests/Features/Bridge/BridgePaneProductFileBootstrapSuspensionTests.swift:368` | `private actor FileBootstrapLifecycleRecorder` | Records lifecycle facts; `waitForFileProducerFinished(count:)` (`:417`), `waitForFileProducerStarted(count:)` (`:424`), `waitForResumeDispatch()` (`:431`) return immediately if the count is already met, else park a `CheckedContinuation` resumed by the next recorded fact. |
| `AgentStudioTests/Features/Bridge/BridgePaneProductFileBootstrapSuspensionTests.swift:288` | `private actor FileBootstrapSnapshotBuilderGate` | Per-invocation `startWaiters` / `cancellationWaiters` / `releaseContinuations` dictionaries; `waitUntilCancelled(invocation:)` (`:346`) and `waitUntilStarted(invocation:)` (`:353`). |
| `AgentStudioTests/Helpers/WorkspaceSurfaceCoordinatorTestHelpers.swift:61` | `@MainActor final class ExactEventAcknowledgement<Event>` | `record(_:)` (`:70`) matches the event against parked predicates and resumes; `wait(where:)` (`:79`) drains an already-recorded match first, else parks. Predicate-keyed, so ordering is explicit. |
| `AgentStudioTests/TestSupport/EventBusHarness.swift:5` | `actor RecordedEventBuffer<Envelope>` | Buffers bus envelopes and resumes a parked waiter on arrival (`:28`). Lives in the same file as the two polling `assertEventually*` helpers. |
| `AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomTestSupport.swift:9` | `final class EagerDerivedAtomTestSignal` | `Mutex`-guarded waiter map; `signal()` (`:22`) resumes all, `wait()` (`:34`) parks with its own timeout task. |
| `AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomTestSupport.swift:192` | `EagerDerivedAtomCompletionRecorder` | `wait(for: ProjectionCompletion)` (`:220`) parks until the exact completion is recorded. |
| `AgentStudioTests/Features/Bridge/BridgeReviewSourceProviderFake.swift:259` | `actor BridgeComparisonGate` | `waitForStartedComparisonCount(_:)` (`:279`) parks a `StartedComparisonWaiter(requestedCount:continuation:)`; `waitUntilReleased()` (`:270`). |
| `AgentStudioTests/Features/Bridge/BridgeReviewSourceProviderFake.swift:314` | `actor BridgeContentLoadGate` | Same shape: `waitForStartedLoadCount(_:)` (`:334`), `waitForFinishedContentLoadCount(_:)` (`:217` on the fake itself). |
| `AgentStudioTests/App/WebKit/Bridge/BridgeProductWebKitCarrierControllerTestSupport.swift:86` | `waitForAcceptedApplication(publicationId:timeout:)` | Fast-path check, then a `TaskGroup` racing a continuation-backed event wait against `ContinuousClock().sleep(for: timeout)`. Timeout is a failure bound, not the polling mechanism. |
| `AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeProductWebKitCarrierTestSupport.swift:482` | `waitForReplayFailureState(timeout:)` | Same event-vs-timeout race shape. |

There are **380** `CheckedContinuation<` declarations across **122** test files — this pattern is already the majority idiom for test doubles; the polling helpers sit *on top of* doubles that mostly could signal instead.

### Stream-driven waits (`for await`)

| file:line | Shape |
| --- | --- |
| `AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapSmokeTests.swift:266` | `waitForFirstRequest(timeout:)` — `TaskGroup` racing `for await request in requestStream` against `clock.sleep(for: timeout)`, `group.cancelAll()` on first result. |
| `AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapSmokeTests.swift:299`, `:334` | `waitForRequest(containing:timeout:)` / `waitForRequest(pathSuffix:containing:timeout:)` — same, with a predicate on the streamed value. |
| `AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPBootstrapSmokeTests.swift:373` | `waitForReady(timeout:)` — same, over `readyStream`. |
| `AgentStudioTests/TestSupport/EventBusHarness.swift:63`, `:71`, `:79` | `RecordingSubscriber` consumes `for await event in stream` / `in subscription` on a dedicated task. |
| `AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorFilteringTests.swift:230`, `:270`, `:365` | `for await envelope in stream` with an in-loop break condition. |
| `AgentStudioTests/Core/PaneRuntime/Sources/DarwinCompositeFSEventContinuityTests.swift:426`, `:531` | `for await item in client.events()` / `for await _ in openedEvents`. |

**73** `for await` sites total in the test tree.

### Production-barrier delegation (the one polling helper that already does it right)

`AgentStudioTests/TestSupport/EventBusHarness.swift:206` — `waitForBusSubscriberRegistration(_:subscriberName:)` is a one-line delegate to the production `EventBus.waitForSubscriberRegistration(subscriberName:)` (continuation-parked). Its sibling `waitForBusSubscriberCount(_:atLeast:minimumTurns:)` at `:193` polls instead, and `assertBusDrained` at `:214` polls `subscriberCount == 0`.

### Observation-based change detection

`withObservationTracking` appears **135** times across the tests — but as one-shot "did this atom notify?" assertions, not as waits. Densest files: `AgentStudioTests/App/ObservableStoreTests.swift` (16), `AgentStudioTests/Core/Stores/RepoCacheAtomFamilyTests.swift` (11), `AgentStudioTests/Infrastructure/AtomLib/AtomFamilyObservationTests.swift` (8), `AgentStudioTests/Core/State/MainActor/Atoms/RepositoryTopologyAtomObservationTests.swift` (8). There are **zero** uses of the Swift 6.2 `Observations(...)` async sequence in either `Tests/` or `Sources/`.

## (e) Production quiescence / drain / barrier APIs a test could await

Inventory only. `grep -rnE "func \w*(rain|ettle|uiesc|arrier|aitFor|aitUntil|dle|lush)\w*\(" Sources --include='*.swift'` → 306 matches; below are the non-private `async` ones. Paths relative to `Sources/AgentStudio/`. Entries marked ✓ were read; the rest are listed from the declaration only.

### Event bus / runtime

| file:line | API | Guarantee |
| --- | --- | --- |
| `Core/RuntimeEventSystem/Events/EventBus.swift:347` | `waitForSubscriberRegistration(subscriberName:)` | ✓ Returns immediately if a subscriber with that name is registered, else parks a continuation resumed at registration. |
| `Core/RuntimeEventSystem/Contracts/RepositoryFactSourceUpdate.swift:31` | `settlement()` | Awaits the outcome of one repository-fact source update. |
| `App/Coordination/FilesystemGitPipeline.swift:47` | `settlement()` | Awaits per-source update outcomes for the whole pipeline. |
| `App/Coordination/FilesystemGitPipeline.swift:303` | `waitForRepositoryFactDemandAdmission()` | Awaits demand admission for repository facts. |
| `App/Coordination/FilesystemGitPipeline.swift:447` | `waitForRecomputation(...)` | Awaits a named recomputation. |
| `App/Coordination/RepositoryFactDemandCoordinator.swift:219` | `waitUntilIdle()` | ✓ Returns immediately when no `deliveryTask` exists, else parks in `idleWaiters` until delivery finishes. |
| `App/Coordination/BackgroundFactApplyGovernor.swift:200` | `flushPending()` | Forces the pending-fact drain loop to run out. |
| `App/Commands/WorkspaceActionExecutor.swift:269` | `stopAcceptingCommandsAndDrain()` | Closes command intake and awaits in-flight commands. |
| `App/Coordination/WorkspaceCacheCoordinator+Retention.swift:7` | `waitForRetentionCommit()` | Awaits the retention commit. |
| `App/Coordination/WorkspaceSurfaceCoordinator+BridgeLifecycle.swift:12` | `drainBridgePaneRetirements()` | Awaits retiring Bridge pane work. |
| `App/Coordination/WorkspaceSurfaceCoordinator+BridgePaneActivity.swift:219` | `drainBridgeGitReadActivityPropagation()` | Awaits git-read activity propagation. |
| `App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift:54`, `:60` | `waitForFilesystemRootsAndActivitySyncIdle()`, `syncFilesystemRootsAndActivityUntilIdle()` | Awaits filesystem root/activity sync reaching idle. |
| `App/Coordination/WorkspaceSurfaceCoordinator+RepositoryFactDemand.swift:16` | `settleRepositoryFactDemandAdmissionForPerformanceProof()` | Settles demand admission (already a proof seam). |
| `App/Boot/AppDelegate+ShellCommandHandling.swift:263` | `waitForRepositoryFactUpdatesToSettle()` | Awaits repository-fact update settlement. |
| `App/Boot/AppDelegate+WorkspaceBoot.swift:687` | `waitForTraceIdentityRefreshIdle()` | Awaits trace-identity refresh idle. |

### Git / filesystem sources

| file:line | API | Guarantee |
| --- | --- | --- |
| `Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift:558` | `waitForCompletion(after: generation)` | ✓ Parks a continuation until `completionGeneration` passes the given generation; cancellation-aware. |
| `Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift:253` | `waitForPhysicalCompletion(after: generation)` | Generation-keyed wait for the physical git pass (protocol default at `Git/GitWorkingTreeStatusProvider.swift:297`/`:316`). |
| `Core/RuntimeEventSystem/Git/AgentStudioGitWorkingTreeStatusProvider.swift:587` | `waitUntilInactive(_ rootPath:)` | Awaits no active work for one root. |
| `Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector+DeadlineRefresh.swift:184` | `waitForVisibilityAdmission()` | ✓ `while let activeTask = visibilityAdmissionTask { await activeTask.value }` — task-join, not a spin. |
| `Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector+RefreshAttribution.swift:138` | `waitForRemoteReferenceRecomputation(...)` | Awaits a remote-reference recomputation. |
| `Core/RuntimeEventSystem/Git/RemoteReferenceRefreshActor+ExplicitUpdates.swift:14` | `waitUntilIdle()` | ✓ Returns if `!hasOutstandingPhysicalWork`, else parks in `idleWaiters`. |
| `Core/RuntimeEventSystem/Filesystem/FSEventStreamClient.swift:193`, `:205` | `captureActivityBarrier()` | Captures an `FSEventActivityBarrier` — the intended "has FSEvent activity reached here" token. |
| `Core/RuntimeEventSystem/Filesystem/RepositoryLocalActivityProjector.swift:199` | `commitBarrier(_:)` | Commits a local-activity barrier; returns whether it was still current. |
| `Core/RuntimeEventSystem/Filesystem/GitCleanContinuityWitness.swift:137`, `:159`, `:167` | `beginBarrier`, `barrierIsCurrent`, `commitBarrier` | Continuity-barrier lifecycle (sync). |
| `Infrastructure/RepoScannerValidationExecutor.swift:388` | `waitUntilPhysicalJobCount(_:)` | ✓ Returns if already at or below the count, else parks in `physicalDrainWaiters` keyed by that count. |

### Bridge

| file:line | API | Guarantee |
| --- | --- | --- |
| `Features/Bridge/Runtime/BridgePaneWorktreeRefreshDriver.swift:293` | `closeAndDrain()` | ✓ Closes intake, cancels active/retiring file tasks and awaits each `task.value` (and the presentation-transition tail). |
| `Features/Bridge/Transport/BridgeContentDemandAdmission.swift:139` | `closeAndDrain()` | ✓ Closes admission and joins the background cooldown/pacing tasks. |
| `Features/Bridge/Transport/BridgeContentDemandAdmission.swift:127`, `:134` | `waitForBackgroundTurn(_:)` / `waitForBackgroundTurn()` | Awaits the next admitted background turn. |
| `Features/Bridge/Transport/BridgePaneProductMetadataCoordinator.swift:169` | `closeAndDrain()` | Closes the metadata coordinator and drains producers. |
| `Features/Bridge/Transport/BridgePaneProductMetadataCoordinator+ProducerLifecycle.swift:301` | `static drain(_ tasks:)` | Joins a list of producer tasks. |
| `Features/Bridge/Transport/BridgePaneProductSchemeProvider.swift:959` | `closeAndDrain()` | Closes the scheme provider and drains. |
| `Features/Bridge/Transport/BridgePaneProductSchemeProvider+ProducerSupport.swift:28` | `waitForProducerCancellation()` | Awaits producer cancellation. |
| `Features/Bridge/Transport/BridgeProductSchemeSessionRouter.swift:96` | `waitForDrain()` | ✓ Returns if `snapshot.hasZeroResidue`, else parks in `drainWaiters`. |
| `Features/Bridge/Transport/BridgeProductStreamWebKitFeasibilityOracle.swift:146`, `:196` | `waitUntilFrameObserved(_:)`, `waitUntilZeroProducerResidue()` | Frame-receipt and residue barriers. |
| `Features/Bridge/Runtime/Construction/BridgeSharedReviewContentBacking.swift:157` | `waitUntilInvalidationCleanupCompletes()` | Awaits shared-review invalidation cleanup. |
| `Features/Bridge/Runtime/ReviewFoundation/BridgeReviewContentLoaderCache.swift:195` | `closeAndDrain()` | Closes and drains the review content loader cache. |
| `Features/Bridge/Runtime/Telemetry/BridgePerformanceTraceRecorder.swift:12`, `:85` | `drain()` | Drains Bridge performance trace records. |
| `Features/Bridge/Transport/WorktreeAnnotations/BridgePaneProductWorktreeAnnotationNotificationSource.swift:141` | `closeAndDrain()` | No-op conformance in this type. |

### Terminal / inbox / repo explorer / atoms

| file:line | API | Guarantee |
| --- | --- | --- |
| `Features/Terminal/Routing/TerminalActivityRouter.swift:205` | `waitForPendingDerivedActivityPosts()` | ✓ Documented test-only seam: `await derivedActivityPostTask?.value`. |
| `Features/Terminal/Routing/TerminalActivityRouter.swift:575`, `:580` | `waitForPendingAttentionSettlement()`, `waitForPendingAttentionDelivery()` | ✓ Join the attention settlement / settlement+delivery tasks. |
| `Features/Terminal/Restore/TerminalActivationSchedulerContracts.swift:117`, `:152` | `waitUntilReleased()` | Awaits startup-deferral release, returning `StartupDeferralOutcome`. |
| `Features/Terminal/Ghostty/GhosttyActionRouter.swift:606`, `+LocalActions.swift:258`, `+Tracing.swift:28` | `drainTraceRuntimeForActionRouting()`, `drainLocalActions(for:)`, `drain()` | Drain Ghostty action/trace queues. |
| `Features/InboxNotification/Routing/PaneFocusTracker.swift:83` | `waitForPendingDelivery()` | ✓ `await pendingDeliveryTask?.value`. |
| `Features/InboxNotification/Routing/InboxNotificationRouter.swift:179` | `flushTraceRecords()` | Flushes router trace records (already used by tests before reading the JSONL file). |
| `Features/InboxNotification/Routing/InboxPromoter.swift:108`, `Views/PaneInboxNotificationPresenter.swift:111` | `drainTraceRecords()` | Drain inbox trace records. |
| `Features/RepoExplorer/RepoExplorerProjectionAdapter.swift:242` | `stopAndDrain()` | ✓ `stop()` then `await projectionFamily.stopAndDrain()`. |
| `Features/RepoExplorer/RepoExplorerTableMaterializer.swift:403` | `drainViewportPublication()` | Awaits viewport publication. |
| `Features/RepoExplorer/Models/RepoExplorerPerformanceTelemetry.swift:404` | `drainForTests()` | Explicit test drain for telemetry. |
| `Infrastructure/AtomLib/EagerDerivedAtom.swift:237` | `stopAndDrain()` | ✓ `stop()` then `await lastProjectionTask.value`. |
| `Infrastructure/AtomLib/EagerDerivedAtomFamily.swift:152`, `:178` | `removeAndDrain(for:)`, `stopAndDrain()` | Per-key and whole-family projection drains. |
| `Infrastructure/AtomLib/AtomPerformanceTelemetry.swift:45` | `drainForTests()` | Explicit test drain. |
| `Core/State/MainActor/Atoms/WindowLifecycleAtom.swift:182` | `waitUntilFirstInteractiveFramePublished()` | ✓ Returns `.completed` if already published, else parks a UUID-keyed continuation with a policy-bounded fallback-timeout task. |

### Persistence / diagnostics

| file:line | API | Guarantee |
| --- | --- | --- |
| `Core/State/MainActor/Persistence/WorkspaceStore.swift:408` | `flushAsync()` | ✓ Cancels the debounced save task and awaits `persistNow()`. |
| `Core/State/MainActor/Persistence/RepoCacheStore.swift:194`, `SidebarCacheStore.swift:68`, `UIStateStore.swift:83`, `RepositoryTopologyStore.swift:51` | `flushAsync(...)` | Force the debounced save for that store/workspace. |
| `Core/State/MainActor/Persistence/EntityRecencyStore.swift:89`, `:96`, `:108` | `flushApplicationAsync()`, `flushWorkspaceAsync(for:)`, `flushAllAsync()` | Scoped recency flushes. |
| `Core/State/MainActor/Persistence/RepositoryTopologyStore.swift:85` | `unsettledRepositoryRetentionKeys()` | Reports retention keys not yet settled. |
| `App/Coordination/WorkspaceSettingsStore.swift:72`, `:79` | `flush(for:)`, `waitForPendingAutosave()` | ✓ `waitForPendingAutosave` is `await debouncedSaveTask?.value`. |
| `App/Boot/AppDelegate+Termination.swift:22`, `:31` | `runFirstPersistenceFlushAfterWorkspaceCacheShutdown(...)`, `flushApplicationStateBeforeTermination(store:)` | Termination-time flush ordering. |
| `Infrastructure/Diagnostics/AgentStudioTraceEventQueue.swift:93`, `:131` | `flush()`, `drain()` | ✓ `drain()` closes the queue, finishes the continuation, joins the worker task, then flushes the runtime. |
| `Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift:730`, `:739` | `drain()`, `flush()` | Recorder drain/flush. |
| `Infrastructure/Diagnostics/AgentStudioStartupTraceRecorder.swift:181`, `AgentStudioTCCDiagnosticRecorder.swift:272` | `drain()` | Recorder drains. |
| `Infrastructure/Diagnostics/AgentStudioTraceRuntime.swift:209`, `AgentStudioTraceSink.swift:5`, `AgentStudioJSONLTraceSink.swift:18`, `AgentStudioOTLPTraceSink.swift:20`, `AgentStudioOTLPBootstrapper.swift:9`/`:29` | `flush()` | Sink/runtime flush contracts. |
| `AgentStudioBridgeDevelopmentServer/BridgeDevelopmentSeededWorktreeObservation.swift:164` | `stopFactAdmissionAndDrainRouting()` | Stops fact admission and drains routing. |

## (f) Inline polling loops not wrapped in any helper

**162** loops of the form `for _ in 0..<N { ... await Task.yield() }` (or `while ContinuousClock.now < deadline { ... await Task.yield() }`) sit directly in `@Test` bodies or in non-wait helper bodies, outside the 123 catalogued helpers. Densest files:

| file | loops |
| --- | ---: |
| `AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift` | 18 (all `for _ in 0..<300`) |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionActivityDemandTests.swift` | 15 |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionObservationDemandTests.swift` | 11 |
| `AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift` | 9 (`for _ in 0..<10 where !store.isDirty`) |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionDemandTests.swift` | 9 |
| `AgentStudioTests/App/Windows/RepoExplorerCommandPresentationBatchTests.swift` | 8 |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerPresentationHostViewTests.swift` | 8 |
| `AgentStudioTests/Features/Bridge/BridgeContentDemandAdmissionTests.swift` | 4 |
| `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionWorkerTests.swift` | 4 |
| `AgentStudioTests/Core/State/PaneActivityStatusAtomTests.swift` | 3 (`for _ in 0..<1000 where atom.status(for:)?.lastOutputLine != ...`) |

Two shapes dominate: a bare `for _ in 0..<300 { await Task.yield() }` used as "let the scheduler settle" with **no condition at all** (most of the `GitWorkingDirectoryProjectorTests` ones), and `for _ in 0..<N where <condition> { await Task.yield() }` which silently falls through when the budget runs out and then asserts.

The full list is reproducible with:
`grep -rn "for _ in 0\.\.<" Tests --include='*.swift'` (296 raw hits, 134 of which are inside the catalogued helpers).

## (g) Ambiguities and limits of this survey

1. **Category G (22 sites) is mostly one shape**: `Mutex`/lock-backed `Sendable` test probes read *synchronously* inside the loop — `waitForBodyWrite` (6), `waitForCancellation` (5), `waitForConnectionClose` (1) in `AgentStudioBridgeDevelopmentServerTests/BridgeDevelopmentHTTPStreamLifetimeTests.swift:216/225/234` and `...HTTPResponseCancellationTests.swift:268/277` (`cancellationRecorded.withLock { $0 }`); `waitUntilRecorded` (4) in `AgentStudioTests/Features/Bridge/BridgeProductProducerObservationPacingTests.swift:608` (`lock.withLock { registrations.contains(...) }`); `waitUntilStarted` (1) in `AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionBrokerTests.swift:63` (`hasStarted.withLock { $0 }`). These are neither A (not `@Observable`, no MainActor publication) nor B (no `await`, not actor-isolated) — they are shared mutable test state behind a lock. The remaining 5: `waitForStableKey` (2, a compound `where` clause my extractor could not reduce), and 3 bare captured locals set by a callback (`AgentStudioTests/App/WorkspaceCommandGestureOrderingTests.swift:31` waits on `predecessorStarted`; `AgentStudioTests/Features/Terminal/State/TerminalActivityRouterAttentionTests.swift:155` on `restartRequested`) — the *writer* is what matters there and I did not trace each writer.

2. **Negative waits (F) are almost certainly undercounted.** I could only confirm 3 mechanically: `neverArrives` (`AgentStudioTests/Integration/FilesystemGitPipelineRegistrationTests.swift:193`, called at `:110`) and two `waitForActiveWorkerInstance` calls whose results are asserted false (`AgentStudioTests/Features/Bridge/BridgePaneProductSessionOwnerTests.swift:196` → `#expect(!secondPublishedBeforeFirstRevocation)` at `:205`; `:253` → `:262`). Detection required the result to be bound to a `let` and negated within 14 lines. A negative wait expressed as "poll for N turns, then assert a count is still 0" reads identically to a positive wait in my extraction and will have landed in A/B/C. Anyone designing the replacement should re-scan for that shape by hand; it is the class where "budget expired" *is* the passing outcome and therefore the class that cannot be replaced by an event wait at all.

3. **Category inheritance for single-purpose helpers.** For the ~74 helpers that embed their own condition, every call site inherits the helper's category. That is correct for what the loop observes, but it hides call-site-specific intent (e.g. `waitForRefreshAdmissionSettledWhileHidden` reads MainActor controller state → A, yet its *purpose* is closer to "prove the hidden pane retained exactly one dirty fact").

4. **Name-collision attribution.** 259 call sites were dropped because their helper name also has a non-polling definition. I verified the two large groups by hand (`waitUntilStarted`: 39 definitions, 38 of them continuation/semaphore-based; `waitForStartedComparisonCount`: all 25 call sites use the actor method form, and the polling free function at `App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:37` has **zero** call sites — it is dead). I did not individually verify every one of the remaining dropped sites, so the 678 total is a *lower* bound by a small margin.

5. **Multi-line conditions are truncated** to 100 characters in the tables, so a few condition excerpts show only the first clause of a compound predicate.

6. **`AgentStudioTests/Features/Bridge/ObservationSpikeTests.swift:264` (`advanceClock`)** is in the helper table but is not a wait — it is a fake-clock stepper that yields between steps. It has no call sites outside its own file's spike tests.

7. **The dual-budget helpers are the only ones whose failure mode is documented.** `EventBusHarness.swift:140-148` carries a comment explaining the turn-floor + wall-clock design and why neither bound alone is reliable. Every other budget in the table is an unexplained literal (`300`, `512`, `1000`, `2000`, `10_000`, `20_000`, `50_000`, `200_000`, `300_000`).

8. **A vs B is a heuristic, not a compiler decision.** No type checking was run (workspace is read-only, no builds). Isolation was inferred from `await` presence, the helper's enclosing declaration, and parameter names. A MainActor `@Observable` read through an `await`-ed accessor, or an actor-isolated double read through a `nonisolated` property, would be misfiled.
