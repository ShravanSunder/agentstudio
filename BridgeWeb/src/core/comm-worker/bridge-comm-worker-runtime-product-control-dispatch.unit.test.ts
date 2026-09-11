import { describe, expect, test, vi } from 'vitest';

import { BridgeCommWorkerProductController } from './bridge-comm-worker-product-controller.js';
import { encodeBridgeWorkerMetadataInterestUpdateCommand } from './bridge-comm-worker-protocol.js';
import { dispatchBridgeCommWorkerRuntimeProductControl } from './bridge-comm-worker-runtime-product-control-dispatch.js';
import { flushBridgeWorkerRuntimeContinuations } from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductWorktreeAnnotationOperation } from './bridge-product-call-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';

describe.each(['fileView', 'review'] as const)(
	'Bridge comm worker runtime %s annotation output control',
	(surface) => {
		test('accepts JSON export success after the ordinary product-control deadline', async () => {
			vi.useFakeTimers();
			try {
				// Arrange
				const action = deferredProductControlAction();
				const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
				const requestId = 'request-json-export';
				dispatchAnnotationOutput({
					surface,
					operation: {
						displayedProjectionRevision: 9,
						expectedSessionRevision: 4,
						kind: 'output.scope.commit',
						outputKind: 'jsonFile',
						scope: 'pending',
						sessionId: '00000000-0000-7000-8000-000000000013',
						sourceGeneration: 7,
					},
					publish: (message): void => {
						publishedMessages.push(message);
					},
					requestId,
					sendProductControl: action.send,
					timeoutMilliseconds: 25,
				});

				// Act
				await vi.advanceTimersByTimeAsync(250);
				await flushBridgeWorkerRuntimeContinuations();
				action.resolve(
					completedOutputResult(
						{
							kind: 'succeeded',
							summary: {
								attemptId: '00000000-0000-7000-8000-000000000014',
								destinationFilename: 'review.json',
								messageCount: 2,
								outputKind: 'json_file',
								sessionId: '00000000-0000-7000-8000-000000000013',
							},
						},
						requestId,
						surface,
					),
				);
				await flushBridgeWorkerRuntimeContinuations();

				// Assert
				expect(action.send).toHaveBeenCalledTimes(1);
				expect(publishedMessages.filter((message) => message.kind === 'health')).toEqual([
					expect.objectContaining({ status: 'ready', requestId }),
				]);
				expect(
					publishedMessages.filter((message) => message.kind === 'annotationCommandAccepted'),
				).toEqual([
					expect.objectContaining({
						kind: 'annotationCommandAccepted',
						outcome: expect.objectContaining({
							status: { kind: 'output', outcome: expect.objectContaining({ kind: 'succeeded' }) },
						}),
						requestId,
					}),
				]);
			} finally {
				vi.useRealTimers();
			}
		});

		test('accepts one repeated-output cancellation after pane backgrounding and the ordinary deadline', async () => {
			vi.useFakeTimers();
			try {
				// Arrange
				const action = deferredProductControlAction();
				const paneWork = new AbortController();
				const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
				const requestId = 'request-repeat-export';
				dispatchAnnotationOutput({
					surface,
					operation: {
						attemptId: '00000000-0000-7000-8000-000000000014',
						kind: 'output.repeat',
					},
					paneWorkSignal: paneWork.signal,
					publish: (message): void => {
						publishedMessages.push(message);
					},
					requestId,
					sendProductControl: action.send,
					timeoutMilliseconds: 25,
				});

				// Act
				paneWork.abort(new DOMException('pane moved to background', 'AbortError'));
				await vi.advanceTimersByTimeAsync(250);
				action.resolve(
					completedOutputResult({ kind: 'destination_cancelled' }, requestId, surface),
				);
				await flushBridgeWorkerRuntimeContinuations();

				// Assert
				expect(action.send).toHaveBeenCalledTimes(1);
				expect(publishedMessages.filter((message) => message.kind === 'health')).toEqual([
					expect.objectContaining({ status: 'ready', requestId }),
				]);
				expect(
					publishedMessages.filter((message) => message.kind === 'annotationCommandAccepted'),
				).toEqual([
					expect.objectContaining({
						kind: 'annotationCommandAccepted',
						outcome: expect.objectContaining({
							status: { kind: 'output', outcome: { kind: 'destination_cancelled' } },
						}),
						requestId,
					}),
				]);
			} finally {
				vi.useRealTimers();
			}
		});

		test('retains the ordinary deadline for clipboard output commits', async () => {
			vi.useFakeTimers();
			try {
				// Arrange
				const action = deferredProductControlAction();
				const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
				dispatchAnnotationOutput({
					surface,
					operation: {
						displayedProjectionRevision: 9,
						expectedSessionRevision: 4,
						kind: 'output.scope.commit',
						outputKind: 'clipboardMarkdown',
						scope: 'pending',
						sessionId: '00000000-0000-7000-8000-000000000013',
						sourceGeneration: 7,
					},
					publish: (message): void => {
						publishedMessages.push(message);
					},
					requestId: 'request-clipboard-output',
					sendProductControl: action.send,
					timeoutMilliseconds: 25,
				});

				// Act
				await vi.advanceTimersByTimeAsync(25);
				await flushBridgeWorkerRuntimeContinuations();

				// Assert
				expect(action.send).toHaveBeenCalledTimes(1);
				expect(publishedMessages).toEqual([
					expect.objectContaining({
						kind: 'health',
						requestId: 'request-clipboard-output',
						status: 'degraded',
					}),
				]);
			} finally {
				vi.useRealTimers();
			}
		});
	},
);

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

