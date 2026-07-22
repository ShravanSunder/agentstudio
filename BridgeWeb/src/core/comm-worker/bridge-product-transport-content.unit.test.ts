import { createHash } from 'node:crypto';

import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgeProductContentIdentityFromDescriptor,
	bridgeProductContentRequestSchema,
	type BridgeProductContentRequest,
	type BridgeProductFileContentDescriptor,
} from './bridge-product-content-contracts.js';
import {
	concatenateBytes,
	encodeMinimalControlFrame,
	encodeMinimalDataFrame,
} from './bridge-product-content-frame-test-support.js';
import { BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES } from './bridge-product-content-response-admission.js';
import {
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_CONTENT_ROUTE,
	BRIDGE_PRODUCT_STREAM_ROUTE,
} from './bridge-product-contract-primitives.js';
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
import { encodeBridgeProductSubscriptionInterestState } from './bridge-product-subscription-interest-state-codec.js';
import {
	createBridgeProductTransport,
	type BridgeProductIdentifierPurpose,
} from './bridge-product-transport.js';

const abcSha256 = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

afterEach(() => {
	vi.unstubAllGlobals();
});

describe('Bridge product content transport', () => {
	test('opens concurrent content outside the control sequence', async () => {
		const harness = createContentTransportHarness(3);
		const first = harness.transport.openContent(
			fileContentDescriptor('descriptor-1'),
			new AbortController().signal,
		);
		const second = harness.transport.openContent(
			fileContentDescriptor('descriptor-2'),
			new AbortController().signal,
		);

		const terminals = await Promise.all([first.terminal, second.terminal]);
		await harness.transport.call('review.markFileViewed', { itemId: 'review-item-1' });

		expect(terminals.map((terminal) => terminal.kind)).toEqual(['complete', 'complete']);
		expect(harness.server.contentRequestHeaders).toEqual([
			{ capability: 'private-capability', contentType: 'application/json' },
			{ capability: 'private-capability', contentType: 'application/json' },
		]);
		expect(harness.server.contentRequests.map((request) => request.workerDerivationEpoch)).toEqual([
			3, 3,
		]);
		expect(harness.server.controlRequests).toHaveLength(1);
		expect(harness.server.controlRequests[0]?.requestSequence).toBe(2);
	});

	test('acknowledges every committed frame with its exact response identity', async () => {
		const harness = createContentTransportHarness(3);
		const content = harness.transport.openContent(
			fileContentDescriptor('descriptor-observed'),
			new AbortController().signal,
		);

		await expect(content.terminal).resolves.toMatchObject({ kind: 'complete' });

		const request = harness.server.contentRequests[0];
		if (request === undefined) throw new Error('Expected one product content request.');
		expect(harness.server.frameAcknowledgements).toEqual(
			[0, 1, 2].map((contentSequence) => ({
				contentRequestId: request.contentRequestId,
				contentSequence,
				kind: 'stream.frameObserved',
				leaseId: request.leaseId,
				paneSessionId: request.paneSessionId,
				streamKind: 'content',
				wireVersion: request.wireVersion,
				workerInstanceId: request.workerInstanceId,
			})),
		);
		expect(harness.server.requestRoutes).toEqual([
			BRIDGE_PRODUCT_CONTENT_ROUTE,
			BRIDGE_PRODUCT_COMMAND_ROUTE,
			BRIDGE_PRODUCT_COMMAND_ROUTE,
			BRIDGE_PRODUCT_COMMAND_ROUTE,
		]);
	});

	test('fails only the response whose observation is rejected', async () => {
		const harness = createContentTransportHarness();
		harness.server.leaveContentOpenAfterAcceptance = true;
		harness.server.nextAcknowledgementStatus = 409;
		const content = harness.transport.openContent(
			fileContentDescriptor('descriptor-rejected-observation'),
			new AbortController().signal,
		);
		const frameIterator = content.frames[Symbol.asyncIterator]();
		const terminalFailure = expect(content.terminal).rejects.toMatchObject({
			failureCode: 'rejected_status',
			name: 'BridgeProductFrameAcknowledgementFailure',
			status: 409,
		});

		await expect(frameIterator.next()).resolves.toMatchObject({
			done: false,
			value: { header: { contentSequence: 0, kind: 'content.accepted' } },
		});
		await terminalFailure;
		await expect(frameIterator.next()).rejects.toMatchObject({ status: 409 });
		expect(harness.server.contentReaderCancelCount).toBe(1);
		expect(harness.server.frameAcknowledgements).toHaveLength(1);
	});

	test('paces content independently from other content, metadata, and control', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentAcknowledgement('content-request-1');
		const first = harness.transport.openContent(
			fileContentDescriptor('descriptor-held-observation'),
			new AbortController().signal,
		);
		let didFirstSettle = false;
		void first.terminal.then(
			(): void => {
				didFirstSettle = true;
			},
			(): void => {},
		);
		await harness.server.waitForFrameAcknowledgementCount(1);

		const second = harness.transport.openContent(
			fileContentDescriptor('descriptor-independent-observation'),
			new AbortController().signal,
		);
		await expect(second.terminal).resolves.toMatchObject({ kind: 'complete' });
		harness.transport.subscribe('review.metadata', { interests: [] });
		await harness.server.waitForMetadataStream();
		harness.server.emitMetadata(metadataAccepted(harness.server.requiredMetadataRequest()));
		await waitForCondition(
			() => harness.transport.metadataStreamDiagnostics?.().acknowledgedFrameCount === 1,
		);
		await expect(
			harness.transport.call('review.markFileViewed', { itemId: 'review-item-independent' }),
		).resolves.toBeNull();

		expect(didFirstSettle).toBe(false);
		expect(
			harness.server.frameAcknowledgements.filter(
				(acknowledgement) =>
					acknowledgement.streamKind === 'content' &&
					acknowledgement.contentRequestId === second.contentRequestId,
			),
		).toHaveLength(3);
		expect(
			harness.server.frameAcknowledgements.filter(
				(acknowledgement) => acknowledgement.streamKind === 'metadata',
			),
		).toHaveLength(1);
		harness.server.releaseHeldContentAcknowledgement();
		await expect(first.terminal).resolves.toMatchObject({ kind: 'complete' });
	});

	test('reserves request capacity for observations while content remains open', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentResponses = true;
		const abortControllers = Array.from({ length: 5 }, () => new AbortController());
		const contentStreams = abortControllers.map((abortController, index) =>
			harness.transport.openContent(
				fileContentDescriptor(`descriptor-admission-${index}`),
				abortController.signal,
			),
		);

		await harness.server.waitForContentRequestCount(
			BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES,
		);
		await Promise.resolve();
		expect(harness.server.contentRequests).toHaveLength(
			BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES,
		);

		abortControllers[0]?.abort(new DOMException('release active admission', 'AbortError'));
		await expect(contentStreams[0]?.terminal).rejects.toThrow();
		await harness.server.waitForContentRequestCount(5);
		expect(harness.server.contentRequests).toHaveLength(5);
		for (const abortController of abortControllers.slice(1)) {
			abortController.abort(new DOMException('test cleanup', 'AbortError'));
		}
		await Promise.allSettled(
			contentStreams.slice(1).map((contentStream) => contentStream.terminal),
		);
	});

	test('cancels the content response reader when its signal aborts', async () => {
		const harness = createContentTransportHarness();
		harness.server.holdContentResponses = true;
		const abortController = new AbortController();
		const content = harness.transport.openContent(
			fileContentDescriptor('descriptor-abort'),
			abortController.signal,
		);
		await harness.server.waitForContentRequestCount(1);

		abortController.abort(new DOMException('cancelled', 'AbortError'));

		await expect(content.terminal).rejects.toThrow();
		expect(harness.server.contentReaderCancelCount).toBe(1);
	});
});

