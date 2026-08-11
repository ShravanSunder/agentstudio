import { describe, expect, test } from 'vitest';

import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionOptions,
} from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

describe('Bridge comm worker Review product bootstrap', () => {
	test('opens canonical Review metadata with empty interests before selection', async () => {
		// Arrange
		const subscriptions: Array<{
			readonly kind: 'review.metadata';
			readonly options: BridgeProductSubscriptionOptions<'review.metadata'>;
		}> = [];
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events: new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'review.metadata'>>(
				1,
			),
			subscriptionId: 'review-bootstrap-subscription',
			subscriptionKind: 'review.metadata',
			update: async (): Promise<void> => {},
		};
		const { dispatch } = createRecordingBridgeCommWorkerPort();

		// Act
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
			productTransport: productTransportRecordingReviewBootstrap({
				reviewSubscription,
				subscriptions,
			}),
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(subscriptions).toEqual([
			{
				kind: 'review.metadata',
				options: { interests: [] },
			},
		]);
	});
});

function productTransportRecordingReviewBootstrap(props: {
	readonly reviewSubscription: BridgeProductSubscription<'review.metadata'>;
	readonly subscriptions: Array<{
		readonly kind: 'review.metadata';
		readonly options: BridgeProductSubscriptionOptions<'review.metadata'>;
	}>;
}): BridgeProductTransportSession {
	let reviewEpoch = 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'review') reviewEpoch += 1;
			return surface === 'review' ? reviewEpoch : 0;
		},
		call: async (): Promise<never> => ({ reason: 'notConfigured', status: 'unavailable' }) as never,
		openContent: (): never => {
			throw new Error('Review bootstrap must not open content.');
		},
		subscribe: (...arguments_): never => {
			const [kind, options] = arguments_;
			if (kind !== 'review.metadata') {
				throw new Error(`Unexpected product subscription ${kind}.`);
			}
			props.subscriptions.push({ kind, options });
			return props.reviewSubscription as never;
		},
		workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
	};
}
