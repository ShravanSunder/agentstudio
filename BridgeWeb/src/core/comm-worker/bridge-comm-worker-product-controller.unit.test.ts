import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
} from './bridge-product-async-queue.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT,
	type BridgeProductSubscriptionEvent,
	type BridgeProductSubscriptionOptions,
} from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

const source = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge comm worker product controller', () => {
	test('opens one Review metadata subscription and reconciles lane interests in the comm worker', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const updates: Array<Parameters<BridgeProductSubscription<'review.metadata'>['update']>[0]> =
			[];
		const observedEvents: BridgeProductSubscriptionEvent<'review.metadata'>[] = [];
		const observedEpochs: number[] = [];
		let reviewEpoch = 0;
		let subscriptionOptions: unknown = null;
		const reviewSubscription: BridgeProductSubscription<'review.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			update: async (options): Promise<void> => {
				updates.push(options);
			},
		};
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewMetadataEvent: (event, workerDerivationEpoch): void => {
				observedEvents.push(event);
				observedEpochs.push(workerDerivationEpoch);
			},
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (surface): number => {
					if (surface === 'review') reviewEpoch += 1;
					return surface === 'review' ? reviewEpoch : 0;
				},
				workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
			},
			subscribeReview: (options) => {
				subscriptionOptions = options;
				return reviewSubscription;
			},
		});

		// Act
		await controller.updateReviewMetadataInterests({
			itemIds: ['item-selected'],
			lane: 'foreground',
			protocol: 'review',
		});
		await controller.updateReviewMetadataInterests({
			itemIds: ['item-selected', 'item-visible'],
			lane: 'visible',
			protocol: 'review',
		});
		await controller.updateReviewMetadataInterests({
			itemIds: [],
			lane: 'foreground',
			protocol: 'review',
		});
		await controller.updateReviewMetadataInterests({
			itemIds: [],
			lane: 'visible',
			protocol: 'review',
		});
		const sourceAcceptedEvent = {
			eventKind: 'review.sourceAccepted',
			generation: 7,
			packageId: 'package-1',
			publicationId: '00000000-0000-7000-8000-000000000011',
			revision: 11,
			sourceIdentity: 'query-1',
		} as const;
		events.push(sourceAcceptedEvent);
		await Promise.resolve();

		// Assert
		expect(reviewEpoch).toBe(1);
		expect(subscriptionOptions).toEqual({
			interests: [{ itemIds: ['item-selected'], lane: 'foreground' }],
		});
		expect(updates).toEqual([
			{
				interests: [
					{ itemIds: ['item-selected'], lane: 'foreground' },
					{ itemIds: ['item-visible'], lane: 'visible' },
				],
			},
			{
				interests: [{ itemIds: ['item-selected', 'item-visible'], lane: 'visible' }],
			},
			{ interests: [] },
		]);
		expect(observedEvents).toEqual([sourceAcceptedEvent]);
		expect(observedEpochs).toEqual([1]);
	});

	test('opens one canonical Review subscription for empty interests and keeps it open', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(1);
		let derivationEpochBumpCount = 0;
		let subscribeReviewCallCount = 0;
		let subscriptionOptions: BridgeProductSubscriptionOptions<'review.metadata'> | null = null;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (): number => {
					derivationEpochBumpCount += 1;
					return derivationEpochBumpCount;
				},
			},
			subscribeReview: (options) => {
				subscribeReviewCallCount += 1;
				subscriptionOptions = options;
				return {
					cancel: async (): Promise<void> => {},
					events,
					subscriptionId: 'review-empty-interest-subscription',
					subscriptionKind: 'review.metadata',
					update: async (): Promise<void> => {},
				};
			},
		});

		// Act
		await controller.updateReviewMetadataInterests({
			itemIds: [],
			lane: 'foreground',
			protocol: 'review',
		});
		await controller.updateReviewMetadataInterests({
			itemIds: [],
			lane: 'visible',
			protocol: 'review',
		});

		// Assert
		expect(subscribeReviewCallCount).toBe(1);
		expect(derivationEpochBumpCount).toBe(1);
		expect(subscriptionOptions).toEqual({ interests: [] });
	});

	test('cancels and reopens Review with the same interests after application failure', async () => {
		const firstEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const secondEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const subscriptionOptions: BridgeProductSubscriptionOptions<'review.metadata'>[] = [];
		let cancelCount = 0;
		let subscriptionCount = 0;
		let reviewEpoch = 0;
		const reopened = createBridgeProductDeferred<void>();
		const subscriptions: readonly BridgeProductSubscription<'review.metadata'>[] = [
			{
				cancel: async (): Promise<void> => {
					cancelCount += 1;
				},
				events: firstEvents,
				subscriptionId: 'review-application-failure-1',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
			{
				cancel: async (): Promise<void> => {},
				events: secondEvents,
				subscriptionId: 'review-application-failure-2',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
		];
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewMetadataEvent: (): never => {
				throw new Error('injected Review application failure');
			},
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (surface): number => {
					if (surface === 'review') reviewEpoch += 1;
					return surface === 'review' ? reviewEpoch : 0;
				},
				workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
			},
			subscribeReview: (options) => {
				subscriptionOptions.push(options);
				const subscription = subscriptions[subscriptionCount];
				if (subscription === undefined) throw new Error('Unexpected third Review subscription.');
				subscriptionCount += 1;
				if (subscriptionCount === 2) reopened.resolve();
				return subscription;
			},
		});
		await controller.updateReviewMetadataInterests({
			itemIds: ['item-selected'],
			lane: 'foreground',
			protocol: 'review',
		});

		firstEvents.push({
			eventKind: 'review.sourceAccepted',
			generation: 7,
			packageId: 'package-1',
			publicationId: '00000000-0000-7000-8000-000000000011',
			revision: 11,
			sourceIdentity: 'query-1',
		});
		await reopened.promise;

		expect(cancelCount).toBe(1);
		expect(reviewEpoch).toBe(2);
		expect(subscriptionOptions).toEqual([
			{ interests: [{ itemIds: ['item-selected'], lane: 'foreground' }] },
			{ interests: [{ itemIds: ['item-selected'], lane: 'foreground' }] },
		]);
	});

	test('sends the exact Review publication receipt after worker application', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const calls: Array<{ readonly method: string; readonly request: unknown }> = [];
		const receiptSent = createBridgeProductDeferred<void>();
		let reviewEpoch = 0;
		const publicationId = '00000000-0000-7000-8000-000000000011';
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewMetadataEvent: (): { readonly publicationId: string } => ({ publicationId }),
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (surface): number => {
					if (surface === 'review') reviewEpoch += 1;
					return surface === 'review' ? reviewEpoch : 0;
				},
				call: async (...arguments_): Promise<never> => {
					const [method, request] = arguments_;
					calls.push({ method, request });
					receiptSent.resolve();
					// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This fake accepts only the asserted null-result receipt call recorded above.
					return null as never;
				},
				workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
			},
			subscribeReview: () => ({
				cancel: async (): Promise<void> => {},
				events,
				subscriptionId: 'review-exact-publication-receipt',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			}),
		});
		controller.ensureReviewMetadata();

		events.push({
			eventKind: 'review.sourceAccepted',
			generation: 7,
			packageId: 'package-1',
			publicationId,
			revision: 11,
			sourceIdentity: 'source-1',
		});
		await receiptSent.promise;

		expect(calls).toEqual([{ method: 'review.publication.applied', request: { publicationId } }]);
	});

	test('bounds failed receipt recovery to one Review-only reopen while File keeps draining', async () => {
		const firstReviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const replayReviewEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.metadata'>
		>(64);
		const fileEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const secondReviewOpened = createBridgeProductDeferred<void>();
		const secondReviewCancelled = createBridgeProductDeferred<void>();
		const fileEventObserved = createBridgeProductDeferred<void>();
		const publicationId = '00000000-0000-7000-8000-000000000011';
		let reviewEpoch = 0;
		let reviewSubscriptionCount = 0;
		let receiptCallCount = 0;
		let fileCancelCount = 0;
		const reviewCancelCounts = [0, 0];
		const reviewSubscriptions: readonly BridgeProductSubscription<'review.metadata'>[] = [
			{
				cancel: async (): Promise<void> => {
					reviewCancelCounts[0] = (reviewCancelCounts[0] ?? 0) + 1;
				},
				events: firstReviewEvents,
				subscriptionId: 'review-receipt-failure-1',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
			{
				cancel: async (): Promise<void> => {
					reviewCancelCounts[1] = (reviewCancelCounts[1] ?? 0) + 1;
					secondReviewCancelled.resolve();
				},
				events: replayReviewEvents,
				subscriptionId: 'review-receipt-failure-2',
				subscriptionKind: 'review.metadata',
				update: async (): Promise<void> => {},
			},
		];
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataEvent: (): void => {
				fileEventObserved.resolve();
			},
			onReviewMetadataEvent: (): { readonly publicationId: string } => ({ publicationId }),
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (surface): number => {
					if (surface === 'review') reviewEpoch += 1;
					return surface === 'review' ? reviewEpoch : 1;
				},
				call: async (...arguments_): Promise<never> => {
					const [method] = arguments_;
					if (method === 'review.publication.applied') {
						receiptCallCount += 1;
						throw new Error('injected receipt transport failure');
					}
					throw new Error(`Unexpected product call ${method}.`);
				},
				workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 1),
			},
			subscribeFile: () => ({
				cancel: async (): Promise<void> => {
					fileCancelCount += 1;
				},
				events: fileEvents,
				subscriptionId: 'file-preserved-through-review-receipt-failure',
				subscriptionKind: 'file.metadata',
				update: async (): Promise<void> => {},
			}),
			subscribeReview: () => {
				const subscription = reviewSubscriptions[reviewSubscriptionCount];
				if (subscription === undefined) throw new Error('Unexpected third Review subscription.');
				reviewSubscriptionCount += 1;
				if (reviewSubscriptionCount === 2) secondReviewOpened.resolve();
				return subscription;
			},
		});
		await controller.ensureFileSource();
		controller.ensureReviewMetadata();

		firstReviewEvents.push({
			eventKind: 'review.sourceAccepted',
			generation: 7,
			packageId: 'package-1',
			publicationId,
			revision: 11,
			sourceIdentity: 'source-1',
		});
		await secondReviewOpened.promise;
		fileEvents.push({ eventKind: 'file.sourceAccepted', source });
		await fileEventObserved.promise;
		replayReviewEvents.push({
			eventKind: 'review.sourceAccepted',
			generation: 7,
			packageId: 'package-1',
			publicationId,
			revision: 11,
			sourceIdentity: 'source-1',
		});
		await secondReviewCancelled.promise;

		expect(receiptCallCount).toBe(2);
		expect(reviewSubscriptionCount).toBe(2);
		expect(reviewCancelCounts).toEqual([1, 1]);
		expect(fileCancelCount).toBe(0);
	});

	test('retains early File demand and reconciles it after one discovered source opens', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const sourceDiscovery = createDeferredFileSourceDiscovery();
		const updates: unknown[] = [];
		let discoveryCallCount = 0;
		let derivationEpochBumpCount = 0;
		let subscriptionCount = 0;
		let resolveDemandReapplication = (): void => {};
		const demandReapplied = new Promise<void>((resolve): void => {
			resolveDemandReapplication = resolve;
		});
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCallCount += 1;
				return await sourceDiscovery.promise;
			},
			onFileMetadataEvent: (): void => {},
			productTransport: productTransportWithFileEpochBump((): void => {
				derivationEpochBumpCount += 1;
			}),
			subscribeFile: (options) => {
				subscriptionCount += 1;
				expect(options).toEqual({
					interests: [],
					pathScope: [],
					source: currentFileSourceConfiguration,
				});
				return {
					cancel: async (): Promise<void> => {},
					events,
					subscriptionId: 'discovered-file-subscription',
					subscriptionKind: 'file.metadata',
					update: async (options): Promise<void> => {
						updates.push(options);
						resolveDemandReapplication();
					},
				};
			},
		});

		const firstEnsure = controller.ensureFileSource();
		const secondEnsure = controller.ensureFileSource();
		await controller.updateFileMetadataDemand({
			epoch: 1,
			nearbyPaths: ['Sources/Nearby-Old.swift'],
			selectedPath: 'Sources/Selected-Old.swift',
			visiblePaths: ['Sources/Visible-Old.swift'],
		});
		await controller.updateFileMetadataDemand({
			epoch: 2,
			nearbyPaths: ['Sources/Nearby.swift'],
			selectedPath: 'Sources/Selected.swift',
			visiblePaths: ['Sources/Visible.swift'],
		});
		expect(subscriptionCount).toBe(0);

		sourceDiscovery.resolve({ source: currentFileSourceConfiguration, status: 'available' });
		await Promise.all([firstEnsure, secondEnsure]);
		events.push({ eventKind: 'file.sourceAccepted', source });
		await demandReapplied;

		expect(discoveryCallCount).toBe(1);
		expect(derivationEpochBumpCount).toBe(1);
		expect(subscriptionCount).toBe(1);
		expect(updates).toEqual([
			{
				interests: [
					{ lane: 'foreground', paths: ['Sources/Selected.swift'] },
					{ lane: 'visible', paths: ['Sources/Visible.swift'] },
					{ lane: 'nearby', paths: ['Sources/Nearby.swift'] },
				],
				pathScope: [],
			},
		]);
	});

	test('continues draining File metadata while an interest barrier is pending', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		let releaseInterestUpdate = (): void => {};
		const pendingInterestUpdate = new Promise<void>((resolve): void => {
			releaseInterestUpdate = resolve;
		});
		const observedEvents: BridgeProductSubscriptionEvent<'file.metadata'>[] = [];
		let resolveAllEventsObserved = (): void => {};
		const allEventsObserved = new Promise<void>((resolve): void => {
			resolveAllEventsObserved = resolve;
		});
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-pending-barrier',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => await pendingInterestUpdate,
		};
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataEvent: (event): void => {
				observedEvents.push(event);
				if (observedEvents.length === 66) resolveAllEventsObserved();
			},
			productTransport: unusedProductTransport(),
			subscribeFile: () => subscription,
		});
		await controller.ensureFileSource();
		const demandUpdate = controller.updateFileMetadataDemand({
			epoch: 1,
			nearbyPaths: [],
			selectedPath: 'Sources/File.swift',
			visiblePaths: [],
		});
		events.push({ eventKind: 'file.sourceAccepted', source });
		for (let index = 0; index < 65; index += 1) {
			events.push({
				eventKind: 'file.treeWindow',
				finalWindow: index === 64,
				lineage: { lane: 'foreground', loadedBy: 'startup_window' },
				pathScope: [],
				rows: [],
				source,
				startIndex: index,
				totalRowCount: index === 64 ? 0 : null,
			});
			await Promise.resolve();
		}

		await allEventsObserved;
		expect(observedEvents).toHaveLength(66);
		releaseInterestUpdate();
		await demandUpdate;
	});

	test('settles unavailable File discovery once without subscribing or retrying', async () => {
		let discoveryCallCount = 0;
		let derivationEpochBumpCount = 0;
		let subscriptionCount = 0;
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCallCount += 1;
				return { reason: 'no-file-source-authority', status: 'unavailable' };
			},
			onFileMetadataEvent: (): void => {},
			productTransport: productTransportWithFileEpochBump((): void => {
				derivationEpochBumpCount += 1;
			}),
			subscribeFile: (): never => {
				subscriptionCount += 1;
				throw new Error('Unavailable discovery must not subscribe.');
			},
		});

		await Promise.all([controller.ensureFileSource(), controller.ensureFileSource()]);
		await controller.updateFileMetadataDemand({
			epoch: 4,
			nearbyPaths: ['Sources/Nearby.swift'],
			selectedPath: 'Sources/Selected.swift',
			visiblePaths: ['Sources/Visible.swift'],
		});
		await controller.ensureFileSource();

		expect(discoveryCallCount).toBe(1);
		expect(derivationEpochBumpCount).toBe(0);
		expect(subscriptionCount).toBe(0);
	});

	test('opens File metadata and replaces worker-owned selected demand without another native RPC path', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const updates: unknown[] = [];
		const observedEvents: BridgeProductSubscriptionEvent<'file.metadata'>[] = [];
		const observedEpochs: number[] = [];
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
			update: async (options): Promise<void> => {
				updates.push(options);
			},
		};
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataEvent: (event, workerDerivationEpoch): void => {
				observedEvents.push(event);
				observedEpochs.push(workerDerivationEpoch);
				if (event.eventKind === 'file.sourceAccepted') resolveSourceAccepted();
			},
			productTransport: unusedProductTransport(),
			subscribeFile: () => subscription,
		});

		// Act
		await controller.ensureFileSource();
		events.push({ eventKind: 'file.sourceAccepted', source });
		await sourceAccepted;
		await controller.updateFileMetadataDemand({
			epoch: 1,
			nearbyPaths: [],
			selectedPath: 'Sources/File.swift',
			visiblePaths: [],
		});
		await controller.updateFileMetadataDemand({
			epoch: 2,
			nearbyPaths: [],
			selectedPath: 'Sources/Other.swift',
			visiblePaths: [],
		});
		await controller.updateFileMetadataDemand({
			epoch: 1,
			nearbyPaths: [],
			selectedPath: 'Sources/Stale.swift',
			visiblePaths: [],
		});

		// Assert
		expect(observedEvents).toEqual([{ eventKind: 'file.sourceAccepted', source }]);
		expect(observedEpochs).toEqual([1]);
		expect(updates).toEqual([
			{
				interests: [{ lane: 'foreground', paths: ['Sources/File.swift'] }],
				pathScope: [],
			},
			{
				interests: [{ lane: 'foreground', paths: ['Sources/Other.swift'] }],
				pathScope: [],
			},
		]);
	});

	test('deduplicates selected, visible, and nearby paths by demand priority', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const updates: unknown[] = [];
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-priority',
			subscriptionKind: 'file.metadata',
			update: async (options): Promise<void> => {
				updates.push(options);
			},
		};
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataEvent: (event): void => {
				if (event.eventKind === 'file.sourceAccepted') resolveSourceAccepted();
			},
			productTransport: unusedProductTransport(),
			subscribeFile: () => subscription,
		});
		await controller.ensureFileSource();
		events.push({ eventKind: 'file.sourceAccepted', source });
		await sourceAccepted;

		await controller.updateFileMetadataDemand({
			epoch: 1,
			selectedPath: 'Sources/Selected.swift',
			visiblePaths: ['Sources/Selected.swift', 'Sources/Visible.swift'],
			nearbyPaths: ['Sources/Visible.swift', 'Sources/Nearby.swift'],
		});

		expect(updates).toEqual([
			{
				interests: [
					{ lane: 'foreground', paths: ['Sources/Selected.swift'] },
					{ lane: 'visible', paths: ['Sources/Visible.swift'] },
					{ lane: 'nearby', paths: ['Sources/Nearby.swift'] },
				],
				pathScope: [],
			},
		]);
	});

	test('bounds aggregate File interests while retaining selected priority', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const updates: Array<Parameters<BridgeProductSubscription<'file.metadata'>['update']>[0]> = [];
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-bounded',
			subscriptionKind: 'file.metadata',
			update: async (options): Promise<void> => {
				updates.push(options);
			},
		};
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataEvent: (event): void => {
				if (event.eventKind === 'file.sourceAccepted') resolveSourceAccepted();
			},
			productTransport: unusedProductTransport(),
			subscribeFile: () => subscription,
		});
		await controller.ensureFileSource();
		events.push({ eventKind: 'file.sourceAccepted', source });
		await sourceAccepted;

		await controller.updateFileMetadataDemand({
			epoch: 1,
			selectedPath: 'Sources/Selected.swift',
			visiblePaths: Array.from(
				{ length: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT },
				(_unused, index) => `Sources/Visible-${index}.swift`,
			),
			nearbyPaths: ['Sources/Nearby.swift'],
		});

		const interests = updates[0]?.interests ?? [];
		expect(interests[0]).toEqual({
			lane: 'foreground',
			paths: ['Sources/Selected.swift'],
		});
		expect(interests.reduce((count, interest) => count + interest.paths.length, 0)).toBe(
			BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT,
		);
		expect(interests.some((interest) => interest.paths.includes('Sources/Nearby.swift'))).toBe(
			false,
		);
	});

	test('reports File interest update failures and permits a same-demand retry', async () => {
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const failures: Array<{ readonly error: unknown; readonly epoch: number }> = [];
		const updates: unknown[] = [];
		let shouldRejectUpdate = true;
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-update-failure',
			subscriptionKind: 'file.metadata',
			update: async (options): Promise<void> => {
				if (shouldRejectUpdate) {
					shouldRejectUpdate = false;
					throw new Error('interest update failed');
				}
				updates.push(options);
			},
		};
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataDemandFailure: (error, epoch): void => {
				failures.push({ epoch, error });
			},
			onFileMetadataEvent: (event): void => {
				if (event.eventKind === 'file.sourceAccepted') resolveSourceAccepted();
			},
			productTransport: unusedProductTransport(),
			subscribeFile: () => subscription,
		});
		await controller.ensureFileSource();
		events.push({ eventKind: 'file.sourceAccepted', source });
		await sourceAccepted;
		const demand = {
			epoch: 1,
			nearbyPaths: [],
			selectedPath: 'Sources/File.swift',
			visiblePaths: [],
		} as const;

		await expect(controller.updateFileMetadataDemand(demand)).rejects.toThrow(
			/interest update failed/i,
		);
		await controller.updateFileMetadataDemand(demand);

		expect(failures).toEqual([{ epoch: 1, error: expect.any(Error) }]);
		expect(updates).toEqual([
			{
				interests: [{ lane: 'foreground', paths: ['Sources/File.swift'] }],
				pathScope: [],
			},
		]);
	});

	test('reports an active File metadata subscription that ends unexpectedly', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(64);
		const subscription: BridgeProductSubscription<'file.metadata'> = {
			cancel: async (): Promise<void> => {},
			events,
			subscriptionId: 'file-subscription-ended',
			subscriptionKind: 'file.metadata',
			update: async (): Promise<void> => {},
		};
		let resolveFailure = (_error: unknown): void => {};
		const failure = new Promise<unknown>((resolve): void => {
			resolveFailure = resolve;
		});
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: discoverCurrentFileSource,
			onFileMetadataFailure: (error): void => {
				resolveFailure(error);
			},
			onFileMetadataEvent: (): void => {},
			productTransport: unusedProductTransport(),
			subscribeFile: () => subscription,
		});

		// Act
		await controller.ensureFileSource();
		events.close(true);

		// Assert
		await expect(failure).resolves.toEqual(expect.any(Error));
		expect(((await failure) as Error).message).toMatch(/ended unexpectedly/i);
	});
});

