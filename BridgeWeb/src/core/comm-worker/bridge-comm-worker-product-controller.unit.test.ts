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
import {
	bridgeProductFileMetadataApplicationProtocol,
	bridgeProductReviewMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT,
	type BridgeProductSubscriptionOptions,
} from './bridge-product-subscription-contracts.js';
import type { BridgeProductMetadataApplicationSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

type FileMetadataProtocol = typeof bridgeProductFileMetadataApplicationProtocol;
type FileMetadataEvent = BridgeProductMetadataApplicationEvent<FileMetadataProtocol>;
type FileMetadataFrame = BridgeProductMetadataDataFrame<FileMetadataEvent>;
type FileMetadataSubscription = BridgeProductMetadataApplicationSubscription<FileMetadataProtocol>;
type ReviewMetadataProtocol = typeof bridgeProductReviewMetadataApplicationProtocol;
type ReviewMetadataEvent = BridgeProductMetadataApplicationEvent<ReviewMetadataProtocol>;
type ReviewMetadataFrame = BridgeProductMetadataDataFrame<ReviewMetadataEvent>;
type ReviewMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<ReviewMetadataProtocol>;

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
		const events = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(64);
		const updates: Array<Parameters<ReviewMetadataSubscription['update']>[0]> = [];
		const observedEvents: ReviewMetadataEvent[] = [];
		const observedEpochs: number[] = [];
		let reviewEpoch = 0;
		let subscriptionOptions: unknown = null;
		const reviewSubscription: ReviewMetadataSubscription = {
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
		controller.ensureReviewMetadata();
		await controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [{ itemId: 'item-selected', role: 'selected' }],
			workerDerivationEpoch: 1,
		});
		await controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [
				{ itemId: 'item-selected', role: 'selected' },
				{ itemId: 'item-visible', role: 'visible' },
			],
			workerDerivationEpoch: 1,
		});
		await controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [{ itemId: 'item-visible', role: 'visible' }],
			workerDerivationEpoch: 1,
		});
		await controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [],
			workerDerivationEpoch: 1,
		});
		const sourceAcceptedEvent = {
			eventKind: 'review.sourceAccepted',
			operationCorrelationId: null,
			generation: 7,
			packageId: 'package-1',
			publicationId: '00000000-0000-7000-8000-000000000011',
			revision: 11,
			sourceIdentity: 'query-1',
		} as const;
		events.push(reviewMetadataFrame(sourceAcceptedEvent));
		await Promise.resolve();

		// Assert
		expect(reviewEpoch).toBe(1);
		expect(subscriptionOptions).toEqual({ interests: [] });
		expect(updates).toEqual([
			{ interests: [{ itemIds: ['item-selected'], lane: 'foreground' }] },
			{
				interests: [
					{ itemIds: ['item-selected'], lane: 'foreground' },
					{ itemIds: ['item-visible'], lane: 'visible' },
				],
			},
			{ interests: [{ itemIds: ['item-visible'], lane: 'visible' }] },
			{ interests: [] },
		]);
		expect(observedEvents).toEqual([sourceAcceptedEvent]);
		expect(observedEpochs).toEqual([1]);
	});

	test('opens one canonical Review subscription for empty interests and keeps it open', async () => {
		// Arrange
		const events = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(1);
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
		controller.ensureReviewMetadata();

		// Assert
		expect(subscribeReviewCallCount).toBe(1);
		expect(derivationEpochBumpCount).toBe(1);
		expect(subscriptionOptions).toEqual({ interests: [] });
	});

	test('cancels and reopens Review with empty interests after application failure', async () => {
		const firstEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(64);
		const secondEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(64);
		const subscriptionOptions: BridgeProductSubscriptionOptions<'review.metadata'>[] = [];
		let cancelCount = 0;
		let subscriptionCount = 0;
		let reviewEpoch = 0;
		const reopened = createBridgeProductDeferred<void>();
		const subscriptions: readonly ReviewMetadataSubscription[] = [
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
		controller.ensureReviewMetadata();
		await controller.replaceReviewMetadataInterestsFromActiveDemand({
			activeDemand: [{ itemId: 'item-selected', role: 'selected' }],
			workerDerivationEpoch: 1,
		});

		firstEvents.push(
			reviewMetadataFrame({
				eventKind: 'review.sourceAccepted',
				operationCorrelationId: null,
				generation: 7,
				packageId: 'package-1',
				publicationId: '00000000-0000-7000-8000-000000000011',
				revision: 11,
				sourceIdentity: 'query-1',
			}),
		);
		await reopened.promise;

		expect(cancelCount).toBe(1);
		expect(reviewEpoch).toBe(2);
		expect(subscriptionOptions).toEqual([{ interests: [] }, { interests: [] }]);
	});

	test('does not send a Review publication receipt after worker metadata application', async () => {
		const events = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(64);
		const calls: Array<{ readonly method: string; readonly request: unknown }> = [];
		const allMetadataApplied = createBridgeProductDeferred<void>();
		let metadataApplicationCount = 0;
		let reviewEpoch = 0;
		const publicationId = '00000000-0000-7000-8000-000000000011';
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewMetadataEvent: (event): { readonly publicationId: string } => {
				metadataApplicationCount += 1;
				if (metadataApplicationCount === 2) allMetadataApplied.resolve();
				return { publicationId: event.publicationId };
			},
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (surface): number => {
					if (surface === 'review') reviewEpoch += 1;
					return surface === 'review' ? reviewEpoch : 0;
				},
				call: async (...arguments_): Promise<never> => {
					const [method, request] = arguments_;
					calls.push({ method, request });
					// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- This fake records any unexpected product call before returning its closed null result.
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

		events.push(
			reviewMetadataFrame({
				eventKind: 'review.sourceAccepted',
				operationCorrelationId: null,
				generation: 7,
				packageId: 'package-1',
				publicationId,
				revision: 11,
				sourceIdentity: 'source-1',
			}),
		);
		events.push(
			reviewMetadataFrame({
				eventKind: 'review.sourceAccepted',
				operationCorrelationId: null,
				generation: 8,
				packageId: 'package-2',
				publicationId: '00000000-0000-7000-8000-000000000012',
				revision: 12,
				sourceIdentity: 'source-2',
			}),
		);
		await allMetadataApplied.promise;

		expect(metadataApplicationCount).toBe(2);
		expect(calls).toEqual([]);
	});

	test('keeps draining Review metadata without coupling applied-call failure to recovery', async () => {
		const reviewEvents = new BridgeProductBoundedAsyncQueue<ReviewMetadataFrame>(64);
		const terminalObservation = createBridgeProductDeferred<
			'metadataContinued' | 'metadataFailure'
		>();
		const publicationId = '00000000-0000-7000-8000-000000000011';
		let reviewEpoch = 0;
		let reviewSubscriptionCount = 0;
		let metadataApplicationCount = 0;
		let appliedCallCount = 0;
		let reviewCancelCount = 0;
		let reviewFailureCount = 0;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			onReviewMetadataEvent: (): { readonly publicationId: string } => {
				metadataApplicationCount += 1;
				if (metadataApplicationCount === 2) terminalObservation.resolve('metadataContinued');
				return { publicationId };
			},
			onReviewMetadataFailure: (): void => {
				reviewFailureCount += 1;
				terminalObservation.resolve('metadataFailure');
			},
			productTransport: {
				...unusedProductTransport(),
				bumpWorkerDerivationEpoch: (surface): number => {
					if (surface === 'review') reviewEpoch += 1;
					return surface === 'review' ? reviewEpoch : 1;
				},
				call: async (...arguments_): Promise<never> => {
					const [method] = arguments_;
					if (method === 'review.publication.applied') {
						appliedCallCount += 1;
						throw new Error('injected receipt transport failure');
					}
					throw new Error(`Unexpected product call ${method}.`);
				},
				workerDerivationEpoch: (surface): number => (surface === 'review' ? reviewEpoch : 0),
			},
			subscribeReview: () => {
				reviewSubscriptionCount += 1;
				return {
					cancel: async (): Promise<void> => {
						reviewCancelCount += 1;
					},
					events: reviewEvents,
					subscriptionId: `review-metadata-independent-${reviewSubscriptionCount}`,
					subscriptionKind: 'review.metadata',
					update: async (): Promise<void> => {},
				};
			},
		});
		controller.ensureReviewMetadata();

		reviewEvents.push(
			reviewMetadataFrame({
				eventKind: 'review.sourceAccepted',
				operationCorrelationId: null,
				generation: 7,
				packageId: 'package-1',
				publicationId,
				revision: 11,
				sourceIdentity: 'source-1',
			}),
		);
		reviewEvents.push(
			reviewMetadataFrame({
				eventKind: 'review.sourceAccepted',
				operationCorrelationId: null,
				generation: 8,
				packageId: 'package-2',
				publicationId: '00000000-0000-7000-8000-000000000012',
				revision: 12,
				sourceIdentity: 'source-2',
			}),
		);
		const observation = await terminalObservation.promise;

		expect(observation).toBe('metadataContinued');
		expect(metadataApplicationCount).toBe(2);
		expect(appliedCallCount).toBe(0);
		expect(reviewFailureCount).toBe(0);
		expect(reviewCancelCount).toBe(0);
		expect(reviewSubscriptionCount).toBe(1);
	});

	test('retains early File demand and reconciles it after one discovered source opens', async () => {
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
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
		events.push(fileMetadataFrame({ eventKind: 'file.sourceAccepted', source }));
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
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
		let releaseInterestUpdate = (): void => {};
		const pendingInterestUpdate = new Promise<void>((resolve): void => {
			releaseInterestUpdate = resolve;
		});
		const observedEvents: FileMetadataEvent[] = [];
		let resolveAllEventsObserved = (): void => {};
		const allEventsObserved = new Promise<void>((resolve): void => {
			resolveAllEventsObserved = resolve;
		});
		const subscription: FileMetadataSubscription = {
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
		events.push(fileMetadataFrame({ eventKind: 'file.sourceAccepted', source }));
		for (let index = 0; index < 65; index += 1) {
			events.push(
				fileMetadataFrame({
					eventKind: 'file.treeWindow',
					finalWindow: index === 64,
					lineage: { lane: 'foreground', loadedBy: 'startup_window' },
					pathScope: [],
					rows: [],
					source,
					startIndex: index,
					totalRowCount: index === 64 ? 0 : null,
				}),
			);
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
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
		const updates: unknown[] = [];
		const observedEvents: FileMetadataEvent[] = [];
		const observedEpochs: number[] = [];
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: FileMetadataSubscription = {
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
		events.push(fileMetadataFrame({ eventKind: 'file.sourceAccepted', source }));
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
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
		const updates: unknown[] = [];
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: FileMetadataSubscription = {
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
		events.push(fileMetadataFrame({ eventKind: 'file.sourceAccepted', source }));
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
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
		const updates: Array<Parameters<FileMetadataSubscription['update']>[0]> = [];
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: FileMetadataSubscription = {
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
		events.push(fileMetadataFrame({ eventKind: 'file.sourceAccepted', source }));
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
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
		const failures: Array<{ readonly error: unknown; readonly epoch: number }> = [];
		const updates: unknown[] = [];
		let shouldRejectUpdate = true;
		let resolveSourceAccepted = (): void => {};
		const sourceAccepted = new Promise<void>((resolve): void => {
			resolveSourceAccepted = resolve;
		});
		const subscription: FileMetadataSubscription = {
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
		events.push(fileMetadataFrame({ eventKind: 'file.sourceAccepted', source }));
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
		const events = new BridgeProductBoundedAsyncQueue<FileMetadataFrame>(64);
		const subscription: FileMetadataSubscription = {
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

function fileMetadataFrame(event: FileMetadataEvent): FileMetadataFrame {
	return {
		data: event,
		metadataStreamId: 'file-metadata-stream',
		operationCorrelationId: null,
		sourceGeneration: event.source.subscriptionGeneration,
		streamSequence: 1,
		subscriptionId: 'file-metadata-subscription',
		subscriptionKind: 'file.metadata',
		subscriptionSequence: 1,
		workerDerivationEpoch: 1,
	};
}

function reviewMetadataFrame(event: ReviewMetadataEvent): ReviewMetadataFrame {
	return {
		data: event,
		metadataStreamId: 'review-metadata-stream',
		operationCorrelationId: event.operationCorrelationId,
		sourceGeneration: event.generation,
		streamSequence: 1,
		subscriptionId: 'review-metadata-subscription',
		subscriptionKind: 'review.metadata',
		subscriptionSequence: 1,
		workerDerivationEpoch: 1,
	};
}
