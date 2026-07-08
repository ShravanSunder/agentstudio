import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerDemandExecutionScheduleRequest,
} from './bridge-comm-worker-command-handler.js';
import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerReviewInvalidateCommand,
	encodeBridgeWorkerReviewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type {
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerReviewContentMetadata,
} from './bridge-worker-contracts.js';

interface ScheduledSelectedReviewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

interface ScheduledSelectedFileViewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

type ScheduledDemandExecution = Pick<
	BridgeCommWorkerDemandExecutionScheduleRequest,
	'affectedItemIds' | 'cause' | 'epoch'
>;

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

	test('review source update preserves worker state so path invalidation deletes stale paint', () => {
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

		handler.handleMessage(
			encodeBridgeWorkerReviewSourceUpdateCommand({
				requestId: 'request-source-update',
				epoch: 8,
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
			sequence: 32,
			patches: [
				{ slice: 'rowPaint', operation: 'delete', itemId: 'item-1' },
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
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		const replayMessages = handler.handleMessage(
			encodeBridgeWorkerViewportCommand({
				requestId: 'request-current',
				epoch: 9,
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
		const receivedSources: {
			readonly contentItems: readonly BridgeWorkerFileViewContentMetadata[];
			readonly contentRequestDescriptors: readonly { readonly resourceUrl: string }[];
		}[] = [];
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

		const messages = handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [
					{
						itemId: 'file-1',
						path: 'Sources/App/file-1.swift',
						handleId: 'handle-file-1',
						descriptorId: 'descriptor-file-1',
						resourceKind: 'worktree.fileContent',
						resourceUrl:
							'agentstudio://resource/worktree-file/worktree.fileContent/descriptor-file-1?cursor=cursor-file-1&generation=6',
						contentHash: 'sha256:file-1',
						contentHashAlgorithm: 'sha256',
						language: 'swift',
						sizeBytes: 128,
						maxBytes: 4096,
						isBinary: false,
					},
				],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source',
				status: 'ready',
			},
		]);
		expect(receivedSources[0]?.contentItems).toEqual([makeWorkerFileViewContentMetadata('file-1')]);
		expect(receivedSources[0]?.contentRequestDescriptors[0]?.resourceUrl).toMatch(
			/^agentstudio:\/\//,
		);
		expect(JSON.stringify(receivedSources[0]?.contentItems)).not.toMatch(
			/resourceUrl|contents|body/i,
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

		handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-no-visible-demand',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 6)],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

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
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		const messages = handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source',
				epoch: 2,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 2)],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

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
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source',
				status: 'ready',
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
		handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-before-select',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 6)],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

		const messages = handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-file-view',
				epoch: 7,
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
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);

		const messages = handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-repair',
				epoch: 2,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 2)],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

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
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source-repair',
				status: 'ready',
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

	test('file view source update labels source-reset terminal availability before health ack', () => {
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			createSequence: createSequenceFrom([71, 72, 73, 74]),
			scheduleSelectedReviewContentReadyPreparation: ignoreScheduledSelectedReviewPreparation,
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
		});
		handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-before-terminal-reset',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 6)],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);
		handler.handleMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-file-before-terminal-reset',
				epoch: 7,
				selectedItemId: 'file-1',
				selectedSource: 'user',
			}),
		);
		const selectedStore = scheduledFileViewPreparations[0]?.store;
		if (selectedStore === undefined) {
			throw new Error('Expected selected File View preparation store.');
		}
		selectedStore.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		selectedStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 81 });

		const messages = handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-terminal-reset',
				epoch: 8,
				contentItems: [
					{
						...makeWorkerFileViewContentMetadata('file-1'),
						canFetchContent: false,
						isBinary: true,
					},
				],
				contentRequestDescriptors: [],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'slicePatch',
				epoch: 8,
				sequence: 73,
				patches: [
					{ slice: 'rowPaint', operation: 'delete', itemId: 'file-1' },
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'file-1',
						payload: { reason: 'source_reset', state: 'unavailable' },
					},
				],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source-terminal-reset',
				status: 'ready',
			},
		]);
		expect(scheduledFileViewPreparations).toHaveLength(1);
	});

	test('file view source update does not schedule selected preparation when ready paint remains current', () => {
		const scheduledReviewPreparations: ScheduledSelectedReviewPreparation[] = [];
		const scheduledFileViewPreparations: ScheduledSelectedFileViewPreparation[] = [];
		const handler = createBridgeCommWorkerCommandHandler({
			contentItems: [],
			rows: [],
			createSequence: createSequenceFrom([81, 82, 83]),
			scheduleSelectedReviewContentReadyPreparation: pushScheduledSelectedReviewPreparation(
				scheduledReviewPreparations,
			),
			scheduleSelectedFileViewContentReadyPreparation: pushScheduledSelectedFileViewPreparation(
				scheduledFileViewPreparations,
			),
		});
		handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-before-ready',
				epoch: 6,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 6)],
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
		const selectedStore = scheduledFileViewPreparations[0]?.store;
		if (selectedStore === undefined) {
			throw new Error('Expected selected File View preparation store.');
		}
		selectedStore.actions.applyContentReady({
			itemId: 'file-1',
			contentCacheKey: 'file-view:sha256:file-1',
		});
		selectedStore.actions.takePendingSlicePatchEvent({ epoch: 7, sequence: 81 });
		scheduledFileViewPreparations.splice(0, scheduledFileViewPreparations.length);

		const messages = handler.handleMessage(
			encodeBridgeWorkerFileViewSourceUpdateCommand({
				requestId: 'request-file-source-same-ready',
				epoch: 7,
				contentItems: [makeWorkerFileViewContentMetadata('file-1')],
				contentRequestDescriptors: [makeWorkerFileViewContentRequestDescriptor('file-1', 6)],
				rows: [{ id: 'file-1', parentId: null, index: 0 }],
			}),
		);

		expect(messages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-file-source-same-ready',
				status: 'ready',
			},
		]);
		expect(scheduledReviewPreparations).toEqual([]);
		expect(scheduledFileViewPreparations).toEqual([]);
		expect(selectedStore.getState().availabilityByItemId.get('file-1')).toBe('ready');
	});
});

