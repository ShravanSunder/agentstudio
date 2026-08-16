import { parseDiffFromFile } from '@pierre/diffs';
import { createElement, type ReactElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderPublication,
	type BridgeMainRenderFulfillmentCoordinator,
} from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerFilePierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerCodeViewDiffItem,
	type BridgeWorkerCodeViewFileItem,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRenderRejectionReason } from '../core/comm-worker/bridge-worker-render-fulfillment.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import type { BridgeFileViewerSelection } from './bridge-file-viewer-display-model.js';
import {
	applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore as applyProductionBridgeWorkerMessagesToFileViewerRenderSnapshotStore,
	BridgeFileViewerSurfaceClientProvider,
	selectedBridgeFileViewerCodeViewItemForSnapshot,
	type BridgeFileViewerRenderSnapshotController,
	useBridgeFileViewerRenderSnapshotController,
} from './bridge-file-viewer-render-snapshot-controller.js';
import { bridgeFileViewerHeaderStatusText } from './bridge-file-viewer-shell.js';

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
		expect(controller.selectedCodeViewItem).toEqual({ ...selectedItem, version: 1 });
		expect(controller.fileDisplaySnapshot.fileStatusSlice).toMatchObject({ state: 'ready' });
	});

	test('exposes only the File surface panel chrome slice from its render store', () => {
		// Arrange
		const renderStore = createBridgeMainRenderSnapshotStore();
		renderStore.applyWorkerPatch({
			operation: 'upsert',
			payload: { isLoading: true, message: 'Updating files…' },
			slice: 'panelChrome',
		});
		const fileViewClient = makeFileViewSurfaceClient([], renderStore);
		const controllerProbe: { current: BridgeFileViewerRenderSnapshotController | null } = {
			current: null,
		};

		function Probe(): ReactElement {
			controllerProbe.current = useBridgeFileViewerRenderSnapshotController({ selection: null });
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

		// Assert
		const controller = controllerProbe.current;
		if (controller === null) throw new Error('Expected the File controller probe to render.');
		expect(controller.panelChromeSlice).toEqual({
			isLoading: true,
			message: 'Updating files…',
		});
	});

	test('passes File updating chrome to the shared header only while File is active', () => {
		// Arrange / Act
		const activeStatus = bridgeFileViewerHeaderStatusText(true, {
			isLoading: true,
			message: 'Updating files…',
		});
		const inactiveStatus = bridgeFileViewerHeaderStatusText(false, {
			isLoading: true,
			message: 'Updating review…',
		});
		const settledStatus = bridgeFileViewerHeaderStatusText(true, {
			isLoading: false,
			message: null,
		});

		// Assert
		expect(activeStatus).toBe('Updating files…');
		expect(inactiveStatus).toBeNull();
		expect(settledStatus).toBeNull();
	});

	test('accepts the exact current owned File publication after installing its Pierre item', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const admissionRecorder = makeFilePublicationAdmissionRecorder();
		const publication = filePierreRenderJobEvent({
			publicationSequence: 2,
			workerDerivationEpoch: 1,
		});

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 }), publication],
			renderFulfillmentCoordinator: admissionRecorder.coordinator,
			renderSnapshotStore,
		});

		const presentedItem = renderSnapshotStore.getSnapshot().codeViewItemsById['file-1'];
		expect(presentedItem).not.toBe(publication.job.payload.item);
		expect(presentedItem).toEqual({ ...publication.job.payload.item, version: 1 });
		expect(admissionRecorder.acceptedPublications).toEqual([publication]);
		expect(admissionRecorder.rejectedPublications).toEqual([]);
	});

	test('rejects stale, wrong-kind, and unowned File publications without replacing File state', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const admissionRecorder = makeFilePublicationAdmissionRecorder();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 1, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore,
		});
		renderSnapshotStore.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });
		const staleItem = {
			...selectedItem,
			file: { ...selectedItem.file, cacheKey: 'cache-stale', contents: 'stale\n' },
			version: 2,
			bridgeMetadata: { ...selectedItem.bridgeMetadata, cacheKey: 'cache-stale' },
		} satisfies BridgeWorkerCodeViewFileItem;
		const unownedItem = {
			...selectedItem,
			id: 'file:file-unowned',
			file: { ...selectedItem.file, cacheKey: 'cache-unowned', name: 'UNOWNED.md' },
			bridgeMetadata: {
				...selectedItem.bridgeMetadata,
				cacheKey: 'cache-unowned',
				displayPath: 'UNOWNED.md',
				itemId: 'file-unowned',
			},
		} satisfies BridgeWorkerCodeViewFileItem;
		const invalidPublications: readonly BridgeWorkerFilePierreRenderJobEvent[] = [
			filePierreRenderJobEvent({
				item: staleItem,
				publicationSequence: 3,
				workerDerivationEpoch: 0,
			}),
			filePierreRenderJobWithDiffItemEvent({
				publicationSequence: 4,
				workerDerivationEpoch: 1,
			}),
			filePierreRenderJobEvent({
				item: unownedItem,
				publicationSequence: 5,
				workerDerivationEpoch: 1,
			}),
		];

		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: invalidPublications,
			renderFulfillmentCoordinator: admissionRecorder.coordinator,
			renderSnapshotStore,
		});

		expect(renderSnapshotStore.getSnapshot().codeViewItemsById).toEqual({ 'file-1': selectedItem });
		expect(admissionRecorder.acceptedPublications).toEqual([]);
		expect(admissionRecorder.rejectedPublications).toEqual(
			invalidPublications.map((publication) => ({
				publication,
				reason: 'stale_submission',
			})),
		);
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

	test('retains only selected File Pierre while clearing availability at a source replacement commit', () => {
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

	test('retains the exact selected Pierre item when source reconciliation deletes its row paint', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 2, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
			selection: { fileId: 'file-1', path: 'README.md' },
		});
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
					itemId: 'file-2',
					operation: 'upsert',
					payload: { contentCacheKey: 'cache-file-2' },
					slice: 'rowPaint',
				},
			],
		});

		// Act
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					direction: 'serverWorkerToMain',
					kind: 'fileRenderPatch',
					patches: [
						{ itemId: 'file-1', operation: 'delete', slice: 'rowPaint' },
						{ itemId: 'file-2', operation: 'delete', slice: 'rowPaint' },
					],
					publicationSequence: 2,
					surface: 'file',
					transferDescriptors: [],
					wireVersion: 1,
					workerDerivationEpoch: 2,
				},
			],
			renderSnapshotStore: store,
			selection: { fileId: 'file-1', path: 'README.md' },
		});

		// Assert
		expect(store.getSnapshot().codeViewItemsById['file-1']).toEqual(selectedItem);
		expect(store.getSnapshot().rowPaintById['file-1']).toEqual({
			contentCacheKey: 'cache-file-1',
		});
		expect(store.getSnapshot().rowPaintById['file-2']).toBeUndefined();
	});

	test('projects selected stale source reconciliation availability as no File availability', () => {
		// Arrange
		const store = createBridgeMainRenderSnapshotStore();
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [fileDisplayEvent({ epoch: 4, projectionRevision: 1, sequence: 1 })],
			renderSnapshotStore: store,
		});
		store.applyWorkerPatch({
			itemId: 'file-1',
			operation: 'upsert',
			payload: { state: 'ready' },
			slice: 'contentAvailability',
		});

		// Act
		applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
			messages: [
				{
					direction: 'serverWorkerToMain',
					kind: 'fileRenderPatch',
					patches: [
						{
							itemId: 'file-1',
							operation: 'upsert',
							payload: { state: 'stale' },
							slice: 'contentAvailability',
						},
					],
					publicationSequence: 2,
					surface: 'file',
					transferDescriptors: [],
					wireVersion: 1,
					workerDerivationEpoch: 4,
				},
			],
			renderSnapshotStore: store,
			selection: { fileId: 'file-1', path: 'README.md' },
		});

		// Assert
		expect(store.getSnapshot().contentAvailabilityById['file-1']).toBeUndefined();
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
		expect(store.getSnapshot().codeViewItemsById['file-1']).toEqual({
			...selectedItem,
			version: 1,
		});

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
		expect(store.getSnapshot().codeViewItemsById['file-1']).toEqual({
			...selectedItem,
			version: 1,
		});
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

	test('keeps exact selected Pierre content eligible while File metadata is temporarily absent', () => {
		const store = createBridgeMainRenderSnapshotStore();
		store.setWorkerCodeViewItem({ item: selectedItem, itemId: 'file-1' });

		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				renderSnapshot: store.getSnapshot(),
				selection: { fileId: 'file-1', path: 'README.md' },
			}),
		).toEqual(selectedItem);
		expect(
			selectedBridgeFileViewerCodeViewItemForSnapshot({
				renderSnapshot: store.getSnapshot(),
				selection: { fileId: 'file-1', path: 'OTHER.md' },
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
		renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
		renderStore,
		send: (command): string => {
			sentCommands.push(command);
			return `file-request-${sentCommands.length}`;
		},
		subscribeMessages: () => (): void => {},
		surface: 'fileView',
	};
}

function createTestRenderFulfillmentCoordinator(): BridgeMainRenderFulfillmentCoordinator {
	return createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: (_frameHandle): void => {},
		nowMilliseconds: (): number => 0,
		requestAnimationFrame: (_callback): number => {
			throw new Error('File controller fixture must not schedule paint validation.');
		},
		sendDisposition: (_receipt): void => {},
	});
}

function applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly renderFulfillmentCoordinator?: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'acceptPublication' | 'bindPublicationItem' | 'markPublicationQueued' | 'rejectPublication'
	>;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
	readonly selection?: BridgeFileViewerSelection | null;
}): void {
	applyProductionBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
		messages: props.messages,
		renderFulfillmentCoordinator:
			props.renderFulfillmentCoordinator ?? makeFilePublicationAdmissionRecorder().coordinator,
		renderSnapshotStore: props.renderSnapshotStore,
		...(props.selection === undefined ? {} : { selection: props.selection }),
	});
}

function makeFilePublicationAdmissionRecorder(): {
	readonly acceptedPublications: BridgeMainRenderPublication[];
	readonly coordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'acceptPublication' | 'bindPublicationItem' | 'markPublicationQueued' | 'rejectPublication'
	>;
	readonly rejectedPublications: {
		readonly publication: BridgeMainRenderPublication;
		readonly reason: BridgeWorkerRenderRejectionReason;
	}[];
} {
	const acceptedPublications: BridgeMainRenderPublication[] = [];
	const rejectedPublications: {
		publication: BridgeMainRenderPublication;
		reason: BridgeWorkerRenderRejectionReason;
	}[] = [];
	return {
		acceptedPublications,
		coordinator: {
			acceptPublication: (publication): 'accepted' => {
				acceptedPublications.push(publication);
				return 'accepted';
			},
			bindPublicationItem: (_props): void => {},
			markPublicationQueued: (_publication): void => {},
			rejectPublication: (publication, reason): void => {
				rejectedPublications.push({ publication, reason });
			},
		},
		rejectedPublications,
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
	readonly item?: BridgeWorkerCodeViewFileItem;
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}): BridgeWorkerFilePierreRenderJobEvent {
	const item = props.item ?? selectedItem;
	const itemId = item.bridgeMetadata.itemId;
	return {
		direction: 'serverWorkerToMain',
		job: buildBridgeWorkerPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 1024, maxWindowLines: 10 },
			contentCacheKey: item.bridgeMetadata.cacheKey,
			contentHash: `sha256:${item.bridgeMetadata.cacheKey}`,
			itemId,
			language: item.file.lang ?? 'plaintext',
			payload: { item, kind: 'codeViewFileItem' },
			renderKind: 'fileText',
			window: { endLine: 1, startLine: 1, totalLineCount: 1 },
		}),
		kind: 'filePierreRenderJob',
		publicationSequence: props.publicationSequence,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId,
			publicationSequence: props.publicationSequence,
			surface: 'file',
			workerDerivationEpoch: props.workerDerivationEpoch,
		}),
		surface: 'file',
		transferDescriptors: [],
		wireVersion: 1,
		workerDerivationEpoch: props.workerDerivationEpoch,
	};
}

