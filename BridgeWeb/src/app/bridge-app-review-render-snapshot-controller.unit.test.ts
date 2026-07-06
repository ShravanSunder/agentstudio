import { parseDiffFromFile } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerSelectCommand } from '../core/comm-worker/bridge-comm-worker-protocol.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeWorkerMainToServerMessage,
	BridgeWorkerPierreRenderJobEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerPierreCourier } from '../core/comm-worker/bridge-worker-pierre-courier.js';
import {
	buildBridgeWorkerPierreRenderJob,
	type BridgeWorkerPierreRenderJob,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	applyBridgeWorkerMessagesToMainRenderSnapshotStore,
	bridgeCommWorkerBootstrapRequestFromReviewRuntimeProps,
	bridgeCommWorkerContentRequestDescriptorsFromReviewPackage,
	bridgeCommWorkerContentItemsFromReviewPackage,
	bridgeCommWorkerRenderSemanticsFromReviewPackage,
	createBridgeReviewWorkerPierreCourier,
	createBridgeReviewRuntimeProtocolDispatcher,
} from './bridge-app-review-render-snapshot-controller.js';

describe('Bridge app review render snapshot controller', () => {
	test('builds a typed bootstrap request for the real comm worker transport', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const bootstrapRequest = bridgeCommWorkerBootstrapRequestFromReviewRuntimeProps({
			requestId: 'bootstrap-review-runtime',
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			publishWorkerMessages: (): void => {},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
		});

		expect(bootstrapRequest).toMatchObject({
			schemaVersion: 1,
			method: 'bridgeCommWorker.bootstrap',
			requestId: 'bootstrap-review-runtime',
			runtime: {
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				budget: expect.objectContaining({ className: 'interactive' }),
			},
		});
		expect(JSON.stringify(bootstrapRequest)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|endpointId/i,
		);
	});

	test('dispatches selected review commands through the real worker transport seam', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];
		let receivedBootstrapRequestId: string | null = null;
		const runtimeDispatcher = createBridgeReviewRuntimeProtocolDispatcher({
			bootstrapRequestId: 'bootstrap-review-runtime',
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			publishWorkerMessages: (): void => {},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
			transportFactory: (props) => {
				receivedBootstrapRequestId = props.bootstrapRequest.requestId;
				return {
					dispatch: (message: BridgeWorkerMainToServerMessage): void => {
						dispatchedMessages.push(message);
					},
					dispose: (): void => {},
				};
			},
		});

		runtimeDispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				selectedItemId: 'item-source',
				selectedSource: 'user',
			}),
		);

		expect(receivedBootstrapRequestId).toBe('bootstrap-review-runtime');
		expect(dispatchedMessages).toEqual([
			expect.objectContaining({
				kind: 'command',
				command: 'select',
				requestId: 'request-select',
				selectedItemId: 'item-source',
			}),
		]);
	});

	test('disposes the real worker transport when the runtime dispatcher retires', () => {
		const reviewPackage = makeBridgeReviewPackage();
		let disposeCount = 0;
		const runtimeDispatcher = createBridgeReviewRuntimeProtocolDispatcher({
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			publishWorkerMessages: (): void => {},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
			transportFactory: () => {
				return {
					dispatch: (): void => {},
					dispose: (): void => {
						disposeCount += 1;
					},
				};
			},
		});

		runtimeDispatcher.dispose();

		expect(disposeCount).toBe(1);
	});

	test('routes worker Pierre render jobs through the courier instead of dropping them', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
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
			transferDescriptors: [
				{
					messageKind: 'pierreRenderJob',
					fieldPath: ['job', 'payload'],
					byteLength: job.payloadByteLength,
					mode: 'clone',
				},
			],
			kind: 'pierreRenderJob',
			job,
		} satisfies BridgeWorkerPierreRenderJobEvent;
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			enqueue: (receivedJob: BridgeWorkerPierreRenderJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
			},
		};

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages: [event],
			pierreCourier,
			renderSnapshotStore,
		});

		expect(enqueuedJobs).toEqual([job]);
		expect(
			(
				renderSnapshotStore.getSnapshot() as {
					readonly codeViewItemsById?: Readonly<Record<string, unknown>>;
				}
			).codeViewItemsById?.['item-1'],
		).toEqual(job.payload.item);
	});

	test('review worker courier returns typed receipts for worker Pierre jobs', () => {
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

		expect(createBridgeReviewWorkerPierreCourier().enqueue(job)).toEqual({
			status: 'enqueued',
			itemId: 'item-worker-courier',
			payloadByteLength: job.payloadByteLength,
			budgetClass: 'interactive',
		});
	});

	test('routes only slice patches into the render snapshot store', () => {
		const renderSnapshotStore = createBridgeMainRenderSnapshotStore();
		const enqueuedJobs: BridgeWorkerPierreRenderJob[] = [];
		const pierreCourier: BridgeWorkerPierreCourier = {
			enqueue: (receivedJob: BridgeWorkerPierreRenderJob) => {
				enqueuedJobs.push(receivedJob);
				return {
					status: 'enqueued',
					itemId: receivedJob.itemId,
					payloadByteLength: receivedJob.payloadByteLength,
					budgetClass: receivedJob.budgetClass,
				};
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
		] satisfies readonly BridgeWorkerServerToMainMessage[];

		applyBridgeWorkerMessagesToMainRenderSnapshotStore({
			messages,
			pierreCourier,
			renderSnapshotStore,
		});

		expect(renderSnapshotStore.getSnapshot().selectionSlice).toEqual({
			selectedItemId: 'item-2',
			source: 'user',
		});
		expect(enqueuedJobs).toEqual([]);
	});

	test('maps review package items into worker content metadata without package snapshots', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const contentItems = bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage);

		expect(contentItems).toHaveLength(1);
		expect(contentItems[0]).toMatchObject({
			itemId: 'item-source',
			path: 'Sources/App/View.swift',
			language: 'swift',
			cacheKey: 'item-source:base|item-source:head',
			sizeBytes: 1024,
			availableContentRoles: ['base', 'head'],
		});
		expect(JSON.stringify(contentItems)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|resourceUrl|endpointId/i,
		);
		expect(bridgeCommWorkerContentItemsFromReviewPackage(null)).toEqual([]);
	});

	test('maps review package handles into explicit worker content request descriptors', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const requestDescriptors =
			bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage);

		expect(requestDescriptors).toHaveLength(2);
		expect(requestDescriptors[0]).toMatchObject({
			itemId: 'item-source',
			role: 'base',
			reviewGeneration: 1,
			resourceUrl: 'agentstudio://resource/review/content/handle-item-source-base?generation=1',
			contentHash: 'sha256:item-source:base',
			language: 'swift',
			isBinary: false,
		});
		expect(JSON.stringify(requestDescriptors)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|endpointId|"cacheKey"|mimeType/i,
		);
		expect(bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(null)).toEqual([]);
	});

	test('maps review package items into worker render semantics without content handles', () => {
		const reviewPackage = makeBridgeReviewPackage();

		const renderSemantics = bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage);

		expect(renderSemantics).toHaveLength(1);
		expect(renderSemantics[0]).toMatchObject({
			itemId: 'item-source',
			itemKind: 'diff',
			changeKind: 'modified',
			displayPath: 'Sources/App/View.swift',
			basePath: 'Sources/App/View.swift',
			headPath: 'Sources/App/View.swift',
			language: 'swift',
		});
		expect(JSON.stringify(renderSemantics)).not.toMatch(
			/itemsById|orderedItemIds|summary|groups|"contentRoles"|resourceUrl|handleId|contentHash|endpointId/i,
		);
		expect(bridgeCommWorkerRenderSemanticsFromReviewPackage(null)).toEqual([]);
	});
});
