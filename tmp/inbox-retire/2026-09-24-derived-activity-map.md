# Derived terminal activity test map

Line references point to the restored integration file at the parent of
`5d845e1de` and the regression file at the current branch head. The integration
fixture's shared `postScrollbackBurst` helper asserts the `TerminalActivityAtom`
scrollbar total at line 986; every integration test below calls that helper at
least once. Additional terminal activity checks and event assertions are listed
per test.

In the table, `Integration:<line>` means
`Tests/AgentStudioTests/Integration/DerivedTerminalActivityNotificationIntegrationTests.swift:<line>`;
`Regression:<line>` means
`Tests/AgentStudioTests/Integration/DerivedTerminalActivityNotificationRegressionTests.swift:<line>`.

**Fixture without `InboxNotificationRouter`:** Every integration test calls
`makeFixture`, which constructs and starts the router at lines 709–747. The
tests therefore do not run unchanged without it. Their Inbox-row outcomes are
listed per test. The three row-absence checks would become vacuous if the router
were removed. The read/dismiss/re-observation tests also depend on the router's
`onPaneActivityObserved` callback forwarding an observed control to
`TerminalActivityRouter` (lines 724–727; waiter lines 936–940).

| `@Test` function | `TerminalActivityAtom` / terminal event assertions | Inbox-row assertions | Fixture without Inbox router? |
| --- | --- | --- | --- |
| `drawerChildOutputBurstReachesParentPaneInboxThroughRuntimeBus` (Integration:73) | Shared scrollbar snapshot assertion (Integration:986). | Integration:90, 92, 102–107 | No; shared fixture starts it and this test expects its emitted row. |
| `continuousOutputBurstsInSamePaneKeepOneUnreadRowUntilObserved` (Integration:113) | Shared snapshot (Integration:986); expects two `.terminalActivity(.unseenActivitySettled)` events via the event filter at Integration:929 and count assertion at Integration:124–126. | Integration:120, 128–134 | No; it asserts one coalesced router-produced row. |
| `readDismissedUnseenActivityRowResetsRuntimeWindowBeforeQuietClose` (Integration:140) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:147, 149–151, 156–161 | No; it reads, dismisses, and expects a new router-produced row; it also waits for router observation at Integration:152. |
| `markingUnseenActivityReadResetsRuntimeWindowBeforeQuietClose` (Integration:167) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:174, 176–179, 184–189 | No; it changes and expects router-produced rows; it also waits for router observation at Integration:180. |
| `twoDrawerChildrenCreateSeparateParentPaneInboxRows` (Integration:195) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:220, 231–234 | No; it expects separate rows emitted by the router. |
| `activeDrawerChildSwitchObservesCurrentUnseenActivityWindow` (Integration:240) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:259–270, 281–285 | No; row observation/read state is driven by the router callback; it waits for that observation at Integration:265. |
| `focusedPaneOutputBurstDoesNotCreatePaneInboxRow` (Integration:291) | Shared snapshot (Integration:986); direct `outputBurst.thresholdReached` assertion at Integration:305. | Integration:307 (empty rows) | No as wired; without the router the empty-row assertion is vacuous. |
| `focusedDrawerChildOutputBurstDoesNotCreatePaneInboxRow` (Integration:313) | Shared snapshot (Integration:986); direct `outputBurst.thresholdReached` assertion at Integration:330. | Integration:332 (empty rows) | No as wired; without the router the empty-row assertion is vacuous. |
| `mainPaneHiddenByOpenDrawerEmitsUnseenActivity` (Integration:338) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:350, 352–355 | No; it expects an emitted Inbox row. |
| `visibleSplitSiblingStaysObservedWhileActivePaneDrawerIsOpen` (Integration:361) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:380–386 | No; it expects the router to mark the sibling's row read and dismissed after observation. |
| `visibleSplitSiblingScrolledUpEmitsUnreadActivityForSmallOutput` (Integration:392) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:408–416 | No; it expects an emitted unread row. |
| `visibleSplitSiblingPinnedToBottomIgnoresSmallOutput` (Integration:422) | Shared snapshot (Integration:986); direct non-nil `outputBurst` assertion at Integration:438. | Integration:440–441 (empty rows and zero unread count) | No as wired; without the router the empty-row assertion is vacuous. |
| `bottomPinnedSmallOutputResetsBeforeVisibleSiblingScrollsUp` (Integration:447) | Shared snapshot (Integration:986) for both bursts; direct non-nil `outputBurst` assertion at Integration:462. | Integration:464, 475–482 | No; the later scroll-up must produce a router-owned unread row. |
| `hiddenDrawerChildEmitsUnreadActivityForSmallOutputEvenWhenPinned` (Integration:488) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:507, 511, 518, 521–524 | No; it expects an emitted row for the hidden drawer child. |
| `expandedDrawerHiddenInactiveChildEmitsUnreadActivityForSmallOutputEvenWhenPinned` (Integration:530) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:552, 556–559 | No; it expects an emitted row for the inactive drawer child. |
| `minimizedSplitSiblingStaysUnobservedEvenWhenBottomPinned` (Integration:565) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:582–587 | No; it expects the router to emit an unread row for the unobserved pane. |
| `zoomHiddenSplitSiblingStaysUnobservedEvenWhenBottomPinned` (Integration:593) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:619–624 | No; it expects the router to emit an unread row for the hidden pane. |
| `mainPaneHiddenByExpandedEmptyDrawerEmitsUnseenActivity` (Integration:630) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:640, 642–645 | No; it expects an emitted Inbox row. |
| `mainPaneHiddenByAllMinimizedDrawerEmitsUnseenActivity` (Integration:651) | Shared snapshot (Integration:986); no direct terminal event assertion. | Integration:665, 667–670 | No; it expects an emitted Inbox row. |
| `transientEntryToBottomClearsObservedPaneUnreadState` (Regression:38) | Direct final `TerminalActivityAtom` scrollbar-state assertion at Regression:88; no terminal event assertion in the test. | Regression:82–88; the test seeds its row at Regression:48–59. | No; the router starts in the fixture (Regression:122–159), and its observation callback calls `markUnseenActivityObserved` (Regression:137–139), which drives the asserted row transition. |

## Shared fixture wiring

- Integration: `makeFixture` constructs `InboxNotificationRouter` at
  `DerivedTerminalActivityNotificationIntegrationTests.swift:709–727`, starts
  it at `:746`, then starts `TerminalActivityRouter` at `:747`. Its observation
  callback forwards to `TerminalRouterBox.observeActivity`.
- Regression: `makeFixture` constructs `InboxNotificationRouter` at
  `DerivedTerminalActivityNotificationRegressionTests.swift:122–140`, starts
  it at `:158`, then starts `TerminalActivityRouter` at `:159`. Its observation
  callback calls `markUnseenActivityObserved`.
