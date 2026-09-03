import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type {
	BridgeProductMetadataApplicationEvent,
	BridgeProductMetadataDataFrame,
} from './bridge-product-metadata-application-protocol.js';
import { bridgeProductReviewMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import type { BridgeProductSubscriptionOptions } from './bridge-product-subscription-contracts.js';
import type { BridgeProductMetadataApplicationSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

type ReviewMetadataProtocol = typeof bridgeProductReviewMetadataApplicationProtocol;
type ReviewMetadataEvent = BridgeProductMetadataApplicationEvent<ReviewMetadataProtocol>;
type ReviewMetadataFrame = BridgeProductMetadataDataFrame<ReviewMetadataEvent>;
type ReviewMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<ReviewMetadataProtocol>;

describe('Bridge comm worker product controller Review interests', () => {
	test('atomically replaces all worker-owned Review demand roles and suppresses an equal snapshot', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(1);
		const updates: Array<Parameters<ReviewMetadataSubscription['update']>[0]> = [];
		let reviewEpoch = 0;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			productTransport: reviewEpochTransport({
				currentEpoch: (): number => reviewEpoch,
				incrementEpoch: (): number => (reviewEpoch += 1),
			}),
			subscribeReview: () => ({
				cancel: async (): Promise<void> => {},
				events,
				subscriptionId: 'review-worker-demand-subscription',
				subscriptionKind: 'review.metadata',
				update: async (options): Promise<void> => {
					updates.push(options);
				},
			}),
		});
		controller.ensureReviewMetadata();
		const snapshot = {
			activeDemand: [
				{ itemId: 'selected', role: 'selected' },
				{ itemId: 'visible', role: 'visible' },
				{ itemId: 'nearby', role: 'nearby' },
				{ itemId: 'speculative', role: 'speculative' },
				{ itemId: 'background', role: 'background' },
			] as const,
			workerDerivationEpoch: 1,
		};

		// Act
		await controller.replaceReviewMetadataInterestsFromActiveDemand(snapshot);
		await controller.replaceReviewMetadataInterestsFromActiveDemand(snapshot);

		// Assert
		expect(updates).toEqual([
			{
				interests: [
					{ itemIds: ['selected'], lane: 'foreground' },
					{ itemIds: ['visible'], lane: 'visible' },
					{ itemIds: ['nearby'], lane: 'nearby' },
					{ itemIds: ['speculative'], lane: 'speculative' },
					{ itemIds: ['background'], lane: 'idle' },
				],
			},
		]);
	});

	test('reopens failed Review interest authority empty before accepting a fresh snapshot', async () => {
		// Arrange
		const firstEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(1);
		const secondEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(1);
		const subscriptionOptions: BridgeProductSubscriptionOptions<'review.metadata'>[] = [];
		const secondUpdates: Array<Parameters<ReviewMetadataSubscription['update']>[0]> = [];
		let cancelCount = 0;
		let failureCount = 0;
		let reviewEpoch = 0;
		let subscriptionIndex = 0;
		const authorityChanges: Array<number | null> = [];
		const subscriptions: readonly ReviewMetadataSubscription[] = [
			{
				cancel: async (): Promise<void> => {
					cancelCount += 1;
				},
				events: firstEvents,
				subscriptionId: 'review-interest-failure-1',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {
					throw new Error('injected Review interest failure');
				},
			},
			{
				cancel: async (): Promise<void> => {},
				events: secondEvents,
				subscriptionId: 'review-interest-failure-2',
				subscriptionKind: 'review.metadata',
				update: async (options): Promise<void> => {
					secondUpdates.push(options);
				},
			},
		];
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewWorkerDerivationEpochChanged: (workerDerivationEpoch): void => {
				authorityChanges.push(workerDerivationEpoch);
			},
			onReviewMetadataFailure: (): void => {
				failureCount += 1;
			},
			productTransport: reviewEpochTransport({
				currentEpoch: (): number => reviewEpoch,
				incrementEpoch: (): number => (reviewEpoch += 1),
			}),
			subscribeReview: (options) => {
				subscriptionOptions.push(options);
				const subscription = subscriptions[subscriptionIndex];
				if (subscription === undefined) throw new Error('Unexpected Review subscription.');
				subscriptionIndex += 1;
				return subscription;
			},
		});
		controller.ensureReviewMetadata();

		// Act / Assert
		await expect(
			controller.replaceReviewMetadataInterestsFromActiveDemand({
				activeDemand: [{ itemId: 'selected-before-failure', role: 'selected' }],
				workerDerivationEpoch: 1,
			}),
		).rejects.toThrow('injected Review interest failure');
		expect(cancelCount).toBe(1);
		expect(failureCount).toBe(1);
		expect(reviewEpoch).toBe(2);
		expect(authorityChanges).toEqual([1, null, 2]);
		expect(subscriptionOptions).toEqual([{ interests: [] }, { interests: [] }]);

		await controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [{ itemId: 'visible-after-reopen', role: 'visible' }],
			workerDerivationEpoch: 2,
		});
		expect(secondUpdates).toEqual([
			{ interests: [{ itemIds: ['visible-after-reopen'], lane: 'visible' }] },
		]);
		firstEvents.close(true);
		secondEvents.close(true);
	});

	test('rejects queued interest commits when their subscription authority retires', async () => {
		// Arrange
		const firstEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(1);
		const secondEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(1);
		const firstUpdate = createBridgeProductDeferred<void>();
		const secondSubscriptionUpdates: Array<Parameters<ReviewMetadataSubscription['update']>[0]> =
			[];
		let reviewEpoch = 0;
		let subscriptionIndex = 0;
		const subscriptions: readonly ReviewMetadataSubscription[] = [
			{
				cancel: async (): Promise<void> => {},
				events: firstEvents,
				subscriptionId: 'review-queued-interest-failure-1',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => await firstUpdate.promise,
			},
			{
				cancel: async (): Promise<void> => {},
				events: secondEvents,
				subscriptionId: 'review-queued-interest-failure-2',
				subscriptionKind: 'review.metadata',
				update: async (options): Promise<void> => {
					secondSubscriptionUpdates.push(options);
				},
			},
		];
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			productTransport: reviewEpochTransport({
				currentEpoch: (): number => reviewEpoch,
				incrementEpoch: (): number => (reviewEpoch += 1),
			}),
			subscribeReview: () => {
				const subscription = subscriptions[subscriptionIndex];
				if (subscription === undefined) throw new Error('Unexpected Review subscription.');
				subscriptionIndex += 1;
				return subscription;
			},
		});
		controller.ensureReviewMetadata();

		// Act
		const firstCommit = controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [{ itemId: 'selected-before-failure', role: 'selected' }],
			workerDerivationEpoch: 1,
		});
		const queuedCommit = controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [{ itemId: 'visible-before-failure', role: 'visible' }],
			workerDerivationEpoch: 1,
		});
		firstUpdate.reject(new Error('retire first Review interest authority'));

		// Assert
		await expect(firstCommit).rejects.toThrow('retire first Review interest authority');
		await expect(queuedCommit).rejects.toThrow('retired Review interest authority');
		expect(reviewEpoch).toBe(2);
		expect(secondSubscriptionUpdates).toEqual([]);
		firstEvents.close(true);
		secondEvents.close(true);
	});
});

function reviewEpochTransport(props: {
	readonly currentEpoch: () => number;
	readonly incrementEpoch: () => number;
}): BridgeProductTransportSession {
	return {
		bumpWorkerDerivationEpoch: (surface): number =>
			surface === 'review' ? props.incrementEpoch() : 0,
		call: async (): Promise<never> => {
			throw new Error('Unexpected product call.');
		},
		openContent: (): never => {
			throw new Error('Unexpected content open.');
		},
		subscribe: (): never => {
			throw new Error('Unexpected direct subscription.');
		},
		workerDerivationEpoch: (surface): number => (surface === 'review' ? props.currentEpoch() : 0),
	};
}
