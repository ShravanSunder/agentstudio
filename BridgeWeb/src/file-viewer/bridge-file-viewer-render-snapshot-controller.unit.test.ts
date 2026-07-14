import { createElement, type ReactElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerCodeViewFileItem,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import {
	applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore,
	BridgeFileViewerSurfaceClientProvider,
	selectedBridgeFileViewerCodeViewItemForSnapshot,
	type BridgeFileViewerRenderSnapshotController,
	useBridgeFileViewerRenderSnapshotController,
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

describe('Bridge File viewer render snapshot controller', () => {
	test('sends File interactions through the injected stable surface client', () => {
		const sentCommands: BridgeWorkerRpcCommandInput[] = [];
		const fileViewClient = makeFileViewSurfaceClient(sentCommands);
		const controllerProbe: { current: BridgeFileViewerRenderSnapshotController | null } = {
			current: null,
		};

		function Probe(): ReactElement {
			controllerProbe.current = useBridgeFileViewerRenderSnapshotController({ selection: null });
			return createElement('div');
		}

		renderToStaticMarkup(
			createElement(
				BridgeFileViewerSurfaceClientProvider,
				{ surfaceClient: fileViewClient },
				createElement(Probe),
			),
		);
		const controller = controllerProbe.current;
		if (controller === null) throw new Error('Expected the File controller probe to render.');

		controller.dispatchSelectedFileViewContentRequest({
			fileId: 'file-1',
			selectedSource: 'user',
		});
		controller.dispatchVisibleFileViewViewportFact({
			firstVisibleIndex: 2,
			lastVisibleIndex: 3,
			visibleItemIds: ['file-1', 'file-2'],
		});

		expect(sentCommands).toEqual([
			expect.objectContaining({
				command: 'select',
				selectedItemId: 'file-1',
				surface: 'fileView',
			}),
			expect.objectContaining({
				command: 'viewport',
				surface: 'fileView',
				visibleItemIds: ['file-1', 'file-2'],
			}),
		]);
	});

	test('reports a ready File display when the selected file is genuinely rendered', () => {
		// Arrange
		const renderStore = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 }),
				fileRenderPatchEvent({ workerDerivationEpoch: 1, publicationSequence: 2 }),
				filePierreRenderJobEvent({ workerDerivationEpoch: 1, publicationSequence: 3 }),
			],
			renderSnapshotStore: renderStore,
		});
		const fileViewClient = makeFileViewSurfaceClient([], renderStore);
		const controllerProbe: { current: BridgeFileViewerRenderSnapshotController | null } = {
			current: null,
		};

		function Probe(): ReactElement {
			controllerProbe.current = useBridgeFileViewerRenderSnapshotController({
				selection: { fileId: 'file-1', path: 'README.md' },
			});
			return createElement('div');
		}

		// Act
		renderToStaticMarkup(
			createElement(
				BridgeFileViewerSurfaceClientProvider,
				{ surfaceClient: fileViewClient },
				createElement(Probe),
			),
		);
		const controller = controllerProbe.current;
		if (controller === null) throw new Error('Expected the File controller probe to render.');

		// Assert
		expect(controller.selectedContentAvailability).toEqual({ state: 'ready' });
		expect(controller.selectedCodeViewItem).toEqual(selectedItem);
		expect(controller.fileDisplaySnapshot.fileStatusSlice).toMatchObject({ state: 'ready' });
	});

	test('applies display patches while rejecting cross-wired generic Review selection patches', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileDisplayEvent({ epoch: 3, projectionRevision: 1, sequence: 1 }),
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'slicePatch',
					epoch: 4,
					sequence: 2,
					patches: [
						{
							operation: 'upsert',
							payload: { selectedItemId: 'review-item', source: 'user' },
							slice: 'selection',
						},
					],
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().fileTreeSlice.sourceId).toBe('source-1');
		expect(store.getSnapshot().fileItemById.get('file-1')?.displayPath).toBe('README.md');
		expect(store.getSnapshot().selectionSlice.selectedItemId).toBeNull();
	});

	test('clears File Pierre and availability residue on an accepted source reset', () => {
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
					],
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().codeViewItemsById).toEqual({});
		expect(store.getSnapshot().contentAvailabilityById).toEqual({});
		expect(store.getSnapshot().rowPaintById).toEqual({});
		expect(store.getSnapshot().fileTreeSlice.sourceId).toBe('source-2');
	});

	test('rejects stale File render publications after a same-id source reset', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileRenderPatchEvent({ workerDerivationEpoch: 1, publicationSequence: 2 }),
				filePierreRenderJobEvent({ workerDerivationEpoch: 1, publicationSequence: 3 }),
			],
			renderSnapshotStore: store,
		});
		expect(store.getSnapshot().contentAvailabilityById['file-1']).toEqual({ state: 'ready' });
		expect(store.getSnapshot().rowPaintById['file-1']).toEqual({
			contentCacheKey: 'cache-file-1',
		});
		expect(store.getSnapshot().codeViewItemsById['file-1']).toEqual(selectedItem);

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileDisplayEvent({
					epoch: 2,
					projectionRevision: 1,
					sequence: 4,
					sourceGeneration: 2,
					sourceId: 'source-2',
				}),
			],
			renderSnapshotStore: store,
		});
		const resetSnapshot = store.getSnapshot();

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileRenderPatchEvent({ workerDerivationEpoch: 1, publicationSequence: 5 }),
				filePierreRenderJobEvent({ workerDerivationEpoch: 1, publicationSequence: 6 }),
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot()).toBe(resetSnapshot);
		expect(store.getSnapshot().fileItemById.get('file-1')?.displayPath).toBe('README.md');
		expect(store.getSnapshot().contentAvailabilityById).toEqual({});
		expect(store.getSnapshot().rowPaintById).toEqual({});
		expect(store.getSnapshot().codeViewItemsById).toEqual({});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileRenderPatchEvent({ workerDerivationEpoch: 2, publicationSequence: 7 }),
				filePierreRenderJobEvent({ workerDerivationEpoch: 2, publicationSequence: 8 }),
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().contentAvailabilityById['file-1']).toEqual({ state: 'ready' });
		expect(store.getSnapshot().rowPaintById['file-1']).toEqual({
			contentCacheKey: 'cache-file-1',
		});
		expect(store.getSnapshot().codeViewItemsById['file-1']).toEqual(selectedItem);
	});

	test('does not let generic slice patches mutate File render copies', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				fileDisplayEvent({ epoch: 3, projectionRevision: 1, sequence: 1 }),
				{
					direction: 'serverWorkerToMain',
					epoch: 99,
					kind: 'slicePatch',
					patches: [
						{
							itemId: 'file-1',
							operation: 'upsert',
							payload: { contentCacheKey: 'generic-cache' },
							slice: 'rowPaint',
						},
						{
							itemId: 'file-1',
							operation: 'upsert',
							payload: { state: 'ready' },
							slice: 'contentAvailability',
						},
					],
					sequence: 2,
					transferDescriptors: [],
					wireVersion: 1,
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().contentAvailabilityById).toEqual({});
		expect(store.getSnapshot().rowPaintById).toEqual({});
	});

	test('does not manufacture terminal File availability from unscoped worker health', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
		});
		store.setLocalSelection({ selectedItemId: 'file-1', source: 'user' });
		store.applyWorkerPatch({
			itemId: 'file-1',
			operation: 'upsert',
			payload: { state: 'loading' },
			slice: 'contentAvailability',
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					direction: 'serverWorkerToMain',
					kind: 'health',
					message: 'worker startup failed',
					requestId: 'worker-startup',
					status: 'degraded',
					transferDescriptors: [],
					wireVersion: 1,
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().contentAvailabilityById['file-1']).toEqual({ state: 'loading' });
	});

	test('does not clear current File content for a stale reset event', () => {
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 5, projectionRevision: 5, sequence: 5 })],
			renderSnapshotStore: store,
		});
		store.setLocalSelection({ selectedItemId: 'file-1', source: 'user' });
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					...fileDisplayEvent({ epoch: 4, projectionRevision: 4, sequence: 4 }),
					patches: [
						{
							operation: 'reset',
							payload: { sourceGeneration: 1, sourceId: 'stale-source' },
							slice: 'fileTree',
						},
					],
				},
			],
			renderSnapshotStore: store,
		});

		expect(store.getSnapshot().codeViewItemsById['file-1']).toEqual(selectedItem);
		expect(store.getSnapshot().fileTreeSlice.sourceId).toBe('source-1');
	});

	test('gates selected Pierre content on the current File display item', () => {
		const store = createBridgeMainRenderSnapshotStore();
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });

		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				renderSnapshot: store.getSnapshot(),
				selection: { fileId: 'file-1', path: 'README.md' },
			}),
		).toBeNull();

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
		});
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });
		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				renderSnapshot: store.getSnapshot(),
				selection: { fileId: 'file-1', path: 'README.md' },
			}),
		).toEqual(selectedItem);
	});
});

