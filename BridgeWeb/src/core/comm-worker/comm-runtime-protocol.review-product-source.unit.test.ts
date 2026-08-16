import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerMetadataInterestUpdateCommand } from './bridge-comm-worker-protocol.js';
import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from './bridge-comm-worker-runtime-protocol.js';
import { reviewSnapshotEvent } from './bridge-comm-worker-runtime-protocol.review-product-fixtures.test-support.js';
import { makeReviewProductTransport } from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import {
	activateBridgeCommWorkerReviewViewerMode,
	createBridgeCommWorkerReviewProductTestSource,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';

describe('Bridge comm worker Review product source projection', () => {
	test('projects typed Review subscription snapshots into worker-owned source truth', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const subscribedKinds: string[] = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeReviewProductTransport({ reviewSubscription, subscribedKinds }),
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'source-truth');

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				epoch: 1,
				request: {
					generation: 7,
					itemIds: ['item-1'],
					lane: 'foreground',
					loaded_by: 'foreground',
					protocol: 'review',
					streamId: 'review-stream-1',
				},
				requestId: 'request-review-interest-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		expect(subscribedKinds).toEqual(['file.annotations', 'review.annotations', 'review.metadata']);
		events.push(reviewSnapshotEvent);
		await flushBridgeWorkerRuntimeContinuations();

		expect(scheduledDrains).toHaveLength(1);
		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(reviewDisplayEvents).toHaveLength(1);
		expect(reviewDisplayEvents[0]).toMatchObject({
			epoch: 1,
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'upsert',
					payload: {
						metadataWindowIdentity: JSON.stringify([
							'bridge-review-metadata-window-v1',
							'source-1',
							7,
							'00000000-0000-7000-8000-000000000011',
							11,
						]),
						status: 'ready',
						totalItemCount: 1,
						totalTreeRowCount: 1,
					},
					slice: 'reviewSource',
				},
				expect.objectContaining({ operation: 'replace', slice: 'reviewComparison' }),
				expect.objectContaining({ operation: 'batch', slice: 'reviewItem' }),
				expect.objectContaining({ operation: 'batch', slice: 'reviewTree' }),
			],
			projectionRevision: 1,
			surface: 'review',
		});
		expect(JSON.stringify(reviewDisplayEvents)).not.toMatch(
			/"(?:capability|resourceUrl|contents|contentBody|sourceBytes)"/i,
		);
	});

	test('publishes a ready empty Review source when the snapshot has no changed files', async () => {
		const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
		const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: reviewProductSource.productTransport,
			schedulePreparationDrain: (drain): void => {
				scheduledDrains.push(drain);
			},
		});
		activateBridgeCommWorkerReviewViewerMode(dispatch, 'empty-source');

		dispatch.message(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				epoch: 1,
				request: {
					generation: 1,
					itemIds: [],
					lane: 'foreground',
					loaded_by: 'foreground',
					protocol: 'review',
					streamId: 'review-stream-empty-source',
				},
				requestId: 'request-review-interest-empty-source',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		reviewProductSource.publishSource(
			{
				contentItems: [],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [],
			},
			7,
		);
		await flushBridgeWorkerRuntimeContinuations();

		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(scheduledDrains).toHaveLength(1);
		expect(reviewDisplayEvents).toHaveLength(1);
		expect(reviewDisplayEvents[0]).toMatchObject({
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'upsert',
					payload: {
						status: 'ready',
						totalItemCount: 0,
						totalTreeRowCount: 0,
					},
					slice: 'reviewSource',
				},
				{ operation: 'replace', payload: null, slice: 'reviewComparison' },
				{
					operation: 'batch',
					payload: { items: [], operations: [], reset: true },
					slice: 'reviewItem',
				},
				{
					operation: 'batch',
					payload: { reset: true, windows: [{ rows: [] }] },
					slice: 'reviewTree',
				},
			],
			epoch: 1,
			surface: 'review',
		});
		reviewProductSource.close();
	});
});
