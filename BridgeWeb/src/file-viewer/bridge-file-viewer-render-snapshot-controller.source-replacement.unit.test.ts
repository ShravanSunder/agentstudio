import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
} from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerCodeViewFileItem } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import {
	bridgeFileViewerOpenStateForSelection,
	type BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import {
	applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore as applyProductionBridgeWorkerMessagesToFileViewerRenderSnapshotStore,
	selectedBridgeFileViewerCodeViewItemForSnapshot,
} from './bridge-file-viewer-render-snapshot-controller.js';

const selectedItem: BridgeWorkerCodeViewFileItem = {
	id: 'file:file-1',
	type: 'file',
	file: {
		cacheKey: 'cache-file-1',
		contents: 'ready\n',
		name: 'README.md',
	},
	bridgeMetadata: {
		cacheKey: 'cache-file-1',
		contentRoles: ['file'],
		contentState: 'hydrated',
		displayPath: 'README.md',
		itemId: 'file-1',
		lineCount: 1,
	},
};

describe('Bridge File viewer source replacement render state', () => {
	test('retains only selected File Pierre while clearing availability at a source replacement reset', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 3, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
		});
		store.setLocalSelection({ selectedItemId: 'file-1', source: 'user' });
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });
		store.applySnapshotUpdate({
			workerPatches: [
				{
					itemId: 'file-1',
					operation: 'upsert',
					payload: { contentCacheKey: 'cache-file-1' },
					slice: 'rowPaint',
				},
				{
					itemId: 'file-1',
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					...fileDisplayEvent({ epoch: 4, projectionRevision: 2, sequence: 2 }),
					patches: [
						{
							operation: 'reset',
							payload: { sourceGeneration: 2, sourceId: 'source-2' },
							slice: 'fileTree',
						},
						{ operation: 'reset', slice: 'fileItem' },
						{ operation: 'reset', slice: 'fileStatus' },
						{
							operation: 'replacementCommit',
							payload: { sourceGeneration: 2, sourceId: 'source-2' },
							slice: 'fileTree',
						},
					],
				},
			],
			renderSnapshotStore: store,
			selection: { fileId: 'file-1', path: 'README.md' },
		});

		expect(store.getSnapshot().codeViewItemsById).toEqual({ 'file-1': selectedItem });
		expect(store.getSnapshot().contentAvailabilityById).toEqual({});
		expect(store.getSnapshot().rowPaintById).toEqual({});
		expect(store.getSnapshot().fileTreeSlice.sourceId).toBe('source-2');
	});

	test('keeps admitted selected File content ready when the same-source bootstrap commits', () => {
		const store = createBridgeMainRenderSnapshotStore();
		const selection = { fileId: 'file-1', path: 'README.md' } as const;
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 3, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
			selection,
		});
		store.setLocalSelection({ selectedItemId: selection.fileId, source: 'user' });
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: selection.fileId });
		store.applySnapshotUpdate({
			workerPatches: [
				{
					itemId: selection.fileId,
					operation: 'upsert',
					payload: { contentCacheKey: 'cache-file-1' },
					slice: 'rowPaint',
				},
				{
					itemId: selection.fileId,
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					...fileDisplayEvent({ epoch: 3, projectionRevision: 2, sequence: 2 }),
					patches: [
						{
							operation: 'replacementCommit',
							payload: { sourceGeneration: 1, sourceId: 'source-1' },
							slice: 'fileTree',
						},
					],
				},
			],
			renderSnapshotStore: store,
			selection,
		});

		const snapshot = store.getSnapshot();
		const displayItem = snapshot.fileItemById.get(selection.fileId);
		expect(snapshot.codeViewItemsById).toEqual({ 'file-1': selectedItem });
		expect(snapshot.contentAvailabilityById[selection.fileId]).toEqual({ state: 'ready' });
		expect(snapshot.rowPaintById[selection.fileId]).toEqual({
			contentCacheKey: 'cache-file-1',
		});
		expect(
			bridgeFileViewerOpenStateForSelection({
				contentAvailability: snapshot.contentAvailabilityById[selection.fileId] ?? null,
				displayItem:
					displayItem === undefined
						? null
						: { ...displayItem, fileId: selection.fileId, path: selection.path },
				hasPierreItem: snapshot.codeViewItemsById[selection.fileId] !== undefined,
				selection,
				status: snapshot.fileStatusSlice,
			}),
		).toMatchObject({ status: 'ready' });
	});

	test('preserves only the exact selected CodeView item across a same-file source replacement', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
			selection: { fileId: 'file-1', path: 'README.md' },
		});
		const unselectedItem = {
			...selectedItem,
			id: 'file:file-2',
			file: { ...selectedItem.file, name: 'OTHER.md' },
			bridgeMetadata: {
				...selectedItem.bridgeMetadata,
				displayPath: 'OTHER.md',
				itemId: 'file-2',
			},
		} satisfies BridgeWorkerCodeViewFileItem;
		store.setLocalSelection({ selectedItemId: 'file-1', source: 'user' });
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });
		store.setWorkerCodeViewItem({ item: unselectedItem, itemId: 'file-2' });
		store.applySnapshotUpdate({
			workerPatches: [
				{
					itemId: 'file-1',
					operation: 'upsert',
					payload: { contentCacheKey: 'cache-file-1' },
					slice: 'rowPaint',
				},
				{
					itemId: 'file-1',
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
		});

		const replacementEvent = fileDisplayEvent({ epoch: 2, projectionRevision: 1, sequence: 2 });
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					...replacementEvent,
					patches: [
						{
							operation: 'reset',
							payload: { sourceGeneration: 2, sourceId: 'source-2' },
							slice: 'fileTree',
						},
						{ operation: 'reset', slice: 'fileItem' },
						{ operation: 'reset', slice: 'fileStatus' },
						...replacementEvent.patches.filter((patch): boolean => patch.slice === 'fileItem'),
					],
				},
			],
			renderSnapshotStore: store,
			selection: { fileId: 'file-1', path: 'README.md' },
		});

		expect(store.getSnapshot().codeViewItemsById).toEqual({ 'file-1': selectedItem });
		expect(store.getSnapshot().contentAvailabilityById).toEqual({});
		expect(store.getSnapshot().rowPaintById).toEqual({});
		expect(store.getSnapshot().fileItemById.get('file-1')?.displayPath).toBe('README.md');
		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				renderSnapshot: store.getSnapshot(),
				selection: { fileId: 'file-1', path: 'README.md' },
			}),
		).toEqual(selectedItem);
	});
});

function applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
	readonly selection?: BridgeFileViewerSelection | null;
}): void {
	applyProductionBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
		messages: props.messages,
		renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
		renderSnapshotStore: props.renderSnapshotStore,
		...(props.selection === undefined ? {} : { selection: props.selection }),
	});
}

function createTestRenderFulfillmentCoordinator(): BridgeMainRenderFulfillmentCoordinator {
	return createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: (_frameHandle): void => {},
		nowMilliseconds: (): number => 0,
		requestAnimationFrame: (_callback): number => {
			throw new Error('File source-replacement fixture must not schedule paint validation.');
		},
		sendDisposition: (_receipt): void => {},
	});
}

function fileDisplayEvent(props: {
	readonly epoch: number;
	readonly projectionRevision: number;
	readonly sequence: number;
}): BridgeWorkerFileDisplayPatchEvent {
	return {
		wireVersion: 1,
		direction: 'serverWorkerToMain',
		transferDescriptors: [],
		kind: 'fileDisplayPatch',
		surface: 'fileView',
		epoch: props.epoch,
		projectionRevision: props.projectionRevision,
		sequence: props.sequence,
		patches: [
			{
				operation: 'reset',
				payload: { sourceGeneration: 1, sourceId: 'source-1' },
				slice: 'fileTree',
			},
			{
				itemId: 'file-1',
				operation: 'upsert',
				payload: {
					availability: { kind: 'available' },
					displayPath: 'README.md',
					endsMidLine: false,
					endsWithNewline: true,
					extent: { kind: 'exactLineCount', lineCount: 1 },
					fileExtension: 'md',
					language: 'markdown',
					payloadByteCount: 6,
					payloadLineCount: 1,
					rowId: 'row-1',
					sizeBytes: 6,
					totalLineCount: 1,
					truncationKind: 'none',
				},
				slice: 'fileItem',
			},
		],
	};
}
