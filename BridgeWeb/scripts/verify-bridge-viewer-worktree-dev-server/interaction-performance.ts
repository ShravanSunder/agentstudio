import type { Page } from 'playwright';

import {
	summarizeInteractionSamples,
	type ReviewClickPhaseDurationSummaries,
	type ReviewClickReadinessBreakdownSummaries,
	type ReviewDevContentResponseTimingProof,
	type ReviewInteractionPerformanceProof,
	type ReviewStartupLoadTimingProof,
	type WorktreeFileClickPhaseDurationSummaries,
	type WorktreeInteractionDurationSummary,
	type WorktreeInteractionFailureDetail,
	type WorktreeInteractionPerformanceProof,
	type WorktreeInteractionSlowSampleDetail,
	type WorktreeStartupLoadTimingProof,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import { readCurrentCommitSha, workerModeFromDevServerUrl } from './artifacts.ts';
import {
	proofRunCreatedAtUnixMilliseconds,
	worktreeDevServerUrl,
	worktreeReviewDevServerUrl,
} from './config.ts';
import { dismissOpenBridgeMenus } from './content-state.ts';
import { fillWorktreeFileSearch } from './file-search-filter.ts';
import { assertObservedWorktreeDevServerUrl, reloadWorktreeDevServerPage } from './page-shell.ts';
import {
	clickVisibleWorktreeFilePath,
	readReviewCodeViewItemCount,
	waitForAnyWorktreeSelectedPathTiming,
	waitForWorktreeFirstVisibleContentWindow,
	waitForWorktreeOpenFileReadyMilliseconds,
	waitForWorktreeSelectedPathMilliseconds,
	worktreeFirstVisibleContentWindowDiagnosticMessage,
} from './performance-click-waits.ts';
import { collectReviewWorkerQueueWaitMilliseconds } from './performance-correlation.ts';
import { reviewClickFailureDiagnosticMessage } from './review-selection.ts';
import {
	collectInPageReviewTreeClickPerformanceSample,
	revealReviewTreeFilePath,
	reviewTreeReachablePathScrollTopMap,
	waitForAnyReviewSelectedContentState,
	waitForReviewTreeScrollSettled,
	waitForVisibleReviewTreeFilePath,
} from './review-tree-click.ts';
import { readBridgeDevTelemetryStatusSamples } from './route-probes.ts';
import {
	collectReviewCodeViewScrollPerformanceSamples,
	collectReviewTreeScrollPerformanceSamples,
	collectWorktreeTreeScrollPerformanceSamples,
	evenlySampledDescriptors,
	evenlySampledReviewClickTargets,
	normalWorktreeFilePerformanceDescriptors,
	normalWorktreeReviewPerformanceClickTargets,
	resetReviewTreeForPerformanceSamples,
	waitForPerformanceFileTreeAnchorSettled,
	worktreeFileDescriptorExpectedBytes,
	worktreeFilePathEligibleForPerformanceClick,
	worktreeFileTreeReachablePathSet,
} from './scroll-performance.ts';
import {
	interactionPerformanceSampleCount,
	interactionPerformanceSampleTimeoutMilliseconds,
	slowInteractionPerformanceSampleMilliseconds,
	type ReviewPerformanceClickTarget,
	type WorktreeBridgeTelemetrySampleProof,
	type WorktreeFileDescriptor,
} from './types.ts';

export async function collectWorktreeInteractionPerformanceProof(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly page: Page;
	readonly startupLoadTiming: WorktreeStartupLoadTimingProof;
}): Promise<WorktreeInteractionPerformanceProof> {
	const clickSamples = await collectWorktreeFileClickPerformanceSamples(props);
	const scrollSamples = await collectWorktreeTreeScrollPerformanceSamples(props.page);
	return {
		blankTreeWindowCount: scrollSamples.blankTreeWindowCount,
		browserOrNativeRuntime: 'vite',
		clickPhaseDurations: summarizeClickPhaseDurations(clickSamples),
		clickToFirstVisibleContentWindow: summarizeInteractionSamples(
			clickSamples.durationMilliseconds,
		),
		commitSha: await readCurrentCommitSha(),
		fileClickFailureDetails: clickSamples.failureDetails,
		fileClickSlowSampleDetails: clickSamples.slowSampleDetails,
		fileClickSampleCount: clickSamples.durationMilliseconds.length,
		runMarker: `bridgeviewer-worktree-vite-${proofRunCreatedAtUnixMilliseconds}`,
		scrollToVisibleRows: summarizeInteractionSamples(scrollSamples.durationMilliseconds),
		startupLoadTiming: props.startupLoadTiming,
		treeScrollSettleFrameCount: summarizeInteractionSamples(scrollSamples.settleFrameCounts),
		treeScrollSampleCount: scrollSamples.durationMilliseconds.length,
		workerMode: workerModeFromDevServerUrl(worktreeDevServerUrl),
		wrongVisibleRowCount: scrollSamples.wrongVisibleRowCount,
	};
}

