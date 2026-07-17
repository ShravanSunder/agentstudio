import { parseDiffFromFile } from '@pierre/diffs';
import { createElement, type ReactElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, test } from 'vitest';

import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
} from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewPierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerPierreCourier } from '../core/comm-worker/bridge-worker-pierre-courier.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderJob,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import type { BridgeWorkerRpcLifecycleSnapshot } from '../core/comm-worker/bridge-worker-rpc-lifecycle-store.js';
import {
	applyBridgeWorkerMessagesToMainRenderSnapshotStore,
	createVisibleReviewCodeViewItemsSelector,
	type BridgeReviewRenderSnapshotController,
	createBridgeReviewWorkerPierreCourier,
	reviewCodeViewBodyDemandItemIds,
	useBridgeReviewRenderSnapshotController,
} from './bridge-app-review-render-snapshot-controller.js';
import { resolveBridgeWorkerMarkFileViewedFailureCallbacks } from './bridge-app-review-worker-health-resolvers.js';

describe('Bridge app review render snapshot controller', () => {
	test('sends Review selection interactions through the stable surface client', async () => {
		const sentCommands: BridgeWorkerRpcCommandInput[] = [];
		const reviewClient = makeReviewSurfaceClient(sentCommands);
		const controllerHolder: { current: BridgeReviewRenderSnapshotController | null } = {
			current: null,
		};

		function Probe(): ReactElement {
			controllerHolder.current = useBridgeReviewRenderSnapshotController({
				pierreCourier: createBridgeReviewWorkerPierreCourier(),
				reviewClient,
			});
			return createElement('div');
		}

		renderToStaticMarkup(createElement(Probe));
		const controller = controllerHolder.current;
		if (controller === null) throw new Error('Expected the Review controller probe to render.');

		controller.commitSelectedReviewItemId('item-source');
		controller.emitSelectedReviewItemIntent('item-source', 'user');
		expect(sentCommands).toEqual([
			expect.objectContaining({
				command: 'select',
				selectedItemId: 'item-source',
				surface: 'review',
			}),
		]);
	});

	test('allocates Review projection epochs from the same command sequence as selection', () => {
		// Arrange
		const sentCommands: BridgeWorkerRpcCommandInput[] = [];
		const reviewClient = makeReviewSurfaceClient(sentCommands);
		const controllerHolder: { current: BridgeReviewRenderSnapshotController | null } = {
			current: null,
		};

		function Probe(): ReactElement {
			controllerHolder.current = useBridgeReviewRenderSnapshotController({
				pierreCourier: createBridgeReviewWorkerPierreCourier(),
				reviewClient,
			});
			return createElement('div');
		}

		renderToStaticMarkup(createElement(Probe));
		const controller = controllerHolder.current;
		if (controller === null) throw new Error('Expected the Review controller probe to render.');

		// Act
		controller.emitSelectedReviewItemIntent('item-source', 'user');
		controller.updateReviewDisplayProjection({ fileClassFilter: 'docs', gitStatusFilter: 'all' });

		// Assert
		expect(sentCommands).toEqual([
			expect.objectContaining({ command: 'select', epoch: 1 }),
			expect.objectContaining({
				command: 'reviewProjectionUpdate',
				epoch: 2,
				query: { fileClassFilter: 'docs', gitStatusFilter: 'all' },
			}),
		]);
	});

	test('exposes only the Review surface panel chrome slice from its render store', () => {
		// Arrange
		const renderStore = createBridgeMainRenderSnapshotStore();
		renderStore.applyWorkerPatch({
			operation: 'upsert',
			payload: { isLoading: true, message: 'Updating review…' },
			slice: 'panelChrome',
		});
		const reviewClient = makeReviewSurfaceClient([], renderStore);
		const controllerHolder: { current: BridgeReviewRenderSnapshotController | null } = {
			current: null,
		};

		function Probe(): ReactElement {
			controllerHolder.current = useBridgeReviewRenderSnapshotController({
				pierreCourier: createBridgeReviewWorkerPierreCourier(),
				reviewClient,
			});
			return createElement('div');
		}

		// Act
		renderToStaticMarkup(createElement(Probe));

		// Assert
		const controller = controllerHolder.current;
		if (controller === null) throw new Error('Expected the Review controller probe to render.');
		expect(controller.panelChromeSlice).toEqual({
			isLoading: true,
			message: 'Updating review…',
		});
	});

	test('derives body demand only from unique CodeView-visible item ids', () => {
		expect(
			reviewCodeViewBodyDemandItemIds(['item-selected', 'item-code-visible', 'item-code-visible']),
		).toEqual(['item-selected', 'item-code-visible']);
	});

	test('selects ready CodeView items in visible order with stable snapshots', () => {
		const firstItem = makeReviewPierreRenderJob('item-first').payload.item;
		const secondItem = makeReviewPierreRenderJob('item-second').payload.item;
		const itemsById = new Map([
			['item-first', firstItem],
			['item-second', secondItem],
		]);
		const selector = createVisibleReviewCodeViewItemsSelector();

		const firstSnapshot = selector({
			getItem: (itemId) => itemsById.get(itemId),
			itemIds: ['item-second', 'item-missing', 'item-first'],
		});
		const repeatedSnapshot = selector({
			getItem: (itemId) => itemsById.get(itemId),
			itemIds: ['item-second', 'item-missing', 'item-first'],
		});

		expect(firstSnapshot).toEqual([secondItem, firstItem]);
		expect(repeatedSnapshot).toBe(firstSnapshot);
	});

	test('resolves mark-viewed failure callbacks from correlated worker health', () => {
		let failedRequestCount = 0;
		let readyRequestFailureCount = 0;
		const failureCallbacksByRequestId = new Map<string, () => void>([
			[
				'request-mark-failed',
				(): void => {
					failedRequestCount += 1;
				},
			],
			[
				'request-mark-ready',
				(): void => {
					readyRequestFailureCount += 1;
				},
			],
		]);

		resolveBridgeWorkerMarkFileViewedFailureCallbacks({
			failureCallbacksByRequestId,
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'health',
					requestId: 'request-mark-ready',
					status: 'ready',
				},
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'health',
					requestId: 'request-mark-failed',
					status: 'degraded',
					message: 'Bridge comm worker failed to forward review.markFileViewed.',
				},
			],
		});

		expect(failedRequestCount).toBe(1);
		expect(readyRequestFailureCount).toBe(0);
		expect([...failureCallbacksByRequestId.keys()]).toEqual([]);
	});

	test('routes worker Pierre render jobs through the courier instead of dropping them', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		renderSnapshotStore.applyReviewDisplayPatchEvent(
			reviewDisplayPatchEvent({ epoch: 4, itemIds: ['item-1'], reset: true }),
		);
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-1',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			contentHash: 'sha256:base+head',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 10,
				totalLineCount: 100,
			},
			payload: {
				kind: 'codeViewDiffItem',
				item: {
					id: 'item-1',
					type: 'diff',
					fileDiff: parseDiffFromFile(
						{
							name: 'Sources/App.ts',
							contents: 'export const answer = 41;\n',
							cacheKey: 'pierre-content:sha256:base',
						},
						{
							name: 'Sources/App.ts',
							contents: 'export const answer = 42;\n',
							cacheKey: 'pierre-content:sha256:head',
						},
					),
					version: 2,
					bridgeMetadata: {
						itemId: 'item-1',
						displayPath: 'Sources/App.ts',
						contentState: 'hydrated',
						contentRoles: ['base', 'head'],
						cacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
						lineCount: 2,
					},
				},
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});
		const event = {
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			publicationSequence: 7,
			surface: 'review',
			transferDescriptors: [
				{
					messageKind: 'reviewPierreRenderJob',
					fieldPath: ['job', 'payload'],
					byteLength: job.payloadByteLength,
					mode: 'clone',
				},
			],
			kind: 'reviewPierreRenderJob',
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: job.itemId,
				publicationSequence: 7,
				surface: 'review',
				workerDerivationEpoch: 4,
			}),
			workerDerivationEpoch: 4,
			job,
		} satisfies BridgeWorkerReviewPierreRenderJobEvent;
		const submittedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			submit: (receivedJob: BridgeWorkerPierreRenderJob): void => {
				submittedJobs.push(receivedJob);
			},
		};
		const renderFulfillmentCoordinator = createTestRenderFulfillmentCoordinator();

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		expect(submittedJobs).toEqual([job]);
		expect(
			(
				renderSnapshotStore.getSnapshot() as {
					readonly codeViewItemsById?: Readonly<Record<string, unknown>>;
				}
			).codeViewItemsById?.['item-1'],
		).toEqual({ ...job.payload.item, version: 1 });
	});

	test('keeps exact replay idempotent while admitting a fresh equivalent Pierre attempt', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		renderSnapshotStore.applyReviewDisplayPatchEvent(
			reviewDisplayPatchEvent({ epoch: 4, itemIds: ['item-duplicate'], reset: true }),
		);
		const job = makeReviewPierreRenderJob('item-duplicate');
		const event = makePierreRenderJobEvent(job);
		const freshAttemptJob = makeReviewPierreRenderJob('item-duplicate');
		const freshAttemptEvent = makePierreRenderJobEvent(freshAttemptJob, 4, 8);
		const submittedJobs: BridgeWorkerPierreRenderJob[] = [];
		let publishCount = 0;
		const unsubscribe = renderSnapshotStore.subscribe(() => {
			publishCount += 1;
		});
		const pierreCourier: BridgeWorkerPierreCourier = {
			submit: (receivedJob: BridgeWorkerPierreRenderJob): void => {
				submittedJobs.push(receivedJob);
			},
		};
		const renderFulfillmentCoordinator = createTestRenderFulfillmentCoordinator();

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		expect(submittedJobs).toEqual([job]);
		expect(publishCount).toBe(1);
		const firstPresentedItem =
			renderSnapshotStore.getSnapshot().codeViewItemsById['item-duplicate'];
		expect(firstPresentedItem).not.toBe(job.payload.item);
		expect(firstPresentedItem).toEqual({ ...job.payload.item, version: 1 });

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [freshAttemptEvent],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		expect(freshAttemptJob.payload.item).not.toBe(job.payload.item);
		expect(submittedJobs).toEqual([job, freshAttemptJob]);
		expect(publishCount).toBe(2);
		expect(renderSnapshotStore.getSnapshot().codeViewItemsById['item-duplicate']).toBe(
			freshAttemptJob.payload.item,
		);

		unsubscribe();
	});

	test('does not suppress a worker Pierre render job for a different item id', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		renderSnapshotStore.applyReviewDisplayPatchEvent(
			reviewDisplayPatchEvent({
				epoch: 4,
				itemIds: ['item-duplicate', 'item-retargeted'],
				reset: true,
			}),
		);
		const job = makeReviewPierreRenderJob('item-duplicate');
		const event = makePierreRenderJobEvent(job);
		const retargetedJob = makeReviewPierreRenderJob('item-retargeted');
		const retargetedEvent = makePierreRenderJobEvent(retargetedJob);
		const submittedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			submit: (receivedJob: BridgeWorkerPierreRenderJob): void => {
				submittedJobs.push(receivedJob);
			},
		};
		const renderFulfillmentCoordinator = createTestRenderFulfillmentCoordinator();

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [retargetedEvent],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		expect(submittedJobs).toEqual([job, retargetedJob]);
		const retargetedPresentedItem =
			renderSnapshotStore.getSnapshot().codeViewItemsById['item-retargeted'];
		expect(retargetedPresentedItem).not.toBe(retargetedJob.payload.item);
		expect(retargetedPresentedItem).toEqual({ ...retargetedJob.payload.item, version: 1 });
	});

	test('review worker courier accepts worker Pierre jobs without minting a receipt', () => {
		const job = buildBridgeWorkerPierreRenderJob({
			itemId: 'item-worker-courier',
			renderKind: 'reviewDiff',
			contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:worker-courier',
			contentHash: 'sha256:worker-courier',
			language: 'typescript',
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			window: {
				startLine: 1,
				endLine: 8,
				totalLineCount: 80,
			},
			payload: {
				kind: 'codeViewDiffItem',
				item: {
					id: 'item-worker-courier',
					type: 'diff',
					fileDiff: parseDiffFromFile(
						{
							name: 'Sources/App.ts',
							contents: 'export const answer = 41;\n',
							cacheKey: 'pierre-content:sha256:base',
						},
						{
							name: 'Sources/App.ts',
							contents: 'export const answer = 42;\n',
							cacheKey: 'pierre-content:sha256:worker-courier',
						},
					),
					version: 2,
					bridgeMetadata: {
						itemId: 'item-worker-courier',
						displayPath: 'Sources/App.ts',
						contentState: 'hydrated',
						contentRoles: ['base', 'head'],
						cacheKey: 'pierre-content:sha256:base|pierre-content:sha256:worker-courier',
						lineCount: 2,
					},
				},
			},
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
		});

		expect(createBridgeReviewWorkerPierreCourier().submit(job)).toBeUndefined();
	});

	test('routes only typed Review render patches into the render snapshot store', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		renderSnapshotStore.applyReviewDisplayPatchEvent(
			reviewDisplayPatchEvent({ epoch: 4, itemIds: ['item-2'], reset: true }),
		);
		const submittedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			submit: (receivedJob: BridgeWorkerPierreRenderJob): void => {
				submittedJobs.push(receivedJob);
			},
		};
		const messages = [
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				status: 'ready',
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'subscription',
				requestId: 'request-subscription',
				subscription: 'reviewContent',
				status: 'subscribed',
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'fileDisplayPatch',
				surface: 'fileView',
				epoch: 4,
				sequence: 6,
				projectionRevision: 2,
				patches: [{ slice: 'fileStatus', operation: 'upsert', payload: { state: 'stale' } }],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 4,
				sequence: 7,
				patches: [
					{
						slice: 'selection',
						operation: 'upsert',
						payload: {
							selectedItemId: 'item-2',
							source: 'user',
						},
					},
				],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'reviewRenderPatch',
				publicationSequence: 8,
				surface: 'review',
				transferDescriptors: [],
				workerDerivationEpoch: 4,
				patches: [
					{
						slice: 'rowPaint',
						operation: 'upsert',
						itemId: 'item-2',
						payload: { status: 'modified' },
					},
				],
			},
		] satisfies readonly BridgeWorkerServerToMainMessage[];
		const renderFulfillmentCoordinator = createTestRenderFulfillmentCoordinator();

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages,
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		expect(renderSnapshotStore.getSnapshot().selectionSlice).toEqual({
			selectedItemId: null,
			source: null,
		});
		expect(renderSnapshotStore.getSnapshot().rowPaintById['item-2']).toEqual({
			status: 'modified',
		});
		expect(renderSnapshotStore.getSnapshot().fileDisplayFreshness).toBeNull();
		expect(submittedJobs).toEqual([]);
	});

	test('applies a worker Review render-patch message as one render snapshot publish', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		renderSnapshotStore.applyReviewDisplayPatchEvent(
			reviewDisplayPatchEvent({ epoch: 4, itemIds: ['item-2'], reset: true }),
		);
		const pierreCourier: BridgeWorkerPierreCourier = {
			submit: (_receivedJob: BridgeWorkerPierreRenderJob): void => {},
		};
		const renderFulfillmentCoordinator = createTestRenderFulfillmentCoordinator();
		let publishCount = 0;
		const unsubscribe = renderSnapshotStore.subscribe(() => {
			publishCount += 1;
		});

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'reviewRenderPatch',
					publicationSequence: 7,
					surface: 'review',
					workerDerivationEpoch: 4,
					patches: [
						{
							slice: 'rowPaint',
							operation: 'upsert',
							itemId: 'item-2',
							payload: {
								status: 'modified',
							},
						},
						{
							slice: 'contentAvailability',
							operation: 'upsert',
							itemId: 'item-2',
							payload: {
								state: 'ready',
							},
						},
					],
				},
			],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		expect(publishCount).toBe(1);
		expect(renderSnapshotStore.getSnapshot().rowPaintById['item-2']).toEqual({
			status: 'modified',
		});
		expect(renderSnapshotStore.getSnapshot().contentAvailabilityById['item-2']).toEqual({
			state: 'ready',
		});

		unsubscribe();
	});

	test('invalidates epoch-seven render copies while preserving current selection before epoch eight', () => {
		// Arrange
		const itemId = 'item-epoch-fenced';
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const submittedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			submit: (receivedJob): void => {
				submittedJobs.push(receivedJob);
			},
		};
		const renderFulfillmentCoordinator = createTestRenderFulfillmentCoordinator();
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [reviewDisplayPatchEvent({ epoch: 7, itemIds: [itemId], reset: true })],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});
		renderSnapshotStore.setLocalSelection({ selectedItemId: itemId, source: 'user' });
		const epochSevenJob = makeReviewPierreRenderJob(itemId);
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [
				makePierreRenderJobEvent(epochSevenJob, 7),
				reviewRenderPatchEvent({ epoch: 7, itemId, publicationSequence: 1 }),
			],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});
		expect(renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId)).toEqual({
			...epochSevenJob.payload.item,
			version: 1,
		});

		// Act: a newer accepted display epoch rotates the Review source before delayed epoch-seven work.
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [reviewDisplayPatchEvent({ epoch: 8, itemIds: [itemId], reset: true })],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});
		const submittedJobCountBeforeStaleMessages = submittedJobs.length;
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [
				makePierreRenderJobEvent(makeReviewPierreRenderJob(itemId), 7),
				reviewRenderPatchEvent({ epoch: 7, itemId, publicationSequence: 2 }),
			],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		// Assert: old render state and delayed old-epoch work cannot survive the reset, while
		// the UI-local selection remains valid because epoch eight reintroduced the same item.
		expect(renderSnapshotStore.getReviewSelectionSnapshot().selectedItemId).toBe(itemId);
		expect(renderSnapshotStore.getReviewAvailabilitySnapshot(itemId)).toBeUndefined();
		expect(renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId)).toBeUndefined();
		expect(renderSnapshotStore.getSnapshot().rowPaintById[itemId]).toBeUndefined();
		expect(submittedJobs).toHaveLength(submittedJobCountBeforeStaleMessages);

		// Act: current-epoch work for a current catalog member is admitted.
		const epochEightJob = makeReviewPierreRenderJob(itemId);
		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [
				makePierreRenderJobEvent(epochEightJob, 8),
				reviewRenderPatchEvent({ epoch: 8, itemId, publicationSequence: 3 }),
			],
			pierreCourier,
			renderFulfillmentCoordinator,
			renderSnapshotStore,
		});

		// Assert
		expect(submittedJobs.at(-1)).toBe(epochEightJob);
		expect(renderSnapshotStore.getReviewCodeViewItemSnapshot(itemId)).toEqual({
			...epochEightJob.payload.item,
			version: 1,
		});
		expect(renderSnapshotStore.getReviewAvailabilitySnapshot(itemId)).toEqual({ state: 'ready' });
		expect(renderSnapshotStore.getSnapshot().rowPaintById[itemId]).toEqual({
			status: 'modified',
		});
	});
});

