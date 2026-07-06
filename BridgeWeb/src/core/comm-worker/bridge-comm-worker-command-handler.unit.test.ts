import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
import {
	encodeBridgeWorkerHoverCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerModeCommand,
	encodeBridgeWorkerReviewInvalidateCommand,
	encodeBridgeWorkerReviewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerStore } from './bridge-comm-worker-store.js';
import type { BridgeWorkerReviewContentMetadata } from './bridge-worker-contracts.js';

interface ScheduledSelectedReviewPreparation {
	readonly epoch: number;
	readonly itemId: string;
	readonly store: BridgeCommWorkerStore;
}

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
				encodeBridgeWorkerMarkFileViewedCommand({
					requestId: 'request-mark-viewed',
					epoch: 1,
					filePathHash: 'file-hash',
					viewedAtSequence: 5,
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
					requestId: 'request-mark-viewed',
					status: 'degraded',
					message: 'Bridge comm worker command markFileViewed is not implemented.',
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