function makeFileViewSurfaceClient(
	sentCommands: BridgeWorkerRpcCommandInput[],
	renderStore: BridgeMainRenderSnapshotStore = createBridgeMainRenderSnapshotStore(),
): BridgePaneSurfaceClient {
	return {
		lifecycle: {
			getSnapshot: () => ({ requestsById: {} }),
			getServerSnapshot: () => ({ requestsById: {} }),
			subscribe: () => (): void => {},
		},
		renderStore,
		send: (command): string => {
			sentCommands.push(command);
			return `file-request-${sentCommands.length}`;
		},
		subscribeMessages: () => (): void => {},
		surface: 'fileView',
	};
}

function fileDisplayEvent(props: {
	readonly epoch: number;
	readonly projectionRevision: number;
	readonly sequence: number;
	readonly sourceGeneration?: number;
	readonly sourceId?: string;
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
				payload: {
					sourceGeneration: props.sourceGeneration ?? 1,
					sourceId: props.sourceId ?? 'source-1',
				},
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

function fileRenderPatchEvent(props: {
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'fileRenderPatch',
		patches: [
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
		publicationSequence: props.publicationSequence,
		surface: 'file',
		transferDescriptors: [],
		wireVersion: 1,
		workerDerivationEpoch: props.workerDerivationEpoch,
	};
}

function filePierreRenderJobEvent(props: {
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		job: buildBridgeWorkerPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 1024, maxWindowLines: 10 },
			contentCacheKey: 'cache-file-1',
			contentHash: 'sha256:file-1',
			itemId: 'file-1',
			language: 'markdown',
			payload: { item: selectedItem, kind: 'codeViewFileItem' },
			renderKind: 'fileText',
			window: { endLine: 1, startLine: 1, totalLineCount: 1 },
		}),
		kind: 'filePierreRenderJob',
		publicationSequence: props.publicationSequence,
		surface: 'file',
		transferDescriptors: [],
		wireVersion: 1,
		workerDerivationEpoch: props.workerDerivationEpoch,
	};
}