function unusedProductTransport(): BridgeProductTransportSession {
	let fileEpoch = 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			return surface === 'file' ? fileEpoch : 0;
		},
		call: async (): Promise<never> => {
			throw new Error('Unexpected product call.');
		},
		openContent: (): never => {
			throw new Error('Unexpected content open.');
		},
		subscribe: (): never => {
			throw new Error('Unexpected direct subscription.');
		},
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : 0),
	};
}

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: source.repoId,
	rootPathToken: 'root-token-1',
	worktreeId: source.worktreeId,
} as const;

function createDeferredFileSourceDiscovery(): {
	readonly promise: Promise<
		| { readonly source: typeof currentFileSourceConfiguration; readonly status: 'available' }
		| { readonly reason: 'no-file-source-authority'; readonly status: 'unavailable' }
	>;
	readonly resolve: (
		result:
			| { readonly source: typeof currentFileSourceConfiguration; readonly status: 'available' }
			| { readonly reason: 'no-file-source-authority'; readonly status: 'unavailable' },
	) => void;
} {
	let resolveDiscovery: (
		result:
			| { readonly source: typeof currentFileSourceConfiguration; readonly status: 'available' }
			| { readonly reason: 'no-file-source-authority'; readonly status: 'unavailable' },
	) => void = (): void => {};
	const promise = new Promise<
		| { readonly source: typeof currentFileSourceConfiguration; readonly status: 'available' }
		| { readonly reason: 'no-file-source-authority'; readonly status: 'unavailable' }
	>((resolve): void => {
		resolveDiscovery = resolve;
	});
	return { promise, resolve: resolveDiscovery };
}

function productTransportWithFileEpochBump(onBump: () => void): BridgeProductTransportSession {
	let fileEpoch = 0;
	return {
		...unusedProductTransport(),
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') {
				fileEpoch += 1;
				onBump();
			}
			return surface === 'file' ? fileEpoch : 0;
		},
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : 0),
	};
}

function discoverCurrentFileSource(): Promise<{
	readonly source: typeof currentFileSourceConfiguration;
	readonly status: 'available';
}> {
	return Promise.resolve({ source: currentFileSourceConfiguration, status: 'available' });
}
