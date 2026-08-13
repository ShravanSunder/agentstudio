import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

const fileSource = {
	repoId: '00000000-0000-4000-8000-000000000001',
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: fileSource.repoId,
	rootPathToken: 'root-token-1',
	worktreeId: fileSource.worktreeId,
} as const;

describe('Bridge comm worker File metadata recovery', () => {
	test('retries File source discovery after a transient rejection', async () => {
		// Arrange
		let discoveryCount = 0;
		const events = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(8);
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				if (discoveryCount === 1) throw new Error('transient source discovery failure');
				return { source: currentFileSourceConfiguration, status: 'available' };
			},
			onFileMetadataEvent: (): void => {},
			productTransport: fileEpochTransport(),
			subscribeFile: () => fileSubscription('file-subscription-after-retry', events),
		});

		// Act
		await expect(controller.ensureFileSource()).rejects.toThrow(
			'transient source discovery failure',
		);
		await controller.ensureFileSource();

		// Assert
		expect(discoveryCount).toBe(2);
	});

	test('a later ensure opens a replacement subscription after the active File stream fails', async () => {
		// Arrange — removing the terminal-subscription cache reset makes this test fail.
		const firstEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(8);
		const replacementEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.metadata'>
		>(8);
		const observedReplacementWindow = makeDeferred<void>();
		const observedFailure = makeDeferred<void>();
		let discoveryCount = 0;
		let subscriptionCount = 0;
		const subscriptions: readonly BridgeProductSubscription<'file.metadata'>[] = [
			fileSubscription('file-subscription-before-invalidation', firstEvents),
			fileSubscription('file-subscription-after-invalidation', replacementEvents),
		];
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				return { source: currentFileSourceConfiguration, status: 'available' };
			},
			onFileMetadataEvent: (event, workerDerivationEpoch): void => {
				if (event.eventKind === 'file.treeWindow' && workerDerivationEpoch === 2) {
					observedReplacementWindow.resolve();
				}
			},
			onFileMetadataFailure: (): void => {
				observedFailure.resolve();
			},
			productTransport: fileEpochTransport(),
			subscribeFile: () => {
				const subscription = subscriptions[subscriptionCount];
				if (subscription === undefined) throw new Error('Unexpected third File subscription.');
				subscriptionCount += 1;
				return subscription;
			},
		});

		// Act
		await controller.ensureFileSource();
		firstEvents.fail(new Error('construction invalidated'), true);
		await observedFailure.promise;
		await controller.ensureFileSource();
		expect(discoveryCount).toBe(2);
		expect(subscriptionCount).toBe(2);
		replacementEvents.push({ eventKind: 'file.sourceAccepted', source: fileSource });
		replacementEvents.push({
			eventKind: 'file.treeWindow',
			finalWindow: true,
			lineage: { lane: 'foreground', loadedBy: 'startup_window' },
			pathScope: [],
			rows: [],
			source: fileSource,
			startIndex: 0,
			totalRowCount: 0,
		});

		// Assert
		await observedReplacementWindow.promise;
	});
});

function fileSubscription(
	subscriptionId: string,
	events: BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'file.metadata'>>,
): BridgeProductSubscription<'file.metadata'> {
	return {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId,
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
}

function fileEpochTransport(): BridgeProductTransportSession {
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

function makeDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
} {
	let resolvePromise: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (value): void => {
			if (resolvePromise === null) throw new Error('Deferred promise resolver is unavailable.');
			resolvePromise(value);
		},
	};
}
