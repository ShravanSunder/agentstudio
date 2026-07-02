import {
	buildReviewContentRoutePressureProof,
	reviewCollapseControlSatisfied,
	reviewContentRouteDeltaSatisfied,
	reviewMetadataBeforeContentSatisfied,
	reviewRenderedSelectionSatisfied,
	reviewRouteCollapseControlArtifactSatisfied,
	reviewRoutePressureSatisfied,
	reviewSelectedDemandTelemetrySatisfied,
	reviewStartupTelemetrySatisfied,
	type ReviewDemandTelemetryProof,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import {
	minimumExpectedReviewMetadataRouteHitCount,
	reviewSelectionFixtureMarker,
	reviewSelectionFixtureRelativePath,
	worktreeDevServerUrl,
	worktreeReviewDevServerUrl,
} from './config.ts';
import { clickReviewTreeFilePathViaSearch } from './file-review-handoff.ts';
import { captureWorktreeDevServerScreenshot } from './file-search-filter.ts';
import { makeVerificationPage } from './page-factory.ts';
import {
	readReviewCollapseControlProof,
	readReviewRenderedSelectionSnapshot,
	waitForReviewRenderedSelection,
} from './review-selection.ts';
import {
	selectedReviewTreeTargetProof,
	waitForReviewSelectedContentState,
	waitForReviewVisibleDemandTelemetry,
} from './review-tree-click.ts';
import {
	fetchWorktreeReviewContentDescriptorIdsForItemId,
	fetchWorktreeReviewItemIdForDisplayPath,
	fetchWorktreeReviewMetadataFrame,
	installReviewRouteProbe,
	readBridgeWorktreeVerifierTelemetrySamples,
	requireWorktreeReviewComparisonProof,
	waitForReviewContentRouteHitAfterIndex,
	waitForReviewContentRouteHitContaining,
	waitForReviewMetadataBeforeContentStartupProof,
} from './route-probes.ts';
import type { WorktreeReviewFileTargetRouteProof, WorktreeReviewRouteProof } from './types.ts';
import {
	makeDeferred,
	reviewFileTargetUrlFromWorktreeDevServerUrl,
	reviewTreeSearchInputMatchesTargetPath,
} from './utils.ts';

export async function verifyWorktreeReviewRoute(): Promise<WorktreeReviewRouteProof> {
	const page = await makeVerificationPage();
	const startupContentGate = makeDeferred<void>();
	const routeProbe = await installReviewRouteProbe(page, { contentGate: startupContentGate });
	try {
		const reviewMetadataResponse = await fetchWorktreeReviewMetadataFrame();
		const reviewComparisonProof = requireWorktreeReviewComparisonProof(reviewMetadataResponse);
		const selectionItemId = await fetchWorktreeReviewItemIdForDisplayPath(
			reviewSelectionFixtureRelativePath,
		);
		const selectionContentDescriptorIds =
			await fetchWorktreeReviewContentDescriptorIdsForItemId(selectionItemId);
		await page.goto(worktreeReviewDevServerUrl, {
			waitUntil: 'domcontentloaded',
			timeout: 30_000,
		});
		await page.waitForSelector('[data-testid="bridge-app-root"]', { timeout: 30_000 });
		await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
		const reviewMetadataBeforeContentProof = await waitForReviewMetadataBeforeContentStartupProof({
			page,
			routeProbe,
		});
		startupContentGate.resolve();
		const reviewContentHitCountBeforeClick = routeProbe.contentHitCount();
		const reviewSelectionProof =
			(await selectedReviewTreeTargetProof({
				page,
				path: reviewSelectionFixtureRelativePath,
			})) ??
			(await clickReviewTreeFilePathViaSearch({
				page,
				path: reviewSelectionFixtureRelativePath,
			}));
		await waitForReviewSelectedContentState({
			displayPath: reviewSelectionFixtureRelativePath,
			page,
			state: 'ready',
		});
		await waitForReviewRenderedSelection({
			expectedMaterializedItemType: 'file',
			expectedItemId: selectionItemId,
			expectedVisibleText: reviewSelectionFixtureMarker,
			page,
		});
		const reviewSelectionPostClickContentRouteProof = await waitForReviewContentRouteHitAfterIndex({
			beforeHitCount:
				reviewSelectionProof.selectionMethod === 'preselected-review-tree-target'
					? 0
					: reviewContentHitCountBeforeClick,
			expectedContentDescriptorIds: selectionContentDescriptorIds,
			expectedItemId: selectionItemId,
			routeProbe,
		});
		const reviewRenderedSelectionProof = await readReviewRenderedSelectionSnapshot(page);
		const reviewCollapseControlProof = await readReviewCollapseControlProof({
			expectedItemId: selectionItemId,
			page,
		});
		if (
			!reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: selectionItemId,
					expectedMaterializedItemType: 'file',
					expectedVisibleText: reviewSelectionFixtureMarker,
				},
				snapshot: reviewRenderedSelectionProof,
			})
		) {
			throw new Error(
				`Expected Review tree click to render ${selectionItemId} in the left CodeView canvas: ${JSON.stringify(reviewRenderedSelectionProof)}`,
			);
		}
		if (
			!reviewCollapseControlSatisfied({
				expectedItemId: selectionItemId,
				proof: reviewCollapseControlProof,
			})
		) {
			throw new Error(
				`Expected Review CodeView collapse control to use compact Button primitive chrome for ${selectionItemId}: ${JSON.stringify(reviewCollapseControlProof)}`,
			);
		}
		if (!reviewContentRouteDeltaSatisfied(reviewSelectionPostClickContentRouteProof)) {
			throw new Error(
				`Expected Review tree click to trigger a post-click content route for ${selectionItemId}: ${JSON.stringify(reviewSelectionPostClickContentRouteProof)}`,
			);
		}
		await waitForReviewContentRouteHitContaining({
			needle: selectionContentDescriptorIds[0] ?? selectionItemId,
			routeProbe,
		});
		await waitForReviewVisibleDemandTelemetry(page);
		const proof = await page.evaluate(() => {
			const appRoots = [...document.querySelectorAll('[data-testid="bridge-app-root"]')];
			const appRoot = appRoots[0];
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const reviewContentHeader = document.querySelector(
				'[data-testid="bridge-viewer-content-topbar"]',
			);
			const reviewRailToolbar = document.querySelector(
				'[data-testid="bridge-review-rail-toolbar"]',
			);
			const reviewContentHeaderRect =
				reviewContentHeader instanceof HTMLElement
					? reviewContentHeader.getBoundingClientRect()
					: null;
			const reviewRailToolbarRect =
				reviewRailToolbar instanceof HTMLElement ? reviewRailToolbar.getBoundingClientRect() : null;
			const visibleContextButtonSelection = (testId: string): string | null => {
				const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
				const visibleButton = buttons.find(
					(button): button is HTMLElement =>
						button instanceof HTMLElement && button.getClientRects().length > 0,
				);
				return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
			};
			const activeVisibleFileViewerSubstituteCount = (testId: string): number =>
				[...document.querySelectorAll(`[data-testid="${testId}"]`)].filter(
					(element): element is HTMLElement => {
						if (!(element instanceof HTMLElement)) {
							return false;
						}
						const fileModeHost = element.closest('[data-testid="bridge-viewer-mode-host-file"]');
						const fileModeIsActive =
							fileModeHost instanceof HTMLElement &&
							fileModeHost.getAttribute('data-bridge-viewer-mode-active') === 'true';
						const rect = element.getBoundingClientRect();
						const style = window.getComputedStyle(element);
						return (
							fileModeIsActive &&
							style.display !== 'none' &&
							style.visibility !== 'hidden' &&
							rect.width > 0 &&
							rect.height > 0
						);
					},
				).length;
			const readNumberAttribute = (
				element: Element | null,
				attributeName: string,
			): number | null => {
				if (!(element instanceof HTMLElement)) {
					return null;
				}
				const attributeValue = element.getAttribute(attributeName);
				if (attributeValue === null) {
					return null;
				}
				const parsedValue = Number(attributeValue);
				return Number.isFinite(parsedValue) ? parsedValue : null;
			};
			const readNumberRecordAttribute = (
				element: Element | null,
				attributeName: string,
			): Record<string, number> | null => {
				if (!(element instanceof HTMLElement)) {
					return null;
				}
				const attributeValue = element.getAttribute(attributeName);
				if (attributeValue === null) {
					return null;
				}
				try {
					const parsedValue: unknown = JSON.parse(attributeValue);
					if (
						parsedValue === null ||
						typeof parsedValue !== 'object' ||
						Array.isArray(parsedValue)
					) {
						return null;
					}
					const record: Record<string, number> = {};
					for (const [key, value] of Object.entries(parsedValue)) {
						if (typeof value !== 'number') {
							return null;
						}
						record[key] = value;
					}
					return record;
				} catch {
					return null;
				}
			};
			const readReviewDemandTelemetry = (
				element: Element | null,
				prefix: 'data-review-selected-demand' | 'data-review-visible-demand',
			): ReviewDemandTelemetryProof => ({
				admittedBytes: readNumberAttribute(element, `${prefix}-admitted-bytes`),
				admittedBytesByLane: readNumberRecordAttribute(element, `${prefix}-admitted-bytes-by-lane`),
				byteBudgetSource:
					element instanceof HTMLElement
						? element.getAttribute(`${prefix}-byte-budget-source`)
						: null,
				configuredExecutorMaxConcurrentLoads: readNumberAttribute(
					element,
					`${prefix}-configured-executor-max-concurrent-loads`,
				),
				configuredExecutorMaxInFlightBytes: readNumberAttribute(
					element,
					`${prefix}-configured-executor-max-in-flight-bytes`,
				),
				configuredSchedulerMaxQueuedEstimatedBytes: readNumberAttribute(
					element,
					`${prefix}-configured-scheduler-max-queued-estimated-bytes`,
				),
				configuredSchedulerMaxQueuedIntentsPerLane: readNumberAttribute(
					element,
					`${prefix}-configured-scheduler-max-queued-intents-per-lane`,
				),
				deferredCount: readNumberAttribute(element, `${prefix}-deferred-count`),
				deferredEstimatedBytesByLane: readNumberRecordAttribute(
					element,
					`${prefix}-deferred-estimated-bytes-by-lane`,
				),
				droppedEstimatedBytesByLane: readNumberRecordAttribute(
					element,
					`${prefix}-dropped-estimated-bytes-by-lane`,
				),
				droppedIntentCount: readNumberAttribute(element, `${prefix}-dropped-intent-count`),
				durationMilliseconds: readNumberAttribute(element, `${prefix}-duration-ms`),
				enqueueAcceptedCount: readNumberAttribute(element, `${prefix}-enqueue-accepted-count`),
				enqueueRejectedCount: readNumberAttribute(element, `${prefix}-enqueue-rejected-count`),
				executorInFlightCountAfterDispatch: readNumberAttribute(
					element,
					`${prefix}-executor-in-flight-after-dispatch`,
				),
				executorInFlightCountAfter: readNumberAttribute(
					element,
					`${prefix}-executor-in-flight-after`,
				),
				executorInFlightCountBefore: readNumberAttribute(
					element,
					`${prefix}-executor-in-flight-before`,
				),
				executorQueuedLoadCountAfter: readNumberAttribute(
					element,
					`${prefix}-executor-queued-load-after`,
				),
				failedCount: readNumberAttribute(element, `${prefix}-failed-count`),
				foregroundIntentCount: readNumberAttribute(element, `${prefix}-foreground-intent-count`),
				interest:
					element instanceof HTMLElement ? element.getAttribute(`${prefix}-interest`) : null,
				itemId: element instanceof HTMLElement ? element.getAttribute(`${prefix}-item-id`) : null,
				packageId:
					element instanceof HTMLElement ? element.getAttribute(`${prefix}-package-id`) : null,
				packageReviewGeneration: readNumberAttribute(element, `${prefix}-package-generation`),
				packageRevision: readNumberAttribute(element, `${prefix}-package-revision`),
				currentPackageId:
					element instanceof HTMLElement ? element.getAttribute('data-review-metadata-id') : null,
				currentPackageReviewGeneration: readNumberAttribute(
					element,
					'data-review-metadata-generation',
				),
				currentPackageRevision: readNumberAttribute(element, 'data-review-metadata-revision'),
				laneUpgradeCount: readNumberAttribute(element, `${prefix}-lane-upgrade-count`),
				loadedCount: readNumberAttribute(element, `${prefix}-loaded-count`),
				maxExecutorInFlightCount: readNumberAttribute(element, `${prefix}-max-executor-in-flight`),
				maxExecutorQueuedLoadCount: readNumberAttribute(
					element,
					`${prefix}-max-executor-queued-load`,
				),
				maxSchedulerQueuedIntentCount: readNumberAttribute(
					element,
					`${prefix}-max-scheduler-queued`,
				),
				schedulerQueuedIntentCountAfterEnqueue: readNumberAttribute(
					element,
					`${prefix}-scheduler-queued-after-enqueue`,
				),
				schedulerQueuedIntentCountAfter: readNumberAttribute(
					element,
					`${prefix}-scheduler-queued-after`,
				),
				schedulerQueuedIntentCountBefore: readNumberAttribute(
					element,
					`${prefix}-scheduler-queued-before`,
				),
				staleDropCount: readNumberAttribute(element, `${prefix}-stale-drop-count`),
				visibleIntentCount: readNumberAttribute(element, `${prefix}-visible-intent-count`),
			});
			return {
				appOwner:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-app-owner') : null,
				appRootCount: appRoots.length,
				appRootVisible: appRoot instanceof HTMLElement && appRoot.getBoundingClientRect().width > 0,
				reviewBaseEndpointId:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-review-base-endpoint-id')
						: null,
				reviewBaseEndpointKind:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-review-base-endpoint-kind')
						: null,
				reviewBaseProviderIdentity:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-review-base-provider-identity')
						: null,
				fileViewerCodeCanvasCount: activeVisibleFileViewerSubstituteCount(
					'bridge-file-viewer-code-canvas',
				),
				fileContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-file'),
				fileViewerShellCount: activeVisibleFileViewerSubstituteCount('bridge-file-viewer-shell'),
				fileViewerSidebarCount: activeVisibleFileViewerSubstituteCount(
					'bridge-file-viewer-sidebar',
				),
				reviewEmptyShellCount: document.querySelectorAll(
					'[data-testid="bridge-review-empty-shell"]',
				).length,
				reviewCanvasCount: document.querySelectorAll('[data-testid="bridge-review-canvas"]').length,
				reviewCodeScrollCount: document.querySelectorAll(
					'[data-testid="bridge-review-code-scroll"]',
				).length,
				reviewContentHeaderHeight: reviewContentHeaderRect?.height ?? 0,
				reviewContentHeaderText: reviewContentHeader?.textContent ?? null,
				reviewContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-review'),
				reviewHeadEndpointId:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-review-head-endpoint-id')
						: null,
				reviewHeadEndpointKind:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-review-head-endpoint-kind')
						: null,
				reviewHeadProviderIdentity:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-review-head-provider-identity')
						: null,
				reviewHeaderMatchesRailToolbarHeight:
					reviewContentHeaderRect !== null &&
					reviewRailToolbarRect !== null &&
					Math.abs(reviewContentHeaderRect.height - reviewRailToolbarRect.height) <= 1,
				reviewViewerShellCount: document.querySelectorAll('[data-testid="review-viewer-shell"]')
					.length,
				reviewRailToolbarHeight: reviewRailToolbarRect?.height ?? 0,
				reviewRailToolbarUsesSharedAttr:
					reviewRailToolbar instanceof HTMLElement &&
					reviewRailToolbar.getAttribute('data-bridge-shared-rail-toolbar') === 'true',
				reviewSelectedDemandTelemetryProof: readReviewDemandTelemetry(
					reviewShell,
					'data-review-selected-demand',
				),
				reviewSelectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				reviewSelectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
				reviewVisibleDemandTelemetryProof: readReviewDemandTelemetry(
					reviewShell,
					'data-review-visible-demand',
				),
				sharedShellMode:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				sharedShellOwner:
					appRoot instanceof HTMLElement
						? appRoot.getAttribute('data-bridge-viewer-shell-owner')
						: null,
				standaloneWorktreeFileAppCount: document.querySelectorAll(
					'[data-testid="worktree-file-app"]',
				).length,
			};
		});
		const selectionState = await page.evaluate(() => {
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			return {
				selectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				selectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
			};
		});
		const reviewStartupTelemetrySamples = await readBridgeWorktreeVerifierTelemetrySamples(page);
		const routeProof = {
			...proof,
			reviewContentRouteHitCount: routeProbe.contentHitCount(),
			reviewContentRouteHitUrls: routeProbe.contentHitUrls(),
			reviewRoutePressureProof: buildReviewContentRoutePressureProof(routeProbe.contentHitUrls()),
			reviewCollapseControlProof,
			...reviewComparisonProof,
			reviewSelectionContentRouteHitCount: routeProbe
				.contentHitUrls()
				.filter((url) =>
					selectionContentDescriptorIds.some((descriptorId: string): boolean =>
						url.includes(descriptorId),
					),
				).length,
			reviewMetadataRouteHitCount: routeProbe.metadataHitCount(),
			reviewMetadataRouteHitUrls: routeProbe.metadataHitUrls(),
			reviewMetadataBeforeContentProof,
			reviewRenderedSelectionProof,
			reviewSelectionPostClickContentRouteProof,
			reviewSelectionProof,
			reviewSelectionSelectedContentState: selectionState.selectedContentState,
			reviewSelectionSelectedDisplayPath: selectionState.selectedDisplayPath,
			reviewStartupTelemetrySamples,
			screenshotPath: await captureWorktreeDevServerScreenshot({
				name: 'worktree-review-ready.png',
				page,
			}),
			locationHref: await page.evaluate(() => window.location.href),
			pageUrl: page.url(),
		} satisfies WorktreeReviewRouteProof;
		const expectedVisibleContentDescriptorIds =
			routeProof.reviewVisibleDemandTelemetryProof.itemId === null
				? null
				: await fetchWorktreeReviewContentDescriptorIdsForItemId(
						routeProof.reviewVisibleDemandTelemetryProof.itemId,
					);
		const expectedReviewUrl = new URL(worktreeReviewDevServerUrl).href;
		if (
			routeProof.appOwner !== 'BridgeApp' ||
			routeProof.appRootCount !== 1 ||
			!routeProof.appRootVisible ||
			routeProof.locationHref !== expectedReviewUrl ||
			routeProof.pageUrl !== expectedReviewUrl ||
			routeProof.sharedShellMode !== 'review' ||
			routeProof.sharedShellOwner !== 'BridgeViewerAppShell' ||
			routeProof.fileContextButtonSelected !== 'false' ||
			routeProof.reviewContextButtonSelected !== 'true' ||
			routeProof.fileViewerShellCount !== 0 ||
			routeProof.fileViewerSidebarCount !== 0 ||
			routeProof.fileViewerCodeCanvasCount !== 0 ||
			routeProof.reviewBaseEndpointId !== routeProof.reviewMetadataBaseEndpointId ||
			routeProof.reviewBaseEndpointKind !== routeProof.reviewMetadataBaseEndpointKind ||
			routeProof.reviewBaseProviderIdentity !== routeProof.reviewMetadataBaseProviderIdentity ||
			routeProof.reviewHeadEndpointId !== routeProof.reviewMetadataHeadEndpointId ||
			routeProof.reviewHeadEndpointKind !== routeProof.reviewMetadataHeadEndpointKind ||
			routeProof.reviewHeadProviderIdentity !== routeProof.reviewMetadataHeadProviderIdentity ||
			routeProof.reviewMetadataBaseEndpointId !== 'baseline-local-default' ||
			routeProof.reviewMetadataBaseEndpointKind !== 'gitRef' ||
			routeProof.reviewMetadataBaseProviderIdentity === 'HEAD' ||
			routeProof.reviewMetadataHeadEndpointId !== 'working-tree' ||
			routeProof.reviewMetadataHeadEndpointKind !== 'workingTree' ||
			routeProof.reviewMetadataHeadProviderIdentity !== 'working-tree' ||
			routeProof.reviewContentHeaderText?.includes('Current worktree vs Default') !== true ||
			routeProof.standaloneWorktreeFileAppCount !== 0 ||
			routeProof.reviewEmptyShellCount !== 0 ||
			routeProof.reviewViewerShellCount !== 1 ||
			routeProof.reviewCanvasCount !== 1 ||
			routeProof.reviewCodeScrollCount !== 1 ||
			routeProof.reviewSelectedContentState !== 'ready' ||
			routeProof.reviewSelectedDisplayPath === null ||
			routeProof.reviewContentHeaderHeight <= 0 ||
			routeProof.reviewRailToolbarHeight <= 0 ||
			!routeProof.reviewHeaderMatchesRailToolbarHeight ||
			!routeProof.reviewRailToolbarUsesSharedAttr ||
			routeProof.reviewMetadataRouteHitCount < minimumExpectedReviewMetadataRouteHitCount ||
			!reviewMetadataBeforeContentSatisfied(routeProof.reviewMetadataBeforeContentProof) ||
			routeProof.reviewContentRouteHitCount <= 0 ||
			!reviewRoutePressureSatisfied({
				expectedVisibleContentDescriptorIds,
				expectedVisibleItemId: routeProof.reviewVisibleDemandTelemetryProof.itemId,
				routePressureProof: routeProof.reviewRoutePressureProof,
				selectedDemandTelemetryProof: routeProof.reviewSelectedDemandTelemetryProof,
				visibleDemandTelemetryProof: routeProof.reviewVisibleDemandTelemetryProof,
			}) ||
			!reviewSelectedDemandTelemetrySatisfied(routeProof.reviewSelectedDemandTelemetryProof) ||
			!reviewStartupTelemetrySatisfied(routeProof.reviewStartupTelemetrySamples) ||
			routeProof.reviewSelectionContentRouteHitCount <= 0 ||
			!reviewContentRouteDeltaSatisfied(routeProof.reviewSelectionPostClickContentRouteProof) ||
			!reviewRouteCollapseControlArtifactSatisfied({
				expectedItemId: selectionItemId,
				routeProof,
			}) ||
			routeProof.reviewSelectionSelectedContentState !== 'ready' ||
			routeProof.reviewSelectionSelectedDisplayPath !== reviewSelectionFixtureRelativePath ||
			!reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: selectionItemId,
					expectedMaterializedItemType: 'file',
					expectedVisibleText: reviewSelectionFixtureMarker,
				},
				snapshot: routeProof.reviewRenderedSelectionProof,
			}) ||
			!routeProof.reviewSelectionProof.searchOpened ||
			(routeProof.reviewSelectionProof.selectionMethod === 'playwright-review-tree-search-click' &&
				!reviewTreeSearchInputMatchesTargetPath({
					actualSearchInputValue: routeProof.reviewSelectionProof.searchInputValue,
					targetPath: reviewSelectionFixtureRelativePath,
				})) ||
			routeProof.reviewSelectionProof.targetPath !== reviewSelectionFixtureRelativePath ||
			routeProof.reviewSelectionProof.clickedRowItemPath !== reviewSelectionFixtureRelativePath ||
			routeProof.reviewSelectionProof.clickedRowItemType !== 'file' ||
			!routeProof.reviewSelectionProof.clickedRowVisible
		) {
			throw new Error(
				`Expected worktree Review URL to load a real shared review metadata without FileViewer substitute: ${JSON.stringify(routeProof)}`,
			);
		}
		return routeProof;
	} finally {
		startupContentGate.resolve();
		await routeProbe.dispose();
		await page.close();
	}
}