export async function collectReviewInteractionPerformanceProof(props: {
	readonly page: Page;
}): Promise<ReviewInteractionPerformanceProof> {
	const reviewStartupLoadTiming = await collectReviewStartupLoadTimingProof(props.page);
	await resetReviewTreeForPerformanceSamples(props.page);
	const reachablePathScrollTopByPath = await reviewTreeReachablePathScrollTopMap(props.page);
	const clickTargets = normalWorktreeReviewPerformanceClickTargets(
		[...reachablePathScrollTopByPath.keys()]
			.filter(worktreeFilePathEligibleForPerformanceClick)
			.map((displayPath): ReviewPerformanceClickTarget => ({ displayPath, lineCount: null })),
	);
	const clickSamples = await collectReviewTreeClickPerformanceSamples({
		clickTargets,
		page: props.page,
	});
	const selectedWorkerQueueSamples = await readBridgeDevTelemetryStatusSamples(props.page);
	const reviewDevContentResponseTiming = await collectReviewDevContentResponseTimingProof(
		props.page,
	);
	await resetReviewTreeForPerformanceSamples(props.page);
	const treeScrollSamples = await collectReviewTreeScrollPerformanceSamples(props.page);
	const visibleWorkerQueueSamples = await readBridgeDevTelemetryStatusSamples(props.page);
	const workerQueueWaitMilliseconds = collectReviewWorkerQueueWaitMilliseconds({
		sampleCount: interactionPerformanceSampleCount,
		selectedPhaseSamples: selectedWorkerQueueSamples,
		visiblePhaseSamples: visibleWorkerQueueSamples,
	});
	const codeViewScrollSamples = await collectReviewCodeViewScrollPerformanceSamples(props.page);
	const codeViewItemCountAfter = await readReviewCodeViewItemCount(props.page);
	return {
		browserOrNativeRuntime: 'vite',
		codeViewBlankWindowCount: codeViewScrollSamples.blankWindowCount,
		codeViewHeightChangeCount: codeViewScrollSamples.heightChangeCount,
		codeViewItemCountAfter,
		codeViewScrollSampleCount: codeViewScrollSamples.durationMilliseconds.length,
		codeViewScrollToStableWindow: summarizeInteractionSamples(
			codeViewScrollSamples.durationMilliseconds,
		),
		commitSha: await readCurrentCommitSha(),
		reviewClickReadinessBreakdown: summarizeReviewClickReadinessBreakdown(clickSamples),
		reviewClickPhaseDurations: summarizeReviewClickPhaseDurations(clickSamples),
		reviewClickFailureDetails: clickSamples.failureDetails,
		reviewClickSlowSampleDetails: clickSamples.slowSampleDetails,
		reviewClickSampleCount: clickSamples.durationMilliseconds.length,
		reviewClickToSelectedReady: summarizeInteractionSamples(clickSamples.durationMilliseconds),
		reviewDevContentResponseTiming,
		reviewStartupLoadTiming,
		reviewTreeBlankWindowCount: treeScrollSamples.blankTreeWindowCount,
		reviewTreeScrollSettleFrameCount: summarizeInteractionSamples(
			treeScrollSamples.settleFrameCounts,
		),
		reviewTreeScrollSampleCount: treeScrollSamples.durationMilliseconds.length,
		reviewTreeScrollToVisibleRows: summarizeInteractionSamples(
			treeScrollSamples.durationMilliseconds,
		),
		reviewTreeWrongVisibleRowCount: treeScrollSamples.wrongVisibleRowCount,
		codeViewScrollSettleFrameCount: summarizeInteractionSamples(
			codeViewScrollSamples.settleFrameCounts,
		),
		runMarker: `bridgeviewer-review-vite-${proofRunCreatedAtUnixMilliseconds}`,
		workerMode: workerModeFromDevServerUrl(worktreeDevServerUrl),
		workerQueueWait: {
			selected: summarizeInteractionSamples(workerQueueWaitMilliseconds.selected),
			visible: summarizeInteractionSamples(workerQueueWaitMilliseconds.visible),
		},
	};
}

