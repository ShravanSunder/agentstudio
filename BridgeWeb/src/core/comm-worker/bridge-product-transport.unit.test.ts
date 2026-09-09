import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgeProductFileMetadataApplicationProtocol,
	bridgeProductReviewMetadataApplicationProtocol,
} from './bridge-product-metadata-application-registry.js';
import { bridgeProductMetadataFrameSchema } from './bridge-product-session-contracts.js';
import {
	createTransportHarness,
	disposeTransportHarnesses,
	emptyInterestHash,
	fileSourceAcceptedData,
	fileSourceConfiguration,
	fileSourceIdentity,
	interestBarrier,
	interestHash,
	metadataAccepted,
	reviewData,
	subscriptionAccepted,
	subscriptionCancelled,
	waitForCondition,
} from './test-fixtures/bridge-product-transport-metadata.test-support.js';

afterEach(async () => {
	try {
		await disposeTransportHarnesses();
	} finally {
		vi.unstubAllGlobals();
	}
});

describe('Bridge product transport', () => {
	test('acknowledges Review data immediately after routing without waiting for consumer application', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		const emptyHash = emptyInterestHash('review.metadata');
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyHash,
				kind: 'review.metadata',
				request,
				streamSequence: 1,
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await waitForCondition(() => harness.server.frameAcknowledgements.length === 2);

		harness.server.emitMetadata(
			reviewData({
				epoch: 0,
				interestHash: emptyHash,
				request,
				streamSequence: 2,
				subscriptionId: subscription.subscriptionId,
				subscriptionSequence: 1,
			}),
		);
		await waitForCondition(() => harness.server.frameAcknowledgements.length === 3);
		expect(harness.server.frameAcknowledgements.at(-1)).toMatchObject({
			kind: 'stream.frameObserved',
			streamKind: 'metadata',
			streamSequence: 2,
		});
		const eventResult = await subscription.events[Symbol.asyncIterator]().next();
		expect(eventResult.done).toBe(false);
	});

	test('keeps a File subscription alive through its initial source event', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
			interests: [],
			pathScope: [],
			source: fileSourceConfiguration(),
		});
		const nextEvent = subscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		const emptyHash = emptyInterestHash('file.metadata');
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyHash,
				kind: 'file.metadata',
				request,
				streamSequence: 1,
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await waitForCondition(
			() => harness.transport.metadataStreamDiagnostics?.().readRequestCount === 3,
		);

		harness.server.emitMetadata(
			fileSourceAcceptedData({
				epoch: 0,
				interestHash: emptyHash,
				request,
				streamSequence: 2,
				subscriptionId: subscription.subscriptionId,
			}),
		);

		await expect(nextEvent).resolves.toEqual({
			done: false,
			value: {
				data: { eventKind: 'file.sourceAccepted', source: fileSourceIdentity() },
				metadataStreamId: request.metadataStreamId,
				operationCorrelationId: null,
				sourceGeneration: 1,
				streamSequence: 2,
				subscriptionId: subscription.subscriptionId,
				subscriptionKind: 'file.metadata',
				subscriptionSequence: 1,
				workerDerivationEpoch: 0,
			},
		});
		expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
			activeSubscriptionCount: 1,
			failureStage: null,
			lastAcknowledgedStreamSequence: 2,
			routedFrameCount: 3,
		});
	});

	test('shares one accepted physical stream, routes early mixed events, and preserves initial interest', async () => {
		const harness = createTransportHarness({ fileEpoch: 5, reviewEpoch: 2 });
		harness.server.holdNextSubscriptionOpen();
		const review = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [{ itemIds: ['review-item-1'], lane: 'foreground' }],
		});
		const reviewEvent = review.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();

		expect(harness.server.controlRequests).toEqual([]);
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));
		await harness.server.waitForControlKind('subscription.open');
		const reviewOpen = harness.server.requiredControlRequest('subscription.open', 0);
		const reviewEmptyHash = interestHash({
			interests: [],
			subscriptionKind: 'review.metadata',
		});
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 2,
				interestHash: reviewEmptyHash,
				kind: 'review.metadata',
				request: harness.server.requiredMetadataRequest(),
				streamSequence: 1,
				subscriptionId: review.subscriptionId,
			}),
		);
		await waitForCondition(
			() => harness.transport.metadataStreamDiagnostics?.().readRequestCount === 3,
		);
		expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
			acknowledgedFrameCount: 2,
			failureStage: null,
			lastAcknowledgedStreamSequence: 1,
			lastRoutedFrameKind: 'subscription.accepted',
			lifecycleState: 'reading',
			readFulfilledCount: 2,
			readPending: true,
			readRequestCount: 3,
			routeFailureCode: null,
			routedFrameCount: 2,
		});
		expect(
			harness.server.frameAcknowledgements.map((acknowledgement) => {
				expect(acknowledgement.streamKind).toBe('metadata');
				if (acknowledgement.streamKind !== 'metadata') {
					throw new Error('Expected a metadata frame acknowledgement.');
				}
				return acknowledgement.streamSequence;
			}),
		).toEqual([0, 1]);
		harness.server.emitMetadata(
			reviewData({
				epoch: 2,
				interestHash: reviewEmptyHash,
				request: harness.server.requiredMetadataRequest(),
				streamSequence: 2,
				subscriptionId: review.subscriptionId,
				subscriptionSequence: 1,
			}),
		);

		expect(await reviewEvent).toEqual({
			done: false,
			value: {
				data: {
					eventKind: 'review.sourceAccepted',
					generation: 1,
					operationCorrelationId: null,
					packageId: 'package-1',
					publicationId: '00000000-0000-7000-8000-000000000001',
					revision: 1,
					sourceIdentity: 'source-1',
				},
				metadataStreamId: harness.server.requiredMetadataRequest().metadataStreamId,
				operationCorrelationId: null,
				sourceGeneration: 1,
				streamSequence: 2,
				subscriptionId: review.subscriptionId,
				subscriptionKind: 'review.metadata',
				subscriptionSequence: 1,
				workerDerivationEpoch: 2,
			},
		});
		harness.server.releaseHeldSubscriptionOpen();
		await harness.server.waitForControlKind('subscription.updateBatch');
		const reviewUpdate = harness.server.requiredControlRequest('subscription.updateBatch', 0);
		expect(reviewOpen).toMatchObject({
			subscription: { subscriptionKind: 'review.metadata' },
			workerDerivationEpoch: 2,
		});
		expect(reviewUpdate).toMatchObject({
			delta: {
				add: [{ itemId: 'review-item-1', lane: 'foreground' }],
				removeItemIds: [],
				subscriptionKind: 'review.metadata',
			},
		});
		harness.server.emitMetadata(
			interestBarrier(reviewUpdate, harness.server.requiredMetadataRequest(), 3, 2),
		);

		const file = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
			interests: [],
			pathScope: [],
			source: fileSourceConfiguration(),
		});
		await harness.server.waitForControlKind('subscription.open', 2);
		const fileOpen = harness.server.requiredControlRequest('subscription.open', 1);
		expect(fileOpen).toMatchObject({
			subscription: {
				source: fileSourceConfiguration(),
				subscriptionKind: 'file.metadata',
			},
			workerDerivationEpoch: 5,
		});
		expect(file.subscriptionKind).toBe('file.metadata');
		expect(harness.server.metadataFetchCount).toBe(1);
	});

	test('rejects a closed acknowledgement conflict status and cancels the metadata reader', async () => {
		const harness = createTransportHarness();
		harness.server.nextAcknowledgementStatus = 409;
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		const nextEvent = subscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));

		await expect(nextEvent).rejects.toThrow(/acknowledgement.*409/iu);
		expect(harness.server.metadataReaderCancelCount).toBe(1);
		expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
			acknowledgedFrameCount: 0,
			failureStage: 'acknowledgement',
			lastAcknowledgedStreamSequence: null,
			lastRoutedFrameKind: 'metadataStream.accepted',
			readRequestCount: 1,
			routedFrameCount: 1,
		});
	});

	test('records an unknown subscription acceptance as a route failure before read three', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		const nextEvent = subscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyInterestHash('review.metadata'),
				kind: 'review.metadata',
				request,
				streamSequence: 1,
				subscriptionId: 'unknown-subscription',
			}),
		);

		await expect(nextEvent).rejects.toThrow(/unknown subscription/iu);
		expect(harness.server.metadataReaderCancelCount).toBe(1);
		expect(
			harness.server.frameAcknowledgements.map((acknowledgement) => {
				expect(acknowledgement.streamKind).toBe('metadata');
				if (acknowledgement.streamKind !== 'metadata') {
					throw new Error('Expected a metadata frame acknowledgement.');
				}
				return acknowledgement.streamSequence;
			}),
		).toEqual([0]);
		expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
			activeSubscriptionCount: 0,
			committedFrameCount: 2,
			failureStage: 'route',
			lastCommittedFrameKind: 'subscription.accepted',
			lastRoutedFrameKind: 'metadataStream.accepted',
			lifecycleState: 'failed',
			readFulfilledCount: 2,
			readPending: false,
			readRequestCount: 2,
			routeFailureCode: 'unknown_subscription',
			routedFrameCount: 1,
		});
	});

	test('poisons a logical subscription on hostile pre-acceptance data', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		const nextEvent = subscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));
		harness.server.emitMetadata(
			reviewData({
				epoch: 0,
				interestHash: interestHash({
					interests: [],
					subscriptionKind: 'review.metadata',
				}),
				request: harness.server.requiredMetadataRequest(),
				streamSequence: 1,
				subscriptionId: subscription.subscriptionId,
				subscriptionSequence: 1,
			}),
		);

		await expect(nextEvent).rejects.toThrow(/accepted sequence zero|sequence is not contiguous/iu);
	});

	test('exposes payload-free metadata stream diagnostics after a poisoned packaged frame', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(bridgeProductFileMetadataApplicationProtocol, {
			interests: [],
			pathScope: [],
			source: fileSourceConfiguration(),
		});
		const nextEvent = subscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			bridgeProductMetadataFrameSchema.parse({
				...subscriptionAccepted({
					epoch: 0,
					interestHash: emptyInterestHash('file.metadata'),
					kind: 'file.metadata',
					request,
					streamSequence: 1,
					subscriptionId: subscription.subscriptionId,
				}),
				metadataStreamId: 'metadata-stream-mismatch',
			}),
		);

		await expect(nextEvent).rejects.toThrow();
		expect(harness.server.metadataReaderCancelCount).toBe(1);
		expect(harness.transport.metadataStreamDiagnostics?.()).toEqual({
			acknowledgedFrameCount: 1,
			activeSubscriptionCount: 0,
			committedFrameCount: 1,
			decoderState: 'poisoned',
			expectedNextStreamSequence: 1,
			failureStage: 'decode',
			failureCode: 'stream_identity_mismatch',
			identityMismatchField: 'metadataStreamId',
			lastSubscriptionTermination: null,
			routeFailureSubscriptionId: null,
			lastChunkByteCount: expect.any(Number),
			lastAcknowledgedStreamSequence: 0,
			lastCommittedFrameKind: 'metadataStream.accepted',
			lastRoutedFrameKind: 'metadataStream.accepted',
			lifecycleState: 'failed',
			peakRetainedByteCount: expect.any(Number),
			pushCount: 2,
			readFulfilledCount: 2,
			readPending: false,
			readRequestCount: 2,
			receivedByteCount: expect.any(Number),
			retainedByteCount: 0,
			routeFailureCode: null,
			routedFrameCount: 1,
			streamOpenCount: 1,
		});
	});

	test('opens a fresh metadata stream after a physical stream failure', async () => {
		const harness = createTransportHarness();
		const firstSubscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		const firstEvent = firstSubscription.events[Symbol.asyncIterator]().next();
		await harness.server.waitForMetadataStream();
		const firstRequest = harness.server.requiredMetadataRequest();
		harness.server.emitMetadata(metadataAccepted(firstRequest, 0));
		harness.server.emitMetadata(
			bridgeProductMetadataFrameSchema.parse({
				...metadataAccepted(firstRequest, 1),
				metadataStreamId: 'metadata-stream-mismatch',
			}),
		);

		await expect(firstEvent).rejects.toThrow();

		const secondSubscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		await waitForCondition(() => harness.server.metadataFetchCount === 2);
		const secondRequest = harness.server.requiredMetadataRequest();
		expect(secondRequest.metadataStreamId).not.toBe(firstRequest.metadataStreamId);
		harness.server.emitMetadata(metadataAccepted(secondRequest, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyInterestHash('review.metadata'),
				kind: 'review.metadata',
				request: secondRequest,
				streamSequence: 1,
				subscriptionId: secondSubscription.subscriptionId,
			}),
		);
		const secondCancel = secondSubscription.cancel();
		await harness.server.waitForControlKind('subscription.cancel');
		harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 0,
				interestHash: emptyInterestHash('review.metadata'),
				request: secondRequest,
				streamSequence: 2,
				subscriptionId: secondSubscription.subscriptionId,
			}),
		);
		await secondCancel;
	});

	test('settles cancel only after the correlated terminal metadata frame', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		const emptyHash = emptyInterestHash('review.metadata');
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: emptyHash,
				kind: 'review.metadata',
				request,
				streamSequence: 1,
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await harness.server.waitForControlKind('subscription.open');
		const cancel = subscription.cancel();
		await harness.server.waitForControlKind('subscription.cancel');
		let didSettle = false;
		void cancel.then((): void => {
			didSettle = true;
		});
		await Promise.resolve();
		expect(didSettle).toBe(false);

		harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 0,
				interestHash: emptyHash,
				request,
				streamSequence: 2,
				subscriptionId: subscription.subscriptionId,
			}),
		);

		await cancel;
		expect(await subscription.events[Symbol.asyncIterator]().next()).toEqual({
			done: true,
			value: undefined,
		});
	});

	test('owns independent File and Review derivation epochs', () => {
		const harness = createTransportHarness({ fileEpoch: 4, reviewEpoch: 9 });

		expect(harness.transport.bumpWorkerDerivationEpoch('file')).toBe(5);
		expect(harness.transport.workerDerivationEpoch('review')).toBe(9);
		expect(harness.transport.bumpWorkerDerivationEpoch('review')).toBe(10);
		expect(harness.transport.workerDerivationEpoch('file')).toBe(5);
	});

	test('round-trips current File source discovery with the captured File epoch', async () => {
		const harness = createTransportHarness({ fileEpoch: 7, reviewEpoch: 2 });

		const result = await harness.transport.call('file.source.current', {});

		expect(result).toEqual({ source: fileSourceConfiguration(), status: 'available' });
		expect(harness.server.requiredControlRequest('product.call', 0)).toMatchObject({
			call: { method: 'file.source.current', request: {} },
			workerDerivationEpoch: 7,
		});
	});
});
