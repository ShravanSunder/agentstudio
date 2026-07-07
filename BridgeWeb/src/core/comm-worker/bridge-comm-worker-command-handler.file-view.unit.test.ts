import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
} from './bridge-worker-contracts.js';

interface ScheduledSelectedFileViewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

describe('Bridge comm worker command handler File View selected refresh', () => {
	test('schedules selected File View preparation when ready paint survives a metadata refresh', () => {
		const scenario = createReadySelectedFileViewScenario();

		const messages = scenario.handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-metadata-refresh',
				epoch: 7,
				contentItems: [
					makeWorkerFileViewContentMetadata({
						lineCount: 8,
					}),
				],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor({ generation: 6 })],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source-metadata-refresh',
				status: 'ready',
			},
		]);
		expect(scenario.scheduledFileViewPreparations).toHaveLength(1);
		expect(scenario.scheduledFileViewPreparations[0]?.epoch).toBe(7);
		expect(scenario.scheduledFileViewPreparations[0]?.itemId).toBe('file-1');
		expect(scenario.readyStore.getState().availabilityByItemId.get('file-1')).toBe('ready');
	});

	test('schedules selected File View preparation when ready paint survives a descriptor refresh', () => {
		const scenario = createReadySelectedFileViewScenario();

		const messages = scenario.handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-descriptor-refresh',
				epoch: 8,
				contentItems: [makeWorkerFileViewContentMetadata()],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor({ generation: 8 })],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source-descriptor-refresh',
				status: 'ready',
			},
		]);
		expect(scenario.scheduledFileViewPreparations).toHaveLength(1);
		expect(scenario.scheduledFileViewPreparations[0]?.epoch).toBe(8);
		expect(scenario.scheduledFileViewPreparations[0]?.itemId).toBe('file-1');
		expect(
			scenario.scheduledFileViewPreparations[0]?.store.getState().demandByKey.get('file-1'),
		).toBe('selected:8');
		expect(scenario.readyStore.getState().availabilityByItemId.get('file-1')).toBe('ready');
	});
});

function createReadySelectedFileViewScenario(): {
	readonly handler: ReturnType<typeof createBridgeCommWorkerCommandHandler>;
	readonly readyStore: BridgeCommWorkerStore;
	readonly scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[];
} {
	const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
	const handler = createBridgeCommWorkerCommandHandler({
		contentItems: [],
		rows: [],
		createSequence: createSequenceFrom([101, 102, 103, 104]),
		scheduleSelectedReviewContentReadyPreparation: (): void => {},
		scheduleSelectedFileViewContentReadyPreparation: (
			preparation: ScheduledSelectedFileViewPreparation,
		): void => {
			scheduledFileViewPreparations.push(preparation);
		},
	});
	handler.handleMessage(
		encodeBridgeWorkerFileViewSourceUpdateCommand({
			requestId: 'request-file-source-before-ready',
			epoch: 6,
			contentItems: [makeWorkerFileViewContentMetadata()],
			contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor({ generation: 6 })],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
		}),
	);
	handler.handleMessage(
		encodeBridgeWorkerSelectCommand({
			requestId: 'request-select-file-before-ready',
			epoch: 7,
			selectedItemId: 'file-1',
			selectedSource: 'user',
		}),
	);
	const readyStore = assertReadyStore(scheduledFileViewPreparations[0]?.store);
	readyStore.actions.applyContentReady({
		itemId: 'file-1',
		contentCacheKey: 'file-view:sha256:file-1',
	});
	readyStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 201 });
	scheduledFileViewPreparations.splice(0, scheduledFileViewPreparations.length);
	return { handler, readyStore, scheduledFileViewPreparations };
}

function assertReadyStore(store: BridgeCommWorkerStore | undefined): BridgeCommWorkerStore {
	if (store === undefined) {
		throw new Error('Expected selected File View preparation store.');
	}
	return store;
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

function makeWorkerFileViewContentMetadata(
	props: { readonly lineCount?: number; readonly path?: string } = {},
): BridgeWorkerFileViewContentMetadata {
	return {
		itemId: 'file-1',
		path: props.path ?? 'Sources/App/file-1.swift',
		language: 'swift',
		cacheKey: 'file-view:sha256:file-1',
		sizeBytes: 128,
		contentHandle: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		contentHash: 'sha256:file-1',
		virtualizedExtentKind: 'exactLineCount',
		lineCount: props.lineCount ?? 7,
		isBinary: false,
		canFetchContent: true,
	};
}

function makeWorkerFileViewContentRequestDescriptor(props: {
	readonly generation: number;
	readonly path?: string;
}): BridgeWorkerFileViewContentRequestDescriptor {
	return {
		itemId: 'file-1',
		path: props.path ?? 'Sources/App/file-1.swift',
		handleId: 'handle-file-1',
		descriptorId: 'descriptor-file-1',
		resourceKind: 'worktree.fileContent',
		resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-file-1&generation=${props.generation}`,
		contentHash: 'sha256:file-1',
		contentHashAlgorithm: 'sha256',
		language: 'swift',
		sizeBytes: 128,
		maxBytes: 4096,
		isBinary: false,
	};
}
