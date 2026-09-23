import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgeProductFileMetadataApplicationProtocol,
	bridgeProductReviewAnnotationMetadataApplicationProtocol,
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
	requestErrorResponse,
	reviewData,
	subscriptionAccepted,
	subscriptionCancelled,
	subscriptionReset,
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

	test('settles cancel on native acknowledgement and drains the correlated terminal frame', async () => {
		// Arrange
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

		// Act: native acknowledges the cancel but has not yet delivered its terminal.
		await subscription.cancel();

		// Assert: the consumer is done without waiting on a frame, and the terminal that
		// follows drains cleanly instead of naming an unknown subscription.
		expect(await subscription.events[Symbol.asyncIterator]().next()).toEqual({
			done: true,
			value: undefined,
		});
		harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 0,
				interestHash: emptyHash,
				request,
				streamSequence: 2,
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await harness.server.waitForFrameAcknowledgementCount(3);
		expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
			activeSubscriptionCount: 0,
			failureStage: null,
			routeFailureCode: null,
		});
	});

	test('releases an older-epoch sibling before any request at the advanced epoch reaches native', async () => {
		// Arrange: a Review annotation subscription is admitted at epoch 1 and its open
		// is still in flight, so its release must queue behind that open.
		const harness = createTransportHarness({ reviewEpoch: 1 });
		const sibling = harness.transport.subscribe(
			bridgeProductReviewAnnotationMetadataApplicationProtocol,
			{},
		);
		const siblingTerminal = sibling.events[Symbol.asyncIterator]().next();
		void siblingTerminal.catch((): void => {});
		await harness.server.waitForMetadataStream();
		harness.server.holdNextSubscriptionOpen();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));
		await harness.server.waitForControlKind('subscription.open');

		// Act: Review advances and immediately subscribes its replacement metadata.
		const nextEpoch = harness.transport.advanceWorkerDerivationEpoch('review');
		harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, { interests: [] });
		harness.server.releaseHeldSubscriptionOpen();
		await harness.server.waitForControlKind('subscription.open', 2);

		// Assert: native sees the epoch-1 cancel before the first epoch-2 request, and the
		// sibling's consumer learns it was retired for the new epoch.
		expect(
			harness.server.controlRequests.map((request) =>
				request.kind === 'subscription.open'
					? `open:${request.subscription.subscriptionKind}:${request.workerDerivationEpoch}`
					: request.kind === 'subscription.cancel'
						? `cancel:${request.subscriptionKind}:${request.workerDerivationEpoch}`
						: request.kind,
			),
		).toEqual([
			'open:review.annotations:1',
			'cancel:review.annotations:1',
			'open:review.metadata:2',
		]);
		await expect(siblingTerminal).rejects.toMatchObject({
			name: 'BridgeProductSubscriptionEpochRetiredError',
			nextWorkerDerivationEpoch: nextEpoch,
		});
	});

	test('keeps routing a retired sibling whose cancel native refused until its in-flight terminal lands', async () => {
		// Arrange: native already reset the Review annotation subscription and dropped
		// its record, so it refuses the retirement cancel while the reset frame is still
		// queued on the shared metadata stream.
		const harness = createTransportHarness();
		const sibling = harness.transport.subscribe(
			bridgeProductReviewAnnotationMetadataApplicationProtocol,
			{},
		);
		const siblingTerminal = sibling.events[Symbol.asyncIterator]().next();
		void siblingTerminal.catch((): void => {});
		await harness.server.waitForMetadataStream();
		const request = harness.server.requiredMetadataRequest();
		const siblingHash = emptyInterestHash('review.annotations');
		harness.server.emitMetadata(metadataAccepted(request, 0));
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: 0,
				interestHash: siblingHash,
				kind: 'review.annotations',
				request,
				streamSequence: 1,
				subscriptionId: sibling.subscriptionId,
			}),
		);
		await harness.server.waitForControlKind('subscription.open');
		await harness.server.waitForFrameAcknowledgementCount(2);
		harness.server.cancelHandler = (cancel): Response => requestErrorResponse(cancel, 'internal');

		// Act: Review advances and subscribes its metadata; native then delivers the
		// sibling's queued reset ahead of the new subscription's frames.
		const nextEpoch = harness.transport.advanceWorkerDerivationEpoch('review');
		const metadata = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [],
		});
		await harness.server.waitForControlKind('subscription.open', 2);
		const metadataHash = emptyInterestHash('review.metadata');
		harness.server.emitMetadata(
			subscriptionReset({
				epoch: 0,
				interestHash: siblingHash,
				kind: 'review.annotations',
				reason: 'stale_source',
				request,
				streamSequence: 2,
				subscriptionId: sibling.subscriptionId,
				subscriptionSequence: 1,
			}),
		);
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: nextEpoch,
				interestHash: metadataHash,
				kind: 'review.metadata',
				request,
				streamSequence: 3,
				subscriptionId: metadata.subscriptionId,
			}),
		);
		harness.server.emitMetadata(
			reviewData({
				epoch: nextEpoch,
				interestHash: metadataHash,
				request,
				streamSequence: 4,
				subscriptionId: metadata.subscriptionId,
				subscriptionSequence: 1,
			}),
		);

		// Assert: the refused sibling's terminal drains instead of poisoning the shared
		// stream, so Review metadata keeps flowing and the sibling is retired, not failed.
		const metadataEvent = await metadata.events[Symbol.asyncIterator]().next();
		expect(metadataEvent.done).toBe(false);
		expect(harness.transport.metadataStreamDiagnostics?.().routeFailureCode).toBeNull();
		await expect(siblingTerminal).rejects.toMatchObject({
			name: 'BridgeProductSubscriptionEpochRetiredError',
			nextWorkerDerivationEpoch: nextEpoch,
		});
	});

	test('advances past a subscription whose interest barrier native never delivers', async () => {
		// Arrange: native accepts the initial interest update but never sends its
		// barrier, as when it silently dropped the subscription.
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [{ itemIds: ['item-1'], lane: 'foreground' }] },
		);
		const terminal = subscription.events[Symbol.asyncIterator]().next();
		void terminal.catch((): void => {});
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest(), 0));
		await harness.server.waitForControlKind('subscription.updateBatch');
		const queuedUpdate = subscription.update({
			interests: [{ itemIds: ['item-2'], lane: 'foreground' }],
		});
		void queuedUpdate.catch((): void => {});

		// Act
		const nextEpoch = harness.transport.advanceWorkerDerivationEpoch('review');
		const call = harness.transport.call('review.markFileViewed', { itemId: 'item-1' });

		// Assert: the release reaches native, the gated call follows it, and everything
		// that waited on the missing barrier settles with the retirement.
		await call;
		expect(
			harness.server.controlRequests.map((request) =>
				request.kind === 'product.call' ? `call:${request.workerDerivationEpoch}` : request.kind,
			),
		).toEqual([
			'subscription.open',
			'subscription.updateBatch',
			'subscription.cancel',
			`call:${nextEpoch}`,
		]);
		const retirement = {
			name: 'BridgeProductSubscriptionEpochRetiredError',
			nextWorkerDerivationEpoch: nextEpoch,
		};
		await expect(terminal).rejects.toMatchObject(retirement);
		await expect(queuedUpdate).rejects.toMatchObject(retirement);
	});

	test('does not hold an advance behind a consumer cancel whose terminal frame is still in flight', async () => {
		// Arrange: the consumer cancelled and native acknowledged, but native has not
		// yet delivered the cancelled frame.
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
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
				subscriptionId: subscription.subscriptionId,
			}),
		);
		await harness.server.waitForControlKind('subscription.open');
		await subscription.cancel();

		// Act
		const nextEpoch = harness.transport.advanceWorkerDerivationEpoch('review');
		await harness.transport.call('review.markFileViewed', { itemId: 'item-1' });

		// Assert: one cancel for the subscription, and the call went out at the new epoch.
		expect(
			harness.server.controlRequests.map((control) =>
				control.kind === 'product.call' ? `call:${control.workerDerivationEpoch}` : control.kind,
			),
		).toEqual(['subscription.open', 'subscription.cancel', `call:${nextEpoch}`]);
	});

	test('settles an update on a retired subscription locally and drains its later terminal', async () => {
		// Arrange
		const harness = createTransportHarness();
		const retired = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
			interests: [],
		});
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
				subscriptionId: retired.subscriptionId,
			}),
		);
		await harness.server.waitForControlKind('subscription.open');
		const nextEpoch = harness.transport.advanceWorkerDerivationEpoch('review');
		await harness.server.waitForControlKind('subscription.cancel');

		// Act: the consumer still updates the retired subscription, then native ends it.
		const lateUpdate = retired.update({ interests: [{ itemIds: ['item-1'], lane: 'foreground' }] });
		await expect(lateUpdate).rejects.toMatchObject({
			name: 'BridgeProductSubscriptionEpochRetiredError',
			nextWorkerDerivationEpoch: nextEpoch,
		});
		harness.server.emitMetadata(
			subscriptionCancelled({
				epoch: 0,
				interestHash: emptyHash,
				request,
				streamSequence: 2,
				subscriptionId: retired.subscriptionId,
			}),
		);
		const replacement = harness.transport.subscribe(
			bridgeProductReviewMetadataApplicationProtocol,
			{ interests: [] },
		);
		await harness.server.waitForControlKind('subscription.open', 2);
		harness.server.emitMetadata(
			subscriptionAccepted({
				epoch: nextEpoch,
				interestHash: emptyHash,
				kind: 'review.metadata',
				request,
				streamSequence: 3,
				subscriptionId: replacement.subscriptionId,
			}),
		);
		harness.server.emitMetadata(
			reviewData({
				epoch: nextEpoch,
				interestHash: emptyHash,
				request,
				streamSequence: 4,
				subscriptionId: replacement.subscriptionId,
				subscriptionSequence: 1,
			}),
		);

		// Assert: the update never reached native and the shared stream kept flowing.
		expect((await replacement.events[Symbol.asyncIterator]().next()).done).toBe(false);
		expect(harness.server.controlRequests.map((control) => control.kind)).not.toContain(
			'subscription.updateBatch',
		);
		expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
			failureStage: null,
			streamOpenCount: 1,
		});
	});

	test.each([
		['a native refusal', 'subscription_control_invalid_request'],
		['an HTTP failure', 'subscription_control_http_rejection'],
	] as const)(
		'keeps the stream alive when an update fails with %s and native frames for it follow',
		async (failure, expectedCode) => {
			// Arrange
			const harness = createTransportHarness();
			const failed = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
				interests: [],
			});
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
					subscriptionId: failed.subscriptionId,
				}),
			);
			await harness.server.waitForControlKind('subscription.open');
			harness.server.updateHandler = (update): Response =>
				failure === 'a native refusal'
					? requestErrorResponse(update, 'invalid_request')
					: new Response(null, { status: 409 });

			// Act: the update fails locally while native keeps serving the subscription.
			await expect(
				failed.update({ interests: [{ itemIds: ['item-1'], lane: 'foreground' }] }),
			).rejects.toThrow();
			harness.server.updateHandler = null;
			harness.server.emitMetadata(
				reviewData({
					epoch: 0,
					interestHash: emptyHash,
					request,
					streamSequence: 2,
					subscriptionId: failed.subscriptionId,
					subscriptionSequence: 1,
				}),
			);
			const sibling = harness.transport.subscribe(bridgeProductReviewMetadataApplicationProtocol, {
				interests: [],
			});
			await harness.server.waitForControlKind('subscription.open', 2);
			harness.server.emitMetadata(
				subscriptionAccepted({
					epoch: 0,
					interestHash: emptyHash,
					kind: 'review.metadata',
					request,
					streamSequence: 3,
					subscriptionId: sibling.subscriptionId,
				}),
			);
			harness.server.emitMetadata(
				reviewData({
					epoch: 0,
					interestHash: emptyHash,
					request,
					streamSequence: 4,
					subscriptionId: sibling.subscriptionId,
					subscriptionSequence: 1,
				}),
			);

			// Assert: the failed subscription's frame drained, the sibling received its
			// data on the same stream, and the failure cause is still reported.
			expect((await sibling.events[Symbol.asyncIterator]().next()).done).toBe(false);
			expect(harness.transport.metadataStreamDiagnostics?.()).toMatchObject({
				failureStage: null,
				lastSubscriptionTermination: {
					outcome: 'failed',
					reason: expectedCode,
					subscriptionId: failed.subscriptionId,
				},
				streamOpenCount: 1,
			});
		},
	);

	test('owns independent File and Review derivation epochs', () => {
		const harness = createTransportHarness({ fileEpoch: 4, reviewEpoch: 9 });

		expect(harness.transport.advanceWorkerDerivationEpoch('file')).toBe(5);
		expect(harness.transport.workerDerivationEpoch('review')).toBe(9);
		expect(harness.transport.advanceWorkerDerivationEpoch('review')).toBe(10);
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
