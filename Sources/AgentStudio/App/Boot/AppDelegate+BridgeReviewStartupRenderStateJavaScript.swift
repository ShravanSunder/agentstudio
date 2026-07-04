import Foundation

@MainActor
extension AppDelegate {
    #if DEBUG
        nonisolated static var bridgeReviewObservabilitySmokeRenderStateJavaScript: String {
            """
            return JSON.stringify((() => {
              const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
              const reviewShellState =
                reviewShell !== null
                  ? 'ready'
                  : document.querySelector('[data-testid="bridge-review-metadata-loading-shell"]') !== null
                    ? 'metadata_loading'
                    : document.querySelector('[data-testid="bridge-review-projection-pending-shell"]') !== null
                      ? 'projection_pending'
                      : document.querySelector('[data-testid="bridge-review-projection-failed-shell"]') !== null
                        ? 'projection_failed'
                        : document.querySelector('[data-testid="bridge-review-empty-shell"]') !== null
                          ? 'empty'
                          : document.querySelector('[data-testid="bridge-review-metadata-failed-shell"]') !== null
                            ? 'metadata_failed'
                            : 'missing';
              const reviewCanvasBranch =
                reviewShell?.getAttribute('data-review-canvas-branch') || 'missing';
              const codeViewPanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
              const codeViewScrollOwner = document.querySelector('.bridge-code-view-scroll-owner');
              const codeViewInstance = window.__INSTANCE || null;
              const codeViewWindowSpecs = codeViewInstance?.getWindowSpecs?.() || null;
              const codeViewRenderState = codeViewInstance?.renderState || null;
              const firstCodeViewInstanceItem = codeViewInstance?.items?.[0] || null;
              const codeViewRenderedItems = codeViewInstance?.getRenderedItems?.() || [];
              const firstCodeViewRenderedItem = codeViewRenderedItems[0] || null;
              const firstCodeViewRenderedItemElement = firstCodeViewRenderedItem?.element || null;
              const firstCodeViewRenderedItemElementRect = firstCodeViewRenderedItemElement?.getBoundingClientRect();
              const selectedItemId = codeViewPanel?.getAttribute('data-selected-item-id') || '';
              const selectedDisplayPath = codeViewPanel?.getAttribute('data-selected-display-path') || '';
              const reviewShellSelectedDisplayPath =
                reviewShell?.getAttribute('data-selected-display-path') || '';
              const reviewShellSelectedContentState =
                reviewShell?.getAttribute('data-selected-content-state') || 'missing';
              const selectedDemandFailedCount =
                Number(reviewShell?.getAttribute('data-review-selected-demand-failed-count') || '0');
              const selectedDemandDeferredCount =
                Number(reviewShell?.getAttribute('data-review-selected-demand-deferred-count') || '0');
              const selectedDemandLoadedCount =
                Number(reviewShell?.getAttribute('data-review-selected-demand-loaded-count') || '0');
              const selectedDemandResultReason =
                reviewShell?.getAttribute('data-review-selected-demand-result-reason') || 'missing';
              const selectedDemandResultStatus =
                reviewShell?.getAttribute('data-review-selected-demand-result-status') || 'missing';
              const selectedDemandLoadFailureKind =
                reviewShell?.getAttribute('data-review-selected-demand-load-failure-kind') || 'missing';
              const reviewMetadataItemCount = Number(reviewShell?.getAttribute('data-review-metadata-item-count') || '0');
              const reviewMetadataTreeRowCount = Number(reviewShell?.getAttribute('data-review-metadata-tree-row-count') || '0');
              const selectedContentState = codeViewPanel?.getAttribute('data-selected-content-state') || 'missing';
              const selectedChangeKind = codeViewPanel?.getAttribute('data-selected-change-kind') || 'missing';
              const selectedContentRoleCount = Number(codeViewPanel?.getAttribute('data-selected-content-role-count') || '0');
              const selectedContentCacheKeyCount = Number(codeViewPanel?.getAttribute('data-selected-content-cache-key-count') || '0');
              const selectedContentRoles = codeViewPanel?.getAttribute('data-selected-content-roles') || '';
              const selectedContentCacheKeys = codeViewPanel?.getAttribute('data-selected-content-cache-keys') || '';
              const selectedContentCharacterCount = Number(codeViewPanel?.getAttribute('data-selected-content-character-count') || '0');
              const selectedContentLineCount = Number(codeViewPanel?.getAttribute('data-selected-content-line-count') || '0');
              const selectedMaterializedUpdateResult = codeViewPanel?.getAttribute('data-selected-materialized-update-result') || 'missing';
              const selectedMaterializedItemType = codeViewPanel?.getAttribute('data-selected-materialized-item-type') || 'missing';
              const selectedMaterializedItemVersion = Number(codeViewPanel?.getAttribute('data-selected-materialized-item-version') || '0');
              const selectedMaterializedAdditionLineCount = Number(codeViewPanel?.getAttribute('data-selected-materialized-addition-line-count') || '0');
              const selectedMaterializedDeletionLineCount = Number(codeViewPanel?.getAttribute('data-selected-materialized-deletion-line-count') || '0');
              const selectedMaterializedFileLineCount = Number(codeViewPanel?.getAttribute('data-selected-materialized-file-line-count') || '0');
              const selectedMaterializedLineCount =
                selectedMaterializedAdditionLineCount +
                selectedMaterializedDeletionLineCount +
                selectedMaterializedFileLineCount;
              const paintedProbe =
                window.__bridgeSelectedContentPaintedProbe &&
                typeof window.__bridgeSelectedContentPaintedProbe === 'object'
                  ? window.__bridgeSelectedContentPaintedProbe
                  : {};
              const paintedProbeAnchoredDeliveryEntryCount =
                Number(paintedProbe.anchoredDeliveryEntryCount || 0);
              const paintedProbeAnchoredDeliveryAnchorPresentCount =
                Number(paintedProbe.anchoredDeliveryAnchorPresentCount || 0);
              const paintedProbeAnchoredDeliverySelectedMatchCount =
                Number(paintedProbe.anchoredDeliverySelectedMatchCount || 0);
              const paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount =
                Number(paintedProbe.anchoredDeliveryTelemetryRecorderPresentCount || 0);
              const paintedProbeAlreadyPaintedByHydrationCount =
                Number(paintedProbe.alreadyPaintedByHydrationCount || 0);
              const paintedProbeScheduleEnteredCount = Number(paintedProbe.scheduleEnteredCount || 0);
              const paintedProbeEarlyReturnCount = Number(paintedProbe.earlyReturnCount || 0);
              const paintedProbeRafScheduledCount = Number(paintedProbe.rafScheduledCount || 0);
              const paintedProbeRafFiredCount = Number(paintedProbe.rafFiredCount || 0);
              const paintedProbeGenerationSupersededCount =
                Number(paintedProbe.generationSupersededCount || 0);
              const paintedProbeSampleRecordedCount = Number(paintedProbe.sampleRecordedCount || 0);
              const paintedProbeFlushCalledCount = Number(paintedProbe.flushCalledCount || 0);
              const paintedProbeLastAnchoredDeliveryHadAnchor =
                paintedProbe.lastAnchoredDeliveryHadAnchor === true;
              const paintedProbeLastAnchoredDeliverySelectedMatched =
                paintedProbe.lastAnchoredDeliverySelectedMatched === true;
              const paintedProbeLastAnchoredDeliveryHadTelemetryRecorder =
                paintedProbe.lastAnchoredDeliveryHadTelemetryRecorder === true;
              const paintedProbeLastReason =
                typeof paintedProbe.lastReason === 'string' ? paintedProbe.lastReason : 'none';
              const paintedProbeLastScheduleEarlyReturnReason =
                typeof paintedProbe.lastScheduleEarlyReturnReason === 'string'
                  ? paintedProbe.lastScheduleEarlyReturnReason
                  : 'none';
              const frameLivenessProbe =
                window.__bridgeFrameLivenessProbe &&
                typeof window.__bridgeFrameLivenessProbe === 'object'
                  ? window.__bridgeFrameLivenessProbe
                  : {};
              const frameLivenessRafAlive =
                typeof frameLivenessProbe.rafAlive === 'string'
                  ? frameLivenessProbe.rafAlive
                  : 'unknown';
              const frameLivenessRafFiredLatencyBucket =
                typeof frameLivenessProbe.rafFiredLatencyBucket === 'string'
                  ? frameLivenessProbe.rafFiredLatencyBucket
                  : 'unknown';
              const panelRect = codeViewPanel?.getBoundingClientRect();
              const codeViewScrollOwnerRect = codeViewScrollOwner?.getBoundingClientRect();
              const diffContainers = [...document.querySelectorAll('diffs-container')];
              const firstDiffContainer = diffContainers[0] || null;
              const firstDiffContainerRect = diffContainers[0]?.getBoundingClientRect();
              const firstDiffContainerPre = firstDiffContainer?.shadowRoot?.querySelector('pre') || null;
              const firstDiffContainerPreRect = firstDiffContainerPre?.getBoundingClientRect();
              const codeLineElements = diffContainers.flatMap((element) =>
                element.shadowRoot === null ? [] : [...element.shadowRoot.querySelectorAll('[data-line-index]')]
              );
              const codeLineWithDataLineElements = diffContainers.flatMap((element) =>
                element.shadowRoot === null ? [] : [...element.shadowRoot.querySelectorAll('[data-line][data-line-index]')]
              );
              const firstShadowRoot = firstDiffContainer?.shadowRoot || null;
              const codeViewPanelWidth = Math.round(panelRect?.width || 0);
              const codeViewPanelHeight = Math.round(panelRect?.height || 0);
              const codeViewScrollOwnerHeight = Math.round(codeViewScrollOwnerRect?.height || 0);
              const codeViewScrollOwnerScrollHeight = Math.round(codeViewScrollOwner?.scrollHeight || 0);
              const codeViewScrollOwnerChildCount = codeViewScrollOwner?.children.length || 0;
              const codeViewScrollOwnerFirstChildTag =
                codeViewScrollOwner?.firstElementChild?.tagName?.toLowerCase() || 'missing';
              const codeViewInstanceHeight = Math.round(codeViewInstance?.getHeight?.() || 0);
              const codeViewInstanceScrollHeight = Math.round(codeViewInstance?.getScrollHeight?.() || 0);
              const codeViewInstanceItemCount = codeViewInstance?.items?.length || 0;
              const codeViewInstanceWindowTop = Math.round(codeViewWindowSpecs?.top || 0);
              const codeViewInstanceWindowBottom = Math.round(codeViewWindowSpecs?.bottom || 0);
              const codeViewInstanceFirstRenderedIndex = Number(codeViewRenderState?.firstIndex ?? -1);
              const codeViewInstanceLastRenderedIndex = Number(codeViewRenderState?.lastIndex ?? -1);
              const codeViewInstanceFirstItemHeight = Math.round(firstCodeViewInstanceItem?.height || 0);
              const codeViewInstanceFirstItemTop = Math.round(firstCodeViewInstanceItem?.top || 0);
              const codeViewRenderedItemCount = codeViewRenderedItems.length;
              const codeViewRenderedItemElementHeight = Math.round(firstCodeViewRenderedItemElementRect?.height || 0);
              const codeViewRenderedItemElementChildCount = firstCodeViewRenderedItemElement?.children.length || 0;
              const codeViewRenderedItemElementFirstChildTag =
                firstCodeViewRenderedItemElement?.firstElementChild?.tagName?.toLowerCase() || 'missing';
              const codeViewRenderedItemType = firstCodeViewRenderedItem?.type || 'missing';
              const codeViewRenderedItemVersion = Number(firstCodeViewRenderedItem?.version || 0);
              const firstDiffContainerWidth = Math.round(firstDiffContainerRect?.width || 0);
              const firstDiffContainerHeight = Math.round(firstDiffContainerRect?.height || 0);
              const firstDiffContainerOffsetHeight = Math.round(firstDiffContainer?.offsetHeight || 0);
              const firstDiffContainerScrollHeight = Math.round(firstDiffContainer?.scrollHeight || 0);
              const firstDiffContainerShadowChildCount = firstShadowRoot?.children.length || 0;
              const firstDiffContainerPreCount = firstShadowRoot?.querySelectorAll('pre').length || 0;
              const firstDiffContainerPreHeight = Math.round(firstDiffContainerPreRect?.height || 0);
              const firstDiffContainerPreTextLength = firstDiffContainerPre?.textContent?.length || 0;
              const firstDiffContainerDisplay =
                firstDiffContainer === null ? 'missing' : window.getComputedStyle(firstDiffContainer).display;
              const workerPoolState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-state') || 'missing';
              const workerPoolManagerState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-manager-state') || 'missing';
              const workerPoolWorkersFailed =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-workers-failed') === 'true';
              const workerPoolTotalWorkers =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-total-workers') || '0');
              const workerPoolBusyWorkers =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-busy-workers') || '0');
              const workerPoolQueuedTasks =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-queued-tasks') || '0');
              const workerPoolActiveTasks =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-active-tasks') || '0');
              const workerPoolFileCacheSize =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-file-cache-size') || '0');
              const workerPoolDiffCacheSize =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-diff-cache-size') || '0');
              const workerPoolInitializationProbeStage =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-stage') || 'missing';
              const workerPoolInitializationProbeThemeCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-theme-count') || '0');
              const workerPoolInitializationProbeLanguageCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-language-count') || '0');
              const workerPoolInitializationProbeFailureReason =
                document.documentElement.getAttribute('data-bridge-pierre-worker-pool-init-probe-failure-reason') || '';
              const workerDiagnosticBootstrapState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-bootstrap-state') || 'missing';
              const workerDiagnosticInitializeRequestIdState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-initialize-request-id-state') || 'missing';
              const workerDiagnosticLastMessageType =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-message-type') || 'missing';
              const workerDiagnosticLastRequestType =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-request-type') || 'missing';
              const workerDiagnosticLastSuccessMatchesInitializeRequest =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-matches-initialize-request') || 'missing';
              const workerDiagnosticLastSuccessIdState =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-id-state') || 'missing';
              const workerDiagnosticLastSuccessIdPrefix =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-id-prefix') || 'none';
              const workerDiagnosticLastSuccessRequestType =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-success-request-type') || 'missing';
              const workerDiagnosticSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-success-count') || '0');
              const workerDiagnosticInitializeSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-initialize-success-count') || '0');
              const workerDiagnosticDiffSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-diff-success-count') || '0');
              const workerDiagnosticFileSuccessCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-file-success-count') || '0');
              const workerDiagnosticForwardedMessageCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-forwarded-message-count') || '0');
              const workerDiagnosticLastForwardResult =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-forward-result') || 'missing';
              const workerDiagnosticErrorCount =
                Number(document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-error-count') || '0');
              const workerDiagnosticLastErrorKind =
                document.documentElement.getAttribute('data-bridge-pierre-worker-diagnostic-last-error-kind') || 'none';
              const codeViewShadowText = diffContainers
                .map((element) => element.shadowRoot?.textContent || '')
                .join(' ');
              const codeText = `${codeViewPanel?.textContent || ''} ${codeViewShadowText}`;
              const queryRowsIncludingOpenShadowRoots = (root, selector) => {
                const rows = [];
                const pendingRoots = root === null ? [] : [root];
                while (pendingRoots.length > 0) {
                  const currentRoot = pendingRoots.shift();
                  rows.push(...currentRoot.querySelectorAll(selector));
                  for (const element of currentRoot.querySelectorAll('*')) {
                    if (element.shadowRoot !== null) {
                      pendingRoots.push(element.shadowRoot);
                    }
                  }
                }
                return rows;
              };
              const reviewTree = document.querySelector('[data-testid="bridge-review-trees-panel"]');
              const reviewTreeScrollStressProbe =
                window.__bridgeReviewTreeScrollStressProbe &&
                typeof window.__bridgeReviewTreeScrollStressProbe === 'object'
                  ? window.__bridgeReviewTreeScrollStressProbe
                  : {};
              let reviewTreeScrollStressCount = Number.isFinite(Number(reviewTreeScrollStressProbe.count))
                ? Number(reviewTreeScrollStressProbe.count)
                : 0;
              let reviewTreeScrollStressReachedBottom = reviewTreeScrollStressProbe.reachedBottom === true;
              const reviewTreeScrollTargets = queryRowsIncludingOpenShadowRoots(
                reviewTree,
                '[data-file-tree-virtualized-scroll="true"]'
              );
              const reviewTreeScrollTarget = reviewTreeScrollTargets[0] || reviewTree;
              let reviewTreeClientHeight = Math.round(reviewTreeScrollTarget?.clientHeight || 0);
              let reviewTreeScrollHeight = Math.round(reviewTreeScrollTarget?.scrollHeight || 0);
              if (reviewTreeScrollTarget !== null && reviewTreeScrollStressCount < 4) {
                const maxReviewTreeScrollTop = Math.max(
                  0,
                  reviewTreeScrollTarget.scrollHeight - reviewTreeScrollTarget.clientHeight
                );
                reviewTreeScrollTarget.scrollTop =
                  reviewTreeScrollStressCount % 2 === 0 ? maxReviewTreeScrollTop : 0;
                reviewTreeScrollTarget.dispatchEvent(new Event('scroll', { bubbles: true }));
                reviewTreeClientHeight = Math.round(reviewTreeScrollTarget.clientHeight || 0);
                reviewTreeScrollHeight = Math.round(reviewTreeScrollTarget.scrollHeight || 0);
                reviewTreeScrollStressReachedBottom =
                  reviewTreeScrollStressReachedBottom ||
                  maxReviewTreeScrollTop === 0 ||
                  Math.abs(reviewTreeScrollTarget.scrollTop - maxReviewTreeScrollTop) <= 2;
                reviewTreeScrollStressCount += 1;
                window.__bridgeReviewTreeScrollStressProbe = {
                  count: reviewTreeScrollStressCount,
                  reachedBottom: reviewTreeScrollStressReachedBottom
                };
              }
              const modifiedClickProbe =
                window.__bridgeReviewModifiedClickProbe &&
                typeof window.__bridgeReviewModifiedClickProbe === 'object'
                  ? window.__bridgeReviewModifiedClickProbe
                  : {};
              let modifiedClickTargetPath =
                typeof modifiedClickProbe.targetPath === 'string' ? modifiedClickProbe.targetPath : '';
              let modifiedClickFilterRequested = modifiedClickProbe.filterRequested === true;
              let modifiedClickRenderedRowCount = Number.isFinite(Number(modifiedClickProbe.renderedRowCount))
                ? Number(modifiedClickProbe.renderedRowCount)
                : 0;
              let modifiedClickFirstRenderedPath =
                typeof modifiedClickProbe.firstRenderedPath === 'string'
                  ? modifiedClickProbe.firstRenderedPath
                  : '';
              let modifiedClickSetFilterStatus =
                typeof modifiedClickProbe.setFilterStatus === 'string'
                  ? modifiedClickProbe.setFilterStatus
                  : 'missing';
              let modifiedClickSetFilterReason =
                typeof modifiedClickProbe.setFilterReason === 'string'
                  ? modifiedClickProbe.setFilterReason
                  : 'missing';
              let modifiedClickSelectedPath =
                typeof modifiedClickProbe.selectedPath === 'string' ? modifiedClickProbe.selectedPath : '';
              let modifiedClickSelectedChangeKind =
                typeof modifiedClickProbe.selectedChangeKind === 'string'
                  ? modifiedClickProbe.selectedChangeKind
                  : 'missing';
              let modifiedClickSelectedContentState =
                typeof modifiedClickProbe.selectedContentState === 'string'
                  ? modifiedClickProbe.selectedContentState
                  : 'missing';
              let modifiedClickSelectedContentRoles =
                typeof modifiedClickProbe.selectedContentRoles === 'string'
                  ? modifiedClickProbe.selectedContentRoles
                  : '';
              let modifiedClickSelectedContentCacheKeys =
                typeof modifiedClickProbe.selectedContentCacheKeys === 'string'
                  ? modifiedClickProbe.selectedContentCacheKeys
                  : '';
              let modifiedClickSelectedMaterializedItemType =
                typeof modifiedClickProbe.selectedMaterializedItemType === 'string'
                  ? modifiedClickProbe.selectedMaterializedItemType
                  : 'missing';
              let modifiedClickSelectedMaterializedItemVersion = Number.isFinite(
                Number(modifiedClickProbe.selectedMaterializedItemVersion)
              )
                ? Number(modifiedClickProbe.selectedMaterializedItemVersion)
                : 0;
              let modifiedClickSelectedCharacterCount = Number.isFinite(
                Number(modifiedClickProbe.selectedCharacterCount)
              )
                ? Number(modifiedClickProbe.selectedCharacterCount)
                : 0;
              let modifiedClickAttemptCount = Number.isFinite(Number(modifiedClickProbe.clickAttemptCount))
                ? Number(modifiedClickProbe.clickAttemptCount)
                : 0;
              const selectedContentRoleList = selectedContentRoles.split(',').filter((role) => role.length > 0);
              const modifiedClickHasConverged =
                modifiedClickTargetPath.length > 0 &&
                selectedDisplayPath === modifiedClickTargetPath &&
                selectedChangeKind === 'modified' &&
                selectedContentState === 'ready' &&
                selectedMaterializedItemType === 'diff' &&
                selectedContentRoleList.includes('base') &&
                selectedContentRoleList.includes('head') &&
                selectedContentCacheKeys.includes('base:') &&
                selectedContentCacheKeys.includes('head:') &&
                selectedContentCharacterCount > 0;
              if (modifiedClickHasConverged && modifiedClickSelectedPath.length === 0) {
                modifiedClickSelectedPath = selectedDisplayPath;
                modifiedClickSelectedChangeKind = selectedChangeKind;
                modifiedClickSelectedContentState = selectedContentState;
                modifiedClickSelectedContentRoles = selectedContentRoles;
                modifiedClickSelectedContentCacheKeys = selectedContentCacheKeys;
                modifiedClickSelectedMaterializedItemType = selectedMaterializedItemType;
                modifiedClickSelectedMaterializedItemVersion = selectedMaterializedItemVersion;
                modifiedClickSelectedCharacterCount = selectedContentCharacterCount;
                window.__bridgeReviewModifiedClickProbe = {
                  targetPath: modifiedClickTargetPath,
                  filterRequested: modifiedClickFilterRequested,
                  renderedRowCount: modifiedClickRenderedRowCount,
                  firstRenderedPath: modifiedClickFirstRenderedPath,
                  setFilterStatus: modifiedClickSetFilterStatus,
                  setFilterReason: modifiedClickSetFilterReason,
                  selectedPath: modifiedClickSelectedPath,
                  selectedChangeKind: modifiedClickSelectedChangeKind,
                  selectedContentState: modifiedClickSelectedContentState,
                  selectedContentRoles: modifiedClickSelectedContentRoles,
                  selectedContentCacheKeys: modifiedClickSelectedContentCacheKeys,
                  selectedMaterializedItemType: modifiedClickSelectedMaterializedItemType,
                  selectedMaterializedItemVersion: modifiedClickSelectedMaterializedItemVersion,
                  selectedCharacterCount: modifiedClickSelectedCharacterCount,
                  clickAttemptCount: modifiedClickAttemptCount
                };
              }
              if (!modifiedClickHasConverged && reviewShell !== null && reviewMetadataItemCount > 0) {
                if (modifiedClickProbe.filterRequested !== true) {
                  const previousBridgeReviewControlProbeSequence =
                    Number(window.bridgeReviewControlProbe?.sequence ?? -1);
                  window.dispatchEvent(
                    new CustomEvent('__bridge_review_control', {
                      detail: {
                        method: 'bridge.fileTree.setFilter',
                        gitStatusFilter: 'modified',
                        fileClassFilter: 'all'
                      }
                    })
                  );
                  const setFilterProbe =
                    window.bridgeReviewControlProbe &&
                    typeof window.bridgeReviewControlProbe === 'object' &&
                    window.bridgeReviewControlProbe.sequence > previousBridgeReviewControlProbeSequence &&
                    window.bridgeReviewControlProbe.method === 'bridge.fileTree.setFilter'
                      ? window.bridgeReviewControlProbe
                      : null;
                  modifiedClickFilterRequested = true;
                  modifiedClickSetFilterStatus =
                    typeof setFilterProbe?.status === 'string' ? setFilterProbe.status : 'missing';
                  modifiedClickSetFilterReason =
                    typeof setFilterProbe?.reason === 'string' && setFilterProbe.reason.length > 0
                      ? setFilterProbe.reason
                      : 'none';
                  window.__bridgeReviewModifiedClickProbe = {
                    filterRequested: true,
                    renderedRowCount: modifiedClickRenderedRowCount,
                    firstRenderedPath: modifiedClickFirstRenderedPath,
                    setFilterStatus: modifiedClickSetFilterStatus,
                    setFilterReason: modifiedClickSetFilterReason,
                    clickAttemptCount: modifiedClickAttemptCount
                  };
                } else if (reviewTree !== null) {
                  const modifiedButtons = queryRowsIncludingOpenShadowRoots(
                    reviewTree,
                    'button[data-item-path][data-item-type="file"]'
                  );
                  const modifiedRows =
                    modifiedButtons.length > 0
                      ? modifiedButtons
                      : queryRowsIncludingOpenShadowRoots(
                          reviewTree,
                          '[data-type="item"][data-item-type="file"][data-item-path]'
                        );
                  modifiedClickRenderedRowCount = modifiedRows.length;
                  modifiedClickFirstRenderedPath = modifiedRows[0]?.getAttribute('data-item-path') || '';
                  const clickTarget =
                    modifiedRows.find((row) => (row.getAttribute('data-item-path') || '').length > 0) ||
                    null;
                  if (clickTarget !== null) {
                    modifiedClickTargetPath = clickTarget.getAttribute('data-item-path') || '';
                    window.__bridgeReviewModifiedClickProbe = {
                      filterRequested: true,
                      targetPath: modifiedClickTargetPath,
                      renderedRowCount: modifiedClickRenderedRowCount,
                      firstRenderedPath: modifiedClickFirstRenderedPath,
                      setFilterStatus: modifiedClickSetFilterStatus,
                      setFilterReason: modifiedClickSetFilterReason,
                      clickAttemptCount: modifiedClickAttemptCount + 1
                    };
                    clickTarget.scrollIntoView?.({ block: 'nearest' });
                    clickTarget.click();
                  } else {
                    window.__bridgeReviewModifiedClickProbe = {
                      filterRequested: true,
                      renderedRowCount: modifiedClickRenderedRowCount,
                      firstRenderedPath: modifiedClickFirstRenderedPath,
                      setFilterStatus: modifiedClickSetFilterStatus,
                      setFilterReason: modifiedClickSetFilterReason,
                      clickAttemptCount: modifiedClickAttemptCount
                    };
                  }
                }
              }
              const reviewTreeClickProbe =
                window.__bridgeReviewTreeClickProbe &&
                typeof window.__bridgeReviewTreeClickProbe === 'object'
                  ? window.__bridgeReviewTreeClickProbe
                  : {};
              let reviewTreeClickTargetPath =
                typeof reviewTreeClickProbe.targetPath === 'string' ? reviewTreeClickProbe.targetPath : '';
              let reviewTreeClickCurrentSelectedPath = selectedDisplayPath;
              let reviewTreeClickCurrentSelectedItemId = selectedItemId;
              let reviewTreeClickShellSelectedPath = reviewShellSelectedDisplayPath;
              let reviewTreeClickRenderedRowCount = Number.isFinite(Number(reviewTreeClickProbe.renderedRowCount))
                ? Number(reviewTreeClickProbe.renderedRowCount)
                : 0;
              let reviewTreeClickTargetRowIndex = Number.isFinite(Number(reviewTreeClickProbe.targetRowIndex))
                ? Number(reviewTreeClickProbe.targetRowIndex)
                : -1;
              let reviewTreeClickTargetRowVisible = reviewTreeClickProbe.targetRowVisible === true;
              let reviewTreeClickAttemptCount = Number.isFinite(Number(reviewTreeClickProbe.clickAttemptCount))
                ? Number(reviewTreeClickProbe.clickAttemptCount)
                : 0;
              const reviewTreeClickReadyAfterScroll = reviewTreeClickProbe.readyAfterScroll === true;
              let reviewTreeClickSelectedPath =
                typeof reviewTreeClickProbe.selectedPath === 'string' ? reviewTreeClickProbe.selectedPath : '';
              let reviewTreeClickSelectedContentState =
                typeof reviewTreeClickProbe.selectedContentState === 'string'
                  ? reviewTreeClickProbe.selectedContentState
                  : 'missing';
              let reviewTreeClickSelectedMaterializedItemType =
                typeof reviewTreeClickProbe.selectedMaterializedItemType === 'string'
                  ? reviewTreeClickProbe.selectedMaterializedItemType
                  : 'missing';
              let reviewTreeClickSelectedMaterializedItemVersion = Number.isFinite(
                Number(reviewTreeClickProbe.selectedMaterializedItemVersion)
              )
                ? Number(reviewTreeClickProbe.selectedMaterializedItemVersion)
                : 0;
              let reviewTreeClickSelectedCharacterCount = Number.isFinite(
                Number(reviewTreeClickProbe.selectedCharacterCount)
              )
                ? Number(reviewTreeClickProbe.selectedCharacterCount)
                : 0;
              const reviewTreeClickHasConverged =
                reviewTreeClickTargetPath.length > 0 &&
                selectedDisplayPath === reviewTreeClickTargetPath &&
                selectedContentState === 'ready' &&
                selectedMaterializedItemType === 'diff' &&
                selectedMaterializedItemVersion > 0 &&
                selectedContentCharacterCount > 0;
              if (reviewTreeClickHasConverged && reviewTreeClickSelectedPath.length === 0) {
                reviewTreeClickSelectedPath = selectedDisplayPath;
                reviewTreeClickSelectedContentState = selectedContentState;
                reviewTreeClickSelectedMaterializedItemType = selectedMaterializedItemType;
                reviewTreeClickSelectedMaterializedItemVersion = selectedMaterializedItemVersion;
                reviewTreeClickSelectedCharacterCount = selectedContentCharacterCount;
                window.__bridgeReviewTreeClickProbe = {
                  targetPath: reviewTreeClickTargetPath,
                  currentSelectedPath: reviewTreeClickCurrentSelectedPath,
                  currentSelectedItemId: reviewTreeClickCurrentSelectedItemId,
                  shellSelectedPath: reviewTreeClickShellSelectedPath,
                  renderedRowCount: reviewTreeClickRenderedRowCount,
                  targetRowIndex: reviewTreeClickTargetRowIndex,
                  targetRowVisible: reviewTreeClickTargetRowVisible,
                  clickAttemptCount: reviewTreeClickAttemptCount,
                  selectedPath: reviewTreeClickSelectedPath,
                  selectedContentState: reviewTreeClickSelectedContentState,
                  selectedMaterializedItemType: reviewTreeClickSelectedMaterializedItemType,
                  selectedMaterializedItemVersion: reviewTreeClickSelectedMaterializedItemVersion,
                  selectedCharacterCount: reviewTreeClickSelectedCharacterCount
                };
              }
              if (
                reviewTreeClickTargetPath.length === 0 &&
                modifiedClickSelectedPath.length > 0 &&
                reviewTreeScrollStressCount >= 4 &&
                reviewTreeScrollTarget !== null
              ) {
                if (!reviewTreeClickReadyAfterScroll) {
                  reviewTreeScrollTarget.scrollTop = reviewTreeScrollTarget.scrollHeight;
                  reviewTreeScrollTarget.dispatchEvent(new Event('scroll', { bubbles: true }));
                  window.__bridgeReviewTreeClickProbe = {
                    currentSelectedPath: reviewTreeClickCurrentSelectedPath,
                    currentSelectedItemId: reviewTreeClickCurrentSelectedItemId,
                    shellSelectedPath: reviewTreeClickShellSelectedPath,
                    renderedRowCount: reviewTreeClickRenderedRowCount,
                    targetRowIndex: reviewTreeClickTargetRowIndex,
                    targetRowVisible: reviewTreeClickTargetRowVisible,
                    clickAttemptCount: reviewTreeClickAttemptCount,
                    readyAfterScroll: true,
                    status: 'awaiting_bottom_scroll_settle'
                  };
                } else {
                  const reviewTreeButtons = queryRowsIncludingOpenShadowRoots(
                    reviewTree,
                    'button[data-item-path][data-item-type="file"]'
                  );
                  const reviewTreeRows = (
                    reviewTreeButtons.length > 0
                      ? reviewTreeButtons
                      : queryRowsIncludingOpenShadowRoots(
                          reviewTree,
                          '[data-type="item"][data-item-type="file"][data-item-path]'
                        )
                  ).filter((row) => {
                    return (
                      !row.hasAttribute('data-file-tree-sticky-row') &&
                      !row.hasAttribute('data-item-parked')
                    );
                  });
                  reviewTreeClickRenderedRowCount = reviewTreeRows.length;
                  const reviewTreeClickTarget =
                    [...reviewTreeRows].reverse().find((row) => {
                      const path = row.getAttribute('data-item-path') || '';
                      return path.length > 0 && path !== selectedDisplayPath;
                    }) ||
                    [...reviewTreeRows].reverse().find((row) => {
                      return (row.getAttribute('data-item-path') || '').length > 0;
                    }) ||
                    null;
                  if (reviewTreeClickTarget !== null) {
                    const targetRowRect = reviewTreeClickTarget.getBoundingClientRect();
                    const reviewTreeRect = reviewTreeScrollTarget?.getBoundingClientRect?.() || null;
                    reviewTreeClickTargetRowIndex = reviewTreeRows.indexOf(reviewTreeClickTarget);
                    reviewTreeClickTargetRowVisible = reviewTreeRect !== null
                      ? targetRowRect.bottom >= reviewTreeRect.top && targetRowRect.top <= reviewTreeRect.bottom
                      : targetRowRect.bottom >= 0 && targetRowRect.top <= window.innerHeight;
                    reviewTreeClickAttemptCount += 1;
                    reviewTreeClickTargetPath = reviewTreeClickTarget.getAttribute('data-item-path') || '';
                    window.__bridgeReviewTreeClickProbe = {
                      targetPath: reviewTreeClickTargetPath,
                      currentSelectedPath: reviewTreeClickCurrentSelectedPath,
                      currentSelectedItemId: reviewTreeClickCurrentSelectedItemId,
                      shellSelectedPath: reviewTreeClickShellSelectedPath,
                      renderedRowCount: reviewTreeClickRenderedRowCount,
                      targetRowIndex: reviewTreeClickTargetRowIndex,
                      targetRowVisible: reviewTreeClickTargetRowVisible,
                      clickAttemptCount: reviewTreeClickAttemptCount,
                      readyAfterScroll: true,
                      status: 'clicked_after_scroll_settle'
                    };
                    reviewTreeClickTarget.scrollIntoView?.({ block: 'nearest' });
                    reviewTreeClickTarget.click();
                  }
                }
              }
              const errorProbe = Array.isArray(window.__bridgeErrorProbe)
                ? window.__bridgeErrorProbe
                : [];
              const commandProbe = Array.isArray(window.__bridgeCommandProbe)
                ? window.__bridgeCommandProbe
                : [];
              const intakeReadyCommandProbe = Array.isArray(window.__bridgeIntakeReadyCommandProbe)
                ? window.__bridgeIntakeReadyCommandProbe
                : [];
              const responseProbe = Array.isArray(window.__bridgeResponseProbe)
                ? window.__bridgeResponseProbe
                : [];
              const intakeProbe = Array.isArray(window.__bridgeIntakeProbe)
                ? window.__bridgeIntakeProbe
                : [];
              const clip = (value, maxLength) =>
                String(value ?? '').slice(0, maxLength);
              const classifyPageIssue = (issue) => {
                const message = String(issue?.message ?? issue?.reason ?? issue?.error ?? '');
                const kind = String(issue?.kind ?? '');
                if (message.includes('ZodError') || message.includes('Invalid input')) {
                  return 'schema_parse_failed';
                }
                if (kind === 'fetch_error') {
                  if (
                    message.includes('aborted') ||
                    message.includes('AbortError') ||
                    message.includes('concurrency_exceeded')
                  ) {
                    return 'context_switch_fetch_aborted';
                  }
                  return 'fetch_failed';
                }
                if (kind === 'unhandledrejection') {
                  return 'unhandled_rejection';
                }
                if (kind === 'error') {
                  return 'page_error';
                }
                return kind.length > 0 ? kind : 'none';
              };
              const lastPageIssue = errorProbe.length > 0
                ? errorProbe[errorProbe.length - 1]
                : null;
              const pageIssueLastKind = lastPageIssue === null
                ? 'none'
                : clip(lastPageIssue.kind, 80) || 'unknown';
              const pageIssueLastClass = lastPageIssue === null
                ? 'none'
                : classifyPageIssue(lastPageIssue);
              const pageIssueClasses = errorProbe.map(classifyPageIssue);
              const pageIssueDisallowedCount = pageIssueClasses.filter((pageIssueClass) => {
                return pageIssueClass !== 'context_switch_fetch_aborted';
              }).length;
              const reviewStreamId =
                document.documentElement.getAttribute('data-bridge-review-stream-id') || '';
              const reviewGeneration = Number(
                reviewShell?.getAttribute('data-review-metadata-generation') || '0'
              );
              const reviewIntakeReadyCommandCount = intakeReadyCommandProbe.filter((entry) => {
                return (
                  entry?.method === 'bridge.intakeReady' &&
                  entry?.protocolId === 'review' &&
                  entry?.streamId === reviewStreamId
                );
              }).length;
              const reviewIntakeFrames = intakeProbe.filter((entry) => {
                return entry?.streamId === reviewStreamId;
              });
              const lastReviewIntakeFrame = reviewIntakeFrames.length > 0
                ? reviewIntakeFrames[reviewIntakeFrames.length - 1]
                : null;
              const reviewIntakeSnapshotFrameCount = reviewIntakeFrames.filter((entry) => {
                return entry?.kind === 'snapshot' && entry?.payloadFrameKind === 'review.metadataSnapshot';
              }).length;
              const reviewIntakeMetadataWindowFrameCount = reviewIntakeFrames.filter((entry) => {
                return entry?.payloadFrameKind === 'review.metadataWindow';
              }).length;
              const metadataInterestProbe =
                window.__bridgeReviewMetadataInterestProbe &&
                typeof window.__bridgeReviewMetadataInterestProbe === 'object'
                  ? window.__bridgeReviewMetadataInterestProbe
                  : {};
              if (
                reviewIntakeMetadataWindowFrameCount === 0 &&
                typeof metadataInterestProbe.commandId !== 'string' &&
                reviewStreamId.length > 0 &&
                Number.isFinite(reviewGeneration) &&
                reviewGeneration >= 0 &&
                selectedItemId.length > 0
              ) {
                const bridgeNonce = document.documentElement.getAttribute('data-bridge-nonce') || '';
                if (bridgeNonce.length > 0) {
                  const commandId = `startup-review-metadata-interest-${Date.now().toString(36)}`;
                  window.__bridgeReviewMetadataInterestProbe = {
                    commandId,
                    itemId: selectedItemId,
                    streamId: reviewStreamId
                  };
                  document.dispatchEvent(
                    new CustomEvent('__bridge_command', {
                      detail: {
                        __commandId: commandId,
                        __nonce: bridgeNonce,
                        jsonrpc: '2.0',
                        method: 'bridge.metadata_interest.update',
                        params: {
                          protocol: 'review',
                          streamId: reviewStreamId,
                          generation: reviewGeneration,
                          itemIds: [selectedItemId],
                          lane: 'foreground'
                        }
                      }
                    })
                  );
                }
              }
              return {
                hasReviewShell: reviewShell !== null,
                reviewShellState,
                reviewCanvasBranch,
                hasCodeViewPanel: codeViewPanel !== null,
                hasSelectedItem: selectedItemId.length > 0,
                hasSelectedDisplayPath: selectedDisplayPath.length > 0,
                reviewShellHasSelectedDisplayPath: reviewShellSelectedDisplayPath.length > 0,
                reviewShellSelectedContentState,
                selectedDemandFailedCount,
                selectedDemandDeferredCount,
                selectedDemandLoadedCount,
                selectedDemandResultReason,
                selectedDemandResultStatus,
                selectedDemandLoadFailureKind,
                selectedChangeKind,
                reviewMetadataItemCount,
                reviewMetadataTreeRowCount,
                reviewTreeScrollStressCount,
                reviewTreeScrollStressReachedBottom,
                reviewTreeClientHeight,
                reviewTreeScrollHeight,
                reviewTreeClickTargetPath,
                reviewTreeClickCurrentSelectedPath,
                reviewTreeClickCurrentSelectedItemId,
                reviewTreeClickShellSelectedPath,
                reviewTreeClickRenderedRowCount,
                reviewTreeClickTargetRowIndex,
                reviewTreeClickTargetRowVisible,
                reviewTreeClickAttemptCount,
                reviewTreeClickSelectedPath,
                reviewTreeClickSelectedContentState,
                reviewTreeClickSelectedMaterializedItemType,
                reviewTreeClickSelectedMaterializedItemVersion,
                reviewTreeClickSelectedCharacterCount,
                hasSelectedContentText:
                  selectedContentState === 'ready' &&
                  selectedContentRoleCount > 0 &&
                  selectedContentCacheKeyCount > 0 &&
                  selectedContentCharacterCount > 0 &&
                  selectedMaterializedUpdateResult === 'updated' &&
                  selectedMaterializedItemVersion > 0 &&
                  selectedMaterializedLineCount > 0 &&
                  codeViewRenderedItemCount > 0 &&
                  codeViewInstanceFirstItemHeight > 0 &&
                  codeText.length > 0 &&
                  codeViewShadowText.length > 0 &&
                  firstDiffContainerWidth > 0 &&
                  workerPoolState === 'ready',
                selectedContentState,
                selectedContentRoleCount,
                selectedContentCacheKeyCount,
                selectedContentRoles,
                selectedContentCacheKeys,
                selectedContentCharacterCount,
                selectedContentLineCount,
                selectedMaterializedUpdateResult,
                selectedMaterializedItemType,
                selectedMaterializedItemVersion,
                selectedMaterializedAdditionLineCount,
                selectedMaterializedDeletionLineCount,
                selectedMaterializedFileLineCount,
                paintedProbeAnchoredDeliveryEntryCount,
                paintedProbeAnchoredDeliveryAnchorPresentCount,
                paintedProbeAnchoredDeliverySelectedMatchCount,
                paintedProbeAnchoredDeliveryTelemetryRecorderPresentCount,
                paintedProbeAlreadyPaintedByHydrationCount,
                paintedProbeScheduleEnteredCount,
                paintedProbeEarlyReturnCount,
                paintedProbeRafScheduledCount,
                paintedProbeRafFiredCount,
                paintedProbeGenerationSupersededCount,
                paintedProbeSampleRecordedCount,
                paintedProbeFlushCalledCount,
                paintedProbeLastAnchoredDeliveryHadAnchor,
                paintedProbeLastAnchoredDeliverySelectedMatched,
                paintedProbeLastAnchoredDeliveryHadTelemetryRecorder,
                paintedProbeLastReason,
                paintedProbeLastScheduleEarlyReturnReason,
                frameLivenessRafAlive,
                frameLivenessRafFiredLatencyBucket,
                pageErrorCount: errorProbe.length,
                pageIssueLastKind,
                pageIssueLastClass,
                pageIssueDisallowedCount,
                diffContainerCount: diffContainers.length,
                codeLineCount: codeLineElements.length,
                codeViewPanelWidth,
                codeViewPanelHeight,
                firstDiffContainerWidth,
                firstDiffContainerHeight,
                codeViewScrollOwnerHeight,
                codeViewScrollOwnerScrollHeight,
                codeViewScrollOwnerChildCount,
                codeViewScrollOwnerFirstChildTag,
                codeViewInstanceHeight,
                codeViewInstanceScrollHeight,
                codeViewInstanceItemCount,
                codeViewInstanceWindowTop,
                codeViewInstanceWindowBottom,
                codeViewInstanceFirstRenderedIndex,
                codeViewInstanceLastRenderedIndex,
                codeViewInstanceFirstItemHeight,
                codeViewInstanceFirstItemTop,
                codeViewRenderedItemCount,
                codeViewRenderedItemElementHeight,
                codeViewRenderedItemElementChildCount,
                codeViewRenderedItemElementFirstChildTag,
                codeViewRenderedItemType,
                codeViewRenderedItemVersion,
                firstDiffContainerShadowChildCount,
                firstDiffContainerPreCount,
                firstDiffContainerOffsetHeight,
                firstDiffContainerScrollHeight,
                firstDiffContainerPreHeight,
                firstDiffContainerPreTextLength,
                codeLineWithDataLineCount: codeLineWithDataLineElements.length,
                firstDiffContainerDisplay,
                workerPoolState,
                workerPoolManagerState,
                workerPoolWorkersFailed,
                workerPoolTotalWorkers,
                workerPoolBusyWorkers,
                workerPoolQueuedTasks,
                workerPoolActiveTasks,
                workerPoolFileCacheSize,
                workerPoolDiffCacheSize,
                workerPoolInitializationProbeStage,
                workerPoolInitializationProbeThemeCount,
                workerPoolInitializationProbeLanguageCount,
                workerPoolInitializationProbeFailureReason,
                workerDiagnosticBootstrapState,
                workerDiagnosticInitializeRequestIdState,
                workerDiagnosticLastMessageType,
                workerDiagnosticLastRequestType,
                workerDiagnosticLastSuccessMatchesInitializeRequest,
                workerDiagnosticLastSuccessIdState,
                workerDiagnosticLastSuccessIdPrefix,
                workerDiagnosticLastSuccessRequestType,
                workerDiagnosticSuccessCount,
                workerDiagnosticInitializeSuccessCount,
                workerDiagnosticDiffSuccessCount,
                workerDiagnosticFileSuccessCount,
                workerDiagnosticForwardedMessageCount,
                workerDiagnosticLastForwardResult,
                workerDiagnosticErrorCount,
                workerDiagnosticLastErrorKind,
                codeTextLength: codeText.length,
                codeShadowTextLength: codeViewShadowText.length,
                modifiedClickTargetPath,
                modifiedClickFilterRequested,
                modifiedClickRenderedRowCount,
                modifiedClickFirstRenderedPath,
                modifiedClickSetFilterStatus,
                modifiedClickSetFilterReason,
                modifiedClickSelectedPath,
                modifiedClickShellSelectedMatchesTarget:
                  modifiedClickTargetPath.length > 0 &&
                  reviewShellSelectedDisplayPath === modifiedClickTargetPath,
                modifiedClickSelectedChangeKind,
                modifiedClickSelectedContentState,
                modifiedClickSelectedContentRoles,
                modifiedClickSelectedContentCacheKeys,
                modifiedClickSelectedMaterializedItemType,
                modifiedClickSelectedMaterializedItemVersion,
                modifiedClickSelectedCharacterCount,
                modifiedClickAttemptCount,
                bridgeCommandCount: commandProbe.length,
                reviewIntakeReadyCommandCount,
                bridgeResponseCount: responseProbe.length,
                intakeFrameCount: intakeProbe.length,
                reviewIntakeSnapshotFrameCount,
                reviewIntakeMetadataWindowFrameCount,
                reviewIntakeLastFrameKind: clip(lastReviewIntakeFrame?.payloadFrameKind || lastReviewIntakeFrame?.kind, 120) || 'none',
                reviewIntakeLastStreamIdMatches: lastReviewIntakeFrame?.streamId === reviewStreamId
              };
            })())
            """
        }
    #endif
}
