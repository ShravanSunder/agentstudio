import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import {
	buildReviewContentRoutePressureProof,
	buildReviewContentRouteDeltaProof,
	normalizeReviewTreeSearchQuery,
	reviewCollapseControlSatisfied,
	reviewContentRouteDeltaSatisfied,
	reviewRenderedSelectionSatisfied,
	reviewRoutePressureSatisfied,
	reviewRouteCollapseControlArtifactSatisfied,
	reviewSelectedDemandTelemetrySatisfied,
	reviewVisibleDemandTelemetryAttributed,
	selectVisibleReviewCollapseControlProof,
	worktreeFileVisibleDemandTelemetrySatisfied,
	worktreeFileOpenLoadTelemetrySatisfied,
} from './verify-bridge-viewer-worktree-review-proof.ts';
import type { ReviewDemandTelemetryProof } from './verify-bridge-viewer-worktree-review-proof.ts';

const verifierSourceUrl = new URL('./verify-bridge-viewer-worktree-dev-server.ts', import.meta.url);

describe('worktree dev-server verifier Review interaction contract', () => {
	test('uses visible Pierre tree search interaction for Review selection proof', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).not.toContain('__bridge_select_review_item');
		expect(verifierSource).not.toContain('document.dispatchEvent');
		expect(verifierSource).toContain('clickReviewTreeFilePathViaSearch');
		expect(verifierSource).toContain('[data-testid="bridge-review-trees-panel"]');
		expect(verifierSource).toContain('[data-file-tree-search-input]');
	});

	test('publishes visible CodeView collapse-control primitive proof in Review route artifacts', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).toContain('reviewCollapseControlProof');
		expect(verifierSource).toContain('readReviewCollapseControlProof');
		expect(verifierSource).toContain('reviewRouteCollapseControlArtifactSatisfied');
		expect(
			reviewRouteCollapseControlArtifactSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				routeProof: {
					reviewCollapseControlProof: {
						ariaExpanded: 'true',
						fontSize: '13px',
						height: 24,
						itemId: 'worktree-review-gitignore',
						present: true,
						primitiveSlot: 'button',
					},
				},
			}),
		).toBe(true);
		expect(
			reviewRouteCollapseControlArtifactSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				routeProof: {},
			}),
		).toBe(false);
	});

	test('publishes selected Review demand pressure telemetry in route artifacts', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).toContain('reviewSelectedDemandTelemetryProof');
		expect(verifierSource).toContain('configured-executor-max-concurrent-loads');
		expect(verifierSource).toContain('admitted-bytes-by-lane');
		expect(verifierSource).toContain('dropped-estimated-bytes-by-lane');
		expect(verifierSource).toContain('lane-upgrade-count');
		expect(verifierSource).toContain('stale-drop-count');
		expect(verifierSource).toContain('max-executor-in-flight');
		expect(verifierSource).toContain('reviewSelectedDemandTelemetrySatisfied');
		expect(
			reviewSelectedDemandTelemetrySatisfied({
				admittedBytes: 40,
				admittedBytesByLane: { foreground: 40 },
				byteBudgetSource: 'review-content-demand',
				configuredExecutorMaxConcurrentLoads: 4,
				configuredExecutorMaxInFlightBytes: 1_000,
				configuredSchedulerMaxQueuedEstimatedBytes: 1_000,
				configuredSchedulerMaxQueuedIntentsPerLane: 8,
				deferredCount: 0,
				deferredEstimatedBytesByLane: { foreground: 0 },
				droppedEstimatedBytesByLane: { foreground: 0 },
				droppedIntentCount: 0,
				enqueueAcceptedCount: 2,
				enqueueRejectedCount: 0,
				executorInFlightCountAfterDispatch: 2,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedLoadCountAfter: 0,
				failedCount: 0,
				foregroundIntentCount: 2,
				interest: 'selected',
				laneUpgradeCount: 0,
				loadedCount: 2,
				maxExecutorInFlightCount: 2,
				maxExecutorQueuedLoadCount: 0,
				maxSchedulerQueuedIntentCount: 2,
				schedulerQueuedIntentCountAfterEnqueue: 2,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
				staleDropCount: 0,
				visibleIntentCount: 0,
			}),
		).toBe(true);
		expect(
			reviewSelectedDemandTelemetrySatisfied({
				admittedBytes: 40,
				admittedBytesByLane: { foreground: 40 },
				byteBudgetSource: 'review-content-demand',
				configuredExecutorMaxConcurrentLoads: 4,
				configuredExecutorMaxInFlightBytes: 1_000,
				configuredSchedulerMaxQueuedEstimatedBytes: 1_000,
				configuredSchedulerMaxQueuedIntentsPerLane: 8,
				deferredCount: 0,
				deferredEstimatedBytesByLane: { foreground: 0 },
				droppedEstimatedBytesByLane: { foreground: 0 },
				droppedIntentCount: 0,
				enqueueAcceptedCount: 2,
				enqueueRejectedCount: 0,
				executorInFlightCountAfterDispatch: 2,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedLoadCountAfter: 0,
				failedCount: 0,
				foregroundIntentCount: 2,
				interest: 'visible',
				laneUpgradeCount: 0,
				loadedCount: 2,
				maxExecutorInFlightCount: 2,
				maxExecutorQueuedLoadCount: 0,
				maxSchedulerQueuedIntentCount: 2,
				schedulerQueuedIntentCountAfterEnqueue: 2,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
				staleDropCount: 0,
				visibleIntentCount: 0,
			}),
		).toBe(false);
	});

	test('publishes attributed Review route-pressure proof instead of treating visible fanout as failure', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');
		const routePressureProof = buildReviewContentRoutePressureProof([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-base',
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-visible-base',
		]);
		const selectedTelemetry = makeReviewDemandTelemetryProof({
			admittedBytes: 40,
			admittedBytesByLane: { foreground: 40, visible: 0 },
			foregroundIntentCount: 2,
			interest: 'selected',
			loadedCount: 2,
			maxExecutorInFlightCount: 2,
			maxSchedulerQueuedIntentCount: 2,
			schedulerQueuedIntentCountAfterEnqueue: 2,
			visibleIntentCount: 0,
		});
		const visibleTelemetry = makeReviewDemandTelemetryProof({
			deferredCount: 1,
			deferredEstimatedBytesByLane: { foreground: 0, visible: 12_000 },
			executorInFlightCountAfterDispatch: 2,
			foregroundIntentCount: 0,
			interest: 'visible',
			maxExecutorInFlightCount: 2,
			schedulerQueuedIntentCountAfterEnqueue: 1,
			visibleIntentCount: 1,
		});

		expect(verifierSource).toContain('reviewRoutePressureProof');
		expect(verifierSource).toContain('buildReviewContentRoutePressureProof');
		expect(verifierSource).toContain('reviewRoutePressureSatisfied');
		expect(routePressureProof).toEqual({
			duplicateRouteCount: 0,
			duplicatedRouteUrls: [],
			routeHitCount: 3,
			uniqueRouteHitCount: 3,
		});
		expect(reviewVisibleDemandTelemetryAttributed(visibleTelemetry)).toBe(true);
		expect(
			reviewRoutePressureSatisfied({
				routePressureProof,
				selectedDemandTelemetryProof: selectedTelemetry,
				visibleDemandTelemetryProof: visibleTelemetry,
			}),
		).toBe(true);
	});

	test('rejects duplicate Review route-pressure hits for the same exact content URL', () => {
		const duplicatedUrl =
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head';
		const routePressureProof = buildReviewContentRoutePressureProof([duplicatedUrl, duplicatedUrl]);

		expect(routePressureProof).toEqual({
			duplicateRouteCount: 1,
			duplicatedRouteUrls: [duplicatedUrl],
			routeHitCount: 2,
			uniqueRouteHitCount: 1,
		});
		expect(
			reviewRoutePressureSatisfied({
				routePressureProof,
				selectedDemandTelemetryProof: makeReviewDemandTelemetryProof({
					admittedBytes: 40,
					admittedBytesByLane: { foreground: 40 },
					foregroundIntentCount: 1,
					interest: 'selected',
					loadedCount: 1,
					maxExecutorInFlightCount: 1,
					maxSchedulerQueuedIntentCount: 1,
					schedulerQueuedIntentCountAfterEnqueue: 1,
					visibleIntentCount: 0,
				}),
				visibleDemandTelemetryProof: makeReviewDemandTelemetryProof({
					deferredEstimatedBytesByLane: { visible: 1 },
					foregroundIntentCount: 0,
					interest: 'visible',
					visibleIntentCount: 1,
				}),
			}),
		).toBe(false);
	});

	test('uses post-handoff Review content route delta proof instead of total route hits', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).toContain('reviewHandoffContentRouteProof');
		expect(verifierSource).toContain('reviewContentHitCountBeforeHandoffClick');
		expect(verifierSource).toContain('reviewContentRouteDeltaSatisfied');
		expect(verifierSource).not.toContain(
			"handoffProof.fileViewerOpenLoadTelemetry.disposition !== 'cold-loaded'",
		);
	});

	test('accepts warmed file-open telemetry when queue and executor are drained', () => {
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'cache-hit',
				durationMilliseconds: 0.4,
				estimatedBytes: 640,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 0,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(true);
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'cache-hit',
				durationMilliseconds: 0.4,
				estimatedBytes: 640,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 0,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'visible',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(false);
	});

	test('accepts foreground file-open telemetry while existing lower-priority work is in flight', () => {
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'cold-loaded',
				durationMilliseconds: 29.6,
				estimatedBytes: 24_905,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 26_199,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 2,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(true);
	});

	test('publishes FileViewer visible preload telemetry as a first-class dev-server proof row', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).toContain('fileViewerVisibleDemandTelemetry');
		expect(verifierSource).toContain('worktreeFileVisibleDemandTelemetrySatisfied');
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				failedCount: 0,
				failedCountByLane: { visible: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDisposition: 'visible-preloaded',
				firstLane: 'visible',
				intentCount: 2,
				loadedCount: 2,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				failedCount: 48,
				failedCountByLane: { visible: 48 },
				failedCountByReason: { byte_budget_exceeded: 48 },
				firstDisposition: 'visible-preloaded',
				firstLane: 'visible',
				intentCount: 50,
				loadedCount: 2,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				failedCount: 48,
				failedCountByLane: null,
				failedCountByReason: null,
				firstDisposition: 'visible-preloaded',
				firstLane: 'visible',
				intentCount: 50,
				loadedCount: 2,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(false);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				failedCount: 0,
				failedCountByLane: { foreground: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDisposition: 'cold-loaded',
				firstLane: 'foreground',
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(false);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				failedCount: 0,
				failedCountByLane: { visible: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDisposition: 'visible-preloaded',
				firstLane: 'visible',
				intentCount: 0,
				loadedCount: 0,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'idle',
				stimulusCount: 0,
			}),
		).toBe(false);
	});

	test('publishes FileViewer click-to-ready load telemetry as a first-class dev-server proof row', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).toContain('fileViewerClickToReadyTelemetry');
		expect(verifierSource).toContain('worktreeFileOpenLoadTelemetrySatisfied');
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'visible-preloaded',
				durationMilliseconds: 0,
				estimatedBytes: 1024,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 0,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(true);
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'cold-loaded',
				durationMilliseconds: 4,
				estimatedBytes: 1024,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 1024,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 1,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(true);
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'visible-preloaded',
				durationMilliseconds: 0,
				estimatedBytes: 1024,
				executorInFlightBytesAfter: 0,
				executorInFlightBytesBefore: 0,
				executorInFlightCountAfter: 0,
				executorInFlightCountBefore: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'visible',
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(false);
	});

	test('does not assume the first Worktree/File content route belongs to the selected file', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).not.toContain('const selectedHitUrl = hitUrls[0];');
		expect(verifierSource).toContain('hitUrls.find');
		expect(verifierSource).toContain('selectedResourceUrlUsesDevServerFrontDoor');
	});

	test('normalizes Review tree search query while preserving clicked row path proof', () => {
		expect(normalizeReviewTreeSearchQuery('Sources/AgentStudio/AtomRegistry.swift')).toBe(
			'sources/agentstudio/atomregistry.swift',
		);
	});

	test('does not count pre-click Review content routes as click proof', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-other-head',
			],
			beforeHitCount: 2,
			expectedItemId: 'worktree-review-missing-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(false);
		expect(proof.matchingPreClickHitUrls).toEqual([]);
		expect(proof.matchingPostClickHitUrls).toEqual([]);
	});

	test('accepts pre-click selected content route only as rendered-selection evidence', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-other-head',
			],
			beforeHitCount: 2,
			expectedItemId: 'worktree-review-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(true);
		expect(proof.contentRouteSatisfiedBy).toBe('matching-pre-click-route-with-rendered-selection');
		expect(proof.matchingPreClickHitUrls).toEqual([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
		]);
		expect(proof.matchingPostClickHitUrls).toEqual([]);
	});

	test('requires a post-click Review content route for the clicked item', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-other-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-base',
			],
			beforeHitCount: 2,
			expectedItemId: 'worktree-review-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(true);
		expect(proof.contentRouteSatisfiedBy).toBe('matching-post-click-route');
		expect(proof.matchingPostClickHitUrls).toEqual([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-base',
		]);
	});

	test('requires clicked item materialization in the visible Review CodeView canvas', () => {
		expect(
			reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: 'worktree-review-gitignore',
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: '# Xcode',
				},
				snapshot: {
					codeViewOverflow: 'wrap',
					selectedHeaderPresent: true,
					selectedItemId: 'worktree-review-gitignore',
					selectedMaterializedFileLineCount: 0,
					selectedMaterializedItemType: 'diff',
					visibleText: '# Xcode\n*.xcodeproj\n',
				},
			}),
		).toBe(true);
		expect(
			reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: 'worktree-review-gitignore',
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: '# Xcode',
				},
				snapshot: {
					codeViewOverflow: 'wrap',
					selectedHeaderPresent: false,
					selectedItemId: 'worktree-review-gitignore',
					selectedMaterializedFileLineCount: 0,
					selectedMaterializedItemType: 'diff',
					visibleText: 'name: CI / Test',
				},
			}),
		).toBe(false);
		expect(
			reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: 'worktree-review-gitignore',
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: '# Xcode',
				},
				snapshot: {
					codeViewOverflow: 'scroll',
					selectedHeaderPresent: true,
					selectedItemId: 'worktree-review-gitignore',
					selectedMaterializedFileLineCount: 0,
					selectedMaterializedItemType: 'diff',
					visibleText: '# Xcode\n*.xcodeproj\n',
				},
			}),
		).toBe(false);
	});

	test('requires the visible Review CodeView collapse control to use compact Button primitive chrome', () => {
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof: {
					ariaExpanded: 'true',
					fontSize: '11px',
					height: 24,
					itemId: 'worktree-review-gitignore',
					present: true,
					primitiveSlot: 'button',
				},
			}),
		).toBe(true);
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof: {
					ariaExpanded: 'true',
					fontSize: '11px',
					height: 24,
					itemId: 'worktree-review-gitignore',
					present: true,
					primitiveSlot: null,
				},
			}),
		).toBe(false);
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof: {
					ariaExpanded: 'true',
					fontSize: '11px',
					height: 28,
					itemId: 'worktree-review-gitignore',
					present: true,
					primitiveSlot: 'button',
				},
			}),
		).toBe(false);
	});

	test('selects visible Review CodeView collapse-control proof over hidden stale matches', () => {
		const proof = selectVisibleReviewCollapseControlProof({
			expectedItemId: 'worktree-review-gitignore',
			candidates: [
				{
					visible: false,
					proof: {
						ariaExpanded: 'true',
						fontSize: '13px',
						height: 24,
						itemId: 'worktree-review-gitignore',
						present: true,
						primitiveSlot: 'button',
					},
				},
				{
					visible: true,
					proof: {
						ariaExpanded: 'true',
						fontSize: '13px',
						height: 28,
						itemId: 'worktree-review-gitignore',
						present: true,
						primitiveSlot: 'button',
					},
				},
			],
		});

		expect(proof.height).toBe(28);
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof,
			}),
		).toBe(false);
		expect(
			selectVisibleReviewCollapseControlProof({
				expectedItemId: 'worktree-review-gitignore',
				candidates: [
					{
						visible: false,
						proof: {
							ariaExpanded: 'true',
							fontSize: '13px',
							height: 24,
							itemId: 'worktree-review-gitignore',
							present: true,
							primitiveSlot: 'button',
						},
					},
				],
			}),
		).toEqual({
			ariaExpanded: null,
			fontSize: null,
			height: 0,
			itemId: null,
			present: false,
			primitiveSlot: null,
		});
	});
});

function makeReviewDemandTelemetryProof(
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
		enqueueAcceptedCount: 1,
		enqueueRejectedCount: 0,
		executorInFlightCountAfterDispatch: 1,
		executorInFlightCountAfter: 0,
		executorInFlightCountBefore: 0,
		executorQueuedLoadCountAfter: 0,
		failedCount: 0,
		foregroundIntentCount: 0,
		interest: 'selected',
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
