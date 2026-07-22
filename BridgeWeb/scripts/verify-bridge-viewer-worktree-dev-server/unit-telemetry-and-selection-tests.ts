import { expect, test } from 'vitest';

import {
	buildReviewContentRouteDeltaProof,
	normalizeReviewTreeSearchQuery,
	reviewCollapseControlSatisfied,
	reviewContentRouteDeltaSatisfied,
	reviewRenderedSelectionSatisfied,
	selectVisibleReviewCollapseControlProof,
	worktreeFileOpenLoadTelemetrySatisfied,
	worktreeFileRecentlyUpdatedDemandTelemetrySatisfied,
	worktreeFileVisibleDemandTelemetrySatisfied,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import { readWorktreeDevServerVerifierSource } from './unit-test-source.ts';

export function registerWorktreeDevServerTelemetryAndSelectionTests(): void {
	test('publishes FileViewer visible preload telemetry as a first-class dev-server proof row', async () => {
		const verifierSource = await readWorktreeDevServerVerifierSource();

		expect(verifierSource).toContain('fileViewerVisibleDemandTelemetry');
		expect(verifierSource).toContain('worktreeFileVisibleDemandTelemetrySatisfied');
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				expectedVisibleFileCount: 2,
				failedCount: 0,
				failedCountByLane: { visible: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDisposition: 'visible-preloaded',
				firstDedupeKey: 'visible-dedupe',
				firstExecutorInFlightMilliseconds: 6,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey: 'visible-freshness',
				firstLane: 'visible',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 2,
				loadedCount: 2,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				expectedVisibleFileCount: 1,
				failedCount: 0,
				failedCountByLane: {},
				failedCountByReason: {},
				firstDisposition: 'cache-hit',
				firstDedupeKey: 'visible-dedupe',
				firstExecutorInFlightMilliseconds: 0,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey: 'visible-freshness',
				firstLane: 'visible',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				expectedVisibleFileCount: 50,
				failedCount: 48,
				failedCountByLane: { visible: 48 },
				failedCountByReason: { byte_budget_exceeded: 48 },
				firstDisposition: 'visible-preloaded',
				firstDedupeKey: 'visible-dedupe',
				firstExecutorInFlightMilliseconds: 6,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey: 'visible-freshness',
				firstLane: 'visible',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 50,
				loadedCount: 2,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(false);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				expectedVisibleFileCount: 50,
				failedCount: 48,
				failedCountByLane: null,
				failedCountByReason: null,
				firstDisposition: 'visible-preloaded',
				firstDedupeKey: 'visible-dedupe',
				firstExecutorInFlightMilliseconds: 6,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey: 'visible-freshness',
				firstLane: 'visible',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 50,
				loadedCount: 2,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(false);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				expectedVisibleFileCount: 1,
				failedCount: 0,
				failedCountByLane: { foreground: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDisposition: 'cold-loaded',
				firstDedupeKey: 'foreground-dedupe',
				firstExecutorInFlightMilliseconds: 4,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey: 'foreground-freshness',
				firstLane: 'foreground',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(false);
		expect(
			worktreeFileVisibleDemandTelemetrySatisfied({
				expectedVisibleFileCount: 0,
				failedCount: 0,
				failedCountByLane: { visible: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDisposition: 'visible-preloaded',
				firstDedupeKey: 'visible-dedupe',
				firstExecutorInFlightMilliseconds: 0,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey: 'visible-freshness',
				firstLane: 'visible',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 0,
				loadedCount: 0,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				status: 'idle',
				stimulusCount: 0,
			}),
		).toBe(false);
	});

	test('publishes FileViewer click-to-ready load telemetry as a first-class dev-server proof row', async () => {
		const verifierSource = await readWorktreeDevServerVerifierSource();

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
				executorInFlightMilliseconds: 0,
				executorPendingWaitMilliseconds: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				resourceBodyRegistryCommitMilliseconds: 0,
				resourceFetchResponseWaitMilliseconds: 1,
				resourceFirstChunkWaitMilliseconds: 1,
				resourceStreamReadMilliseconds: 1,
				schedulerQueueWaitMilliseconds: 0,
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
				executorInFlightMilliseconds: 4,
				executorPendingWaitMilliseconds: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				resourceBodyRegistryCommitMilliseconds: 0,
				resourceFetchResponseWaitMilliseconds: 1,
				resourceFirstChunkWaitMilliseconds: 1,
				resourceStreamReadMilliseconds: 1,
				schedulerQueueWaitMilliseconds: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(true);
		expect(
			worktreeFileOpenLoadTelemetrySatisfied({
				disposition: 'cold-loaded',
				durationMilliseconds: 44.3,
				estimatedBytes: 282_731,
				executorInFlightBytesAfter: 7_708,
				executorInFlightBytesBefore: 38_407,
				executorInFlightCountAfter: 1,
				executorInFlightCountBefore: 8,
				executorInFlightMilliseconds: 42.9,
				executorPendingWaitMilliseconds: 1.3,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'foreground',
				resourceBodyRegistryCommitMilliseconds: 0,
				resourceFetchResponseWaitMilliseconds: 34.9,
				resourceFirstChunkWaitMilliseconds: 0,
				resourceStreamReadMilliseconds: 8,
				schedulerQueueWaitMilliseconds: 0,
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
				executorInFlightMilliseconds: 0,
				executorPendingWaitMilliseconds: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedBytesBefore: 0,
				executorQueuedLoadCountAfter: 0,
				executorQueuedLoadCountBefore: 0,
				lane: 'visible',
				resourceBodyRegistryCommitMilliseconds: 0,
				resourceFetchResponseWaitMilliseconds: 1,
				resourceFirstChunkWaitMilliseconds: 1,
				resourceStreamReadMilliseconds: 1,
				schedulerQueueWaitMilliseconds: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedEstimatedBytesBefore: 0,
				schedulerQueuedIntentCountAfter: 0,
				schedulerQueuedIntentCountBefore: 0,
			}),
		).toBe(false);
	});

	test('publishes FileViewer recently-updated preload telemetry as a first-class dev-server proof row', async () => {
		const verifierSource = await readWorktreeDevServerVerifierSource();

		expect(verifierSource).toContain('fileViewerRecentlyUpdatedDemandTelemetry');
		expect(verifierSource).toContain('bridge-worktree-file-recently-updated');
		expect(
			worktreeFileRecentlyUpdatedDemandTelemetrySatisfied({
				expectedVisibleFileCount: null,
				failedCount: 0,
				failedCountByLane: { nearby: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDedupeKey: 'pane-1:worktree-file:worktree.fileContent:recently-updated-content',
				firstDisposition: 'nearby-preloaded',
				firstExecutorInFlightMilliseconds: 4,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey:
					'pane-1:worktree-file:dev-worktree-source:1:revision-none:cursor-none:recently-updated-content',
				firstLane: 'nearby',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: 'BridgeWeb/src/app/bridge-app.tsx',
				recentlyUpdatedOpenFilePathBefore: 'BridgeWeb/src/app/bridge-app.tsx',
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileRecentlyUpdatedDemandTelemetrySatisfied({
				expectedVisibleFileCount: null,
				failedCount: 0,
				failedCountByLane: { nearby: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDedupeKey:
					'pane-1:worktree-file:worktree.fileContent:already-visible-recently-updated-content',
				firstDisposition: 'visible-preloaded',
				firstExecutorInFlightMilliseconds: 0,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey:
					'pane-1:worktree-file:dev-worktree-source:1:revision-none:cursor-none:already-visible-recently-updated-content',
				firstLane: 'nearby',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: 'BridgeWeb/src/test-fixtures/canary.txt',
				recentlyUpdatedOpenFilePathBefore: 'BridgeWeb/src/test-fixtures/canary.txt',
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileRecentlyUpdatedDemandTelemetrySatisfied({
				expectedVisibleFileCount: null,
				failedCount: 0,
				failedCountByLane: { nearby: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDedupeKey: 'pane-1:worktree-file:worktree.fileContent:recently-updated-content',
				firstDisposition: 'nearby-preloaded',
				firstExecutorInFlightMilliseconds: 4,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey:
					'pane-1:worktree-file:dev-worktree-source:1:revision-none:cursor-none:recently-updated-content',
				firstLane: 'nearby',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: null,
				recentlyUpdatedOpenFilePathBefore: null,
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(true);
		expect(
			worktreeFileRecentlyUpdatedDemandTelemetrySatisfied({
				expectedVisibleFileCount: null,
				failedCount: 0,
				failedCountByLane: { visible: 0 },
				failedCountByReason: { byte_budget_exceeded: 0 },
				firstDedupeKey: 'pane-1:worktree-file:worktree.fileContent:visible-content',
				firstDisposition: 'visible-preloaded',
				firstExecutorInFlightMilliseconds: 4,
				firstExecutorPendingWaitMilliseconds: 0,
				firstFreshnessKey:
					'pane-1:worktree-file:dev-worktree-source:1:revision-none:cursor-none:visible-content',
				firstLane: 'visible',
				firstSchedulerQueueWaitMilliseconds: 0,
				intentCount: 1,
				loadedCount: 1,
				executorInFlightBytesAfter: 0,
				executorInFlightCountAfter: 0,
				executorQueuedBytesAfter: 0,
				executorQueuedLoadCountAfter: 0,
				schedulerQueuedEstimatedBytesAfter: 0,
				schedulerQueuedIntentCountAfter: 0,
				recentlyUpdatedOpenFilePathAfter: 'src/visible.ts',
				recentlyUpdatedOpenFilePathBefore: 'none',
				status: 'settled',
				stimulusCount: 1,
			}),
		).toBe(false);
	});

	test('does not assume the first Worktree/File content route belongs to the selected file', async () => {
		const verifierSource = await readWorktreeDevServerVerifierSource();

		expect(verifierSource).not.toContain('const selectedHitUrl = hitUrls[0];');
		expect(verifierSource).toContain('hits.find');
		expect(verifierSource).toContain('hit.descriptorId === props.expectedContentHandle');
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
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-other-head',
			],
			beforeHitCount: 2,
			expectedContentDescriptorIds: ['handle-missing-target'],
			expectedItemId: 'worktree-review-missing-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(false);
		expect(proof.matchingPreClickHitUrls).toEqual([]);
		expect(proof.matchingPostClickHitUrls).toEqual([]);
	});

	test('keeps pre-click selected content routes as diagnostics, not click proof', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-other-head',
			],
			beforeHitCount: 2,
			expectedContentDescriptorIds: ['handle-target-head'],
			expectedItemId: 'worktree-review-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(false);
		expect(proof.contentRouteSatisfiedBy).toBe('no-matching-post-click-route');
		expect(proof.matchingPreClickHitUrls).toEqual([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-target-head',
		]);
		expect(proof.matchingPostClickHitUrls).toEqual([]);
	});

	test('requires a post-click Review content route for the clicked item', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-other-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-target-base',
			],
			beforeHitCount: 2,
			expectedContentDescriptorIds: ['handle-target-head', 'handle-target-base'],
			expectedItemId: 'worktree-review-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(true);
		expect(proof.contentRouteSatisfiedBy).toBe('matching-post-click-route');
		expect(proof.matchingPostClickHitUrls).toEqual([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/handle-target-base',
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
					expectedItemId: 'worktree-review-selection-canary',
					expectedMaterializedItemType: 'file',
					expectedVisibleText: 'bridge_worktree_devserver_review_selection',
				},
				snapshot: {
					codeViewOverflow: 'wrap',
					selectedHeaderPresent: true,
					selectedItemId: 'worktree-review-selection-canary',
					selectedMaterializedFileLineCount: 6,
					selectedMaterializedItemType: 'file',
					visibleText:
						'// bridge_worktree_devserver_review_selection_123\nBridgeViewer worktree review selection canary.',
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
}
