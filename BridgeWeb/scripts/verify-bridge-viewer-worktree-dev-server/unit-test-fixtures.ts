import { summarizeInteractionSamples } from '../verify-bridge-viewer-worktree-review-proof.ts';
import type {
	ReviewDemandTelemetryProof,
	ReviewInteractionPerformanceProof,
	ReviewMetadataBeforeContentProof,
	ReviewStartupTelemetrySampleProof,
	WorktreeInteractionPerformanceProof,
} from '../verify-bridge-viewer-worktree-review-proof.ts';

export function makeReviewStartupTelemetrySample(name: string): ReviewStartupTelemetrySampleProof {
	return {
		durationMilliseconds: 1,
		name,
		numericAttributes: {},
		phase: name.replace('performance.bridge.web.', ''),
		result: 'success',
		slice: 'review_metadata',
		transport: 'content',
	};
}

export function makePassingInteractionPerformanceProof(): WorktreeInteractionPerformanceProof {
	const passingClickSamples = Array.from({ length: 100 }, (_, index): number =>
		index < 95 ? 24 : 48,
	);
	const passingScrollSamples = Array.from({ length: 100 }, (_, index): number =>
		index < 95 ? 18 : 42,
	);
	return {
		blankTreeWindowCount: 0,
		browserOrNativeRuntime: 'vite',
		clickPhaseDurations: {
			firstVisibleAfterReady: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 2),
			),
			openReadyAfterSelection: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 40),
			),
			selectionCommit: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 20)),
		},
		clickToFirstVisibleContentWindow: summarizeInteractionSamples(passingClickSamples),
		commitSha: '0123456789abcdef',
		demandQueueWait: {
			foreground: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 8)),
			visible: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 16)),
		},
		foregroundContentLoadTiming: {
			executorInFlight: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 24)),
			executorPendingWait: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 0),
			),
			resourceBodyRegistryCommit: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 1),
			),
			resourceFetchResponseWait: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 12),
			),
			resourceFirstChunkWait: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 4),
			),
			resourceStreamRead: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 18),
			),
		},
		fileClickSampleCount: 100,
		runMarker: 'bridgeviewer-worktree-vite-123',
		scrollToVisibleRows: summarizeInteractionSamples(passingScrollSamples),
		startupLoadTiming: {
			pageLoadToContentReady: summarizeInteractionSamples([55]),
			pageLoadToFirstVisibleContentWindow: summarizeInteractionSamples([70]),
			pageLoadToSelectedPath: summarizeInteractionSamples([24]),
		},
		treeScrollSettleFrameCount: summarizeInteractionSamples(
			Array.from({ length: 100 }, (): number => 2),
		),
		treeScrollSampleCount: 100,
		workerMode: 'on',
		wrongVisibleRowCount: 0,
	};
}