function createContentTransportHarness(fileEpoch = 0): {
	readonly server: TestContentProductServer;
	readonly transport: ReturnType<typeof createBridgeProductTransport>;
} {
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
	const server = new TestContentProductServer();
	vi.stubGlobal('fetch', server.fetch);
	return {
		server,
		transport: createBridgeProductTransport({
			authority,
			controlMux: new BridgeProductControlMux({
				authority,
				createRequestId: sequenceIdentifier('control-request'),
			}),
			createIdentifier: purposeIdentifier(),
			initialWorkerDerivationEpochs: { file: fileEpoch, review: 0 },
		}),
	};
}

class TestContentProductServer {
	readonly contentRequestHeaders: {
		readonly capability: string | null;
		readonly contentType: string | null;
	}[] = [];
	readonly contentRequests: BridgeProductContentRequest[] = [];
	contentReaderCancelCount = 0;
	readonly controlRequests: BridgeProductControlRequest[] = [];
	readonly frameAcknowledgements: BridgeProductFrameAcknowledgementRequest[] = [];
	holdContentResponses = false;
	leaveContentOpenAfterAcceptance = false;
	nextAcknowledgementStatus = 204;
	readonly requestRoutes: string[] = [];
	#heldAcknowledgement: Promise<void> | null = null;
	#heldContentRequestId: string | null = null;
	#metadataController: ReadableStreamDefaultController<Uint8Array> | null = null;
	#metadataRequest: BridgeProductMetadataStreamRequest | null = null;
	#releaseHeldAcknowledgement: (() => void) | null = null;

