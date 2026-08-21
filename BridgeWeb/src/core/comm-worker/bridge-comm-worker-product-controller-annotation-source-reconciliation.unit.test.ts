import { describe, expect, test } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';

const currentFileSourceConfiguration = {
	cwdScope: null,
	freshness: 'live',
	includeStatuses: true,
	repoId: '00000000-0000-4000-8000-000000000001',
	rootPathToken: 'root-token-1',
	worktreeId: '00000000-0000-4000-8000-000000000002',
} as const;

describe('Bridge comm worker annotation source reconciliation', () => {
	test('reopens File metadata from current source authority for a strictly newer generation', async () => {
		let cancellationCount = 0;
		let discoveryCount = 0;
		let subscriptionCount = 0;
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				return { source: currentFileSourceConfiguration, status: 'available' };
			},
			onFileMetadataEvent: (): void => {},
			productTransport: unusedProductTransport(),
			subscribeFile: () => {
				subscriptionCount += 1;
				return fileMetadataSubscription({
					cancel: async (): Promise<void> => {
						cancellationCount += 1;
					},
					subscriptionId: `file-metadata-${subscriptionCount}`,
				});
			},
		});
		await controller.ensureFileSource();

		await controller.reconcileAnnotationProjectionSourceAuthority({
			currentSourceGeneration: 12,
			requestedSourceGeneration: 10,
			surface: 'file',
		});

		expect(cancellationCount).toBe(1);
		expect(discoveryCount).toBe(2);
		expect(subscriptionCount).toBe(2);
	});

	test('reopens Review metadata for a strictly newer generation', async () => {
		let cancellationCount = 0;
		let subscriptionCount = 0;
		const controller = new BridgeCommWorkerProductController({
			onFileMetadataEvent: (): void => {},
			productTransport: unusedProductTransport(),
			subscribeReview: () => {
				subscriptionCount += 1;
				return reviewMetadataSubscription({
					cancel: async (): Promise<void> => {
						cancellationCount += 1;
					},
					subscriptionId: `review-metadata-${subscriptionCount}`,
				});
			},
		});
		controller.ensureReviewMetadata();

		await controller.reconcileAnnotationProjectionSourceAuthority({
			currentSourceGeneration: 12,
			requestedSourceGeneration: 10,
			surface: 'review',
		});

		expect(cancellationCount).toBe(1);
		expect(subscriptionCount).toBe(2);
	});

	test('does not reopen metadata when source authority did not advance', async () => {
		const convergenceStates: string[] = [];
		let discoveryCount = 0;
		const controller = new BridgeCommWorkerProductController({
			callCurrentFileSource: async () => {
				discoveryCount += 1;
				return { source: currentFileSourceConfiguration, status: 'available' };
			},
			onAnnotationProjectionConvergence: ({ state }): void => {
				convergenceStates.push(state.kind);
			},
			onFileMetadataEvent: (): void => {},
			productTransport: unusedProductTransport(),
		});
		controller.setAnnotationProjectionSurfaceActive('file', false, 10);

		await controller.reconcileAnnotationProjectionSourceAuthority({
			currentSourceGeneration: 10,
			requestedSourceGeneration: 10,
			surface: 'file',
		});

		expect(convergenceStates).toEqual([]);
		expect(discoveryCount).toBe(0);
	});
});

function fileMetadataSubscription(props: {
	readonly cancel: () => Promise<void>;
	readonly subscriptionId: string;
}): BridgeProductSubscription<'file.metadata'> {
	return {
		cancel: props.cancel,
		events: new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'file.metadata'>>(1),
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
}

function reviewMetadataSubscription(props: {
	readonly cancel: () => Promise<void>;
	readonly subscriptionId: string;
}): BridgeProductSubscription<'review.metadata'> {
	return {
		cancel: props.cancel,
		events: new BridgeProductBoundedAsyncQueue<BridgeProductSubscriptionEvent<'review.metadata'>>(
			1,
		),
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'review.metadata',
		update: async (): Promise<void> => {},
	};
}

function unusedProductTransport(): BridgeProductTransportSession {
	let fileEpoch = 0;
	let reviewEpoch = 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			else reviewEpoch += 1;
			return surface === 'file' ? fileEpoch : reviewEpoch;
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
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : reviewEpoch),
	};
}