function filePierreRenderJobWithDiffItemEvent(props: {
	readonly publicationSequence: number;
	readonly workerDerivationEpoch: number;
}): BridgeWorkerFilePierreRenderJobEvent {
	const diffItem: BridgeWorkerCodeViewDiffItem = {
		bridgeMetadata: {
			cacheKey: 'cache-diff-file-1',
			contentRoles: ['diff'],
			contentState: 'hydrated',
			displayPath: 'README.md',
			itemId: 'file-1',
			lineCount: 1,
		},
		fileDiff: parseDiffFromFile(
			{ contents: 'before\n', name: 'README.md' },
			{ contents: 'after\n', name: 'README.md' },
		),
		id: 'diff:file-1',
		type: 'diff',
	};
	const fileEnvelope = filePierreRenderJobEvent(props);
	return {
		...fileEnvelope,
		job: buildBridgeWorkerPierreRenderJob({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 1024, maxWindowLines: 10 },
			contentCacheKey: diffItem.bridgeMetadata.cacheKey,
			contentHash: 'sha256:diff-file-1',
			itemId: 'file-1',
			language: 'markdown',
			payload: { item: diffItem, kind: 'codeViewDiffItem' },
			renderKind: 'reviewDiff',
			window: { endLine: 1, startLine: 1, totalLineCount: 1 },
		}),
	};
}