	readonly fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		const url = input instanceof Request ? input.url : input instanceof URL ? input.href : input;
		this.requestRoutes.push(url);
		if (url === BRIDGE_PRODUCT_CONTENT_ROUTE) return this.#openContent(init);
		if (url === BRIDGE_PRODUCT_STREAM_ROUTE) return this.#openMetadataStream(init);
		if (url !== BRIDGE_PRODUCT_COMMAND_ROUTE) return new Response(null, { status: 404 });
		const body = parseBody(init);
		if (
			typeof body === 'object' &&
			body !== null &&
			'kind' in body &&
			body.kind === 'stream.frameObserved'
		) {
			return await this.#acknowledgeFrame(body);
		}
		return await this.#handleControl(body);
	};

	emitMetadata(frame: BridgeProductMetadataFrame): void {
		if (this.#metadataController === null) throw new Error('Metadata stream is not open.');
		this.#metadataController.enqueue(encodeBridgeProductMetadataFrame(frame));
	}

	holdContentAcknowledgement(contentRequestId: string): void {
		this.#heldContentRequestId = contentRequestId;
		this.#heldAcknowledgement = new Promise<void>((resolve): void => {
			this.#releaseHeldAcknowledgement = resolve;
		});
	}

	releaseHeldContentAcknowledgement(): void {
		const release = this.#releaseHeldAcknowledgement;
		if (release === null) throw new Error('No content acknowledgement is held.');
		this.#heldAcknowledgement = null;
		this.#heldContentRequestId = null;
		this.#releaseHeldAcknowledgement = null;
		release();
	}

	requiredMetadataRequest(): BridgeProductMetadataStreamRequest {
		if (this.#metadataRequest === null) throw new Error('Metadata request is not available.');
		return this.#metadataRequest;
	}

	async waitForContentRequestCount(count: number): Promise<void> {
		await waitForCondition(() => this.contentRequests.length >= count);
	}

	async waitForFrameAcknowledgementCount(count: number): Promise<void> {
		await waitForCondition(() => this.frameAcknowledgements.length >= count);
	}

	async waitForMetadataStream(): Promise<void> {
		await waitForCondition(() => this.#metadataRequest !== null);
	}

	async #acknowledgeFrame(body: unknown): Promise<Response> {
		const request = bridgeProductFrameAcknowledgementRequestSchema.parse(body);
		this.frameAcknowledgements.push(request);
		if (
			request.streamKind === 'content' &&
			request.contentRequestId === this.#heldContentRequestId
		) {
			if (this.#heldAcknowledgement === null) throw new Error('Held acknowledgement is missing.');
			await this.#heldAcknowledgement;
		}
		const status = this.nextAcknowledgementStatus;
		this.nextAcknowledgementStatus = 204;
		return new Response(null, { status });
	}

	async #handleControl(body: unknown): Promise<Response> {
		const request = bridgeProductControlRequestSchema.parse(body);
		this.controlRequests.push(request);
		const identity = {
			paneSessionId: request.paneSessionId,
			requestId: request.requestId,
			requestSequence: request.requestSequence,
			wireVersion: request.wireVersion,
			workerInstanceId: request.workerInstanceId,
		};
		if (request.kind === 'product.call') {
			return jsonResponse({
				...identity,
				call: { method: request.call.method, result: null },
				kind: 'call.completed',
			});
		}
		if (request.kind === 'subscription.open') {
			return jsonResponse({
				...identity,
				interestRevision: 0,
				interestSha256: emptyReviewInterestHash(),
				kind: 'subscription.openAccepted',
				subscriptionId: request.subscriptionId,
				subscriptionKind: request.subscription.subscriptionKind,
			});
		}
		throw new Error(`Unexpected control request ${request.kind}.`);
	}

	#openContent(init?: RequestInit): Response {
		const headers = new Headers(init?.headers);
		this.contentRequestHeaders.push({
			capability: headers.get('X-AgentStudio-Bridge-Product-Capability'),
			contentType: headers.get('Content-Type'),
		});
		const request = bridgeProductContentRequestSchema.parse(parseBody(init));
		this.contentRequests.push(request);
		if (this.holdContentResponses) {
			return new Response(
				new ReadableStream<Uint8Array>({
					cancel: (): void => {
						this.contentReaderCancelCount += 1;
					},
				}),
			);
		}
		const acceptedBody = {
			contentRequestId: request.contentRequestId,
			declaredByteLength: 3,
			expectedSha256: abcSha256,
			identity: bridgeProductContentIdentityFromDescriptor(request.descriptor),
			leaseId: request.leaseId,
			maximumBytes: request.descriptor.maximumBytes,
			paneSessionId: request.paneSessionId,
			wireVersion: request.wireVersion,
			workerDerivationEpoch: request.workerDerivationEpoch,
			workerInstanceId: request.workerInstanceId,
		};
		if (this.leaveContentOpenAfterAcceptance) {
			return new Response(
				new ReadableStream<Uint8Array>({
					cancel: (): void => {
						this.contentReaderCancelCount += 1;
					},
					start: (controller): void => {
						controller.enqueue(encodeMinimalControlFrame(0x01, 0, acceptedBody));
					},
				}),
			);
		}
		return new Response(
			Uint8Array.from(
				concatenateBytes(
					encodeMinimalControlFrame(0x01, 0, acceptedBody),
					encodeMinimalDataFrame(1, 0, Uint8Array.from([97, 98, 99])),
					encodeMinimalControlFrame(0x03, 2, {
						endOfSource: true,
						observedByteLength: 3,
						observedSha256: abcSha256,
					}),
				),
			).buffer,
		);
	}

	#openMetadataStream(init?: RequestInit): Response {
		this.#metadataRequest = bridgeProductMetadataStreamRequestSchema.parse(parseBody(init));
		return new Response(
			new ReadableStream<Uint8Array>({
				start: (controller): void => {
					this.#metadataController = controller;
				},
			}),
		);
	}
}

