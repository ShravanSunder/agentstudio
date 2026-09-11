import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { makeReviewProductTransport } from './bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import type {
	BridgeProductMetadataApplicationEvent,
	BridgeProductMetadataDataFrame,
} from './bridge-product-metadata-application-protocol.js';
import { bridgeProductReviewMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import { BridgeProductSubscriptionResetError } from './bridge-product-subscription-state.js';
import type { BridgeProductMetadataApplicationSubscription } from './bridge-product-transport-contract.js';

type ReviewMetadataProtocol = typeof bridgeProductReviewMetadataApplicationProtocol;
type ReviewMetadataEvent = BridgeProductMetadataApplicationEvent<ReviewMetadataProtocol>;
type ReviewMetadataFrame = BridgeProductMetadataDataFrame<ReviewMetadataEvent>;
type ReviewMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<ReviewMetadataProtocol>;

const reviewRecoveryControls: readonly BridgeProductControlCommand[] = [
	{ method: 'review.comparisonTargets.query', params: {} },
	{
		method: 'review.comparison.update',
		params: { target: { basis: 'commonCommit', kind: 'branch', name: 'origin/main' } },
	},
];

describe('Bridge comm worker Review metadata recovery', () => {
	test('a current Review subscription reset reopens once without another UI action', async () => {
		// Arrange
		const firstEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(8);
		const replacementEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(8);
		const subscriptions = [
			reviewSubscription('review-before-reset', firstEvents),
			reviewSubscription('review-after-reset', replacementEvents),
		] as const;
		let subscriptionCount = 0;
		let failureCount = 0;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewMetadataFailure: (): void => {
				failureCount += 1;
			},
			productTransport: makeReviewProductTransport({
				calledMethods: [],
				onCall: (): null => null,
				reviewSubscription: subscriptions[0],
				subscribedKinds: [],
			}),
			subscribeReview: () => {
				const subscription = subscriptions[subscriptionCount];
				if (subscription === undefined) throw new Error('Unbounded Review reset recovery.');
				subscriptionCount += 1;
				return subscription;
			},
		});
		controller.ensureReviewMetadata();
		try {
			// Act / Assert — retry a terminal reset, but stop if the new subscription makes no progress.
			firstEvents.fail(new BridgeProductSubscriptionResetError('stale_source'), true);
			await expect.poll(() => subscriptionCount, { timeout: 250 }).toBe(2);
			replacementEvents.fail(new BridgeProductSubscriptionResetError('stale_source'), true);
			await expect.poll(() => failureCount, { timeout: 250 }).toBe(2);
			expect(subscriptionCount).toBe(2);
		} finally {
			firstEvents.close(true);
			replacementEvents.close(true);
		}
	});

	test.each(reviewRecoveryControls)(
		'reopens failed Review metadata before $method control',
		async (command) => {
			// Arrange
			const firstEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(8);
			const replacementEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(8);
			const observedFailure = makeDeferred<void>();
			const subscriptions = [
				reviewSubscription('review-subscription-before-failure', firstEvents),
				reviewSubscription('review-subscription-after-failure', replacementEvents),
			] as const;
			let subscriptionCount = 0;
			const calledMethods: string[] = [];
			const controller = new BridgeCommWorkerProductController({
				onFileMetadataEvent: (): void => {},
				onReviewMetadataFailure: (): void => observedFailure.resolve(),
				productTransport: makeReviewProductTransport({
					calledMethods,
					onCall: (): null => null,
					reviewSubscription: subscriptions[0],
					subscribedKinds: [],
				}),
				subscribeReview: () => {
					const subscription = subscriptions[subscriptionCount];
					if (subscription === undefined) throw new Error('Unexpected third Review subscription.');
					subscriptionCount += 1;
					return subscription;
				},
			});
			controller.ensureReviewMetadata();
			firstEvents.fail(
				Object.assign(new Error('metadata acknowledgement timed out'), {
					failureCode: 'request_timeout',
				}),
				true,
			);
			await observedFailure.promise;
			expect(subscriptionCount).toBe(2);

			// Act
			await controller.sendProductControl(command);

			// Assert
			expect(subscriptionCount).toBe(2);
			expect(calledMethods).toEqual([command.method]);
		},
	);
});

function reviewSubscription(
	subscriptionId: string,
	events: BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>,
): ReviewMetadataSubscription {
	return {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId,
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
}

function makeDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
} {
	let resolvePromise: ((value: TValue) => void) | undefined;
	const promise = new Promise<TValue>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (value): void => resolvePromise?.(value),
	};
}