function createTestRenderFulfillmentCoordinator(): BridgeMainRenderFulfillmentCoordinator {
	return createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: (_frameHandle): void => {},
		nowMilliseconds: (): number => 0,
		requestAnimationFrame: (_callback): number => {
			throw new Error('Review controller fixture must not schedule paint validation.');
		},
		sendDisposition: (_receipt): void => {},
	});
}

function makeReviewSurfaceClient(
	sentCommands: BridgeWorkerRpcCommandInput[],
	renderStore = createBridgeMainRenderSnapshotStore(),
): BridgePaneSurfaceClient {
	let lifecycleSnapshot: BridgeWorkerRpcLifecycleSnapshot = { requestsById: {} };
	return {
		lifecycle: {
			getSnapshot: () => lifecycleSnapshot,
			getServerSnapshot: () => lifecycleSnapshot,
			subscribe: () => (): void => {},
		},
		renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
		renderStore,
		send: (command): string => {
			sentCommands.push(command);
			const requestId = `review-request-${sentCommands.length}`;
			lifecycleSnapshot = {
				requestsById: {
					...lifecycleSnapshot.requestsById,
					[requestId]: {
						acknowledgedAtSequence: sentCommands.length,
						command: command.command,
						requestId,
						state: 'acked',
						surface: 'review',
					},
				},
			};
			return requestId;
		},
		subscribeMessages: () => (): void => {},
		surface: 'review',
	};
}

