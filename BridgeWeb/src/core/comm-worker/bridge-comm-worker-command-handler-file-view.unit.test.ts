import { describe, expect, test } from 'vitest';

import { createBridgeCommWorkerCommandHandler } from './bridge-comm-worker-command-handler.js';
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
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';

describe('Bridge comm worker File View command handler', () => {
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
