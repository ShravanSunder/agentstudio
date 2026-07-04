#if DEBUG
    enum BridgeReviewStartupTreeClickProbeJavaScript {
        static let counterState = """
                  let reviewTreeClickProbeCaptureHandlerInvokedCount = reviewTreeClickProbeNumber('captureHandlerInvokedCount', 0);
                  let reviewTreeClickProbeCaptureHandlerResolvedRowItemId = reviewTreeClickProbeString('captureHandlerResolvedRowItemId', '');
                  let reviewTreeClickProbeSelectionCommandIssuedCount = reviewTreeClickProbeNumber('selectionCommandIssuedCount', 0);
                  let reviewTreeClickProbeSelectionCommandAcceptedCount = reviewTreeClickProbeNumber('selectionCommandAcceptedCount', 0);
                  let reviewTreeClickProbeSelectionCommandLastResult = reviewTreeClickProbeString('selectionCommandLastResult', 'missing');
                  let reviewTreeClickProbeHandlerInvokedDelta = reviewTreeClickProbeNumber('handlerInvokedDelta', 0);
                  let reviewTreeClickProbeSelectionCommandIssuedDelta = reviewTreeClickProbeNumber('selectionCommandIssuedDelta', 0);
                  let reviewTreeClickProbeLateSelectedMatches = reviewTreeClickProbe.lateSelectedMatches === true;
                  let reviewTreeClickProbePollsToSelectionMatch = reviewTreeClickProbeNumber('pollsToSelectionMatch', -1);
                  let reviewTreeClickProbeClickToSelectionMs = reviewTreeClickProbeNumber('clickToSelectionMs', -1);
                  const reviewTreeClickProbeBreadcrumbState = () => ({
                    targetRowPathAtFind: reviewTreeClickProbeTargetRowPathAtFind, targetRowIdAtFind: reviewTreeClickProbeTargetRowIdAtFind,
                    targetRowIdAtDispatch: reviewTreeClickProbeTargetRowIdAtDispatch, targetRowConnectedAtDispatch: reviewTreeClickProbeTargetRowConnectedAtDispatch,
                    targetRowSameIdAtDispatch: reviewTreeClickProbeTargetRowSameIdAtDispatch, renderedRowCountAtFind: reviewTreeClickProbeRenderedRowCountAtFind,
                    renderedRowCountAtDispatch: reviewTreeClickProbeRenderedRowCountAtDispatch, renderedRowCountDeltaBeforeDispatch: reviewTreeClickProbeRenderedRowCountDeltaBeforeDispatch,
                    dispatchResult: reviewTreeClickProbeDispatchResult, selectionPollTrace: reviewTreeClickProbeSelectionPollTrace,
                    selectionPollCount: reviewTreeClickProbeSelectionPollCount, selectionPollLastIndex: reviewTreeClickProbeSelectionPollLastIndex, secondClickAttempted: reviewTreeClickProbeSecondClickAttempted,
                    captureHandlerInvokedCount: reviewTreeClickProbeCaptureHandlerInvokedCount, captureHandlerResolvedRowItemId: reviewTreeClickProbeCaptureHandlerResolvedRowItemId,
                    selectionCommandIssuedCount: reviewTreeClickProbeSelectionCommandIssuedCount, selectionCommandAcceptedCount: reviewTreeClickProbeSelectionCommandAcceptedCount,
                    selectionCommandLastResult: reviewTreeClickProbeSelectionCommandLastResult, handlerInvokedDelta: reviewTreeClickProbeHandlerInvokedDelta,
                    selectionCommandIssuedDelta: reviewTreeClickProbeSelectionCommandIssuedDelta, lateSelectedMatches: reviewTreeClickProbeLateSelectedMatches,
                    pollsToSelectionMatch: reviewTreeClickProbePollsToSelectionMatch, clickToSelectionMs: reviewTreeClickProbeClickToSelectionMs
                  });
            """

        static let selectionPollState = """
                  const reviewTreeClickProbeSelectionPollBudget = 160;
                  const reviewTreeClickProbePollCadenceMs = 50;
                  const reviewTreeClickProbeSelectionMatchesCommit =
                    reviewTreeClickTargetPath.length > 0 &&
                    reviewTreeClickProbeCaptureHandlerResolvedRowItemId.length > 0 &&
                    selectedItemId === reviewTreeClickProbeCaptureHandlerResolvedRowItemId;
                  if (
                    reviewTreeClickProbeSelectionMatchesCommit &&
                    reviewTreeClickProbePollsToSelectionMatch < 0
                  ) {
                    reviewTreeClickProbePollsToSelectionMatch = Math.max(0, reviewTreeClickProbeSelectionPollCount);
                    reviewTreeClickProbeClickToSelectionMs =
                      reviewTreeClickProbePollsToSelectionMatch * reviewTreeClickProbePollCadenceMs;
                  }
                  if (
                    reviewTreeClickTargetPath.length > 0 &&
                    reviewTreeClickSelectedPath.length === 0 &&
                    !reviewTreeClickProbeSelectionMatchesCommit &&
                    reviewTreeClickProbeSelectionPollCount < reviewTreeClickProbeSelectionPollBudget
                  ) {
                    const selectionPollIndex = reviewTreeClickProbeSelectionPollCount;
                    const selectionPollEntry =
                      `${selectionPollIndex}:${reviewTreeClickProbeClip(selectedItemId || 'missing', 80)}`;
                    reviewTreeClickProbeSelectionPollTrace =
                      reviewTreeClickProbeSelectionPollTrace.length > 0
                        ? `${reviewTreeClickProbeSelectionPollTrace}|${selectionPollEntry}`
                        : selectionPollEntry;
                    reviewTreeClickProbeSelectionPollCount += 1;
                    reviewTreeClickProbeSelectionPollLastIndex = selectionPollIndex;
                  }
                  if (reviewTreeClickTargetPath.length > 0 && reviewTreeClickSelectedPath.length === 0) {
                    window.__bridgeReviewTreeClickProbe = {
                      ...reviewTreeClickProbe,
                      currentSelectedPath: reviewTreeClickCurrentSelectedPath,
                      currentSelectedItemId: reviewTreeClickCurrentSelectedItemId,
                      shellSelectedPath: reviewTreeClickShellSelectedPath,
                      selectionPollTrace: reviewTreeClickProbeSelectionPollTrace,
                      selectionPollCount: reviewTreeClickProbeSelectionPollCount,
                      selectionPollLastIndex: reviewTreeClickProbeSelectionPollLastIndex,
                      secondClickAttempted: reviewTreeClickProbeSecondClickAttempted,
                      ...reviewTreeClickProbeBreadcrumbState()
                    };
                  }
            """

        static let afterDispatchState = """
                        const reviewTreeClickProbeCaptureHandlerInvokedBeforeDispatch = reviewTreeClickProbeCaptureHandlerInvokedCount;
                        const reviewTreeClickProbeSelectionCommandIssuedBeforeDispatch = reviewTreeClickProbeSelectionCommandIssuedCount;
                        reviewTreeClickTarget.click();
                        reviewTreeClickProbeDispatchResult = 'completed';
                        const reviewTreeClickProbeAfterDispatch =
                          window.__bridgeReviewTreeClickProbe && typeof window.__bridgeReviewTreeClickProbe === 'object'
                            ? window.__bridgeReviewTreeClickProbe
                            : {};
                        reviewTreeClickProbeCaptureHandlerInvokedCount =
                          Number.isFinite(Number(reviewTreeClickProbeAfterDispatch.captureHandlerInvokedCount))
                            ? Number(reviewTreeClickProbeAfterDispatch.captureHandlerInvokedCount)
                            : reviewTreeClickProbeCaptureHandlerInvokedCount;
                        reviewTreeClickProbeSelectionCommandIssuedCount =
                          Number.isFinite(Number(reviewTreeClickProbeAfterDispatch.selectionCommandIssuedCount))
                            ? Number(reviewTreeClickProbeAfterDispatch.selectionCommandIssuedCount)
                            : reviewTreeClickProbeSelectionCommandIssuedCount;
                        reviewTreeClickProbeCaptureHandlerResolvedRowItemId =
                          typeof reviewTreeClickProbeAfterDispatch.captureHandlerResolvedRowItemId === 'string'
                            ? reviewTreeClickProbeAfterDispatch.captureHandlerResolvedRowItemId
                            : reviewTreeClickProbeCaptureHandlerResolvedRowItemId;
                        reviewTreeClickProbeSelectionCommandAcceptedCount =
                          Number.isFinite(Number(reviewTreeClickProbeAfterDispatch.selectionCommandAcceptedCount))
                            ? Number(reviewTreeClickProbeAfterDispatch.selectionCommandAcceptedCount)
                            : reviewTreeClickProbeSelectionCommandAcceptedCount;
                        reviewTreeClickProbeSelectionCommandLastResult =
                          typeof reviewTreeClickProbeAfterDispatch.selectionCommandLastResult === 'string'
                            ? reviewTreeClickProbeAfterDispatch.selectionCommandLastResult
                            : reviewTreeClickProbeSelectionCommandLastResult;
                        reviewTreeClickProbeHandlerInvokedDelta =
                          reviewTreeClickProbeCaptureHandlerInvokedCount - reviewTreeClickProbeCaptureHandlerInvokedBeforeDispatch;
                        reviewTreeClickProbeSelectionCommandIssuedDelta =
                          reviewTreeClickProbeSelectionCommandIssuedCount - reviewTreeClickProbeSelectionCommandIssuedBeforeDispatch;
            """

        static let lateSelectedState = """
                  if (reviewTreeClickTargetPath.length > 0) {
                    reviewTreeClickProbeLateSelectedMatches =
                      reviewTreeClickProbeCaptureHandlerResolvedRowItemId.length > 0 &&
                      selectedItemId === reviewTreeClickProbeCaptureHandlerResolvedRowItemId;
                    window.__bridgeReviewTreeClickProbe = {
                      ...(window.__bridgeReviewTreeClickProbe || {}),
                      currentSelectedPath: reviewTreeClickCurrentSelectedPath,
                      currentSelectedItemId: reviewTreeClickCurrentSelectedItemId,
                      shellSelectedPath: reviewTreeClickShellSelectedPath,
                      ...reviewTreeClickProbeBreadcrumbState()
                    };
                  }
            """
    }
#endif
