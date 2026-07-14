import { createHash } from 'node:crypto';

import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_STREAM_ROUTE,
} from './bridge-product-contract-primitives.js';
import type { BridgeProductFileSourceIdentity } from './bridge-product-file-contracts.js';
import {
	bridgeProductFrameAcknowledgementRequestSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from './bridge-product-frame-acknowledgement-contracts.js';
import { encodeBridgeProductMetadataFrame } from './bridge-product-metadata-frame-codec.js';
import {
	BridgeProductControlMux,
	type BridgeProductSessionAuthority,
} from './bridge-product-session-authority.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductMetadataFrameSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductMetadataFrame,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import type { BridgeProductSubscriptionOptions } from './bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from './bridge-product-subscription-interest-state-codec.js';
import {
	createBridgeProductTransport,
	type BridgeProductIdentifierPurpose,
} from './bridge-product-transport.js';

afterEach(() => {
	vi.unstubAllGlobals();
});

describe('Bridge product transport', () => {
	test('keeps a File subscription alive through its initial source event', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe('file.metadata', {
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

		await expect(nextEvent).resolves.toMatchObject({
			done: false,
			value: { eventKind: 'file.sourceAccepted', source: fileSourceIdentity() },
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
		const review = harness.transport.subscribe('review.metadata', {
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

		expect(await reviewEvent).toMatchObject({
			done: false,
			value: { eventKind: 'review.sourceAccepted', packageId: 'package-1' },
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

		const file = harness.transport.subscribe('file.metadata', {
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
		const subscription = harness.transport.subscribe('review.metadata', { interests: [] });
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
		const subscription = harness.transport.subscribe('review.metadata', { interests: [] });
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
		const subscription = harness.transport.subscribe('review.metadata', { interests: [] });
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
		const subscription = harness.transport.subscribe('file.metadata', {
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

	test('settles cancel only after the correlated terminal metadata frame', async () => {
		const harness = createTransportHarness();
		const subscription = harness.transport.subscribe('review.metadata', { interests: [] });
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

interface TransportHarness {
	readonly server: TestProductServer;
	readonly transport: ReturnType<typeof createBridgeProductTransport>;
}

function createTransportHarness(
	epochs: { readonly fileEpoch?: number; readonly reviewEpoch?: number } = {},
): TransportHarness {
	const authority: BridgeProductSessionAuthority = {
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: 2 * 1024 * 1024,
				maximumMetadataFrameBytes: 256 * 1024,
				maximumQueuedStreamBytes: 4 * 1024 * 1024,
				maximumQueuedStreamFrames: 64,
				maximumRequestBodyBytes: 128 * 1024,
				terminalFrameReserve: 1,
			},
			wireVersion: 2,
			workerInstanceId: 'worker-instance-1',
		},
		capabilityHeader: 'private-capability',
		open: Promise.resolve(),
	};
	const server = new TestProductServer();
	vi.stubGlobal('fetch', server.fetch);
	const controlMux = new BridgeProductControlMux({
		authority,
		createRequestId: sequenceIdentifier('control-request'),
	});
	return {
		server,
		transport: createBridgeProductTransport({
			authority,
			controlMux,
			createIdentifier: purposeIdentifier(),
			initialWorkerDerivationEpochs: {
				file: epochs.fileEpoch ?? 0,
				review: epochs.reviewEpoch ?? 0,
			},
		}),
	};
}

class TestProductServer {
	readonly controlRequests: BridgeProductControlRequest[] = [];
	readonly frameAcknowledgements: BridgeProductFrameAcknowledgementRequest[] = [];
	metadataFetchCount = 0;
	metadataReaderCancelCount = 0;
	nextAcknowledgementStatus = 204;
	readonly requestRoutes: string[] = [];
	#heldOpen: (() => void) | null = null;
	#holdOpen = false;
	#metadataController: ReadableStreamDefaultController<Uint8Array> | null = null;
	#metadataRequest: BridgeProductMetadataStreamRequest | null = null;

	readonly fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const url = input instanceof Request ? input.url : input instanceof URL ? input.href : input;
		this.requestRoutes.push(url);
		if (url === BRIDGE_PRODUCT_STREAM_ROUTE) return this.#openMetadataStream(init);
		if (url === BRIDGE_PRODUCT_COMMAND_ROUTE) {
			const body = parseBody(init);
			return typeof body === 'object' &&
				body !== null &&
				'kind' in body &&
				body.kind === 'stream.frameObserved'
				? this.#acknowledgeFrame(body)
				: await this.#handleControl(body);
		}
		return new Response(null, { status: 404 });
	};

	async #acknowledgeFrame(body: unknown): Promise<Response> {
		const request = bridgeProductFrameAcknowledgementRequestSchema.parse(body);
		this.frameAcknowledgements.push(request);
		const status = this.nextAcknowledgementStatus;
		this.nextAcknowledgementStatus = 204;
		return new Response(null, { status });
	}

	emitMetadata(frame: BridgeProductMetadataFrame): void {
		if (this.#metadataController === null) throw new Error('Metadata stream is not open.');
		this.#metadataController.enqueue(encodeBridgeProductMetadataFrame(frame));
	}

	holdNextSubscriptionOpen(): void {
		this.#holdOpen = true;
	}

	releaseHeldSubscriptionOpen(): void {
		const release = this.#heldOpen;
		this.#heldOpen = null;
		release?.();
	}

	requiredControlRequest<TKind extends BridgeProductControlRequest['kind']>(
		kind: TKind,
		index: number,
	): Extract<BridgeProductControlRequest, { kind: TKind }> {
		const request = this.controlRequests.filter(
			(candidate): candidate is Extract<BridgeProductControlRequest, { kind: TKind }> =>
				candidate.kind === kind,
		)[index];
		if (request === undefined) throw new Error(`Missing control request ${kind} at ${index}.`);
		return request;
	}

	requiredMetadataRequest(): BridgeProductMetadataStreamRequest {
		if (this.#metadataRequest === null) throw new Error('Metadata request is not available.');
		return this.#metadataRequest;
	}

	async waitForControlKind(kind: BridgeProductControlRequest['kind'], count = 1): Promise<void> {
		await waitForCondition(
			() => this.controlRequests.filter((request) => request.kind === kind).length >= count,
		);
	}

	async waitForMetadataStream(): Promise<void> {
		await waitForCondition(() => this.#metadataRequest !== null);
	}

	#openMetadataStream(init?: RequestInit): Response {
		this.metadataFetchCount += 1;
		this.#metadataRequest = bridgeProductMetadataStreamRequestSchema.parse(parseBody(init));
		return new Response(
			new ReadableStream<Uint8Array>({
				cancel: (): void => {
					this.metadataReaderCancelCount += 1;
				},
				start: (controller): void => {
					this.#metadataController = controller;
				},
			}),
		);
	}

	async #handleControl(body: unknown): Promise<Response> {
		const request = bridgeProductControlRequestSchema.parse(body);
		this.controlRequests.push(request);
		if (request.kind === 'subscription.open' && this.#holdOpen) {
			this.#holdOpen = false;
			await new Promise<void>((resolve): void => {
				this.#heldOpen = resolve;
			});
		}
		const identity = {
			paneSessionId: request.paneSessionId,
			requestId: request.requestId,
			requestSequence: request.requestSequence,
			wireVersion: request.wireVersion,
			workerInstanceId: request.workerInstanceId,
		};
		switch (request.kind) {
			case 'product.call':
				return jsonResponse({
					...identity,
					call: {
						method: request.call.method,
						result:
							request.call.method === 'file.source.current'
								? { source: fileSourceConfiguration(), status: 'available' }
								: null,
					},
					kind: 'call.completed',
				});
			case 'subscription.open':
				return jsonResponse({
					...identity,
					interestRevision: 0,
					interestSha256: emptyInterestHash(request.subscription.subscriptionKind),
					kind: 'subscription.openAccepted',
					subscriptionId: request.subscriptionId,
					subscriptionKind: request.subscription.subscriptionKind,
				});
			case 'subscription.updateBatch':
				return jsonResponse({
					...identity,
					batchIndex: request.batchIndex,
					disposition: 'committed',
					kind: 'subscription.updateBatchAccepted',
					subscriptionId: request.subscriptionId,
					subscriptionKind: request.subscriptionKind,
					targetInterestRevision: request.targetInterestRevision,
					targetInterestSha256: request.targetInterestSha256,
					updateId: request.updateId,
				});
			case 'subscription.cancel':
				return jsonResponse({
					...identity,
					kind: 'subscription.cancelAccepted',
					subscriptionId: request.subscriptionId,
					subscriptionKind: request.subscriptionKind,
				});
			case 'workerSession.open':
			case 'workerSession.resync':
				throw new Error(`Unexpected control request ${request.kind}.`);
		}
		return assertNeverControlRequest(request);
	}
}

function metadataAccepted(
	request: BridgeProductMetadataStreamRequest,
	streamSequence: number,
): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(request, streamSequence),
		kind: 'metadataStream.accepted',
		resumeDisposition: 'snapshot_required',
	});
}

function subscriptionAccepted(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly kind: 'file.metadata' | 'review.metadata';
	readonly request: BridgeProductMetadataStreamRequest;
	readonly streamSequence: number;
	readonly subscriptionId: string;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(props.request, props.streamSequence),
		cursor: null,
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.accepted',
		sourceGeneration: 0,
		subscriptionId: props.subscriptionId,
		subscriptionKind: props.kind,
		subscriptionSequence: 0,
		workerDerivationEpoch: props.epoch,
	});
}

function reviewData(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly streamSequence: number;
	readonly subscriptionId: string;
	readonly subscriptionSequence: number;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(props.request, props.streamSequence),
		cursor: 'cursor-1',
		data: {
			event: {
				eventKind: 'review.sourceAccepted',
				generation: 1,
				packageId: 'package-1',
				revision: 1,
				sourceIdentity: 'source-1',
			},
			subscriptionKind: 'review.metadata',
		},
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.data',
		sourceGeneration: 1,
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'review.metadata',
		subscriptionSequence: props.subscriptionSequence,
		workerDerivationEpoch: props.epoch,
	});
}

function fileSourceAcceptedData(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly streamSequence: number;
	readonly subscriptionId: string;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(props.request, props.streamSequence),
		cursor: 'source-cursor-1',
		data: {
			event: { eventKind: 'file.sourceAccepted', source: fileSourceIdentity() },
			subscriptionKind: 'file.metadata',
		},
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.data',
		sourceGeneration: 1,
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'file.metadata',
		subscriptionSequence: 1,
		workerDerivationEpoch: props.epoch,
	});
}

function subscriptionCancelled(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly streamSequence: number;
	readonly subscriptionId: string;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(props.request, props.streamSequence),
		cursor: null,
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.cancelled',
		sourceGeneration: 0,
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'review.metadata',
		subscriptionSequence: 1,
		workerDerivationEpoch: props.epoch,
	});
}

function interestBarrier(
	update: Extract<BridgeProductControlRequest, { kind: 'subscription.updateBatch' }>,
	request: BridgeProductMetadataStreamRequest,
	streamSequence: number,
	subscriptionSequence: number,
): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(request, streamSequence),
		cursor: null,
		interestRevision: update.targetInterestRevision,
		interestSha256: update.targetInterestSha256,
		kind: 'subscription.interestsCommitted',
		sourceGeneration: 1,
		subscriptionId: update.subscriptionId,
		subscriptionKind: update.subscriptionKind,
		subscriptionSequence,
		updateId: update.updateId,
		workerDerivationEpoch: update.workerDerivationEpoch,
	});
}

function metadataIdentity(
	request: BridgeProductMetadataStreamRequest,
	streamSequence: number,
): {
	readonly metadataStreamId: string;
	readonly paneSessionId: string;
	readonly streamSequence: number;
	readonly wireVersion: 2;
	readonly workerInstanceId: string;
} {
	return {
		metadataStreamId: request.metadataStreamId,
		paneSessionId: request.paneSessionId,
		streamSequence,
		wireVersion: request.wireVersion,
		workerInstanceId: request.workerInstanceId,
	};
}

function fileSourceConfiguration(): BridgeProductSubscriptionOptions<'file.metadata'>['source'] {
	return {
		cwdScope: null,
		freshness: 'live',
		includeStatuses: true,
		repoId: '00000000-0000-4000-8000-000000000001',
		rootPathToken: 'root-token-1',
		worktreeId: '00000000-0000-4000-8000-000000000002',
	} as const;
}

function fileSourceIdentity(): BridgeProductFileSourceIdentity {
	return {
		repoId: '00000000-0000-4000-8000-000000000001',
		rootRevisionToken: null,
		sourceCursor: 'source-cursor-1',
		sourceId: 'source-1',
		subscriptionGeneration: 1,
		worktreeId: '00000000-0000-4000-8000-000000000002',
	} as const;
}

function emptyInterestHash(kind: 'file.metadata' | 'review.metadata'): string {
	return kind === 'file.metadata'
		? interestHash({ interests: [], pathScope: [], subscriptionKind: kind })
		: interestHash({ interests: [], subscriptionKind: kind });
}

function interestHash(
	state: Parameters<typeof encodeBridgeProductSubscriptionInterestState>[0],
): string {
	return createHash('sha256')
		.update(encodeBridgeProductSubscriptionInterestState(state))
		.digest('hex');
}

function parseBody(init?: RequestInit): unknown {
	const body = init?.body;
	if (body instanceof ArrayBuffer) {
		return JSON.parse(new TextDecoder().decode(body)) as unknown;
	}
	if (ArrayBuffer.isView(body)) {
		return JSON.parse(new TextDecoder().decode(body)) as unknown;
	}
	throw new Error('Expected a binary request body.');
}

function jsonResponse(value: unknown): Response {
	return new Response(JSON.stringify(value), {
		headers: { 'Content-Type': 'application/json' },
		status: 200,
	});
}

function purposeIdentifier(): (purpose: BridgeProductIdentifierPurpose) => string {
	const sequenceByPurpose = new Map<BridgeProductIdentifierPurpose, number>();
	return (purpose): string => {
		const sequence = (sequenceByPurpose.get(purpose) ?? 0) + 1;
		sequenceByPurpose.set(purpose, sequence);
		return `${purpose}-${sequence}`;
	};
}

function sequenceIdentifier(prefix: string): () => string {
	let sequence = 0;
	return (): string => `${prefix}-${(sequence += 1)}`;
}

async function waitForCondition(predicate: () => boolean): Promise<void> {
	for (let attempt = 0; attempt < 100; attempt += 1) {
		if (predicate()) return;
		// eslint-disable-next-line no-await-in-loop -- Advances one bounded stream event turn.
		await new Promise<void>((resolve): void => {
			setImmediate(resolve);
		});
	}
	throw new Error('Timed out waiting for the bounded protocol condition.');
}

function assertNeverControlRequest(request: never): never {
	throw new Error(`Unhandled control request: ${JSON.stringify(request)}`);
}
