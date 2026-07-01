import { writeFile } from 'node:fs/promises';

import type { Page } from 'playwright';

import { worktreeFileSplitResetReplacementSatisfied } from '../verify-bridge-viewer-worktree-review-proof.ts';
import {
	clickWorktreeFilePath,
	readWorktreeRenderedContentState,
	renderedTextIncludesContent,
	scrollTreeToFilePath,
	waitForPierreFileTreeAnchorSettled,
} from './content-state.ts';
import {
	assertWorktreeFileProductControlsProof,
	captureWorktreeDevServerScreenshot,
	clickWorktreeFileControl,
	fillWorktreeFileSearch,
	projectedTreeSizePixels,
	readWorktreeFileSearchChromeProof,
	selectWorktreeFileFilter,
	visibleWorktreeFilePathSample,
	visibleWorktreeFileRowCount,
	waitForWorktreeFileFilterStatus,
	waitForWorktreeFileFilterStatusAtLeast,
	waitForWorktreeFileInvalidRegexStatus,
	waitForWorktreeOpenFileState,
	waitForWorktreeRenderedFilePathSample,
	worktreeFileControlPressed,
	worktreeFileFilterMenuContains,
	worktreeFileFilterStatusText,
	worktreeFileFilterStatusVisibleCount,
	worktreeFileRowExists,
	worktreeFileTreeTotalSizePixels,
	worktreeFileTreeTotalSizeSource,
} from './file-search-filter.ts';
import {
	installWorktreeRefreshClickProbe,
	readWorktreeDevReloadProof,
	readWorktreeRefreshButtonDisabled,
	setWorktreeDevPollingEnabled,
	setWorktreeDevSplitResetReplacementDelay,
	setWorktreeOpenStateWaitLabel,
	waitForWorktreeDevForceSplitReloadDelivered,
	waitForWorktreeFileSourceCleared,
	waitForWorktreeRefreshButtonEnabled,
	waitForWorktreeRefreshClickProbe,
	waitForWorktreeSourceCursor,
} from './review-selection.ts';
import { installFileContentRouteGate } from './route-probes.ts';
import {
	assertWorktreeVisibleContentText,
	dispatchWorktreeDevForceSplitResetReload,
	dispatchWorktreeDevReload,
	waitForWorktreeVisibleContentText,
	worktreeVisibleContentText,
} from './telemetry.ts';
import {
	splitResetReplacementObservationDelayMilliseconds,
	type WorktreeFileDescriptor,
	type WorktreeFileOpenLoadTelemetryProof,
	type WorktreeFileProductControlsProof,
	type WorktreeFileSplitResetReplacementProof,
	type WorktreeFileStaleRefreshProof,
	type WorktreeFileUnavailableOpenProof,
	type WorktreeRenderedContentState,
} from './types.ts';
import { escapeRegExp, makeDeferred } from './utils.ts';
import {
	fetchFetchableWorktreeFileDescriptorForPath,
	fetchWorktreeSurface,
	type WorktreeFileStaleRefreshFixture,
} from './worktree-data.ts';

