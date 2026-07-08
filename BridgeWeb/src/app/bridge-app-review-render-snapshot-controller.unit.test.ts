import { parseDiffFromFile } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerSelectCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
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
import type { BridgeTelemetryBootstrapConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import {
	applyBridgeWorkerMessagesToMainRenderSnapshotStore,
	bridgeCommWorkerBootstrapRequestFromReviewRuntimeProps,
	bridgeCommWorkerContentRequestDescriptorsFromReviewPackage,
	bridgeCommWorkerContentItemsFromReviewPackage,
	bridgeCommWorkerRenderSemanticsFromReviewPackage,
	createBridgeReviewWorkerPierreCourier,
	createBridgeReviewRuntimeProtocolDispatcher,
	createVisibleBridgeCodeViewItemsSelector,
	selectedContentAvailabilityForReviewPackage,
	selectedBridgeCodeViewItemForReviewPackage,
	visibleBridgeCodeViewItemsForReviewPackage,
} from './bridge-app-review-render-snapshot-controller.js';
import { resolveBridgeWorkerMarkFileViewedFailureCallbacks } from './bridge-app-review-worker-health-resolvers.js';

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

	test('passes cloneable telemetry config into the worker bootstrap request', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const telemetryConfig: BridgeTelemetryBootstrapConfig = {
			enabledScopes: new Set(['web']),
			endpointUrl: 'agentstudio://telemetry/batch',
			maxEncodedBatchBytes: 16_384,
			maxSamplesPerBatch: 4,
			minimumFlushIntervalMilliseconds: 250,
			scenario: 'bridge-review',
			viewerOpenEpochUnixMillis: 1_783_430_000_000,
			viewerOpenTraceparent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00',
		};

		const bootstrapRequest = bridgeCommWorkerBootstrapRequestFromReviewRuntimeProps({
			requestId: 'bootstrap-review-runtime',
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			publishWorkerMessages: (): void => {},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
			telemetryConfig,
		});

		expect(bootstrapRequest.runtime.telemetryConfig).toEqual({
			enabledScopes: ['web'],
			endpointUrl: 'agentstudio://telemetry/batch',
			maxEncodedBatchBytes: 16_384,
			maxSamplesPerBatch: 4,
			minimumFlushIntervalMilliseconds: 250,
			scenario: 'bridge-review',
		});
		expect(JSON.stringify(bootstrapRequest.runtime.telemetryConfig)).not.toContain(
			'viewerOpenTraceparent',
		);
		expect(JSON.stringify(bootstrapRequest.runtime.telemetryConfig)).not.toContain(
			'viewerOpenEpochUnixMillis',
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

	test('dispatches mark-viewed review commands through the real worker transport seam', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];
		const runtimeDispatcher = createBridgeReviewRuntimeProtocolDispatcher({
			bootstrapRequestId: 'bootstrap-review-runtime',
			contentItems: bridgeCommWorkerContentItemsFromReviewPackage(reviewPackage),
			contentRequestDescriptors:
				bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(reviewPackage),
			publishWorkerMessages: (): void => {},
			renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(reviewPackage),
			rows: [{ id: 'item-source', parentId: null, index: 0 }],
			transportFactory: () => ({
				dispatch: (message: BridgeWorkerMainToServerMessage): void => {
					dispatchedMessages.push(message);
				},
				dispose: (): void => {},
			}),
		});

		runtimeDispatcher.dispatch(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed',
				epoch: 7,
				fileId: 'item-source',
			}),
		);

		expect(dispatchedMessages).toEqual([
			expect.objectContaining({
				kind: 'command',
				command: 'markFileViewed',
				requestId: 'request-mark-viewed',
				fileId: 'item-source',
			}),
		]);
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

	test('selected CodeView selector rejects stale same-item package rollover content', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewItem = reviewPackage.itemsById['item-source'];
		const currentHeadHandle = reviewItem?.contentRoles.head;
		if (reviewItem === undefined || currentHeadHandle === null || currentHeadHandle === undefined) {
			throw new Error('expected item-source head handle');
		}
		const selectedCodeViewItem = makeSelectedCodeViewItem({
			cacheKey:
				'pierre-content:fixture-preview:sha256:item-source:base|pierre-content:fixture-preview:sha256:item-source:head',
		});
		const changedHeadHandle = {
			...currentHeadHandle,
			contentHash: 'sha256:item-source:head:new',
		};
		const changedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'item-source': {
					...reviewItem,
					contentRoles: {
						...reviewItem.contentRoles,
						head: changedHeadHandle,
					},
					headContentHash: changedHeadHandle.contentHash,
				},
			},
		};

		expect(
			selectedBridgeCodeViewItemForReviewPackage({
				codeViewItemsById: { 'item-source': selectedCodeViewItem },
				reviewPackage,
				selectedItemId: 'item-source',
			}),
		).toBe(selectedCodeViewItem);
		expect(
			selectedBridgeCodeViewItemForReviewPackage({
				codeViewItemsById: { 'item-source': selectedCodeViewItem },
				reviewPackage: changedPackage,
				selectedItemId: 'item-source',
			}),
		).toBeNull();
	});

	test('visible CodeView selector keeps fresh non-selected worker-prepared items', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const reviewItem = reviewPackage.itemsById['item-source'];
		const currentHeadHandle = reviewItem?.contentRoles.head;
		if (reviewItem === undefined || currentHeadHandle === null || currentHeadHandle === undefined) {
			throw new Error('expected item-source head handle');
		}
		const visibleCodeViewItem = makeSelectedCodeViewItem({
			cacheKey:
				'pierre-content:fixture-preview:sha256:item-source:base|pierre-content:fixture-preview:sha256:item-source:head',
		});
		const changedHeadHandle = {
			...currentHeadHandle,
			contentHash: 'sha256:item-source:head:new',
		};
		const changedPackage = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				'item-source': {
					...reviewItem,
					contentRoles: {
						...reviewItem.contentRoles,
						head: changedHeadHandle,
					},
					headContentHash: changedHeadHandle.contentHash,
				},
			},
		};

		expect(
			visibleBridgeCodeViewItemsForReviewPackage({
				codeViewItemsById: { 'item-source': visibleCodeViewItem },
				reviewPackage,
				visibleItemIds: ['item-source'],
			}),
		).toEqual([visibleCodeViewItem]);
		expect(
			visibleBridgeCodeViewItemsForReviewPackage({
				codeViewItemsById: { 'item-source': visibleCodeViewItem },
				reviewPackage: changedPackage,
				visibleItemIds: ['item-source'],
			}),
		).toEqual([]);
	});

	test('visible CodeView selector memoizes unchanged visible worker-prepared item references', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const visibleCodeViewItem = makeSelectedCodeViewItem({
			cacheKey:
				'pierre-content:fixture-preview:sha256:item-source:base|pierre-content:fixture-preview:sha256:item-source:head',
		});
		const changedCodeViewItem = {
			...visibleCodeViewItem,
			version: (visibleCodeViewItem.version ?? 0) + 1,
		};
		const selector = createVisibleBridgeCodeViewItemsSelector();

		const firstSelection = selector({
			codeViewItemsById: { 'item-source': visibleCodeViewItem },
			reviewPackage,
			visibleItemIds: ['item-source'],
		});
		const secondSelection = selector({
			codeViewItemsById: { 'item-source': visibleCodeViewItem },
			reviewPackage,
			visibleItemIds: ['item-source'],
		});
		const changedSelection = selector({
			codeViewItemsById: { 'item-source': changedCodeViewItem },
			reviewPackage,
			visibleItemIds: ['item-source'],
		});

		expect(secondSelection).toBe(firstSelection);
		expect(changedSelection).not.toBe(firstSelection);
		expect(changedSelection).toEqual([changedCodeViewItem]);
	});

	test('selected availability treats stale ready worker content as loading across package rollover', () => {
		expect(
			selectedContentAvailabilityForReviewPackage({
				rawAvailability: { state: 'ready' },
				selectedCodeViewItem: null,
			}),
		).toEqual({ state: 'loading' });
		expect(
			selectedContentAvailabilityForReviewPackage({
				rawAvailability: { state: 'ready' },
				selectedCodeViewItem: makeSelectedCodeViewItem({
					cacheKey:
						'pierre-content:fixture-preview:sha256:item-source:base|pierre-content:fixture-preview:sha256:item-source:head',
				}),
			}),
		).toEqual({ state: 'ready' });
		expect(
			selectedContentAvailabilityForReviewPackage({
				rawAvailability: { state: 'failed' },
				selectedCodeViewItem: null,
			}),
		).toEqual({ state: 'failed' });
		expect(
			selectedContentAvailabilityForReviewPackage({
				rawAvailability: { state: 'unavailable' },
				selectedCodeViewItem: null,
			}),
		).toEqual({ state: 'unavailable' });
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

	test('preserves inexact review handle byte caps in worker request descriptors', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const sourceItem = reviewPackage.itemsById['item-source'];
		const baseHandle = sourceItem?.contentRoles.base ?? null;
		if (sourceItem === undefined || baseHandle === null) {
			throw new Error('Expected fixture review package to include base content');
		}
		const packageWithInexactBase = {
			...reviewPackage,
			itemsById: {
				...reviewPackage.itemsById,
				[sourceItem.itemId]: {
					...sourceItem,
					contentRoles: {
						...sourceItem.contentRoles,
						base: {
							...baseHandle,
							sizeBytes: 4,
							sizeBytesIsExact: false,
							maxBytes: 64,
						},
					},
				},
			},
		};

		const requestDescriptors =
			bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(packageWithInexactBase);
		const baseDescriptor = requestDescriptors.find((descriptor) => descriptor.role === 'base');

		expect(baseDescriptor).toMatchObject({
			itemId: 'item-source',
			role: 'base',
			sizeBytes: 4,
			maxBytes: 64,
		});
		expect(baseDescriptor).not.toHaveProperty('expectedBytes');
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

function makeSelectedCodeViewItem(props: { readonly cacheKey: string }): BridgeMainCodeViewItem {
	const fileDiff = parseDiffFromFile(
		{
			name: 'Sources/App/View.swift',
			contents: 'let before = 1\n',
			cacheKey: 'pierre-content:fixture-preview:sha256:item-source:base',
		},
		{
			name: 'Sources/App/View.swift',
			contents: 'let after = 2\n',
			cacheKey: 'pierre-content:fixture-preview:sha256:item-source:head',
		},
	);
	fileDiff.cacheKey = props.cacheKey;
	return {
		id: 'item-source',
		type: 'diff',
		fileDiff,
		version: 2,
		bridgeMetadata: {
			itemId: 'item-source',
			displayPath: 'Sources/App/View.swift',
			contentState: 'hydrated',
			contentRoles: ['base', 'head'],
			cacheKey: props.cacheKey,
			lineCount: 2,
		},
	};
}