function metadataAccepted(request: BridgeProductMetadataStreamRequest): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		kind: 'metadataStream.accepted',
		metadataStreamId: request.metadataStreamId,
		paneSessionId: request.paneSessionId,
		resumeDisposition: 'snapshot_required',
		streamSequence: 0,
		wireVersion: request.wireVersion,
		workerInstanceId: request.workerInstanceId,
	});
}

function fileContentDescriptor(descriptorId: string): BridgeProductFileContentDescriptor {
	return {
		contentKind: 'file.content',
		declaredByteLength: 3,
		descriptorId,
		encoding: 'utf-8',
		expectedSha256: abcSha256,
		fileId: `file-${descriptorId}`,
		maximumBytes: 3,
		source: {
			repoId: '00000000-0000-4000-8000-000000000001',
			rootRevisionToken: null,
			sourceCursor: 'source-cursor-1',
			sourceId: 'source-1',
			subscriptionGeneration: 1,
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
		window: { kind: 'prefix', maximumBytes: 3, maximumLines: 10_000, startByte: 0 },
	} as const;
}

function emptyReviewInterestHash(): string {
	return createHash('sha256')
		.update(
			encodeBridgeProductSubscriptionInterestState({
				interests: [],
				subscriptionKind: 'review.metadata',
			}),
		)
		.digest('hex');
}

function parseBody(init?: RequestInit): unknown {
	const body = init?.body;
	if (body instanceof ArrayBuffer) return JSON.parse(new TextDecoder().decode(body)) as unknown;
	if (ArrayBuffer.isView(body)) return JSON.parse(new TextDecoder().decode(body)) as unknown;
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
		// oxlint-disable-next-line eslint/no-await-in-loop -- Advances one bounded stream event turn.
		await new Promise<void>((resolve): void => {
			setImmediate(resolve);
		});
	}
	throw new Error('Timed out waiting for the bounded protocol condition.');
}