export async function verifyWorktreeFileProductControls(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly page: Page;
	readonly targetPath: string;
}): Promise<WorktreeFileProductControlsProof> {
	const expectedFetchableFilterCount = props.descriptors.filter((descriptor) =>
		isFetchableWorktreeFileDescriptor(descriptor),
	).length;
	const expectedUnavailableFilterCount = props.descriptors.filter((descriptor) =>
		isUnavailableWorktreeFileDescriptor(descriptor),
	).length;
	const fetchablePaths = props.descriptors
		.filter((descriptor) => isFetchableWorktreeFileDescriptor(descriptor))
		.map((descriptor) => descriptor.path);
	const unavailablePathSet = new Set(
		props.descriptors
			.filter((descriptor) => isUnavailableWorktreeFileDescriptor(descriptor))
			.map((descriptor) => descriptor.path),
	);
	const unavailablePaths = [...unavailablePathSet];
	const expectedUnavailableDescriptor =
		props.descriptors.find((descriptor) => isUnavailableWorktreeFileDescriptor(descriptor)) ?? null;
	const expectedSearchTreeSizePixels = projectedTreeSizePixels([props.targetPath]);
	const expectedRegexTreeSizePixels = projectedTreeSizePixels([props.targetPath]);
	const expectedInvalidRegexTreeSizePixels = projectedTreeSizePixels([]);
	const expectedFetchableTreeSizePixels =
		fetchablePaths.length === props.descriptors.length
			? null
			: projectedTreeSizePixels(fetchablePaths);
	const expectedUnavailableTreeSizePixels =
		unavailablePaths.length === 0 ? null : projectedTreeSizePixels(unavailablePaths);
	const initialVisibleCount = await visibleWorktreeFileRowCount(props.page);
	const initialRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const initialTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await fillWorktreeFileSearch(props.page, props.targetPath);
	await waitForWorktreeFileFilterStatus(props.page, 1, undefined);
	await waitForWorktreeRenderedFilePathSample(props.page, [props.targetPath]);
	const searchStatusText = await worktreeFileFilterStatusText(props.page);
	const searchResultIncludesTarget = await worktreeFileRowExists(props.page, props.targetPath);
	const searchRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const searchTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const searchTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	const searchChromeProof = await readWorktreeFileSearchChromeProof(props.page);
	const searchScreenshotPath = await captureWorktreeDevServerScreenshot({
		name: 'worktree-file-search-result.png',
		page: props.page,
	});
	await clickWorktreeFileControl(props.page, 'bridge-review-regex-toggle');
	await fillWorktreeFileSearch(props.page, `^${escapeRegExp(props.targetPath)}$`);
	await waitForWorktreeFileFilterStatus(props.page, 1, undefined);
	const regexModeActive = await worktreeFileControlPressed(
		props.page,
		'bridge-review-regex-toggle',
	);
	const regexVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	await waitForWorktreeRenderedFilePathSample(props.page, [props.targetPath]);
	const regexRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const regexTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const regexTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await fillWorktreeFileSearch(props.page, '(');
	await waitForWorktreeFileInvalidRegexStatus(props.page);
	const invalidRegexModeActive = await worktreeFileControlPressed(
		props.page,
		'bridge-review-regex-toggle',
	);
	const invalidRegexStatusText = await worktreeFileFilterStatusText(props.page);
	const invalidRegexRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const invalidRegexTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const invalidRegexTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await fillWorktreeFileSearch(props.page, '');
	await waitForWorktreeFileFilterStatusAtLeast(props.page, 1);
	await selectWorktreeFileFilter(props.page, 'Text files');
	await waitForWorktreeFileFilterStatusAtLeast(props.page, 1);
	const fetchableFilterActive = await worktreeFileFilterMenuContains(props.page, 'Text');
	const fetchableFilterVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	const fetchableRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const fetchableTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const fetchableTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	await selectWorktreeFileFilter(props.page, 'Unavailable files');
	await waitForWorktreeFileFilterStatus(props.page, expectedUnavailableFilterCount, undefined);
	const unavailableFilterActive = await worktreeFileFilterMenuContains(props.page, 'Unavailable');
	const unavailableFilterVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	if (expectedUnavailableDescriptor !== null) {
		await scrollTreeToFilePath(props.page, expectedUnavailableDescriptor.path);
		await waitForPierreFileTreeAnchorSettled(props.page, expectedUnavailableDescriptor.path);
	}
	const unavailableRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const unavailableTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const unavailableTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	const unavailableOpenProof =
		expectedUnavailableDescriptor === null
			? null
			: await verifyUnavailableWorktreeFileOpen({
					descriptor: expectedUnavailableDescriptor,
					page: props.page,
				});
	await selectWorktreeFileFilter(props.page, 'All files');
	await fillWorktreeFileSearch(props.page, '');
	await waitForWorktreeFileFilterStatusAtLeast(props.page, 1);
	const allFilterVisibleCount = await worktreeFileFilterStatusVisibleCount(props.page);
	const allRenderedPathSample = await visibleWorktreeFilePathSample(props.page);
	const allTreeSizePixels = await worktreeFileTreeTotalSizePixels(props.page);
	const allTreeSizeSource = await worktreeFileTreeTotalSizeSource(props.page);
	const proof: WorktreeFileProductControlsProof = {
		allFilterVisibleCount,
		allRenderedPathSample,
		allTreeSizePixels,
		allTreeSizeSource,
		expectedFetchableFilterCount,
		expectedFetchableTreeSizePixels,
		expectedInvalidRegexTreeSizePixels,
		expectedRegexTreeSizePixels,
		expectedSearchTreeSizePixels,
		expectedUnavailableTreeSizePixels,
		expectedUnavailableFilterCount,
		expectedUnavailablePath: expectedUnavailableDescriptor?.path ?? null,
		fetchableFilterActive,
		fetchableFilterVisibleCount,
		fetchableRenderedPathSample,
		fetchableTreeSizePixels,
		fetchableTreeSizeSource,
		initialVisibleCount,
		initialRenderedPathSample,
		initialTreeSizeSource,
		invalidRegexModeActive,
		invalidRegexRenderedPathSample,
		invalidRegexStatusText,
		invalidRegexTreeSizePixels,
		invalidRegexTreeSizeSource,
		regexModeActive,
		regexVisibleCount,
		regexRenderedPathSample,
		regexTreeSizePixels,
		regexTreeSizeSource,
		searchScreenshotPath,
		searchChromeProof,
		searchResultIncludesTarget,
		searchRenderedPathSample,
		searchStatusText,
		searchTreeSizePixels,
		searchTreeSizeSource,
		searchVisibleCount: searchRenderedPathSample.length,
		targetPath: props.targetPath,
		totalTreeRowCount: allFilterVisibleCount,
		unavailableFilterActive,
		unavailableFilterVisibleCount,
		unavailableOpenProof,
		unavailableRenderedPathSample,
		unavailableTreeSizePixels,
		unavailableTreeSizeSource,
	};
	assertWorktreeFileProductControlsProof({
		proof,
		unavailablePathSet,
	});
	return proof;
}