export function makePassingReviewInteractionPerformanceProof(): ReviewInteractionPerformanceProof {
	const passingReviewClickSamples = Array.from({ length: 100 }, (_, index): number =>
		index < 95 ? 30 : 70,
	);
	const passingReviewTreeScrollSamples = Array.from({ length: 100 }, (_, index): number =>
		index < 95 ? 12 : 18,
	);
	return {
		browserOrNativeRuntime: 'vite',
		codeViewBlankWindowCount: 0,
		codeViewHeightChangeCount: 0,
		codeViewItemCountAfter: 5,
		codeViewScrollSampleCount: 100,
		codeViewScrollToStableWindow: summarizeInteractionSamples(passingReviewTreeScrollSamples),
		commitSha: '0123456789abcdef',
		reviewClickReadinessBreakdown: {
			codeViewMaterializedAfterContentReady: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 2),
			),
			contentReadyAfterSelectedPath: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 10),
			),
			selectedDemandDuration: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 8),
			),
			selectedPathState: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 30)),
			treeSelectionVisible: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 4),
			),
			visibleContentRenderedAfterMaterialization: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 3),
			),
		},
		reviewClickPhaseDurations: {
			firstVisibleAfterReady: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 3),
			),
			readyAfterSelection: summarizeInteractionSamples(
				Array.from({ length: 100 }, (): number => 15),
			),
			selectionCommit: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 30)),
		},
		reviewClickFailureDetails: [],
		reviewClickSampleCount: 100,
		reviewClickToSelectedReady: summarizeInteractionSamples(passingReviewClickSamples),
		reviewDevContentResponseTiming: {
			getProvider: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 1)),
			providerLoad: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 2)),
			responseTotal: summarizeInteractionSamples(Array.from({ length: 100 }, (): number => 3)),
		},
		reviewStartupLoadTiming: {
			metadataApplyDuration: summarizeInteractionSamples([8]),
			pageLoadToMetadata: summarizeInteractionSamples([42]),
			pageLoadToReviewReady: summarizeInteractionSamples([80]),
			pageLoadToSelectedContentReady: summarizeInteractionSamples([65]),
			reviewReadyDuration: summarizeInteractionSamples([12]),
			selectedContentReadyDuration: summarizeInteractionSamples([10]),
		},
		reviewTreeBlankWindowCount: 0,
		reviewTreeScrollSettleFrameCount: summarizeInteractionSamples(
			Array.from({ length: 100 }, (): number => 2),
		),
		reviewTreeScrollSampleCount: 100,
		reviewTreeScrollToVisibleRows: summarizeInteractionSamples(passingReviewTreeScrollSamples),
		reviewTreeWrongVisibleRowCount: 0,
		codeViewScrollSettleFrameCount: summarizeInteractionSamples(
			Array.from({ length: 100 }, (): number => 2),
		),
		runMarker: 'bridgeviewer-review-vite-123',
		workerMode: 'on',
	};
}

export function makePassingReviewMetadataBeforeContentProof(): ReviewMetadataBeforeContentProof {
	return {
		blockedContentHitCount: 1,
		metadataHitCount: 1,
		selectedContentStateWhileBlocked: 'loading',
		selectedDisplayPathWhileBlocked: 'Sources/AgentStudio/AtomRegistry.swift',
		treeVisibleRowCountWhileBlocked: 12,
		treeVisibleWhileBlocked: true,
	};
}

export function makeReviewDemandTelemetryProof(
	props: Partial<ReviewDemandTelemetryProof>,
): ReviewDemandTelemetryProof {
	return {
		admittedBytes: 0,
		admittedBytesByLane: {
			foreground: 0,
			active: 0,
			visible: 0,
			nearby: 0,
			speculative: 0,
			idle: 0,
		},
		byteBudgetSource: 'review-content-demand',
		configuredExecutorMaxConcurrentLoads: 4,
		configuredExecutorMaxInFlightBytes: 1_000_000,
		configuredSchedulerMaxQueuedEstimatedBytes: 1_000_000,
		configuredSchedulerMaxQueuedIntentsPerLane: 8,
		deferredCount: 0,
		deferredEstimatedBytesByLane: {
			foreground: 0,
			active: 0,
			visible: 0,
			nearby: 0,
			speculative: 0,
			idle: 0,
		},
		droppedEstimatedBytesByLane: {
			foreground: 0,
			active: 0,
			visible: 0,
			nearby: 0,
			speculative: 0,
			idle: 0,
		},
		droppedIntentCount: 0,
		durationMilliseconds: 1,
		enqueueAcceptedCount: 1,
		enqueueRejectedCount: 0,
		executorInFlightCountAfterDispatch: 1,
		executorInFlightCountAfter: 0,
		executorInFlightCountBefore: 0,
		executorQueuedLoadCountAfter: 0,
		failedCount: 0,
		foregroundIntentCount: 0,
		interest: 'selected',
		itemId: 'item-source',
		packageId: 'package-1',
		packageReviewGeneration: 1,
		packageRevision: 1,
		currentPackageId: 'package-1',
		currentPackageReviewGeneration: 1,
		currentPackageRevision: 1,
		laneUpgradeCount: 0,
		loadedCount: 0,
		maxExecutorInFlightCount: 1,
		maxExecutorQueuedLoadCount: 0,
		maxSchedulerQueuedIntentCount: 1,
		schedulerQueuedIntentCountAfterEnqueue: 1,
		schedulerQueuedIntentCountAfter: 0,
		schedulerQueuedIntentCountBefore: 0,
		staleDropCount: 0,
		visibleIntentCount: 0,
		...props,
	};
}
