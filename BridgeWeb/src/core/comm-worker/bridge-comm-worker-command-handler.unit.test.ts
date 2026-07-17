import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerFileMetadataDemand,
	type BridgeCommWorkerFileViewRuntimeSource,
} from './bridge-comm-worker-command-handler.js';
import {
	createSequenceFrom,
	ignoreScheduledSelectedFileViewPreparation,
	ignoreScheduledSelectedReviewPreparation,
	makeWorkerFileViewContentMetadata,
	pushScheduledDemandExecution,
	pushScheduledSelectedFileViewPreparation,
	pushScheduledSelectedReviewPreparation,
	type ScheduledDemandExecution,
	type ScheduledSelectedFileViewPreparation,
	type ScheduledSelectedReviewPreparation,
} from './bridge-comm-worker-command-handler.test-support.js';
import {
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerRenderDispositionCommand,
	encodeBridgeWorkerReviewInvalidateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerReviewMetadataApplication } from './bridge-comm-worker-review-metadata-applicator.js';
import {
	makeContentRequestDescriptor,
	makeRenderSemantics,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeWorkerReviewContentMetadata } from './bridge-worker-contracts.js';

describe('Bridge comm worker command handler', () => {
	test('select command publishes loading availability and schedules selected preparation', () => {
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-2')],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
			],
			createSequence: (): number => 11,
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-2',
				selectedSource: 'user',
			}),
		);

		expect(messages).toHaveLength(2);
		expect(messages[0]).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 7,
			sequence: 11,
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'item-2' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-2',
					payload: { state: 'loading' },
				},
			],
		});
		expect(messages[1]).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-select',
			status: 'ready',
		});
		expect(scheduledPreparations).toHaveLength(1);
		expect(scheduledPreparations[0]?.itemId).toBe('item-2');
		expect(scheduledPreparations[0]?.store.getState().demandByKey.get('item-2')).toBe('selected:7');
		expect(JSON.stringify(messages)).not.toMatch(/rowById|orderedIds|rootSnapshot|allRows/i);
	});

	test('selected review content-ready follow-up is not emitted by the immediate select response', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			createSequence: (): number => 21,
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-immediate',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(messages.map((message) => message.kind)).toEqual(['slicePatch', 'health']);
		expect(JSON.stringify(messages)).not.toMatch(/pierreRenderJob/i);
		expect(JSON.stringify(messages)).not.toContain('"state":"ready"');
	});

	test('select command schedules selected review preparation through an injected hook only after local slice publication', () => {
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			createSequence: (): number => 22,
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-schedule',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(messages.map((message) => message.kind)).toEqual(['slicePatch', 'health']);
		expect(JSON.stringify(messages)).not.toMatch(/pierreRenderJob/i);
		expect(JSON.stringify(messages)).not.toContain('"state":"ready"');
		expect(scheduledPreparations).toHaveLength(1);
		expect(scheduledPreparations[0]?.itemId).toBe('item-1');
		expect(scheduledPreparations[0]?.epoch).toBe(7);
		expect(scheduledPreparations[0]?.store.getState().selectedId).toBe('item-1');
		expect(scheduledPreparations[0]?.store.getState().demandByKey.get('item-1')).toBe('selected:7');
	});

	test('select command does not schedule visible demand execution', () => {
		const scheduledVisibleDemand: ScheduledDemandExecution[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleDemandExecution: pushScheduledDemandExecution(scheduledVisibleDemand),
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-no-visible-demand',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(scheduledVisibleDemand).toEqual([]);
	});

	test('viewport command mutates worker-local store and publishes a typed viewport patch', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
				{ id: 'item-3', parentId: null, index: 2 },
			],
			createSequence: (): number => 12,
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-viewport',
				epoch: 8,
				surface: 'review',
				visibleItemIds: ['item-2', 'item-3'],
				firstVisibleIndex: 1,
				lastVisibleIndex: 2,
				phase: 'settled',
			}),
		);

		expect(messages).toHaveLength(2);
		expect(messages[0]).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 8,
			sequence: 12,
			patches: [
				{
					slice: 'viewport',
					operation: 'upsert',
					payload: {
						firstVisibleIndex: 1,
						lastVisibleIndex: 2,
						visibleItemIds: ['item-2', 'item-3'],
					},
				},
			],
		});
		expect(messages[1]).toMatchObject({
			kind: 'health',
			requestId: 'request-viewport',
			status: 'ready',
		});
		expect(JSON.stringify(messages)).not.toMatch(/rowById|orderedIds|rootSnapshot|allRows/i);
	});

	test('explicit interaction surfaces isolate File and Review demand side effects', () => {
		// Arrange
		const scheduledReviewPreparations: ScheduledSelectedReviewPreparation[] = [];
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const scheduledReviewDemand: ScheduledDemandExecution[] = [];
		const fileMetadataDemands: BridgeCommWorkerFileMetadataDemand[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('review-1')],
			rows: [{ id: 'review-1', parentId: null, index: 0 }],
			createSequence: (): number => 71,
			scheduleDemandExecution: pushScheduledDemandExecution(scheduledReviewDemand),
			scheduleSelectedReviewContentReadyPreparation: pushScheduledSelectedReviewPreparation(
				scheduledReviewPreparations,
			),
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
			updateFileMetadataDemand: (demand): void => {
				fileMetadataDemands.push(demand);
			},
		});
		handler.applyFileViewRuntimeSource({
			epoch: 1,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				filePathsByItemId: new Map([['file-1', 'Sources/App/file-1.swift']]),
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		// Act: File-targeted interactions must not enter Review demand lanes.
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-hostile-file-select',
				epoch: 2,
				surface: 'fileView',
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);
		handler.handleMessage(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-hostile-file-viewport',
				epoch: 3,
				surface: 'fileView',
				visibleItemIds: ['file-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);
		const fileDomainSideEffectsBeforeReview = {
			metadataDemandCount: fileMetadataDemands.length,
			preparationCount: scheduledFileViewPreparations.length,
		};

		// Act: Review-targeted interactions must not enter File demand lanes.
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-hostile-review-select',
				epoch: 4,
				surface: 'review',
				selectedItemId: 'review-1',
				selectedSource: 'user',
			}),
		);
		handler.handleMessage(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-hostile-review-viewport',
				epoch: 5,
				surface: 'review',
				visibleItemIds: ['review-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);

		// Assert
		expect(scheduledFileViewPreparations.map(({ itemId }) => itemId)).toEqual(['file-1']);
		expect(scheduledReviewPreparations.map(({ itemId }) => itemId)).toEqual(['review-1']);
		expect(scheduledReviewDemand).toEqual([{ cause: 'viewport', epoch: 5 }]);
		expect(fileDomainSideEffectsBeforeReview).toEqual({
			metadataDemandCount: 2,
			preparationCount: 1,
		});
		expect(fileMetadataDemands).toHaveLength(fileDomainSideEffectsBeforeReview.metadataDemandCount);
		expect(scheduledFileViewPreparations).toHaveLength(
			fileDomainSideEffectsBeforeReview.preparationCount,
		);
	});

	test('review invalidation command marks selected content stale and schedules refresh demand', () => {
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			createSequence: (): number => 23,
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-invalidate',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		const messages = handler.handleMessage(
			encodeBridgeWorkerReviewInvalidateCommand({
				requestId: 'request-invalidate',
				epoch: 8,
				itemIds: ['item-1'],
				pathHints: [],
				reason: 'watchEvent',
				scope: 'items',
			}),
		);

		expect(messages[0]).toMatchObject({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'slicePatch',
			epoch: 8,
			sequence: 23,
			patches: [
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'stale' },
				},
			],
		});
		expect(messages[1]).toMatchObject({
			kind: 'health',
			requestId: 'request-invalidate',
			status: 'ready',
		});
		expect(scheduledPreparations).toHaveLength(2);
		expect(scheduledPreparations[1]?.itemId).toBe('item-1');
		expect(scheduledPreparations[1]?.epoch).toBe(8);
		expect(scheduledPreparations[1]?.store.getState().demandByKey.get('item-1')).toBe('selected:8');
	});

	test('worker-owned Review metadata clears non-executable paint and preserves path state for later invalidation', () => {
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [
				makeWorkerReviewContentMetadata('item-1', {
					path: 'Sources/App/Before.swift',
				}),
			],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			createSequence: createSequenceFrom([31, 32, 33]),
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-source-update',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		const selectedStore = scheduledPreparations[0]?.store;
		if (selectedStore === undefined) {
			throw new Error('expected selected preparation store');
		}
		selectedStore.actions.applyContentReady({
			itemId: 'item-1',
			contentCacheKey: 'pierre-content:sha256:before',
		});
		selectedStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 41 });

		const metadataMessages = handler.applyReviewMetadataApplication(
			reviewMetadataApplication({
				sourceEpoch: 8,
				contentItems: [
					makeWorkerReviewContentMetadata('item-1', {
						path: 'Sources/App/After.swift',
					}),
				],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);
		expect(metadataMessages[0]).toMatchObject({
			kind: 'slicePatch',
			epoch: 8,
			sequence: 32,
			patches: [
				{ slice: 'rowPaint', operation: 'delete', itemId: 'item-1' },
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'stale' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'unavailable' },
				},
			],
		});
		const messages = handler.handleMessage(
			encodeBridgeWorkerReviewInvalidateCommand({
				requestId: 'request-invalidate-after-source-update',
				epoch: 9,
				itemIds: [],
				pathHints: ['Sources/App/After.swift'],
				reason: 'watchEvent',
				scope: 'paths',
			}),
		);

		expect(messages[0]).toMatchObject({
			kind: 'slicePatch',
			epoch: 9,
			sequence: 33,
			patches: [
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-1',
					payload: { state: 'stale' },
				},
			],
		});
		expect(scheduledPreparations.at(-1)?.epoch).toBe(9);
		expect(scheduledPreparations.at(-1)?.store.getState().demandByKey.get('item-1')).toBe(
			'selected:9',
		);
	});

	test('worker-owned Review metadata repairs executable selected demand from its selection epoch', () => {
		// Arrange
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const contentItems = [makeWorkerReviewContentMetadata('item-1')];
		const contentRequestDescriptors = [
			makeContentRequestDescriptor({
				generation: 8,
				itemId: 'item-1',
				role: 'base',
				text: 'base generation 8\n',
			}),
			makeContentRequestDescriptor({
				generation: 8,
				itemId: 'item-1',
				role: 'head',
				text: 'head generation 8\n',
			}),
		];
		const renderSemantics = [makeRenderSemantics({ itemId: 'item-1' })];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			createSequence: createSequenceFrom([34, 35]),
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		// Act
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-review-source',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		const repairedMessages = handler.applyReviewMetadataApplication(
			reviewMetadataApplication({
				sourceEpoch: 8,
				contentItems,
				contentRequestDescriptors,
				renderSemantics,
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
			}),
		);

		// Assert
		expect(repairedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 8,
				sequence: 35,
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: { state: 'loading' },
					},
				],
			},
		]);
		expect(scheduledPreparations).toHaveLength(1);
		expect(scheduledPreparations[0]?.itemId).toBe('item-1');
		expect(scheduledPreparations[0]?.epoch).toBe(7);
		expect(scheduledPreparations[0]?.store.getState().visibleIds).toEqual([]);
		expect(scheduledPreparations[0]?.store.getState().demandByKey.get('item-1')).toBe('selected:7');
	});

	test('Review metadata transaction rollback restores runtime source, store, and pending patches', () => {
		// Arrange
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const updatedRuntimeItemIds: string[][] = [];
		let scheduledResetCount = 0;
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-a')],
			rows: [{ id: 'item-a', parentId: null, index: 0 }],
			scheduleReviewMetadataReset: (): void => {
				scheduledResetCount += 1;
			},
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
			updateReviewRuntimeSource: (source): void => {
				updatedRuntimeItemIds.push(source.contentItems.map(({ itemId }) => itemId));
			},
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-transaction',
				epoch: 7,
				surface: 'review',
				selectedItemId: 'item-a',
				selectedSource: 'user',
			}),
		);
		const reviewStore = scheduledPreparations[0]?.store;
		if (reviewStore === undefined) throw new Error('expected selected Review store');
		reviewStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 41 });

		// Act
		const transaction = handler.prepareReviewMetadataApplication(
			reviewMetadataApplication({
				contentItems: [makeWorkerReviewContentMetadata('item-b')],
				contentRequestDescriptors: [],
				renderSemantics: [],
				reset: true,
				rows: [{ id: 'item-b', parentId: null, index: 0 }],
				sourceEpoch: 8,
			}),
		);
		expect([...reviewStore.getState().contentMetadataByItemId.keys()]).toEqual(['item-b']);
		transaction.rollback();

		// Assert
		expect(updatedRuntimeItemIds).toEqual([['item-b'], ['item-a']]);
		expect([...reviewStore.getState().contentMetadataByItemId.keys()]).toEqual(['item-a']);
		expect([...reviewStore.getState().rowById.keys()]).toEqual(['item-a']);
		expect(reviewStore.actions.takePendingSlicePatchEvent({ epoch: 8, sequence: 42 })).toBeNull();
		expect(scheduledResetCount).toBe(0);
	});

	test('unsupported commands return degraded health instead of silent success', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const commandMessages = [
			handler.handleMessage(
				encodeBridgeWorkerHoverCommand({
					requestId: 'request-hover',
					epoch: 1,
					surface: 'review',
					hoveredItemId: 'item-1',
				}),
			),
			handler.handleMessage(
				encodeBridgeWorkerModeCommand({
					requestId: 'request-mode',
					epoch: 1,
					mode: 'review',
				}),
			),
		];

		expect(commandMessages).toEqual([
			[
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'health',
					requestId: 'request-hover',
					status: 'degraded',
					message: 'Bridge comm worker command hover is not implemented.',
				},
			],
			[
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					transferDescriptors: [],
					kind: 'health',
					requestId: 'request-mode',
					status: 'degraded',
					message: 'Bridge comm worker command mode is not implemented.',
				},
			],
		]);
	});

	test('markFileViewed commands are accepted as worker-owned ordinary RPC intents', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed',
				epoch: 1,
				fileId: 'item-1',
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'ready',
			},
		]);
	});

	test('metadataInterestUpdate commands are accepted as worker-owned ordinary RPC intents', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 1,
				request: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 7,
					itemIds: ['item-1'],
					lane: 'foreground',
					loaded_by: 'foreground',
				},
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'ready',
			},
		]);
	});

	test('routes render dispositions to the matching worker-owned surface store', () => {
		const appliedStoreSelections: Array<string | null> = [];
		const handler = createBridgeCommWorkerCommandHandler({
			applyRenderDisposition: ({ command, store }) => {
				appliedStoreSelections.push(store.getState().selectedId);
				return [
					{
						direction: 'serverWorkerToMain',
						kind: 'health',
						requestId: command.requestId,
						status: 'ready',
						transferDescriptors: [],
						wireVersion: 1,
					},
				];
			},
			contentItems: [makeWorkerReviewContentMetadata('review-item-1')],
			rows: [{ id: 'review-item-1', parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				epoch: 5,
				requestId: 'request-select-review-before-disposition',
				selectedItemId: 'review-item-1',
				selectedSource: 'user',
				surface: 'review',
			}),
		);

		const messages = handler.handleMessage(
			encodeBridgeWorkerRenderDispositionCommand({
				epoch: 5,
				receipt: {
					attemptId: 'attempt-review-8',
					disposition: 'queued',
					itemId: 'review-item-1',
					kind: 'render.disposition',
					paneSessionId: 'pane-session-1',
					publicationId: 'publication-review-8',
					publicationSequence: 8,
					receivedAtMilliseconds: 42,
					submissionId: 'submission-review-8',
					surface: 'review',
					windowKey: 'window-review-8',
					workerDerivationEpoch: 5,
					workerInstanceId: 'worker-instance-1',
				},
				requestId: 'request-render-disposition-review',
			}),
		);

		expect(appliedStoreSelections).toEqual(['review-item-1']);
		expect(messages).toEqual([
			{
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-render-disposition-review',
				status: 'ready',
				transferDescriptors: [],
				wireVersion: 1,
			},
		]);
	});

	test('activeViewerModeUpdate commands are accepted as worker-owned ordinary RPC intents', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [makeWorkerReviewContentMetadata('item-1')],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode',
				epoch: 1,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 2,
					mode: 'review',
					activeSource: null,
				},
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'ready',
			},
		]);
	});

	test('stale and replayed commands are rejected before slice mutation', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [
				makeWorkerReviewContentMetadata('item-1'),
				makeWorkerReviewContentMetadata('item-2'),
			],
			rows: [
				{ id: 'item-1', parentId: null, index: 0 },
				{ id: 'item-2', parentId: null, index: 1 },
			],
			createSequence: (): number => 13,
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		expect(
			handler.handleMessage(
				encodeBridgeWorkerSelectCommand({
					requestId: 'request-current',
					epoch: 9,
					surface: 'review',
					selectedItemId: 'item-2',
					selectedSource: 'user',
				}),
			)[0],
		).toMatchObject({
			kind: 'slicePatch',
			epoch: 9,
		});

		const staleMessages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-stale',
				epoch: 8,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		const replayMessages = handler.handleMessage(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-current',
				epoch: 9,
				surface: 'review',
				visibleItemIds: ['item-1'],
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
			}),
		);

		expect(staleMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-stale',
				status: 'degraded',
				message: 'Bridge comm worker rejected stale epoch 8 after 9.',
			},
		]);
		expect(replayMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-current',
				status: 'degraded',
				message: 'Bridge comm worker rejected replayed request request-current.',
			},
		]);
		expect(JSON.stringify([...staleMessages, ...replayMessages])).not.toMatch(/slicePatch/i);
	});

	test('select command marks content unavailable when worker metadata is missing', () => {
		const scheduledPreparations: ScheduledSelectedReviewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [{ id: 'item-no-metadata', parentId: null, index: 0 }],
			createSequence: (): number => 14,
			scheduleSelectedReviewContentReadyPreparation:
				pushScheduledSelectedReviewPreparation(scheduledPreparations),
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-no-metadata',
				epoch: 10,
				surface: 'review',
				selectedItemId: 'item-no-metadata',
				selectedSource: 'user',
			}),
		);

		expect(messages[0]).toMatchObject({
			kind: 'slicePatch',
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'item-no-metadata' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'item-no-metadata',
					payload: { state: 'unavailable' },
				},
			],
		});
		expect(scheduledPreparations).toEqual([]);
	});

	test('file view source update command installs worker-local metadata without raw content', () => {
		const receivedSources: BridgeCommWorkerFileViewRuntimeSource[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			createSequence: (): number => 31,
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
			updateFileViewRuntimeSource: (source): void => {
				receivedSources.push(source);
			},
		});

		const messages = handler.applyFileViewRuntimeSource({
			epoch: 6,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		expect(messages).toEqual([]);
		expect(receivedSources[0]?.contentItems).toEqual([makeWorkerFileViewContentMetadata('file-1')]);
		expect(JSON.stringify(receivedSources[0]?.contentItems)).not.toMatch(
			/resourceUrl|contentHandle|contents|body/i,
		);
		expect(JSON.stringify(receivedSources)).not.toMatch(/contents|body/i);
	});

	test('file view source update does not schedule visible Review demand execution', () => {
		const scheduledVisibleDemand: ScheduledDemandExecution[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			scheduleDemandExecution: pushScheduledDemandExecution(scheduledVisibleDemand),
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});

		handler.applyFileViewRuntimeSource({
			epoch: 6,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		expect(scheduledVisibleDemand).toEqual([]);
	});

	test('file view source update command publishes availability repairs before health ack', () => {
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
			createSequence: createSequenceFrom([41, 42]),
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: ignoreScheduledSelectedFileViewPreparation,
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-file-metadata',
				epoch: 1,
				surface: 'fileView',
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		const messages = handler.applyFileViewRuntimeSource({
			epoch: 2,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 2,
				sequence: 42,
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { state: 'loading' },
					},
				],
			},
		]);
	});

	test('select command schedules selected File View preparation instead of Review preparation', () => {
		const scheduledReviewPreparations: ScheduledSelectedReviewPreparation[] = [];
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			createSequence: createSequenceFrom([51, 52]),
			scheduleSelectedReviewContentReadyPreparation: pushScheduledSelectedReviewPreparation(
				scheduledReviewPreparations,
			),
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
		});
		handler.applyFileViewRuntimeSource({
			epoch: 6,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-file-view',
				epoch: 7,
				surface: 'fileView',
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		expect(messages.map((message) => message.kind)).toEqual(['slicePatch', 'health']);
		expect(messages[0]).toMatchObject({
			kind: 'slicePatch',
			epoch: 7,
			sequence: 52,
			patches: [
				{
					slice: 'selection',
					operation: 'upsert',
					payload: { selectedItemId: 'file-1' },
				},
				{
					slice: 'contentAvailability',
					operation: 'upsert',
					itemId: 'file-1',
					payload: { state: 'loading' },
				},
			],
		});
		expect(scheduledReviewPreparations).toEqual([]);
		expect(scheduledFileViewPreparations).toHaveLength(1);
		expect(scheduledFileViewPreparations[0]?.itemId).toBe('file-1');
		expect(scheduledFileViewPreparations[0]?.epoch).toBe(7);
		expect(scheduledFileViewPreparations[0]?.store.getState().demandByKey.get('file-1')).toBe(
			'selected:7',
		);
	});

	test('file view source update schedules selected preparation when source repair restores selected demand', () => {
		const scheduledReviewPreparations: ScheduledSelectedReviewPreparation[] = [];
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [{ id: 'file-1', parentId: null, index: 0 }],
			createSequence: createSequenceFrom([61, 62]),
			scheduleSelectedReviewContentReadyPreparation: pushScheduledSelectedReviewPreparation(
				scheduledReviewPreparations,
			),
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
		});
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-file-source',
				epoch: 1,
				surface: 'fileView',
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		const messages = handler.applyFileViewRuntimeSource({
			epoch: 2,
			source: {
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequests: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			},
		});

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 2,
				sequence: 62,
				patches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { state: 'loading' },
					},
				],
			},
		]);
		expect(scheduledReviewPreparations).toEqual([]);
		expect(scheduledFileViewPreparations).toHaveLength(1);
		expect(scheduledFileViewPreparations[0]?.itemId).toBe('file-1');
		expect(scheduledFileViewPreparations[0]?.epoch).toBe(2);
		expect(scheduledFileViewPreparations[0]?.store.getState().demandByKey.get('file-1')).toBe(
			'selected:2',
		);
	});
});

