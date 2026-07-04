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
                    selectionCommandIssuedDelta: reviewTreeClickProbeSelectionCommandIssuedDelta, lateSelectedMatches: reviewTreeClickProbeLateSelectedMatches
                  });
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
