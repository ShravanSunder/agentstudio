import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductControlCommand } from './bridge-product-control-contracts.js';
import { bridgeProductFileMetadataApplicationProtocol } from './bridge-product-metadata-application-registry.js';
import { BridgeProductSubscriptionResetError } from './bridge-product-subscription-state.js';
import type { BridgeProductMetadataApplicationSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

type FileMetadataProtocol = typeof bridgeProductFileMetadataApplicationProtocol;
type FileMetadataSubscription = BridgeProductMetadataApplicationSubscription<FileMetadataProtocol>;

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: '00000000-0000-4000-8000-000000000001',
	rootPathToken: 'root-token-1',
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

const installedFileSource = {
	repoId: currentFileSourceConfiguration.repoId,
	rootRevisionToken: 'root-revision-1',
	sourceCursor: 'source-cursor-1',
	sourceId: 'file-source-1',
	subscriptionGeneration: 3,
	worktreeId: currentFileSourceConfiguration.worktreeId,
} as const;

describe('Bridge comm worker File metadata recovery', () => {
	test.each(['stale_source', 'snapshot_required'] as const)(
		'an active %s reset rediscovers File metadata without another UI action',
		async (reason) => {
			// Arrange — the error is the transport's existing valid subscription.reset outcome.
			const firstEvents = new BridgeProductBoundedAsyncQueue<never>(8);
			const replacementEvents = new BridgeProductBoundedAsyncQueue<never>(8);
			const observedFailure = makeDeferred<void>();
			const secondFailure = makeDeferred<void>();
			let discoveryCount = 0;
			let subscriptionCount = 0;
			let failureCount = 0;
			const controller = new BridgeCommWorkerProductController({
				callCurrentFileSource: async () => {
					discoveryCount += 1;
					return { source: currentFileSourceConfiguration, status: 'available' };
				},
				onFileMetadataFailure: (): void => {
					failureCount += 1;
					observedFailure.resolve();
					if (failureCount === 2) secondFailure.resolve();
				},
				productTransport: fileEpochTransport(),
				subscribeFile: () => {
					subscriptionCount += 1;
					if (subscriptionCount > 2) throw new Error('Unbounded File metadata reset recovery.');
					return fileSubscription(
						`file-reset-${subscriptionCount}`,
						subscriptionCount === 1 ? firstEvents : replacementEvents,
					);
				},
			});
			await controller.ensureFileSource();
			try {
				// Act — no explicit ensure, view reactivation, or interest change follows the reset.
				firstEvents.fail(new BridgeProductSubscriptionResetError(reason), true);
				await observedFailure.promise;

				// Assert — the existing source owner must reconnect from the latest source authority.
				expect(subscriptionCount).toBe(2);
				expect(discoveryCount).toBe(2);
				// A replacement that resets again before a certified batch must not loop.
				replacementEvents.fail(new BridgeProductSubscriptionResetError(reason), true);
				await secondFailure.promise;
				expect(failureCount).toBe(2);
				expect(subscriptionCount).toBe(2);
			} finally {
				firstEvents.close(true);
				replacementEvents.close(true);
			}
		},
	);

	test('a certified File batch permits a later automatic reset recovery', async () => {
		const firstEvents = new BridgeProductBoundedAsyncQueue<never>(1);
		const secondEvents = new BridgeProductBoundedAsyncQueue<never>(1);
		const thirdEvents = new BridgeProductBoundedAsyncQueue<never>(1);
		const secondOpened = makeDeferred<void>();
		const thirdOpened = makeDeferred<void>();
		let subscriptionCount = 0;
		const events = [firstEvents, secondEvents, thirdEvents] as const;
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => ({
				source: currentFileSourceConfiguration,
				status: 'available',
			}),
			productTransport: fileEpochTransport(),
			subscribeFile: () => {
				const eventQueue = events[subscriptionCount];
				if (eventQueue === undefined) throw new Error('Unexpected fourth File subscription.');
				subscriptionCount += 1;
				if (subscriptionCount === 2) secondOpened.resolve();
				if (subscriptionCount === 3) thirdOpened.resolve();
				return fileSubscription(`file-reset-${subscriptionCount}`, eventQueue);
			},
		});
		await controller.ensureFileSource();
		try {
			firstEvents.fail(new BridgeProductSubscriptionResetError('stale_source'), true);
			await secondOpened.promise;
			controller.acceptInstalledFileBatch({
				source: installedFileSource,
				subscriptionId: 'file-reset-2',
				workerDerivationEpoch: 2,
			});
			secondEvents.fail(new BridgeProductSubscriptionResetError('stale_source'), true);
			await thirdOpened.promise;
			expect(subscriptionCount).toBe(3);
		} finally {
			firstEvents.close(true);
			secondEvents.close(true);
			thirdEvents.close(true);
		}
	});

	test('retries File source discovery after a transient rejection', async () => {
		// Arrange
		let discoveryCount = 0;
		const events = new BridgeProductBoundedAsyncQueue<never>(8);
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				if (discoveryCount === 1) throw new Error('transient source discovery failure');
				return { source: currentFileSourceConfiguration, status: 'available' };
			},
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
		const firstEvents = new BridgeProductBoundedAsyncQueue<never>(8);
		const replacementEvents = new BridgeProductBoundedAsyncQueue<never>(8);
		const observedFailure = makeDeferred<void>();
		let discoveryCount = 0;
		let subscriptionCount = 0;
		const subscriptions: readonly FileMetadataSubscription[] = [
			fileSubscription('file-subscription-before-invalidation', firstEvents),
			fileSubscription('file-subscription-after-invalidation', replacementEvents),
		];
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				return { source: currentFileSourceConfiguration, status: 'available' };
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
		firstEvents.fail(
			Object.assign(new Error('metadata acknowledgement timed out'), {
				failureCode: 'request_timeout',
			}),
			true,
		);
		await observedFailure.promise;
		await controller.ensureFileSource();
		expect(discoveryCount).toBe(2);
		expect(subscriptionCount).toBe(2);
		// Assert: a later ensure opens one replacement from fresh source authority.
	});

	test('File activation reopens a source retired by metadata stream failure', async () => {
		// Arrange
		const firstEvents = new BridgeProductBoundedAsyncQueue<never>(8);
		const replacementEvents = new BridgeProductBoundedAsyncQueue<never>(8);
		const observedFailure = makeDeferred<void>();
		let discoveryCount = 0;
		let subscriptionCount = 0;
		const subscriptions: readonly FileMetadataSubscription[] = [
			fileSubscription('file-subscription-before-failure', firstEvents),
			fileSubscription('file-subscription-after-failure', replacementEvents),
		];
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				return { source: currentFileSourceConfiguration, status: 'available' };
			},
			onFileMetadataFailure: (): void => observedFailure.resolve(),
			productTransport: fileEpochTransport(),
			subscribeFile: () => {
				const subscription = subscriptions[subscriptionCount];
				if (subscription === undefined) throw new Error('Unexpected third File subscription.');
				subscriptionCount += 1;
				return subscription;
			},
		});
		await controller.ensureFileSource();
		firstEvents.fail(new Error('File metadata stream ended'), true);
		await observedFailure.promise;

		// Act
		await controller.sendProductControl(fileActiveViewerModeCommand());

		// Assert
		expect(discoveryCount).toBe(2);
		expect(subscriptionCount).toBe(2);
	});

	test('File activation succeeds before best-effort source recovery fails', async () => {
		// Arrange
		const callOrder: string[] = [];
		const baseTransport = fileEpochTransport();
		const productTransport = {
			...baseTransport,
			call: async (...arguments_) => {
				const method = arguments_[0];
				if (method !== 'file.activeViewerMode.update') {
					throw new Error(`Unexpected product call: ${method}.`);
				}
				callOrder.push('native-active-mode');
				return null;
			},
		} satisfies BridgeProductTransportSession;
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				callOrder.push('file-source-discovery');
				throw new Error('File source recovery unavailable');
			},
			onActiveViewerModeAdmitted: (mode): void => {
				callOrder.push(`admitted-${mode}`);
			},
			productTransport,
		});

		// Act
		const result = await controller.sendProductControl(fileActiveViewerModeCommand());

		// Assert
		expect(result).toBeNull();
		expect(callOrder).toEqual(['native-active-mode', 'admitted-file', 'file-source-discovery']);
	});
});

function fileActiveViewerModeCommand(): Extract<
	BridgeProductControlCommand,
	{ readonly method: 'bridge.activeViewerMode.update' }
> {
	return {
		method: 'bridge.activeViewerMode.update',
		params: {
			activeSource: null,
			mode: 'file',
			nativeSelectionRequestId: null,
			sequence: 1,
			sessionId: 'active-viewer-session',
		},
	};
}

function fileSubscription(
	subscriptionId: string,
	events: BridgeProductBoundedAsyncQueue<never>,
): FileMetadataSubscription {
	return {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId,
		subscriptionKind: 'file.metadata',
	};
}

function fileEpochTransport(): BridgeProductTransportSession {
	let fileEpoch = 0;
	return {
		advanceWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			return surface === 'file' ? fileEpoch : 0;
		},
		call: async (...arguments_) => {
			const method = arguments_[0];
			if (method === 'file.activeViewerMode.update') return null;
			throw new Error(`Unexpected product call: ${method}.`);
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
