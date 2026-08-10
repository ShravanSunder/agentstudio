import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from './bridge-main-render-snapshot-store.js';
import { BRIDGE_WORKER_WIRE_VERSION } from './bridge-worker-contracts.js';

describe('Bridge main render snapshot store File query publication', () => {
	test('observes an accepted File query only after its snapshot publication', () => {
		// Arrange
		const publicationOrder: string[] = [];
		const store = createBridgeMainRenderSnapshotStore({
			onFileQueryTransactionPublished: (transactionId): void => {
				publicationOrder.push(`query:${transactionId}`);
			},
		});
		store.subscribe((): void => {
			publicationOrder.push('snapshot');
		});
		store.applyFileDisplayPatchEvent({
			direction: 'serverWorkerToMain',
			epoch: 1,
			kind: 'fileDisplayPatch',
			patches: [
				{
					operation: 'upsert',
					payload: {
						filterMode: 'source',
						projectedRowCount: 0,
						searchError: null,
						searchMode: 'text',
						searchText: 'missing',
						totalRowCount: 1,
					},
					slice: 'fileQuery',
				},
			],
			projectionRevision: 1,
			queryTransaction: {
				batchCount: 1,
				batchIndex: 0,
				phase: 'batch',
				transactionId: 'query-publication',
			},
			sequence: 1,
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		// Act / Assert
		expect(publicationOrder).toEqual([]);
		expect(store.completeFileQueryTransaction('query-publication')).toBe(true);
		expect(publicationOrder).toEqual(['snapshot', 'query:query-publication']);
		expect(store.getSnapshot().fileQuerySlice?.searchText).toBe('missing');
		expect(store.completeFileQueryTransaction('wrong-query')).toBe(false);
		expect(publicationOrder).toEqual(['snapshot', 'query:query-publication']);
	});
});