function makeReviewPierreRenderJob(itemId: string): BridgeWorkerPierreRenderJob {
	return buildBridgeWorkerPierreRenderJob({
		itemId,
		renderKind: 'reviewDiff',
		contentCacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
		contentHash: 'sha256:base+head',
		language: 'typescript',
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		window: {
			startLine: 1,
			endLine: 10,
			totalLineCount: 100,
		},
		payload: {
			kind: 'codeViewDiffItem',
			item: {
				id: itemId,
				type: 'diff',
				fileDiff: parseDiffFromFile(
					{
						name: 'Sources/App.ts',
						contents: 'export const answer = 41;\n',
						cacheKey: 'pierre-content:sha256:base',
					},
					{
						name: 'Sources/App.ts',
						contents: 'export const answer = 42;\n',
						cacheKey: 'pierre-content:sha256:head',
					},
				),
				version: 2,
				bridgeMetadata: {
					itemId,
					displayPath: 'Sources/App.ts',
					contentState: 'hydrated',
					contentRoles: ['base', 'head'],
					cacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
					lineCount: 2,
				},
			},
		},
		budget: {
			className: 'interactive',
			maxBytes: 512 * 1024,
			maxWindowLines: 400,
		},
	});
}

function makePierreRenderJobEvent(
	job: BridgeWorkerPierreRenderJob,
	workerDerivationEpoch = 4,
	publicationSequence = 7,
): BridgeWorkerReviewPierreRenderJobEvent {
	return {
		wireVersion: 1,
		direction: 'serverWorkerToMain',
		publicationSequence,
		surface: 'review',
		transferDescriptors: [
			{
				messageKind: 'reviewPierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: job.payloadByteLength,
				mode: 'clone',
			},
		],
		kind: 'reviewPierreRenderJob',
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId: job.itemId,
			publicationSequence,
			surface: 'review',
			workerDerivationEpoch,
		}),
		workerDerivationEpoch,
		job,
	};
}