export function isFetchableWorktreeFileDescriptor(descriptor: WorktreeFileDescriptor): boolean {
	return descriptor['isBinary'] !== true && descriptor['virtualizedExtentKind'] !== 'unavailable';
}

export function isUnavailableWorktreeFileDescriptor(descriptor: WorktreeFileDescriptor): boolean {
	return descriptor['isBinary'] === true || descriptor['virtualizedExtentKind'] === 'unavailable';
}

export async function verifyUnavailableWorktreeFileOpen(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly page: Page;
}): Promise<WorktreeFileUnavailableOpenProof> {
	const unavailableGate = makeDeferred<void>();
	unavailableGate.resolve();
	const unavailableRouteProbe = await installFileContentRouteGate({
		gate: unavailableGate,
		page: props.page,
	});
	let renderedState: WorktreeRenderedContentState;
	try {
		await clickWorktreeFilePath(props.page, props.descriptor.path);
		await waitForWorktreeOpenFileState({
			page: props.page,
			path: props.descriptor.path,
			state: 'unavailable',
		});
		renderedState = await readWorktreeRenderedContentState(props.page);
	} finally {
		await unavailableRouteProbe.dispose();
	}
	const proof: WorktreeFileUnavailableOpenProof = {
		contentRouteHitCount: unavailableRouteProbe.hitCount(),
		expectedContentHandle: props.descriptor.contentHandle,
		foreignContentRouteHitCount: unavailableRouteProbe.foreignHitCount(),
		foreignContentRouteHitUrls: unavailableRouteProbe.foreignHitUrls(),
		openedPath: props.descriptor.path,
		selectedContentState: renderedState.selectedContentState,
		selectedLineCount: renderedState.selectedLineCount,
	};
	if (
		proof.contentRouteHitCount !== 0 ||
		proof.foreignContentRouteHitCount !== 0 ||
		proof.selectedContentState !== 'unavailable' ||
		proof.selectedLineCount !== 0
	) {
		throw new Error(
			`Expected unavailable Worktree/File descriptor to open metadata-only without fetching body: ${JSON.stringify(proof)}`,
		);
	}
	return proof;
}

