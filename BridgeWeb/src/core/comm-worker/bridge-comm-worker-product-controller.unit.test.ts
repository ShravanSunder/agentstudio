import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT,
	type BridgeProductSubscriptionEvent,
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
		await controller.send({
			method: 'bridge.metadata_interest.update',
			params: {
				itemIds: ['item-selected'],
				lane: 'foreground',
				protocol: 'review',
			},
		});
		await controller.send({
			method: 'bridge.metadata_interest.update',
			params: {
				itemIds: ['item-selected', 'item-visible'],
				lane: 'visible',
				protocol: 'review',
			},
		});
		const sourceAcceptedEvent = {
			eventKind: 'review.sourceAccepted',
			generation: 7,
			packageId: 'package-1',
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
		]);
		expect(observedEvents).toEqual([sourceAcceptedEvent]);
		expect(observedEpochs).toEqual([1]);
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