export async function collectReviewDevContentResponseTimingProof(
	page: Page,
): Promise<ReviewDevContentResponseTimingProof> {
	const samples = await waitForReviewDevContentResponseTelemetrySamples({
		page,
	});
	const reviewDevContentSamples = samples.filter(
		(sample): boolean =>
			sample.name === 'performance.bridge.web.dev_content_response' &&
			sample.viewer === 'review' &&
			sample.result === 'success',
	);
	return {
		getProvider: summarizeBridgeTelemetryPhaseDurations({
			phase: 'dev_content_get_provider',
			samples: reviewDevContentSamples,
		}),
		providerLoad: summarizeBridgeTelemetryPhaseDurations({
			phase: 'dev_content_provider_load',
			samples: reviewDevContentSamples,
		}),
		responseTotal: summarizeBridgeTelemetryPhaseDurations({
			phase: 'dev_content_response_total',
			samples: reviewDevContentSamples,
		}),
	};
}

export async function waitForReviewDevContentResponseTelemetrySamples(props: {
	readonly page: Page;
	readonly remainingAttempts?: number;
}): Promise<readonly WorktreeBridgeTelemetrySampleProof[]> {
	const samples = await readBridgeDevTelemetryStatusSamples(props.page);
	const reviewDevContentSamples = samples.filter(
		(sample): boolean =>
			sample.name === 'performance.bridge.web.dev_content_response' &&
			sample.viewer === 'review' &&
			sample.result === 'success',
	);
	const phaseNames = new Set(reviewDevContentSamples.map((sample): string | null => sample.phase));
	if (
		phaseNames.has('dev_content_get_provider') &&
		phaseNames.has('dev_content_provider_load') &&
		phaseNames.has('dev_content_response_total')
	) {
		return samples;
	}
	const remainingAttempts = props.remainingAttempts ?? 100;
	if (remainingAttempts <= 0) {
		return samples;
	}
	await new Promise<void>((resolve): void => {
		setTimeout(resolve, 10);
	});
	return await waitForReviewDevContentResponseTelemetrySamples({
		page: props.page,
		remainingAttempts: remainingAttempts - 1,
	});
}

export function summarizeBridgeTelemetryPhaseDurations(props: {
	readonly phase: string;
	readonly samples: readonly WorktreeBridgeTelemetrySampleProof[];
}): WorktreeInteractionDurationSummary {
	return summarizeInteractionSamples(
		props.samples
			.filter((sample): boolean => sample.phase === props.phase)
			.map((sample): number => sample.durationMilliseconds ?? Number.NaN),
	);
}

