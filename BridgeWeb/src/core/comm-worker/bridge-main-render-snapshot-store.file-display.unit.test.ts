import { describe, expect, test } from 'vitest';

import { createBridgeMainRenderSnapshotStore } from './bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerFileDisplayPatchEvent,
} from './bridge-worker-contracts.js';

describe('Bridge main render snapshot store File display', () => {
	test('atomically applies a strict File display event without product authority fields', () => {
		const store = createBridgeMainRenderSnapshotStore();
		let publishCount = 0;
		const unsubscribe = store.subscribe(() => {
			publishCount += 1;
		});

		store.applyFileDisplayPatchEvent(makeFileDisplayPatchEvent());

		expect(publishCount).toBe(1);
		const snapshot = store.getSnapshot();
		expect(snapshot).toMatchObject({
			fileDisplayFreshness: {
				epoch: 4,
				projectionRevision: 8,
				sequence: 12,
			},
			fileStatusSlice: {
				ahead: 1,
				behind: 0,
				branchName: 'main',
				staged: 2,
				state: 'ready',
				unstaged: 3,
				untracked: 4,
			},
			fileTreeSlice: {
				sourceGeneration: 6,
				sourceId: 'file-source-1',
			},
		});
		expect(snapshot.fileItemById.size).toBe(1);
		expect(snapshot.fileItemById.get('file-1')).toMatchObject({
			displayPath: 'Sources/File.swift',
			payloadByteCount: 100_000,
			payloadLineCount: 10_000,
			truncationKind: 'lineLimit',
		});
		expect(snapshot.fileTreeSlice.index.size).toBe(1);
		expect(snapshot.fileTreeSlice.index.rowForId('row-file-1')).toMatchObject({
			path: 'Sources/File.swift',
			projectionIndex: 3,
		});
		expect(JSON.stringify(snapshot)).not.toMatch(
			/contentDescriptor|descriptorId|expectedSha256|leaseId|sourceCursor|byteCache|demandMembership|retryAfterVersion/i,
		);

		unsubscribe();
	});

	test('rejects stale File display events and clears old display copies on epoch advance', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const acceptedEvent = makeFileDisplayPatchEvent();
		store.applyFileDisplayPatchEvent(acceptedEvent);
		const acceptedSnapshot = store.getSnapshot();

		for (const staleEvent of [
			{ ...acceptedEvent, epoch: 3, sequence: 99, projectionRevision: 99 },
			{ ...acceptedEvent, sequence: acceptedEvent.sequence },
			{ ...acceptedEvent, sequence: 13, projectionRevision: acceptedEvent.projectionRevision },
		]) {
			store.applyFileDisplayPatchEvent(staleEvent);
			expect(store.getSnapshot()).toBe(acceptedSnapshot);
		}

		store.applyFileDisplayPatchEvent({
			...acceptedEvent,
			epoch: 5,
			sequence: 1,
			projectionRevision: 9,
			patches: [
				{
					slice: 'fileStatus',
					operation: 'upsert',
					payload: { state: 'stale' },
				},
			],
		});

		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot).toMatchObject({
			fileDisplayFreshness: { epoch: 5, projectionRevision: 9, sequence: 1 },
			fileStatusSlice: { state: 'stale' },
			fileTreeSlice: {
				sourceGeneration: null,
				sourceId: null,
			},
		});
		expect(nextSnapshot.fileItemById.size).toBe(0);
		expect(nextSnapshot.fileTreeSlice.index.size).toBe(0);
	});

	test('applies File tree removals and File item/status reset variants', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const initialEvent = makeFileDisplayPatchEvent();
		store.applyFileDisplayPatchEvent(initialEvent);

		store.applyFileDisplayPatchEvent({
			...initialEvent,
			sequence: 13,
			projectionRevision: 9,
			patches: [
				{
					slice: 'fileTree',
					operation: 'batch',
					payload: {
						operations: [
							{
								operation: 'remove',
								path: 'Sources/File.swift',
								rowId: 'row-file-1',
							},
						],
					},
				},
				{ slice: 'fileItem', operation: 'delete', itemId: 'file-1' },
				{ slice: 'fileStatus', operation: 'reset' },
			],
		});

		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot.fileItemById.size).toBe(0);
		expect(nextSnapshot.fileStatusSlice).toBeNull();
		expect(nextSnapshot.fileTreeSlice.index.size).toBe(0);
	});

	test('clears File source identity and display copies on a failure epoch', () => {
		const store = createBridgeMainRenderSnapshotStore();
		store.applyFileDisplayPatchEvent(makeFileDisplayPatchEvent());

		store.applyFileDisplayPatchEvent({
			direction: 'serverWorkerToMain',
			epoch: 5,
			kind: 'fileDisplayPatch',
			patches: [
				{ operation: 'clear', slice: 'fileTree' },
				{ operation: 'reset', slice: 'fileItem' },
				{ operation: 'reset', slice: 'fileStatus' },
			],
			projectionRevision: 1,
			sequence: 13,
			surface: 'fileView',
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		});

		const nextSnapshot = store.getSnapshot();
		expect(nextSnapshot).toMatchObject({
			fileDisplayFreshness: { epoch: 5, projectionRevision: 1, sequence: 13 },
			fileStatusSlice: null,
			fileTreeSlice: { sourceGeneration: null, sourceId: null },
		});
		expect(nextSnapshot.fileItemById.size).toBe(0);
		expect(nextSnapshot.fileTreeSlice.index.size).toBe(0);
	});
});

function makeFileDisplayPatchEvent(): BridgeWorkerFileDisplayPatchEvent {
	return {
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'fileDisplayPatch',
		surface: 'fileView',
		epoch: 4,
		sequence: 12,
		projectionRevision: 8,
		patches: [
			{
				slice: 'fileTree',
				operation: 'reset',
				payload: { sourceGeneration: 6, sourceId: 'file-source-1' },
			},
			{
				slice: 'fileTree',
				operation: 'batch',
				payload: {
					operations: [
						{
							operation: 'upsert',
							row: {
								changeStatus: 'modified',
								depth: 1,
								fileId: 'file-1',
								fileClass: 'source',
								isDirectory: false,
								lineCount: 12_000,
								name: 'File.swift',
								parentPath: 'Sources',
								path: 'Sources/File.swift',
								projectionIndex: 3,
								rowId: 'row-file-1',
								sizeBytes: 120_000,
							},
						},
					],
				},
			},
			{
				slice: 'fileItem',
				operation: 'upsert',
				itemId: 'file-1',
				payload: {
					availability: { kind: 'available' },
					displayPath: 'Sources/File.swift',
					endsMidLine: false,
					endsWithNewline: true,
					extent: { kind: 'exactLineCount', lineCount: 12_000 },
					fileExtension: 'swift',
					language: 'swift',
					payloadByteCount: 100_000,
					payloadLineCount: 10_000,
					rowId: 'row-file-1',
					sizeBytes: 120_000,
					totalLineCount: 12_000,
					truncationKind: 'lineLimit',
				},
			},
			{
				slice: 'fileStatus',
				operation: 'upsert',
				payload: {
					state: 'ready',
					ahead: 1,
					behind: 0,
					branchName: 'main',
					staged: 2,
					unstaged: 3,
					untracked: 4,
				},
			},
		],
	};
}
