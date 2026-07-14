import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerFileViewContentMetadata } from './bridge-worker-contracts.js';

interface ScheduledSelectedReviewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

interface ScheduledSelectedFileViewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

describe('Bridge comm worker command handler File source reconciliation', () => {
	test('file view source update labels source-reset terminal availability before health ack', () => {
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			createSequence: createSequenceFrom([71, 72, 73, 74]),
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
		});
		handler.applyFileViewRuntimeSource({
			epoch: 6,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-file-before-terminal-reset',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		const selectedStore = scheduledFileViewPreparations[0]?.store;
		if (selectedStore === undefined) {
			throw new Error('Expected selected File View preparation store.');
		}
		selectedStore.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		selectedStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 81 });

		const messages = handler.applyFileViewRuntimeSource({
			epoch: 8,
			source: {
				contentItems: [
					{
						...makeWorkerFileViewContentMetadata('file-1'),
						canFetchContent: false,
						isBinary: true,
					},
				],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 8,
				sequence: 73,
				patches: [
					{ slice: 'rowPaint', operation: 'delete', itemId: 'file-1' },
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { reason: 'source_reset', state: 'unavailable' },
					},
				],
			},
		]);
		expect(scheduledFileViewPreparations).toHaveLength(1);
	});

	test('file view source update does not schedule selected preparation when ready paint remains current', () => {
		const scheduledReviewPreparations: ScheduledSelectedReviewPreparation[] = [];
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			createSequence: createSequenceFrom([81, 82, 83]),
			scheduleSelectedReviewContentReadyPreparation: pushScheduledSelectedReviewPreparation(
				scheduledReviewPreparations,
			),
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
		});
		handler.applyFileViewRuntimeSource({
			epoch: 6,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-file-before-ready',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
				surface: 'fileView',
			}),
		);
		const selectedStore = scheduledFileViewPreparations[0]?.store;
		if (selectedStore === undefined) {
			throw new Error('Expected selected File View preparation store.');
		}
		selectedStore.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		selectedStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 81 });
		scheduledFileViewPreparations.splice(0, scheduledFileViewPreparations.length);

		const messages = handler.applyFileViewRuntimeSource({
			epoch: 7,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		expect(messages).toEqual([]);
		expect(scheduledReviewPreparations).toEqual([]);
		expect(scheduledFileViewPreparations).toEqual([]);
		expect(selectedStore.getState().availabilityByItemId.get('file-1')).toBe('ready');
	});
});

function pushScheduledSelectedReviewPreparation(
	target: ScheduledSelectedReviewPreparation[],
): (preparation: ScheduledSelectedReviewPreparation) => void {
	return (preparation: ScheduledSelectedReviewPreparation): void => {
		target.push(preparation);
	};
}

function ignoreScheduledSelectedReviewPreparation(
	_preparation: ScheduledSelectedReviewPreparation,
): void {}

function pushScheduledSelectedFileViewPreparation(
	target: ScheduledSelectedFileViewPreparation[],
): (preparation: ScheduledSelectedFileViewPreparation) => void {
	return (preparation: ScheduledSelectedFileViewPreparation): void => {
		target.push(preparation);
	};
}

function createSequenceFrom(sequences: readonly number[]): () => number {
	let index = 0;
	return (): number => {
		const sequence = sequences[index];
		if (sequence === undefined) {
			throw new Error('test sequence exhausted');
		}
		index += 1;
		return sequence;
	};
}

function makeWorkerFileViewContentMetadata(itemId: string): BridgeWorkerFileViewContentMetadata {
	return {
		metadataKind: 'fileView',
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `file-view:sha256:${itemId}`,
		sizeBytes: 128,
		descriptorId: `descriptor-${itemId}`,
		contentHash: `sha256:${itemId}`,
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		virtualizedExtentKind: 'exactLineCount',
		payloadByteCount: 128,
		payloadLineCount: 7,
		totalLineCount: 7,
		truncationKind: 'none',
		isBinary: false,
		canFetchContent: true,
	};
}