function dispatchAnnotationOutput(props: {
	readonly surface: 'fileView' | 'review';
	readonly operation: BridgeProductWorktreeAnnotationOperation;
	readonly paneWorkSignal?: AbortSignal;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly requestId: string;
	readonly sendProductControl: () => Promise<unknown>;
	readonly timeoutMilliseconds: number;
}): void {
	dispatchBridgeCommWorkerRuntimeProductControl({
		activeReviewWorkerDerivationEpoch: null,
		comparisonTargetsQueryRunner: {
			abort: (): void => {},
			fail: (): void => {},
			run: async (): Promise<void> => {},
		},
		getActiveComparisonTargetsRequestId: (): null => null,
		mainCommand: {
			command: 'annotationCommand',
			direction: 'mainToServerWorker',
			epoch: 1,
			kind: 'command',
			operation: props.operation,
			requestId: props.requestId,
			surface: props.surface,
			...(props.surface === 'review'
				? {
						reviewPublicationIdentity: {
							packageId: 'installed-package',
							publicationId: '00000000-0000-7000-8000-000000000031',
							reviewGeneration: 1,
							revision: 1,
							sourceIdentity: 'installed-source',
						},
					}
				: {}),
			transferDescriptors: [],
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		},
		messages: [
			{
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: props.requestId,
				status: 'ready',
				transferDescriptors: [],
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			},
		],
		paneWorkSignal: props.paneWorkSignal ?? new AbortController().signal,
		productControlTimeoutMilliseconds: props.timeoutMilliseconds,
		productController: null,
		productTransport: undefined,
		publish: props.publish,
		publishReviewMetadataInterests: async (): Promise<void> => {},
		reviewMetadataApplicator: null,
		sendProductControl: props.sendProductControl,
		setActiveComparisonTargetsRequestId: (): void => {},
	});
}

function deferredProductControlAction(): {
	readonly resolve: (value: unknown) => void;
	readonly send: ReturnType<typeof vi.fn<() => Promise<unknown>>>;
} {
	let resolveAction!: (value: unknown) => void;
	const promise = new Promise<unknown>((resolve): void => {
		resolveAction = resolve;
	});
	return {
		resolve: resolveAction,
		send: vi.fn(async (): Promise<unknown> => promise),
	};
}

function completedOutputResult(
	outcome: Readonly<Record<string, unknown>>,
	requestId: string,
	surface: 'fileView' | 'review',
): Readonly<Record<string, unknown>> {
	return {
		kind: 'completed',
		outcome: {
			requestId: `product-${requestId}`,
			sessionId: '00000000-0000-7000-8000-000000000013',
			status: { kind: 'output', outcome },
			surface: surface === 'review' ? 'review' : 'file',
		},
	};
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