export async function verifyWorktreeFileStaleRefresh(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly fixture: WorktreeFileStaleRefreshFixture;
	readonly page: Page;
}): Promise<WorktreeFileStaleRefreshProof> {
	await fillWorktreeFileSearch(props.page, props.fixture.relativePath);
	await waitForWorktreeFileFilterStatus(props.page, 1, undefined);
	await clickWorktreeFilePath(props.page, props.fixture.relativePath);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'ready',
	});
	await assertWorktreeVisibleContentText({
		expectedText: props.fixture.initialContent,
		label: 'initial stale-refresh proof content',
		page: props.page,
	});
	await writeFile(props.fixture.absolutePath, props.fixture.updatedContent);
	const replacementSurface = await fetchWorktreeSurface();
	const replacementDescriptor = await fetchFetchableWorktreeFileDescriptorForPath({
		path: props.fixture.relativePath,
		surface: replacementSurface,
	});
	if (replacementDescriptor.contentHandle === props.descriptor.contentHandle) {
		throw new Error(
			`Expected stale-refresh proof to use replacement content handle for ${props.fixture.relativePath}`,
		);
	}
	await dispatchWorktreeDevReload(props.page);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'stale',
	});
	await waitForWorktreeSourceCursor({
		page: props.page,
		sourceCursor: replacementSurface.source.sourceCursor,
	});
	const staleNotice = props.page.locator('[data-testid="worktree-file-content-stale"]');
	await staleNotice.getByText('Content changed').waitFor({ state: 'visible', timeout: 10_000 });
	const staleMessageRect = await staleNotice.boundingBox();
	if (staleMessageRect === null) {
		throw new Error('Expected visible Worktree/File stale notice bounding box');
	}
	const staleText = await worktreeVisibleContentText(props.page);
	const staleScreenshotPath = await captureWorktreeDevServerScreenshot({
		name: 'worktree-file-stale-refresh.png',
		page: props.page,
	});
	const staleMessageVisible = await staleNotice.isVisible();
	const refreshGate = makeDeferred<void>();
	const refreshRouteProbe = await installFileContentRouteGate({
		gate: refreshGate,
		page: props.page,
	});
	refreshGate.resolve();
	const refreshFetchHitsBeforeClick = refreshRouteProbe.hitCount();
	await waitForWorktreeRefreshButtonEnabled(props.page);
	await installWorktreeRefreshClickProbe(props.page);
	await clickWorktreeFileControl(props.page, 'worktree-file-refresh');
	await waitForWorktreeRefreshClickProbe(props.page);
	const refreshFetchHitsAfterFirstClick = refreshRouteProbe.hitCount();
	try {
		await setWorktreeOpenStateWaitLabel(props.page, 'stale-refresh-ready');
		await waitForWorktreeOpenFileState({
			page: props.page,
			path: props.fixture.relativePath,
			state: 'ready',
		});
	} catch (error) {
		throw new Error(
			`Expected retry refresh to become ready after second click: ${JSON.stringify({
				hitCount: refreshRouteProbe.hitCount(),
				hitUrls: refreshRouteProbe.hitUrls(),
				replacementContentHandle: replacementDescriptor.contentHandle,
				replacementContentHash: replacementDescriptor.contentHash ?? null,
				replacementSourceCursor: replacementSurface.source.sourceCursor,
				proofPath: props.fixture.relativePath,
			})}`,
			{ cause: error },
		);
	}
	const refreshFetchHitsAfterSecondClick = refreshRouteProbe.hitCount();
	await refreshRouteProbe.dispose();
	const refreshedText = await waitForWorktreeVisibleContentText({
		expectedText: props.fixture.updatedContent,
		label: 'refreshed stale-refresh proof content',
		page: props.page,
	});
	const refreshLoadTelemetry = await props.page.evaluate((): WorktreeFileOpenLoadTelemetryProof => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
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
		return {
			disposition:
				shell instanceof HTMLElement ? shell.getAttribute('data-last-open-load-disposition') : null,
			durationMilliseconds: optionalNumberAttribute(shell, 'data-last-open-load-duration-ms'),
			estimatedBytes: optionalNumberAttribute(shell, 'data-last-open-load-estimated-bytes'),
			executorInFlightBytesAfter: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-in-flight-bytes-after',
			),
			executorInFlightBytesBefore: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-in-flight-bytes-before',
			),
			executorInFlightCountAfter: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-in-flight-after',
			),
			executorInFlightCountBefore: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-in-flight-before',
			),
			executorInFlightMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-in-flight-ms',
			),
			executorPendingWaitMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-pending-wait-ms',
			),
			executorQueuedBytesAfter: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-queued-bytes-after',
			),
			executorQueuedBytesBefore: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-queued-bytes-before',
			),
			executorQueuedLoadCountAfter: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-queued-after',
			),
			executorQueuedLoadCountBefore: optionalNumberAttribute(
				shell,
				'data-last-open-load-executor-queued-before',
			),
			lane: shell instanceof HTMLElement ? shell.getAttribute('data-last-open-load-lane') : null,
			resourceBodyRegistryCommitMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-resource-body-registry-commit-ms',
			),
			resourceFetchResponseWaitMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-resource-fetch-response-wait-ms',
			),
			resourceFirstChunkWaitMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-resource-first-chunk-wait-ms',
			),
			resourceStreamReadMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-resource-stream-read-ms',
			),
			schedulerQueueWaitMilliseconds: optionalNumberAttribute(
				shell,
				'data-last-open-load-scheduler-queue-wait-ms',
			),
			schedulerQueuedEstimatedBytesAfter: optionalNumberAttribute(
				shell,
				'data-last-open-load-scheduler-queued-bytes-after',
			),
			schedulerQueuedEstimatedBytesBefore: optionalNumberAttribute(
				shell,
				'data-last-open-load-scheduler-queued-bytes-before',
			),
			schedulerQueuedIntentCountAfter: optionalNumberAttribute(
				shell,
				'data-last-open-load-scheduler-queued-after',
			),
			schedulerQueuedIntentCountBefore: optionalNumberAttribute(
				shell,
				'data-last-open-load-scheduler-queued-before',
			),
		};
	});
	const proof: WorktreeFileStaleRefreshProof = {
		failedRefreshReturnedStale: true,
		foreignContentRouteHitCount: refreshRouteProbe.foreignHitCount(),
		foreignContentRouteHitUrls: refreshRouteProbe.foreignHitUrls(),
		initialContentStillVisibleWhileStale: renderedTextIncludesContent(
			staleText,
			props.fixture.initialContent,
		),
		proofPath: props.descriptor.path,
		refreshLoadTelemetry,
		refreshFetchHitsAfterFirstClick,
		refreshFetchHitsAfterSecondClick,
		refreshFetchHitsBeforeClick,
		refreshEnteredRefreshing: true,
		refreshReturnedReady: true,
		refreshedContentVisible: renderedTextIncludesContent(
			refreshedText,
			props.fixture.updatedContent,
		),
		staleContentState: 'stale',
		staleMessageRect,
		staleMessageVisible,
		staleScreenshotPath,
	};
	assertWorktreeFileStaleRefreshProof(proof);
	return proof;
}

