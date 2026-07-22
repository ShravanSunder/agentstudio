import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerFileViewContentMetadata } from './bridge-worker-contracts.js';

describe('Bridge comm worker File source mutation', () => {
	test('deletes stale availability for one affected non-visible item without touching peers', () => {
		const store = createBridgeCommWorkerStore({
			surface: 'file',
			contentItems: [makeContentMetadata('file-1'), makeContentMetadata('file-2')],
			rows: [
				{ id: 'file-1', index: 0, parentId: null },
				{ id: 'file-2', index: 1, parentId: null },
			],
		});
		store.actions.applyContentTerminalAvailability({
			itemId: 'file-1',
			reason: 'load_failed',
			sourceEpoch: 1,
			state: 'failed',
		});
		store.actions.applyContentTerminalAvailability({
			itemId: 'file-2',
			reason: 'load_failed',
			sourceEpoch: 1,
			state: 'failed',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 1, sequence: 1 });

		const result = store.actions.applyFileViewSourceMutationFact({
			epoch: 2,
			mutation: {
				contentRemovals: ['file-1'],
				contentRequestRemovals: ['file-1'],
				contentRequestUpserts: [],
				contentUpserts: [],
				filePathRemovals: [],
				filePathUpserts: [],
				kind: 'delta',
				rowRemovals: [],
				rowUpserts: [],
			},
			selectedContentRequestChanged: false,
		});
		const patch = store.actions.takePendingSlicePatchEvent({ epoch: 2, sequence: 2 });

		expect(store.getState().availabilityByItemId.has('file-1')).toBe(false);
		expect(store.getState().availabilityByItemId.get('file-2')).toBe('failed');
		expect(result.touchedKeys).toContain('availability:file-1');
		expect(patch?.patches).toEqual([
			{ itemId: 'file-1', operation: 'delete', slice: 'contentAvailability' },
		]);
	});
});

function makeContentMetadata(itemId: string): BridgeWorkerFileViewContentMetadata {
	return {
		cacheKey: `cache-${itemId}`,
		canFetchContent: true,
		contentHash: 'a'.repeat(64),
		descriptorId: `descriptor-${itemId}`,
		encoding: 'utf-8',
		endsMidLine: false,
		endsWithNewline: true,
		isBinary: false,
		itemId,
		language: 'swift',
		metadataKind: 'fileView',
		path: `Sources/${itemId}.swift`,
		payloadByteCount: 16,
		payloadLineCount: 1,
		sizeBytes: 16,
		totalLineCount: 1,
		truncationKind: 'none',
		virtualizedExtentKind: 'exactLineCount',
	};
}