function reviewDisplayPatchEvent(props: {
	readonly epoch: number;
	readonly itemIds: readonly string[];
	readonly reset: boolean;
}): Extract<BridgeWorkerServerToMainMessage, { readonly kind: 'reviewDisplayPatch' }> {
	return {
		direction: 'serverWorkerToMain',
		epoch: props.epoch,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity: `review-window-epoch-${props.epoch}`,
					status: 'ready',
					summary: {
						additions: 0,
						deletions: 0,
						filesChanged: props.itemIds.length,
						hiddenFileCount: 0,
						visibleFileCount: props.itemIds.length,
					},
					totalItemCount: props.itemIds.length,
					totalTreeRowCount: props.itemIds.length,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: props.itemIds.map(reviewDisplayItem),
					operations: [],
					reset: props.reset,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
		],
		projectionRevision: props.epoch,
		sequence: props.epoch,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function reviewDisplayItem(itemId: string): BridgeWorkerReviewDisplayItem {
	return {
		contentFacts: [],
		extentFacts: [],
		metadata: {
			basePath: `${itemId}.ts`,
			changeKind: 'modified',
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: [],
			extension: 'ts',
			fileClass: 'source',
			headPath: `${itemId}.ts`,
			isHiddenByDefault: false,
			itemId,
			language: 'typescript',
			mimeTypes: ['text/plain'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity: `review-window-${itemId}`,
	};
}

function reviewRenderPatchEvent(props: {
	readonly epoch: number;
	readonly itemId: string;
	readonly publicationSequence: number;
}): Extract<BridgeWorkerServerToMainMessage, { readonly kind: 'reviewRenderPatch' }> {
	return {
		direction: 'serverWorkerToMain',
		kind: 'reviewRenderPatch',
		patches: [
			{
				itemId: props.itemId,
				operation: 'upsert',
				payload: { status: 'modified' },
				slice: 'rowPaint',
			},
			{
				itemId: props.itemId,
				operation: 'upsert',
				payload: { state: 'ready' },
				slice: 'contentAvailability',
			},
		],
		publicationSequence: props.publicationSequence,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
		workerDerivationEpoch: props.epoch,
	};
}
