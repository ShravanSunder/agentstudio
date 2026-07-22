import type { Page } from 'playwright';

import { reviewContentRouteDeltaSatisfied } from '../verify-bridge-viewer-worktree-review-proof.ts';
import {
	fileToReviewHandoffFixtureRelativePath,
	minimumExpectedReviewMetadataRouteHitCount,
	worktreeDevServerUrl,
} from './config.ts';
import { clickWorktreeFilePath, dismissOpenBridgeMenus } from './content-state.ts';
import {
	clickWorktreeFileControl,
	fillWorktreeFileSearch,
	waitForWorktreeFileFilterStatusAtLeast,
	waitForWorktreeOpenFileState,
} from './file-search-filter.ts';
import { makeVerificationPage } from './page-factory.ts';
import { waitForWorktreeFileViewerSurfaceReady } from './page-shell.ts';
import {
	reviewTreeSelectedPathMatches,
	waitForReviewSelectedContentState,
} from './review-tree-click.ts';
import {
	fetchWorktreeReviewContentDescriptorIdsForItemId,
	fetchWorktreeReviewItemIdForDisplayPath,
	installReviewRouteProbe,
	waitForReviewContentRouteHitAfterIndex,
} from './route-probes.ts';
import type {
	ReviewTreeSearchClickProof,
	WorktreeFileOpenLoadTelemetryProof,
	WorktreeFileToReviewHandoffProof,
} from './types.ts';
import { cssStringLiteral } from './utils.ts';