function makeWorkerReviewContentMetadata(
	itemId: string,
	props: { readonly path?: string } = {},
): BridgeWorkerReviewContentMetadata {
	const item = makeBridgeReviewItem({
		itemId,
		path: props.path ?? `Sources/App/${itemId}.swift`,
	});
	return {
		itemId: item.itemId,
		path: item.headPath ?? item.basePath ?? item.itemId,
		language: item.language ?? null,
		cacheKey: item.cacheKey,
		sizeBytes: item.sizeBytes,
		availableContentRoles: ['head'],
		contentLineCountsByRole: item.contentLineCountsByRole ?? {},
	};
}

function reviewMetadataApplication(props: {
	readonly contentItems: BridgeCommWorkerReviewMetadataApplication['source']['contentItems'];
	readonly contentRequestDescriptors: BridgeCommWorkerReviewMetadataApplication['source']['contentRequestDescriptors'];
	readonly renderSemantics: BridgeCommWorkerReviewMetadataApplication['source']['renderSemantics'];
	readonly rows: BridgeCommWorkerReviewMetadataApplication['source']['rows'];
	readonly reset?: boolean;
	readonly sourceEpoch: number;
}): BridgeCommWorkerReviewMetadataApplication {
	return {
		affectedItemIds: props.contentItems.map((item) => item.itemId),
		affectedRowIds: props.rows.map((row) => row.id),
		completeContentItemIds: props.contentItems.map((item) => item.itemId),
		completeRowIds: props.rows.map((row) => row.id),
		projectionRevision: 1,
		removedItemIds: [],
		reset: props.reset ?? false,
		rowMutation: { removedRowIds: [], rowUpserts: props.rows },
		source: {
			contentItems: props.contentItems,
			contentRequestDescriptors: props.contentRequestDescriptors,
			renderSemantics: props.renderSemantics,
			rows: props.rows,
		},
		sourceEpoch: props.sourceEpoch,
		workerDerivationEpoch: 1,
	};
}
