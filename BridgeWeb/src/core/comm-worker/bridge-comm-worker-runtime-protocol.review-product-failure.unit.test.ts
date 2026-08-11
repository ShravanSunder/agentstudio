import { describe, expect, test } from 'vitest';

import { expectedEmptyReviewProjectionResetPatches } from './bridge-comm-worker-entry.test-support.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import { makeReviewProductTransport } from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';

describe('Bridge comm worker Review product source failure policy', () => {
	test('publishes a bounded Review display failure when the product subscription fails', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-failure',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: makeReviewProductTransport({
				reviewSubscription,
				subscribedKinds: [],
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();

		events.fail(new Error('private transport failure detail'), true);
		await flushBridgeWorkerRuntimeContinuations();

		const reviewDisplayEvents = postedMessages
			.map(({ message }) => message as unknown as Readonly<Record<string, unknown>>)
			.filter((message) => message['kind'] === 'reviewDisplayPatch');
		expect(reviewDisplayEvents.at(-1)).toMatchObject({
			kind: 'reviewDisplayPatch',
			patches: [
				{
					operation: 'failed',
					payload: { error: 'metadataUnavailable', status: 'failed' },
					slice: 'reviewSource',
				},
				...expectedEmptyReviewProjectionResetPatches(),
			],
			surface: 'review',
		});
		expect(JSON.stringify(reviewDisplayEvents)).not.toContain('private transport failure detail');
	});
});
