import { describe, expect, test, vi } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { encodeBridgeWorkerMetadataInterestUpdateCommand } from './bridge-comm-worker-protocol.js';
import { dispatchBridgeCommWorkerRuntimeProductControl } from './bridge-comm-worker-runtime-product-control-dispatch.js';
import { flushBridgeWorkerRuntimeContinuations } from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeWorkerServerToMainMessage } from './bridge-worker-contracts.js';

describe('Bridge comm worker runtime Review interest control', () => {
	test('reports degraded health when worker-owned interest publication rejects', async () => {
		// Arrange
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];

		// Act
		dispatchMetadataInterestUpdate({
			publish: (message): void => {
				publishedMessages.push(message);
			},
			publishReviewMetadataInterests: async (): Promise<void> => {
				throw new Error('injected Review interest failure');
			},
			requestId: 'request-review-interest-rejected',
		});
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(publishedMessages).toEqual([
			expect.objectContaining({
				kind: 'health',
				message: 'Bridge comm worker failed to update Review metadata interests.',
				requestId: 'request-review-interest-rejected',
				status: 'degraded',
			}),
		]);
	});

	test('reports degraded health when worker-owned interest publication does not settle', async () => {
		vi.useFakeTimers();
		try {
			// Arrange
			const publishedMessages: BridgeWorkerServerToMainMessage[] = [];

			// Act
			dispatchMetadataInterestUpdate({
				publish: (message): void => {
					publishedMessages.push(message);
				},
				publishReviewMetadataInterests: async (): Promise<never> => new Promise((): void => {}),
				requestId: 'request-review-interest-timeout',
				timeoutMilliseconds: 25,
			});
			await flushBridgeWorkerRuntimeContinuations();
			expect(publishedMessages).toEqual([]);
			await vi.advanceTimersByTimeAsync(25);
			await flushBridgeWorkerRuntimeContinuations();

			// Assert
			expect(publishedMessages).toEqual([
				expect.objectContaining({
					kind: 'health',
					message: 'Bridge comm worker failed to update Review metadata interests.',
					requestId: 'request-review-interest-timeout',
					status: 'degraded',
				}),
			]);
		} finally {
			vi.useRealTimers();
		}
	});
});

function dispatchMetadataInterestUpdate(props: {
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly publishReviewMetadataInterests: () => Promise<void>;
	readonly requestId: string;
	readonly timeoutMilliseconds?: number;
}): void {
	const command = encodeBridgeWorkerMetadataInterestUpdateCommand({
		epoch: 3,
		request: {
			itemIds: ['forged-caller-item'],
			lane: 'foreground',
			protocol: 'review',
		},
		requestId: props.requestId,
	});
	dispatchBridgeCommWorkerRuntimeProductControl({
		activeReviewWorkerDerivationEpoch: 3,
		comparisonTargetsQueryRunner: {
			abort: (): void => {},
			fail: (): void => {},
			run: async (): Promise<void> => {},
		},
		getActiveComparisonTargetsRequestId: (): null => null,
		mainCommand: command,
		messages: [
			{
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: props.requestId,
				status: 'ready',
				transferDescriptors: [],
				wireVersion: 1,
			},
		],
		paneWorkSignal: new AbortController().signal,
		productControlTimeoutMilliseconds: props.timeoutMilliseconds ?? 5_000,
		productController: createUnusedProductController(),
		productTransport: undefined,
		publish: props.publish,
		publishReviewMetadataInterests: props.publishReviewMetadataInterests,
		reviewMetadataApplicator: null,
		sendProductControl: async (): Promise<null> => null,
		setActiveComparisonTargetsRequestId: (): void => {},
	});
}

function createUnusedProductController(): BridgeCommWorkerProductController {
	return new BridgeCommWorkerProductController({
		onFileMetadataEvent: (): void => {},
		productTransport: unusedProductTransport(),
	});
}

function unusedProductTransport(): BridgeProductTransportSession {
	return {
		bumpWorkerDerivationEpoch: (): number => 0,
		call: async (): Promise<never> => {
			throw new Error('Unexpected product call.');
		},
		openContent: (): never => {
			throw new Error('Unexpected content open.');
		},
		subscribe: (): never => {
			throw new Error('Unexpected product subscription.');
		},
		workerDerivationEpoch: (): number => 0,
	};
}