export async function verifyWorktreeFileToReviewHandoff(): Promise<WorktreeFileToReviewHandoffProof> {
	const page = await makeVerificationPage();
	const routeProbe = await installReviewRouteProbe(page);
	try {
		const expectedDisplayPath = fileToReviewHandoffFixtureRelativePath;
		const expectedReviewItemId = await fetchWorktreeReviewItemIdForDisplayPath(expectedDisplayPath);
		const expectedContentDescriptorIds =
			await fetchWorktreeReviewContentDescriptorIdsForItemId(expectedReviewItemId);
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await page.waitForSelector('[data-testid="bridge-file-viewer-shell"]', { timeout: 30_000 });
		await waitForWorktreeFileViewerSurfaceReady(page);
		await clickWorktreeFilePathViaSearch({ page, path: expectedDisplayPath });
		const openFileState = await waitForWorktreeOpenFileReadyOrStale({
			page,
			path: expectedDisplayPath,
		});
		if (openFileState === 'stale') {
			const refreshButton = page.locator('[data-testid="worktree-file-refresh"]:visible').first();
			if ((await refreshButton.count()) > 0) {
				await refreshButton.click();
				await waitForWorktreeOpenFileState({
					page,
					path: expectedDisplayPath,
					state: 'ready',
				});
			}
		} else {
			await waitForWorktreeOpenFileState({
				page,
				path: expectedDisplayPath,
				state: 'ready',
			});
		}
		const beforeLocationHref = await page.evaluate(() => window.location.href);
		const reviewContentHitCountBeforeHandoffClick = routeProbe.contentHitCount();
		await clickWorktreeFileControl(page, 'worktree-file-open-review-comparison');
		await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
		await waitForReviewSelectedContentState({
			displayPath: expectedDisplayPath,
			page,
			state: 'ready',
		});
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
		const reviewHandoffContentRouteProof = await waitForReviewContentRouteHitAfterIndex({
			beforeHitCount: reviewContentHitCountBeforeHandoffClick,
			expectedContentDescriptorIds,
			expectedItemId: expectedReviewItemId,
			routeProbe,
		});
		const proof = await page.evaluate(() => {
			const appRoots = [...document.querySelectorAll('[data-testid="bridge-app-root"]')];
			const appRoot = appRoots[0];
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const codePanel = document.querySelector('[data-testid="bridge-code-view-panel"]');
			const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
			const fileViewerShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			const optionalNumberAttribute = (
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
			const fileViewerOpenLoadTelemetry: WorktreeFileOpenLoadTelemetryProof = {
				disposition:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-last-open-load-disposition')
						: null,
				durationMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-duration-ms',
				),
				estimatedBytes: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-estimated-bytes',
				),
				executorInFlightBytesAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-bytes-after',
				),
				executorInFlightBytesBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-bytes-before',
				),
				executorInFlightCountAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-after',
				),
				executorInFlightCountBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-before',
				),
				executorInFlightMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-in-flight-ms',
				),
				executorPendingWaitMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-pending-wait-ms',
				),
				executorQueuedLoadCountAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-queued-after',
				),
				executorQueuedBytesAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-queued-bytes-after',
				),
				executorQueuedBytesBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-queued-bytes-before',
				),
				executorQueuedLoadCountBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-executor-queued-before',
				),
				lane:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-last-open-load-lane')
						: null,
				resourceBodyRegistryCommitMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-resource-body-registry-commit-ms',
				),
				resourceFetchResponseWaitMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-resource-fetch-response-wait-ms',
				),
				resourceFirstChunkWaitMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-resource-first-chunk-wait-ms',
				),
				resourceStreamReadMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-resource-stream-read-ms',
				),
				schedulerQueueWaitMilliseconds: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queue-wait-ms',
				),
				schedulerQueuedIntentCountAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queued-after',
				),
				schedulerQueuedEstimatedBytesAfter: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queued-bytes-after',
				),
				schedulerQueuedEstimatedBytesBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queued-bytes-before',
				),
				schedulerQueuedIntentCountBefore: optionalNumberAttribute(
					fileViewerShell,
					'data-last-open-load-scheduler-queued-before',
				),
			};
			const visibleContextButtonSelection = (testId: string): string | null => {
				const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
				const visibleButton = buttons.find(
					(button): button is HTMLElement =>
						button instanceof HTMLElement && button.getClientRects().length > 0,
				);
				return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
			};
			return {
				afterLocationHref: window.location.href,
				appOwner:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-app-owner') : null,
				appRootCount: appRoots.length,
				fileContextButtonSelectedAfterSwitch: visibleContextButtonSelection(
					'bridge-viewer-context-file',
				),
				fileModeHostHiddenAfterSwitch:
					fileModeHost instanceof HTMLElement && fileModeHost.hasAttribute('hidden'),
				fileViewerShellCountAfterSwitch: document.querySelectorAll(
					'[data-testid="bridge-file-viewer-shell"]',
				).length,
				fileViewerShellHiddenAfterSwitch:
					fileViewerShell instanceof HTMLElement && fileViewerShell.closest('[hidden]') !== null,
				fileViewerOpenLoadTelemetry,
				fileViewerSelectedPathAfterSwitch:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-selected-display-path')
						: null,
				reviewContextButtonSelectedAfterSwitch: visibleContextButtonSelection(
					'bridge-viewer-context-review',
				),
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
		await page.click('[data-testid="bridge-viewer-context-file"]:visible');
		await page.waitForFunction(
			(expected: { readonly displayPath: string }): boolean => {
				const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
				const contentPanel = document.querySelector('[data-worktree-open-file-path]');
				return (
					appRoot?.getAttribute('data-bridge-viewer-mode') === 'file' &&
					contentPanel?.getAttribute('data-worktree-open-file-path') === expected.displayPath
				);
			},
			{ displayPath: expectedDisplayPath },
			{ timeout: 20_000 },
		);
		const returnToFileProof = await page.evaluate(() => {
			const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
			const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
			const fileViewerShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			return {
				fileModeHostActiveAfterReturnToFile:
					fileModeHost instanceof HTMLElement
						? fileModeHost.getAttribute('data-bridge-viewer-mode-active')
						: null,
				fileModeHostHiddenAfterReturnToFile:
					fileModeHost instanceof HTMLElement && fileModeHost.hasAttribute('hidden'),
				fileViewerSelectedPathAfterReturnToFile:
					fileViewerShell instanceof HTMLElement
						? fileViewerShell.getAttribute('data-selected-display-path')
						: null,
				reviewModeAfterReturnToFile:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
			};
		});
		await page.click('[data-testid="bridge-viewer-context-review"]:visible');
		await waitForReviewSelectedContentState({
			displayPath: expectedDisplayPath,
			page,
			state: 'ready',
		});
		const returnToReviewProof = await page.evaluate(() => {
			const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
			const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const visibleContextButtonSelection = (testId: string): string | null => {
				const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
				const visibleButton = buttons.find(
					(button): button is HTMLElement =>
						button instanceof HTMLElement && button.getClientRects().length > 0,
				);
				return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
			};
			return {
				fileModeHostActiveAfterReturnToReview:
					fileModeHost instanceof HTMLElement
						? fileModeHost.getAttribute('data-bridge-viewer-mode-active')
						: null,
				fileModeHostHiddenAfterReturnToReview:
					fileModeHost instanceof HTMLElement && fileModeHost.hasAttribute('hidden'),
				reviewContextButtonSelectedAfterReturnToReview: visibleContextButtonSelection(
					'bridge-viewer-context-review',
				),
				reviewModeAfterReturnToReview:
					appRoot instanceof HTMLElement ? appRoot.getAttribute('data-bridge-viewer-mode') : null,
				reviewSelectedDisplayPathAfterReturnToReview:
					reviewShell instanceof HTMLElement
						? reviewShell.getAttribute('data-selected-display-path')
						: null,
			};
		});
		const handoffProof = {
			...proof,
			...returnToFileProof,
			...returnToReviewProof,
			beforeLocationHref,
			expectedDisplayPath,
			expectedReviewItemId,
			reviewHandoffContentRouteProof,
			reviewContentRouteHitCount: routeProbe.contentHitCount(),
			reviewContentRouteHitUrls: routeProbe.contentHitUrls(),
			reviewMetadataRouteHitCount: routeProbe.metadataHitCount(),
		} satisfies WorktreeFileToReviewHandoffProof;
		const failedInvariants = [
			handoffProof.appRootCount === 1 ? null : 'appRootCount',
			handoffProof.appOwner === 'BridgeApp' ? null : 'appOwner',
			handoffProof.beforeLocationHref === worktreeDevServerUrl ? null : 'beforeLocationHref',
			handoffProof.afterLocationHref === worktreeDevServerUrl ? null : 'afterLocationHref',
			handoffProof.sharedShellMode === 'review' ? null : 'sharedShellMode',
			handoffProof.sharedShellOwner === 'BridgeViewerAppShell' ? null : 'sharedShellOwner',
			handoffProof.fileContextButtonSelectedAfterSwitch === 'false'
				? null
				: 'fileContextButtonSelectedAfterSwitch',
			handoffProof.reviewContextButtonSelectedAfterSwitch === 'true'
				? null
				: 'reviewContextButtonSelectedAfterSwitch',
			handoffProof.fileViewerShellCountAfterSwitch === 1 ? null : 'fileViewerShellCountAfterSwitch',
			handoffProof.fileModeHostHiddenAfterSwitch ? null : 'fileModeHostHiddenAfterSwitch',
			handoffProof.fileViewerShellHiddenAfterSwitch ? null : 'fileViewerShellHiddenAfterSwitch',
			handoffProof.fileViewerSelectedPathAfterSwitch === expectedDisplayPath
				? null
				: 'fileViewerSelectedPathAfterSwitch',
			handoffProof.reviewModeAfterReturnToFile === 'file' ? null : 'reviewModeAfterReturnToFile',
			handoffProof.fileModeHostActiveAfterReturnToFile === 'true'
				? null
				: 'fileModeHostActiveAfterReturnToFile',
			!handoffProof.fileModeHostHiddenAfterReturnToFile
				? null
				: 'fileModeHostHiddenAfterReturnToFile',
			handoffProof.fileViewerSelectedPathAfterReturnToFile === expectedDisplayPath
				? null
				: 'fileViewerSelectedPathAfterReturnToFile',
			handoffProof.reviewModeAfterReturnToReview === 'review'
				? null
				: 'reviewModeAfterReturnToReview',
			handoffProof.fileModeHostActiveAfterReturnToReview === 'false'
				? null
				: 'fileModeHostActiveAfterReturnToReview',
			handoffProof.fileModeHostHiddenAfterReturnToReview
				? null
				: 'fileModeHostHiddenAfterReturnToReview',
			handoffProof.reviewContextButtonSelectedAfterReturnToReview === 'true'
				? null
				: 'reviewContextButtonSelectedAfterReturnToReview',
			handoffProof.reviewSelectedDisplayPathAfterReturnToReview === expectedDisplayPath
				? null
				: 'reviewSelectedDisplayPathAfterReturnToReview',
			handoffProof.selectedContentState === 'ready' ? null : 'selectedContentState',
			handoffProof.selectedDisplayPath === expectedDisplayPath ? null : 'selectedDisplayPath',
			handoffProof.selectedItemId === expectedReviewItemId ? null : 'selectedItemId',
			handoffProof.selectedMaterializedItemType === 'file' ? null : 'selectedMaterializedItemType',
			handoffProof.selectedMaterializedFileLineCount > 0
				? null
				: 'selectedMaterializedFileLineCount',
			handoffProof.standaloneWorktreeFileAppCount === 0 ? null : 'standaloneWorktreeFileAppCount',
			handoffProof.reviewMetadataRouteHitCount >= minimumExpectedReviewMetadataRouteHitCount
				? null
				: 'reviewMetadataRouteHitCount',
			reviewContentRouteDeltaSatisfied(handoffProof.reviewHandoffContentRouteProof)
				? null
				: 'reviewHandoffContentRouteProof',
		].filter((failure): failure is string => failure !== null);
		if (failedInvariants.length > 0) {
			throw new Error(
				`Expected FileViewer to hand off selected file to ReviewViewer inside one shared app; failed ${failedInvariants.join(', ')}: ${JSON.stringify(handoffProof)}`,
			);
		}
		return handoffProof;
	} finally {
		await routeProbe.dispose();
		await page.close();
	}
}