export async function verifyWorktreeFileSplitResetReplacement(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly fixture: WorktreeFileStaleRefreshFixture;
	readonly page: Page;
}): Promise<WorktreeFileSplitResetReplacementProof> {
	await fillWorktreeFileSearch(props.page, props.fixture.relativePath);
	await waitForWorktreeFileFilterStatus(props.page, 1, undefined);
	await clickWorktreeFilePath(props.page, props.fixture.relativePath);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'ready',
	});
	await assertWorktreeVisibleContentText({
		expectedText: props.fixture.initialContent,
		label: 'initial split-reset proof content',
		page: props.page,
	});
	await setWorktreeDevPollingEnabled({ enabled: false, page: props.page });
	try {
		await writeFile(props.fixture.absolutePath, props.fixture.updatedContent);
		const replacementSurface = await fetchWorktreeSurface();
		const replacementDescriptor = await fetchFetchableWorktreeFileDescriptorForPath({
			path: props.fixture.relativePath,
			surface: replacementSurface,
		});
		if (replacementDescriptor.contentHandle === props.descriptor.contentHandle) {
			throw new Error(
				`Expected split-reset proof to create a replacement content handle for ${props.fixture.relativePath}`,
			);
		}
		const refreshGate = makeDeferred<void>();
		refreshGate.resolve();
		const refreshRouteProbe = await installFileContentRouteGate({
			gate: refreshGate,
			page: props.page,
		});
		let staleText = '';
		let staleMessageVisible = false;
		try {
			const preDispatchContentRouteHitCount = refreshRouteProbe.hitCount();
			await setWorktreeDevSplitResetReplacementDelay({
				delayMilliseconds: splitResetReplacementObservationDelayMilliseconds,
				page: props.page,
			});
			await dispatchWorktreeDevForceSplitResetReload(props.page);
			await waitForWorktreeFileSourceCleared(props.page);
			await waitForWorktreeOpenFileState({
				page: props.page,
				path: props.fixture.relativePath,
				state: 'stale',
			});
			const staleNotice = props.page.locator('[data-testid="worktree-file-content-stale"]');
			await staleNotice.getByText('Content changed').waitFor({ state: 'visible', timeout: 10_000 });
			const refreshDisabledAtFirstStale = await readWorktreeRefreshButtonDisabled(props.page);
			await waitForWorktreeDevForceSplitReloadDelivered({
				page: props.page,
				sourceCursor: replacementSurface.source.sourceCursor,
			});
			const devReloadProof = await readWorktreeDevReloadProof(props.page);
			await waitForWorktreeRefreshButtonEnabled(props.page);
			const refreshEnabledAfterReplacement = !(await readWorktreeRefreshButtonDisabled(props.page));
			staleMessageVisible = await staleNotice.isVisible();
			staleText = await worktreeVisibleContentText(props.page);
			const postReplacementContentRouteHitCount = refreshRouteProbe.hitCount();
			await installWorktreeRefreshClickProbe(props.page);
			await clickWorktreeFileControl(props.page, 'worktree-file-refresh');
			await waitForWorktreeRefreshClickProbe(props.page);
			await setWorktreeOpenStateWaitLabel(props.page, 'split-reset-refresh-ready');
			await waitForWorktreeOpenFileState({
				page: props.page,
				path: props.fixture.relativePath,
				state: 'ready',
			});
			const postRefreshContentRouteHitCount = refreshRouteProbe.hitCount();
			const refreshedText = await waitForWorktreeVisibleContentText({
				expectedText: props.fixture.updatedContent,
				label: 'split-reset replacement proof content',
				page: props.page,
			});
			const hitUrls = refreshRouteProbe.hitUrls();
			const oldContentRouteHitCount = hitUrls.filter((hitUrl) =>
				hitUrl.includes(encodeURIComponent(props.descriptor.contentHandle)),
			).length;
			const replacementContentRouteHitCount = hitUrls.filter((hitUrl) =>
				hitUrl.includes(encodeURIComponent(replacementDescriptor.contentHandle)),
			).length;
			const proof: WorktreeFileSplitResetReplacementProof = {
				devReloadFrameCount: devReloadProof.frameCount,
				devReloadFrameGenerations: devReloadProof.frameGenerations,
				devReloadFrameKinds: devReloadProof.frameKinds,
				devReloadFrameSequences: devReloadProof.frameSequences,
				devReloadFrameStreamIds: devReloadProof.frameStreamIds,
				devReloadRequest: devReloadProof.request,
				devReloadSourceCursor: devReloadProof.sourceCursor,
				devReloadStatus: devReloadProof.status,
				foreignContentRouteHitCount: refreshRouteProbe.foreignHitCount(),
				foreignContentRouteHitUrls: refreshRouteProbe.foreignHitUrls(),
				initialContentStillVisibleWhileStale: renderedTextIncludesContent(
					staleText,
					props.fixture.initialContent,
				),
				oldContentHandle: props.descriptor.contentHandle,
				oldContentRouteHitCount,
				postRefreshContentRouteHitCount,
				postReplacementContentRouteHitCount,
				preDispatchContentRouteHitCount,
				proofPath: props.fixture.relativePath,
				refreshDisabledAtFirstStale,
				refreshEnabledAfterReplacement,
				refreshedContentVisible: renderedTextIncludesContent(
					refreshedText,
					props.fixture.updatedContent,
				),
				replacementContentHandle: replacementDescriptor.contentHandle,
				replacementContentHash: replacementDescriptor.contentHash ?? null,
				replacementContentRouteHitCount,
				replacementSourceCursor: replacementSurface.source.sourceCursor,
				selectedContentStateAfterReset: 'stale',
				staleMessageVisible,
			};
			assertWorktreeFileSplitResetReplacementProof(proof);
			return proof;
		} finally {
			await setWorktreeDevSplitResetReplacementDelay({
				delayMilliseconds: null,
				page: props.page,
			});
			await refreshRouteProbe.dispose();
		}
	} finally {
		await setWorktreeDevPollingEnabled({ enabled: true, page: props.page });
	}
}

