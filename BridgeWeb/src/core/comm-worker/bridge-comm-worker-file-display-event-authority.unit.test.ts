import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerFileDisplayEventAuthority } from './bridge-comm-worker-file-display-event-authority.js';
import type { BridgeWorkerFileDisplayPatch } from './bridge-worker-contracts.js';

describe('Bridge comm worker File display event authority', () => {
	test('owns one monotonic revision sequence across metadata and query publications', () => {
		let sequence = 40;
		const authority = new BridgeCommWorkerFileDisplayEventAuthority({
			createSequence: (): number => ++sequence,
		});

		const metadataEvents = authority.publish({ epoch: 7, patches: [fileStatusPatch()] });
		const queryEvents = authority.publish({ epoch: 7, patches: [fileQueryPatch()] });
		const resetEvents = authority.publish({ epoch: 8, patches: [fileTreeResetPatch()] });

		expect(
			[...metadataEvents, ...queryEvents, ...resetEvents].map((event) => ({
				epoch: event.epoch,
				projectionRevision: event.projectionRevision,
				sequence: event.sequence,
			})),
		).toEqual([
			{ epoch: 7, projectionRevision: 1, sequence: 41 },
			{ epoch: 7, projectionRevision: 2, sequence: 42 },
			{ epoch: 8, projectionRevision: 3, sequence: 43 },
		]);
	});

	test('limits each 100k-query event to one bounded tree operation batch', () => {
		let sequence = 0;
		const authority = new BridgeCommWorkerFileDisplayEventAuthority({
			createSequence: (): number => ++sequence,
		});
		const patches = Array.from({ length: Math.ceil(100_000 / 256) }, (_batch, batchIndex) => ({
			operation: 'batch' as const,
			payload: {
				operations: Array.from(
					{ length: Math.min(256, 100_000 - batchIndex * 256) },
					(_operation, operationIndex) => ({
						operation: 'remove' as const,
						path: `Sources/File-${String(batchIndex * 256 + operationIndex)}.swift`,
						rowId: `row-${String(batchIndex * 256 + operationIndex)}`,
					}),
				),
			},
			slice: 'fileTree' as const,
		}));

		const events = authority.publishQueryTransaction({
			epoch: 5,
			patches,
			transactionId: 'query-100k',
		});

		expect(events).toHaveLength(patches.length);
		expect(
			Math.max(
				...events.map((event) =>
					event.patches.reduce(
						(count, patch) =>
							count +
							(patch.slice === 'fileTree' && patch.operation === 'batch'
								? patch.payload.operations.length
								: 0),
						0,
					),
				),
			),
		).toBeLessThanOrEqual(256);
		expect(events.map((event) => event.projectionRevision)).toEqual(
			Array.from({ length: events.length }, (_, index) => index + 1),
		);
		expect(
			events.map((event) =>
				event.queryTransaction?.phase === 'batch' ? event.queryTransaction.batchIndex : undefined,
			),
		).toEqual(Array.from({ length: events.length }, (_, index) => index));
	});

	test('publishes a strict empty abort event before replacement display patches', () => {
		let sequence = 0;
		const authority = new BridgeCommWorkerFileDisplayEventAuthority({
			createSequence: (): number => ++sequence,
		});
		authority.publishQueryTransaction({
			epoch: 5,
			patches: [fileQueryPatch()],
			transactionId: 'query-aborted',
		});

		const abort = authority.publishQueryAbort({ epoch: 5, transactionId: 'query-aborted' });
		const replacement = authority.publish({ epoch: 5, patches: [fileStatusPatch()] });

		expect(abort).toMatchObject({
			patches: [],
			projectionRevision: 2,
			queryTransaction: { phase: 'abort', transactionId: 'query-aborted' },
			sequence: 2,
		});
		expect(replacement[0]).toMatchObject({ projectionRevision: 3, sequence: 3 });
	});
});

function fileStatusPatch(): BridgeWorkerFileDisplayPatch {
	return { operation: 'upsert', payload: { state: 'stale' }, slice: 'fileStatus' };
}

function fileQueryPatch(): BridgeWorkerFileDisplayPatch {
	return {
		operation: 'upsert',
		payload: {
			filterMode: 'all',
			projectedRowCount: 0,
			searchError: null,
			searchMode: 'text',
			searchText: '',
			totalRowCount: 0,
		},
		slice: 'fileQuery',
	};
}

function fileTreeResetPatch(): BridgeWorkerFileDisplayPatch {
	return {
		operation: 'reset',
		payload: { sourceGeneration: 2, sourceId: 'source-2' },
		slice: 'fileTree',
	};
}