async function waitForWorktreeOpenFileReadyOrStale(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<'ready' | 'stale'> {
	const stateHandle = await props.page.waitForFunction(
		(expectedPath: string): 'ready' | 'stale' | false => {
			const contentPanel = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			if (contentPanel?.getAttribute('data-worktree-open-file-path') !== expectedPath) {
				return false;
			}
			const state = contentPanel.getAttribute('data-worktree-open-file-state');
			return state === 'ready' || state === 'stale' ? state : false;
		},
		props.path,
		{ timeout: 20_000 },
	);
	const state = await stateHandle.jsonValue();
	if (state !== 'ready' && state !== 'stale') {
		throw new Error(`Expected Worktree/File ready-or-stale state, got ${String(state)}`);
	}
	return state;
}

export async function clickWorktreeFilePathViaSearch(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<void> {
	await dismissOpenBridgeMenus(props.page);
	await fillWorktreeFileSearch(props.page, props.path);
	await waitForWorktreeFileFilterStatusAtLeast(props.page, 1);
	await clickWorktreeFilePath(props.page, props.path);
}

export async function clickReviewTreeFilePathViaSearch(props: {
	readonly page: Page;
	readonly path: string;
}): Promise<ReviewTreeSearchClickProof> {
	const reviewTreeContainerSelector =
		'[data-testid="bridge-review-trees-panel"] file-tree-container';
	const searchInputLocator = props.page
		.locator(`${reviewTreeContainerSelector} input[data-file-tree-search-input]`)
		.first();
	const searchContainerLocator = props.page
		.locator(`${reviewTreeContainerSelector} [data-file-tree-search-container][data-open="true"]`)
		.first();
	const targetRowLocator = props.page
		.locator(
			`${reviewTreeContainerSelector} button[data-item-path=${cssStringLiteral(
				props.path,
			)}][data-item-type="file"]:not([data-file-tree-sticky-row]):not([data-item-parked])`,
		)
		.first();

	await dismissOpenBridgeMenus(props.page);
	if (!(await searchInputLocator.isVisible())) {
		await props.page.locator('button[data-testid="bridge-review-search-toggle"]:visible').click();
	}
	await searchInputLocator.waitFor({ state: 'visible', timeout: 10_000 });
	await searchInputLocator.fill(props.path);
	await searchContainerLocator.waitFor({ state: 'visible', timeout: 10_000 });
	await targetRowLocator.waitFor({ state: 'attached', timeout: 10_000 });
	await targetRowLocator.scrollIntoViewIfNeeded({ timeout: 10_000 });
	await targetRowLocator.waitFor({ state: 'visible', timeout: 10_000 });

	const clickProof = await targetRowLocator.evaluate(
		(row: Element, targetPath: string): ReviewTreeSearchClickProof => {
			const rowRect = row.getBoundingClientRect();
			const rootNode = row.getRootNode();
			const queryRoot =
				rootNode instanceof Document || rootNode instanceof ShadowRoot ? rootNode : document;
			const searchInput = queryRoot.querySelector('input[data-file-tree-search-input]');
			const searchContainer = queryRoot.querySelector(
				'[data-file-tree-search-container][data-open="true"]',
			);
			return {
				clickedRowItemPath: row instanceof HTMLElement ? row.getAttribute('data-item-path') : null,
				clickedRowItemType: row instanceof HTMLElement ? row.getAttribute('data-item-type') : null,
				clickedRowVisible: rowRect.width > 0 && rowRect.height > 0,
				searchInputValue: searchInput instanceof HTMLInputElement ? searchInput.value : null,
				searchOpened: searchContainer instanceof HTMLElement,
				selectedContentStateAfterClick: null,
				selectedDisplayPathAfterClick: null,
				selectionMethod: 'playwright-review-tree-search-click',
				targetPath,
			};
		},
		props.path,
	);
	let didSelectTarget = false;
	for (let attempt = 0; attempt < 3; attempt += 1) {
		await targetRowLocator.click({ force: attempt > 0, timeout: 2_000 });
		didSelectTarget = await reviewTreeSelectedPathMatches({
			page: props.page,
			path: props.path,
			timeoutMilliseconds: 1_000,
		});
		if (didSelectTarget) {
			break;
		}
		await props.page.evaluate((targetPath: string): void => {
			const treeHost = document.querySelector(
				'[data-testid="bridge-review-trees-panel"] file-tree-container',
			);
			const button = treeHost?.shadowRoot?.querySelector<HTMLElement>(
				`button[data-item-path="${CSS.escape(targetPath)}"][data-item-type="file"]`,
			);
			button?.focus();
			button?.click();
		}, props.path);
		didSelectTarget = await reviewTreeSelectedPathMatches({
			page: props.page,
			path: props.path,
			timeoutMilliseconds: 1_000,
		});
		if (didSelectTarget) {
			break;
		}
	}
	if (!didSelectTarget) {
		const debugState = await props.page.evaluate((targetPath: string) => {
			const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
			const treeHost = document.querySelector(
				'[data-testid="bridge-review-trees-panel"] file-tree-container',
			);
			const visiblePaths = Array.from(
				treeHost?.shadowRoot?.querySelectorAll<HTMLElement>(
					'button[data-item-path]:not([data-file-tree-sticky-row]):not([data-item-parked])',
				) ?? [],
			)
				.slice(0, 24)
				.map((button) => button.getAttribute('data-item-path'));
			return {
				selectedDisplayPath: reviewShell?.getAttribute('data-selected-display-path') ?? null,
				targetPath,
				visiblePaths,
			};
		}, props.path);
		throw new Error(`Expected Review tree click to select target: ${JSON.stringify(debugState)}`);
	}
	const selectedStateAfterClick = await props.page.evaluate(() => {
		const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
		return {
			selectedContentStateAfterClick:
				reviewShell?.getAttribute('data-selected-content-state') ?? null,
			selectedDisplayPathAfterClick:
				reviewShell?.getAttribute('data-selected-display-path') ?? null,
		};
	});
	return {
		...clickProof,
		...selectedStateAfterClick,
	};
}