export async function verifyWorktreeReviewFileTargetRoute(): Promise<WorktreeReviewFileTargetRouteProof> {
	const page = await makeVerificationPage();
	const routeProbe = await installReviewRouteProbe(page);
	try {
		const expectedDisplayPath = reviewSelectionFixtureRelativePath;
		const expectedReviewItemId = await fetchWorktreeReviewItemIdForDisplayPath(expectedDisplayPath);
		const expectedVersion = 'current';
		const reviewFileTargetUrl = reviewFileTargetUrlFromWorktreeDevServerUrl({
			itemId: expectedReviewItemId,
			path: expectedDisplayPath,
			url: worktreeDevServerUrl,
			version: expectedVersion,
		});
		await page.goto(reviewFileTargetUrl, {
			waitUntil: 'domcontentloaded',
			timeout: 30_000,
		});
		await page.waitForSelector('[data-testid="bridge-app-root"]', { timeout: 30_000 });
		await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
		await waitForReviewSelectedContentState({
			displayPath: expectedDisplayPath,
			page,
			state: 'ready',
		});
		try {
			await page.waitForFunction(
				(expected: { readonly itemId: string }): boolean => {
					const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
					return (
						codePanel?.getAttribute('data-selected-item-id') === expected.itemId &&
						codePanel?.getAttribute('data-selected-materialized-item-type') === 'file'
					);
				},
				{ itemId: expectedReviewItemId },
				{ timeout: 30_000 },
			);
		} catch (error) {
			const debugState = await page.evaluate(() => {
				const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
				const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
				const attributes =
					codePanel instanceof HTMLElement
						? Object.fromEntries(
								[...codePanel.attributes].map((attribute) => [attribute.name, attribute.value]),
							)
						: {};
				return {
					codePanelAttributes: attributes,
					reviewSelectedContentState:
						reviewShell instanceof HTMLElement
							? reviewShell.getAttribute('data-selected-content-state')
							: null,
					reviewSelectedDisplayPath:
						reviewShell instanceof HTMLElement
							? reviewShell.getAttribute('data-selected-display-path')
							: null,
				};
			});
			throw new Error(
				`Timed out waiting for Review file-target route to materialize a file item: ${JSON.stringify(debugState)}`,
				{ cause: error },
			);
		}
		const proof = await page.evaluate(() => {
			const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			const reviewContentHeader = document.querySelector(
				'[data-testid="bridge-viewer-content-topbar"]',
			);
			const reviewRailToolbar = document.querySelector(
				'[data-testid="bridge-review-rail-toolbar"]',
			);
			const reviewContentHeaderRect =
				reviewContentHeader instanceof HTMLElement
					? reviewContentHeader.getBoundingClientRect()
					: null;
			const reviewRailToolbarRect =
				reviewRailToolbar instanceof HTMLElement ? reviewRailToolbar.getBoundingClientRect() : null;
			return {
				appOwner:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-app-owner') : null,
				reviewContentHeaderHeight: reviewContentHeaderRect?.height ?? 0,
				reviewHeaderMatchesRailToolbarHeight:
					reviewContentHeaderRect !== null &&
					reviewRailToolbarRect !== null &&
					Math.abs(reviewContentHeaderRect.height - reviewRailToolbarRect.height) <= 1,
				reviewRailToolbarHeight: reviewRailToolbarRect?.height ?? 0,
				reviewRailToolbarUsesSharedAttr:
					reviewRailToolbar instanceof HTMLElement &&
					reviewRailToolbar.getAttribute('data-bridge-shared-rail-toolbar') === 'true',
				selectedContentRoleCount:
					codePanel instanceof HTMLElement
						? Number(codePanel.getAttribute('data-selected-content-role-count') ?? '0')
						: 0,
				selectedCodeViewOverflow:
					codePanel instanceof HTMLElement
						? codePanel.getAttribute('data-bridge-code-view-overflow')
						: null,
				selectedContentState:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-content-state')
						: null,
				selectedDisplayPath:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
				selectedItemId:
					codePanel instanceof HTMLElement ? codePanel.getAttribute('data-selected-item-id') : null,
				selectedMaterializedFileLineCount:
					codePanel instanceof HTMLElement
						? Number(codePanel.getAttribute('data-selected-materialized-file-line-count') ?? '0')
						: 0,
				selectedMaterializedItemType:
					codePanel instanceof HTMLElement
						? codePanel.getAttribute('data-selected-materialized-item-type')
						: null,
				sharedShellMode:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				sharedShellOwner:
					appRoot instanceof HTMLElement
						? appRoot.getAttribute('data-bridge-viewer-shell-owner')
						: null,
				standaloneWorktreeFileAppCount: document.querySelectorAll(
					'[data-testid="worktree-file-app"]',
				).length,
			};
		});
		const routeProof = {
			...proof,
			expectedDisplayPath,
			expectedReviewItemId,
			expectedVersion,
			locationHref: await page.evaluate(() => window.location.href),
			pageUrl: page.url(),
			reviewContentRouteHitCount: routeProbe.contentHitCount(),
			reviewContentRouteHitUrls: routeProbe.contentHitUrls(),
			reviewMetadataRouteHitCount: routeProbe.metadataHitCount(),
			screenshotPath: await captureWorktreeDevServerScreenshot({
				name: 'worktree-review-file-target-ready.png',
				page,
			}),
		} satisfies WorktreeReviewFileTargetRouteProof;
		if (
			routeProof.appOwner !== 'BridgeApp' ||
			routeProof.locationHref !== reviewFileTargetUrl ||
			routeProof.pageUrl !== reviewFileTargetUrl ||
			routeProof.sharedShellMode !== 'review' ||
			routeProof.sharedShellOwner !== 'BridgeViewerAppShell' ||
			routeProof.selectedContentState !== 'ready' ||
			routeProof.selectedCodeViewOverflow !== 'wrap' ||
			routeProof.selectedDisplayPath !== expectedDisplayPath ||
			routeProof.selectedItemId !== expectedReviewItemId ||
			routeProof.selectedMaterializedItemType !== 'file' ||
			routeProof.selectedMaterializedFileLineCount <= 0 ||
			routeProof.reviewContentHeaderHeight <= 0 ||
			routeProof.reviewRailToolbarHeight <= 0 ||
			!routeProof.reviewHeaderMatchesRailToolbarHeight ||
			!routeProof.reviewRailToolbarUsesSharedAttr ||
			routeProof.standaloneWorktreeFileAppCount !== 0 ||
			routeProof.reviewMetadataRouteHitCount < minimumExpectedReviewMetadataRouteHitCount ||
			routeProof.reviewContentRouteHitCount <= 0
		) {
			throw new Error(
				`Expected worktree Review file-target URL to render a typed Pierre file target in Review context: ${JSON.stringify(routeProof)}`,
			);
		}
		return routeProof;
	} finally {
		await routeProbe.dispose();
		await page.close();
	}
}