export function assertWorktreeFileSplitResetReplacementProof(
	proof: WorktreeFileSplitResetReplacementProof,
): void {
	if (!worktreeFileSplitResetReplacementSatisfied(proof)) {
		throw new Error(`Expected durable Worktree/File split reset proof: ${JSON.stringify(proof)}`);
	}
}

export function assertWorktreeFileStaleRefreshProof(proof: WorktreeFileStaleRefreshProof): void {
	if (proof.proofPath.length === 0) {
		throw new Error(`Expected Worktree/File stale-refresh proof path: ${JSON.stringify(proof)}`);
	}
	if (
		!proof.initialContentStillVisibleWhileStale ||
		!proof.staleMessageVisible ||
		proof.staleContentState !== 'stale'
	) {
		throw new Error(`Expected Worktree/File stale state before refresh: ${JSON.stringify(proof)}`);
	}
	if (
		!proof.refreshEnteredRefreshing ||
		!proof.refreshReturnedReady ||
		!proof.refreshedContentVisible ||
		proof.foreignContentRouteHitCount !== 0 ||
		proof.refreshFetchHitsBeforeClick !== 0 ||
		proof.refreshFetchHitsAfterSecondClick < proof.refreshFetchHitsAfterFirstClick ||
		!(
			proof.refreshLoadTelemetry.disposition === 'refreshed' ||
			proof.refreshLoadTelemetry.disposition === 'cache-hit' ||
			proof.refreshLoadTelemetry.disposition === 'visible-preloaded'
		) ||
		proof.refreshLoadTelemetry.lane !== 'foreground' ||
		proof.refreshLoadTelemetry.durationMilliseconds === null ||
		proof.refreshLoadTelemetry.durationMilliseconds < 0 ||
		proof.refreshLoadTelemetry.estimatedBytes === null ||
		proof.refreshLoadTelemetry.estimatedBytes <= 0 ||
		proof.refreshLoadTelemetry.schedulerQueuedIntentCountAfter !== 0 ||
		proof.refreshLoadTelemetry.schedulerQueuedEstimatedBytesAfter !== 0 ||
		proof.refreshLoadTelemetry.executorInFlightCountAfter !== 0 ||
		proof.refreshLoadTelemetry.executorInFlightBytesAfter !== 0 ||
		proof.refreshLoadTelemetry.executorQueuedLoadCountAfter !== 0 ||
		proof.refreshLoadTelemetry.executorQueuedBytesAfter !== 0 ||
		proof.refreshLoadTelemetry.schedulerQueuedIntentCountBefore !== 0 ||
		proof.refreshLoadTelemetry.schedulerQueuedEstimatedBytesBefore !== 0 ||
		proof.refreshLoadTelemetry.executorInFlightCountBefore !== 0 ||
		proof.refreshLoadTelemetry.executorInFlightBytesBefore !== 0 ||
		proof.refreshLoadTelemetry.executorQueuedLoadCountBefore !== 0 ||
		proof.refreshLoadTelemetry.executorQueuedBytesBefore !== 0
	) {
		throw new Error(
			`Expected Worktree/File explicit refresh to render update: ${JSON.stringify(proof)}`,
		);
	}
}