function pushScheduledSelectedReviewPreparation(
	target: ScheduledSelectedReviewPreparation[],
): (preparation: ScheduledSelectedReviewPreparation) => void {
	return (preparation: ScheduledSelectedReviewPreparation): void => {
		target.push(preparation);
	};
}

function ignoreScheduledSelectedReviewPreparation(
	_preparation: ScheduledSelectedReviewPreparation,
): void {}

function pushScheduledSelectedFileViewPreparation(
	target: ScheduledSelectedFileViewPreparation[],
): (preparation: ScheduledSelectedFileViewPreparation) => void {
	return (preparation: ScheduledSelectedFileViewPreparation): void => {
		target.push(preparation);
	};
}

function ignoreScheduledSelectedFileViewPreparation(
	_preparation: ScheduledSelectedFileViewPreparation,
): void {}

function pushScheduledDemandExecution(
	target: ScheduledDemandExecution[],
): (request: BridgeCommWorkerDemandExecutionScheduleRequest) => void {
	return (request: BridgeCommWorkerDemandExecutionScheduleRequest): void => {
		target.push({
			...(request.affectedItemIds === undefined
				? {}
				: { affectedItemIds: request.affectedItemIds }),
			cause: request.cause,
			epoch: request.epoch,
		});
	};
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

function makeWorkerFileViewContentMetadata(itemId: string): BridgeWorkerFileViewContentMetadata {
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		language: 'swift',
		cacheKey: `file-view:sha256:${itemId}`,
		sizeBytes: 128,
		contentHandle: `handle-${itemId}`,
		descriptorId: `descriptor-${itemId}`,
		contentHash: `sha256:${itemId}`,
		virtualizedExtentKind: 'exactLineCount',
		lineCount: 7,
		isBinary: false,
		canFetchContent: true,
	};
}

function makeWorkerFileViewContentRequestDescriptor(
	itemId: string,
	generation: number,
): {
	readonly itemId: string;
	readonly path: string;
	readonly handleId: string;
	readonly descriptorId: string;
	readonly resourceKind: 'worktree.fileContent';
	readonly resourceUrl: string;
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
	readonly language: string;
	readonly sizeBytes: number;
	readonly maxBytes: number;
	readonly isBinary: boolean;
} {
	return {
		itemId,
		path: `Sources/App/${itemId}.swift`,
		handleId: `handle-${itemId}`,
		descriptorId: `descriptor-${itemId}`,
		resourceKind: 'worktree.fileContent',
		resourceUrl: `agentstudio://resource/worktree-file/worktree.fileContent/descriptor-${itemId}?cursor=cursor-${itemId}&generation=${generation}`,
		contentHash: `sha256:${itemId}`,
		contentHashAlgorithm: 'sha256',
		language: 'swift',
		sizeBytes: 128,
		maxBytes: 4096,
		isBinary: false,
	};
}
