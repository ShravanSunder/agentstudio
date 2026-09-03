import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerFileViewContentMetadata } from './bridge-worker-contracts.js';

describe('Bridge comm worker File terminal retention', () => {
	test('retains the last complete paint when a replacement becomes unavailable', () => {
		const store = createBridgeCommWorkerStore({
			surface: 'file',
			contentItems: [fileContentMetadata()],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		});
		store.actions.applySelectedFact({ itemId: 'file-1', epoch: 15 });
		store.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		store.actions.takePendingSlicePatchEvent({ epoch: 15, sequence: 1 });

		store.actions.applyContentTerminalAvailability({
			itemId: 'file-1',
			reason: 'descriptor_missing',
			sourceEpoch: 15,
			state: 'unavailable',
		});

		expect(store.getState().paintReadyByItemId.get('file-1')).toBe('file-view:sha256:file-1');
		expect(store.getState().byteCache.get('file-view:sha256:file-1')).toBe('file-1');
		expect(store.getState().availabilityByItemId.get('file-1')).toBe('unavailable');
		expect(store.actions.takePendingSlicePatchEvent({ epoch: 15, sequence: 2 })?.patches).toEqual([
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: 'file-1',
				payload: { reason: 'descriptor_missing', state: 'unavailable' },
			},
		]);
	});
});

function fileContentMetadata(): BridgeWorkerFileViewContentMetadata {
	return {
		metadataKind: 'fileView',
		itemId: 'file-1',
		path: 'Sources/App/file-1.swift',
		language: 'swift',
		cacheKey: 'file-view:sha256:file-1',
		sizeBytes: 128,
		descriptorId: 'descriptor-file-1',
		contentHash: 'sha256:file-1',
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