export async function collectWorktreeStartupLoadTimingProof(props: {
	readonly page: Page;
}): Promise<WorktreeStartupLoadTimingProof> {
	const pageLoadStartedAt = performance.now();
	await reloadWorktreeDevServerPage(props.page);
	await assertObservedWorktreeDevServerUrl(props.page);
	const selectedPathTiming = await waitForAnyWorktreeSelectedPathTiming({
		page: props.page,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	const contentReadyMilliseconds = await waitForWorktreeOpenFileReadyMilliseconds({
		page: props.page,
		path: selectedPathTiming.path,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	await waitForWorktreeFirstVisibleContentWindow({
		page: props.page,
		path: selectedPathTiming.path,
		timeoutMilliseconds: 20_000,
	});
	const firstVisibleContentWindowMilliseconds = Math.max(0, performance.now() - pageLoadStartedAt);
	return {
		pageLoadToContentReady: summarizeInteractionSamples([contentReadyMilliseconds]),
		pageLoadToFirstVisibleContentWindow: summarizeInteractionSamples([
			firstVisibleContentWindowMilliseconds,
		]),
		pageLoadToSelectedPath: summarizeInteractionSamples([
			selectedPathTiming.selectedPathMilliseconds,
		]),
	};
}

export async function collectReviewStartupLoadTimingProof(
	page: Page,
): Promise<ReviewStartupLoadTimingProof> {
	const pageLoadStartedAt = performance.now();
	await page.goto(worktreeReviewDevServerUrl, {
		waitUntil: 'domcontentloaded',
		timeout: 30_000,
	});
	await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
	await page.waitForFunction(
		(): boolean => {
			const shell = document.querySelector('[data-testid="review-viewer-shell"]');
			return Number(shell?.getAttribute('data-review-metadata-item-count') ?? '0') > 0;
		},
		undefined,
		{ timeout: 30_000 },
	);
	const pageLoadToMetadataMilliseconds = Math.max(0, performance.now() - pageLoadStartedAt);
	await waitForAnyReviewSelectedContentState({ page, state: 'ready' });
	const pageLoadToSelectedContentReadyMilliseconds = Math.max(
		0,
		performance.now() - pageLoadStartedAt,
	);
	return {
		pageLoadToMetadata: summarizeInteractionSamples([pageLoadToMetadataMilliseconds]),
		pageLoadToSelectedContentReady: summarizeInteractionSamples([
			pageLoadToSelectedContentReadyMilliseconds,
		]),
	};
}

export async function collectReviewTreeClickPerformanceSamples(props: {
	readonly clickTargets: readonly ReviewPerformanceClickTarget[];
	readonly page: Page;
}): Promise<{
	readonly durationMilliseconds: readonly number[];
	readonly codeViewMaterializedAfterContentReadyMilliseconds: readonly number[];
	readonly firstVisibleAfterReadyMilliseconds: readonly number[];
	readonly failureDetails: readonly WorktreeInteractionFailureDetail[];
	readonly contentReadyAfterSelectedPathMilliseconds: readonly number[];
	readonly readyAfterSelectionMilliseconds: readonly number[];
	readonly selectionCommitMilliseconds: readonly number[];
	readonly selectedPathStateMilliseconds: readonly number[];
	readonly slowSampleDetails: readonly WorktreeInteractionSlowSampleDetail[];
	readonly treeSelectionVisibleMilliseconds: readonly number[];
	readonly visibleContentRenderedAfterMaterializationMilliseconds: readonly number[];
}> {
	if (props.clickTargets.length === 0) {
		throw new Error(
			`Expected normal Worktree/Review performance click targets, got ${props.clickTargets.length}`,
		);
	}
	const durationMilliseconds: number[] = [];
	const codeViewMaterializedAfterContentReadyMilliseconds: number[] = [];
	const firstVisibleAfterReadyMilliseconds: number[] = [];
	const failureDetails: WorktreeInteractionFailureDetail[] = [];
	const contentReadyAfterSelectedPathMilliseconds: number[] = [];
	const readyAfterSelectionMilliseconds: number[] = [];
	const selectionCommitMilliseconds: number[] = [];
	const selectedPathStateMilliseconds: number[] = [];
	const slowSampleDetails: WorktreeInteractionSlowSampleDetail[] = [];
	const treeSelectionVisibleMilliseconds: number[] = [];
	const visibleContentRenderedAfterMaterializationMilliseconds: number[] = [];
	await resetReviewTreeForPerformanceSamples(props.page);
	const reachablePathScrollTopByPath = await reviewTreeReachablePathScrollTopMap(props.page);
	const reachableTargets = props.clickTargets.filter((target): boolean =>
		reachablePathScrollTopByPath.has(target.displayPath),
	);
	const clickSampleTargets = evenlySampledReviewClickTargets({
		clickTargets: reachableTargets,
		sampleCount: interactionPerformanceSampleCount,
	});
	if (clickSampleTargets.length < interactionPerformanceSampleCount) {
		throw new Error(
			`Expected tree-reachable normal Worktree/Review performance click targets, got ${reachableTargets.length}`,
		);
	}
	for (const clickTarget of clickSampleTargets) {
		await dismissOpenBridgeMenus(props.page);
		await revealReviewTreeFilePath({
			page: props.page,
			path: clickTarget.displayPath,
			scrollTopHint: reachablePathScrollTopByPath.get(clickTarget.displayPath) ?? 0,
		});
		await waitForReviewTreeScrollSettled(props.page);
		try {
			const preClickStartedAt = performance.now();
			await waitForVisibleReviewTreeFilePath({
				page: props.page,
				path: clickTarget.displayPath,
			});
			const preClickMilliseconds = Math.max(0, performance.now() - preClickStartedAt);
			const sample = await collectInPageReviewTreeClickPerformanceSample({
				displayPath: clickTarget.displayPath,
				page: props.page,
				timeoutMilliseconds: interactionPerformanceSampleTimeoutMilliseconds,
			});
			const durationMillisecondsForSample = sample.durationMilliseconds;
			durationMilliseconds.push(durationMillisecondsForSample);
			codeViewMaterializedAfterContentReadyMilliseconds.push(
				Math.max(0, sample.codeViewMaterializedMilliseconds - sample.readyMilliseconds),
			);
			contentReadyAfterSelectedPathMilliseconds.push(
				Math.max(0, sample.readyMilliseconds - sample.selectedMilliseconds),
			);
			selectionCommitMilliseconds.push(sample.selectedMilliseconds);
			selectedPathStateMilliseconds.push(sample.selectedMilliseconds);
			readyAfterSelectionMilliseconds.push(
				Math.max(0, sample.readyMilliseconds - sample.selectedMilliseconds),
			);
			firstVisibleAfterReadyMilliseconds.push(
				Math.max(0, durationMillisecondsForSample - sample.readyMilliseconds),
			);
			treeSelectionVisibleMilliseconds.push(sample.treeSelectionVisibleMilliseconds);
			visibleContentRenderedAfterMaterializationMilliseconds.push(
				Math.max(
					0,
					sample.visibleContentRenderedMilliseconds - sample.codeViewMaterializedMilliseconds,
				),
			);
			if (durationMillisecondsForSample >= slowInteractionPerformanceSampleMilliseconds) {
				slowSampleDetails.push({
					appSelectionCommitMilliseconds: sample.appSelectionCommitMilliseconds,
					codeViewMaterializedMilliseconds: sample.codeViewMaterializedMilliseconds,
					clickDispatchMilliseconds: sample.clickDispatchMilliseconds,
					durationMilliseconds: durationMillisecondsForSample,
					expectedBytes: null,
					lineCount: clickTarget.lineCount,
					path: clickTarget.displayPath,
					preClickMilliseconds,
					readyMilliseconds: sample.readyMilliseconds,
					selectedMilliseconds: sample.selectedMilliseconds,
					selectedMaterializationMilliseconds: sample.selectedMaterializationMilliseconds,
					treeSelectionVisibleMilliseconds: sample.treeSelectionVisibleMilliseconds,
					visibleContentRenderedMilliseconds: sample.visibleContentRenderedMilliseconds,
				});
			}
		} catch {
			durationMilliseconds.push(Number.NaN);
			codeViewMaterializedAfterContentReadyMilliseconds.push(Number.NaN);
			contentReadyAfterSelectedPathMilliseconds.push(Number.NaN);
			selectionCommitMilliseconds.push(Number.NaN);
			selectedPathStateMilliseconds.push(Number.NaN);
			readyAfterSelectionMilliseconds.push(Number.NaN);
			firstVisibleAfterReadyMilliseconds.push(Number.NaN);
			treeSelectionVisibleMilliseconds.push(Number.NaN);
			visibleContentRenderedAfterMaterializationMilliseconds.push(Number.NaN);
			failureDetails.push({
				message: await reviewClickFailureDiagnosticMessage({
					page: props.page,
					targetPath: clickTarget.displayPath,
				}),
				path: clickTarget.displayPath,
			});
		}
	}
	return {
		codeViewMaterializedAfterContentReadyMilliseconds,
		contentReadyAfterSelectedPathMilliseconds,
		durationMilliseconds,
		failureDetails,
		firstVisibleAfterReadyMilliseconds,
		readyAfterSelectionMilliseconds,
		selectionCommitMilliseconds,
		selectedPathStateMilliseconds,
		slowSampleDetails,
		treeSelectionVisibleMilliseconds,
		visibleContentRenderedAfterMaterializationMilliseconds,
	};
}

export function summarizeReviewClickReadinessBreakdown(clickSamples: {
	readonly codeViewMaterializedAfterContentReadyMilliseconds: readonly number[];
	readonly contentReadyAfterSelectedPathMilliseconds: readonly number[];
	readonly selectedPathStateMilliseconds: readonly number[];
	readonly treeSelectionVisibleMilliseconds: readonly number[];
	readonly visibleContentRenderedAfterMaterializationMilliseconds: readonly number[];
}): ReviewClickReadinessBreakdownSummaries {
	return {
		codeViewMaterializedAfterContentReady: summarizeInteractionSamples(
			clickSamples.codeViewMaterializedAfterContentReadyMilliseconds,
		),
		contentReadyAfterSelectedPath: summarizeInteractionSamples(
			clickSamples.contentReadyAfterSelectedPathMilliseconds,
		),
		selectedPathState: summarizeInteractionSamples(clickSamples.selectedPathStateMilliseconds),
		treeSelectionVisible: summarizeInteractionSamples(
			clickSamples.treeSelectionVisibleMilliseconds,
		),
		visibleContentRenderedAfterMaterialization: summarizeInteractionSamples(
			clickSamples.visibleContentRenderedAfterMaterializationMilliseconds,
		),
	};
}

export function summarizeReviewClickPhaseDurations(clickSamples: {
	readonly firstVisibleAfterReadyMilliseconds: readonly number[];
	readonly readyAfterSelectionMilliseconds: readonly number[];
	readonly selectionCommitMilliseconds: readonly number[];
}): ReviewClickPhaseDurationSummaries {
	return {
		firstVisibleAfterReady: summarizeInteractionSamples(
			clickSamples.firstVisibleAfterReadyMilliseconds,
		),
		readyAfterSelection: summarizeInteractionSamples(clickSamples.readyAfterSelectionMilliseconds),
		selectionCommit: summarizeInteractionSamples(clickSamples.selectionCommitMilliseconds),
	};
}

export async function collectWorktreeFileClickPerformanceSamples(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly page: Page;
}): Promise<{
	readonly durationMilliseconds: readonly number[];
	readonly firstVisibleAfterReadyMilliseconds: readonly number[];
	readonly failureDetails: readonly WorktreeInteractionFailureDetail[];
	readonly openReadyAfterSelectionMilliseconds: readonly number[];
	readonly selectionCommitMilliseconds: readonly number[];
	readonly slowSampleDetails: readonly WorktreeInteractionSlowSampleDetail[];
}> {
	const reachablePathSet = await worktreeFileTreeReachablePathSet(props.page);
	const sampleDescriptors = normalWorktreeFilePerformanceDescriptors(props.descriptors).filter(
		(descriptor): boolean => reachablePathSet.has(descriptor.path),
	);
	if (sampleDescriptors.length < interactionPerformanceSampleCount) {
		throw new Error(
			`Expected at least ${interactionPerformanceSampleCount} demanded normal tree-reachable Worktree/File descriptors for click performance proof, got ${sampleDescriptors.length}`,
		);
	}
	const durationMilliseconds: number[] = [];
	const failureDetails: WorktreeInteractionFailureDetail[] = [];
	const firstVisibleAfterReadyMilliseconds: number[] = [];
	const openReadyAfterSelectionMilliseconds: number[] = [];
	const selectionCommitMilliseconds: number[] = [];
	const slowSampleDetails: WorktreeInteractionSlowSampleDetail[] = [];
	for (const descriptor of evenlySampledDescriptors({
		descriptors: sampleDescriptors,
		sampleCount: interactionPerformanceSampleCount,
	})) {
		await dismissOpenBridgeMenus(props.page);
		await fillWorktreeFileSearch(props.page, descriptor.path);
		await waitForPerformanceFileTreeAnchorSettled(props.page, descriptor.path);
		const startedAt = performance.now();
		await clickVisibleWorktreeFilePath(props.page, descriptor.path);
		try {
			const selectedMilliseconds = await waitForWorktreeSelectedPathMilliseconds({
				page: props.page,
				path: descriptor.path,
				startedAt,
				timeoutMilliseconds: interactionPerformanceSampleTimeoutMilliseconds,
			});
			const readyMilliseconds = await waitForWorktreeOpenFileReadyMilliseconds({
				page: props.page,
				path: descriptor.path,
				startedAt,
				timeoutMilliseconds: interactionPerformanceSampleTimeoutMilliseconds,
			});
			await waitForWorktreeFirstVisibleContentWindow({
				page: props.page,
				path: descriptor.path,
				timeoutMilliseconds: interactionPerformanceSampleTimeoutMilliseconds,
			});
			const durationMillisecondsForSample = Math.max(0, performance.now() - startedAt);
			durationMilliseconds.push(durationMillisecondsForSample);
			selectionCommitMilliseconds.push(selectedMilliseconds);
			openReadyAfterSelectionMilliseconds.push(
				Math.max(0, readyMilliseconds - selectedMilliseconds),
			);
			firstVisibleAfterReadyMilliseconds.push(
				Math.max(0, durationMillisecondsForSample - readyMilliseconds),
			);
			if (durationMillisecondsForSample >= slowInteractionPerformanceSampleMilliseconds) {
				slowSampleDetails.push({
					durationMilliseconds: durationMillisecondsForSample,
					expectedBytes: worktreeFileDescriptorExpectedBytes(descriptor),
					lineCount: Number.isFinite(Number(descriptor['lineCount']))
						? Number(descriptor['lineCount'])
						: null,
					path: descriptor.path,
					readyMilliseconds,
					selectedMilliseconds,
				});
			}
		} catch {
			durationMilliseconds.push(Number.NaN);
			failureDetails.push({
				message: await worktreeFirstVisibleContentWindowDiagnosticMessage(props.page),
				path: descriptor.path,
			});
		}
	}
	return {
		durationMilliseconds,
		failureDetails,
		firstVisibleAfterReadyMilliseconds,
		openReadyAfterSelectionMilliseconds,
		selectionCommitMilliseconds,
		slowSampleDetails,
	};
}

export function summarizeClickPhaseDurations(clickSamples: {
	readonly firstVisibleAfterReadyMilliseconds: readonly number[];
	readonly openReadyAfterSelectionMilliseconds: readonly number[];
	readonly selectionCommitMilliseconds: readonly number[];
}): WorktreeFileClickPhaseDurationSummaries {
	return {
		firstVisibleAfterReady: summarizeInteractionSamples(
			clickSamples.firstVisibleAfterReadyMilliseconds,
		),
		openReadyAfterSelection: summarizeInteractionSamples(
			clickSamples.openReadyAfterSelectionMilliseconds,
		),
		selectionCommit: summarizeInteractionSamples(clickSamples.selectionCommitMilliseconds),
	};
}
