import { createHash } from 'node:crypto';

import { vi } from 'vitest';

import { executeAgentStudioBridgeProductRequest } from '../bridge-product-agent-studio-request-executor.js';
import { createBridgeProductDeferred } from '../bridge-product-async-queue.js';
import type { BridgeProductFileSourceIdentity } from '../bridge-product-file-contracts.js';
import {
	bridgeProductFrameAcknowledgementRequestSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from '../bridge-product-frame-acknowledgement-contracts.js';
import { bridgeProductMetadataApplicationRegistry } from '../bridge-product-metadata-application-registry.js';
import { encodeBridgeProductMetadataFrame } from '../bridge-product-metadata-frame-codec.js';
import {
	BridgeProductControlMux,
	type BridgeProductSessionAuthority,
} from '../bridge-product-session-authority.js';
import {
	assertBridgeProductResyncReconciliationMatchesRequest,
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataFrameSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductMetadataFrame,
	type BridgeProductMetadataStreamRequest,
} from '../bridge-product-session-contracts.js';
import type {
	BridgeProductSubscriptionKind,
	BridgeProductSubscriptionOptions,
} from '../bridge-product-subscription-contracts.js';
import { bridgeProductSubscriptionKindSchema } from '../bridge-product-subscription-contracts.js';
import { encodeBridgeProductSubscriptionInterestState } from '../bridge-product-subscription-interest-state-codec.js';
import {
	createBridgeProductTransport,
	type BridgeProductIdentifierPurpose,
} from '../bridge-product-transport.js';

export interface TransportHarness {
	readonly server: TestProductServer;
	readonly transport: ReturnType<typeof createBridgeProductTransport>;
}

const activeHarnesses = new Set<TransportHarness>();

export async function disposeTransportHarnesses(): Promise<void> {
	const harnesses = [...activeHarnesses];
	try {
		for (const harness of harnesses) harness.server.shutdown();
		await Promise.all(
			harnesses.map((harness) =>
				waitForCondition(
					() => harness.transport.metadataStreamDiagnostics?.().activeSubscriptionCount === 0,
				),
			),
		);
	} finally {
		activeHarnesses.clear();
	}
}

export function createTransportHarness(
	options: {
		readonly fileEpoch?: number;
		readonly reviewEpoch?: number;
	} = {},
): TransportHarness {
	const authority: BridgeProductSessionAuthority = {
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: 2 * 1024 * 1024,
				maximumMetadataFrameBytes: 128 * 1024,
				maximumQueuedStreamBytes: 4 * 1024 * 1024,
				maximumQueuedStreamFrames: 64,
				maximumRequestBodyBytes: 256 * 1024,
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
		executeProductRequest: executeAgentStudioBridgeProductRequest,
	});
	const harness: TransportHarness = {
		server,
		transport: createBridgeProductTransport({
			authority,
			controlMux,
			createIdentifier: purposeIdentifier(),
			executeProductRequest: executeAgentStudioBridgeProductRequest,
			initialWorkerDerivationEpochs: {
				file: options.fileEpoch ?? 0,
				review: options.reviewEpoch ?? 0,
			},
			metadataApplicationRegistry: bridgeProductMetadataApplicationRegistry,
		}),
	};
	activeHarnesses.add(harness);
	return harness;
}

export class TestProductServer {
	#closed = false;
	readonly #shutdownSignal = createBridgeProductDeferred<never>();

	constructor() {
		void this.#shutdownSignal.promise.catch((): void => {});
	}
	readonly controlRequests: BridgeProductControlRequest[] = [];
	readonly frameAcknowledgements: BridgeProductFrameAcknowledgementRequest[] = [];
	metadataFetchCount = 0;
	metadataReaderCancelCount = 0;
	nextAcknowledgementStatus = 204;
	nextAcknowledgementHandler:
		| ((request: BridgeProductFrameAcknowledgementRequest) => Response | Promise<Response>)
		| null = null;
	resyncHandler:
		| ((
				request: Extract<BridgeProductControlRequest, { kind: 'workerSession.resync' }>,
		  ) => Promise<Response> | Response)
		| null = null;
	readonly requestRoutes: string[] = [];
	#heldOpen: (() => void) | null = null;
	#holdOpen = false;
	#metadataControllers: ReadableStreamDefaultController<Uint8Array>[] = [];
	readonly #metadataRequests: BridgeProductMetadataStreamRequest[] = [];

	readonly fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
		if (this.#closed) throw new Error('Test product server is closed.');
		const url = input instanceof Request ? input.url : input instanceof URL ? input.href : input;
		this.requestRoutes.push(url);
		if (url === 'agentstudio://rpc/stream') return this.#openMetadataStream(init);
		if (url === 'agentstudio://rpc/command') {
			const body = parseBody(init);
			return typeof body === 'object' &&
				body !== null &&
				'kind' in body &&
				body.kind === 'stream.frameObserved'
				? await Promise.race([this.#acknowledgeFrame(body), this.#shutdownSignal.promise])
				: await Promise.race([this.#handleControl(body), this.#shutdownSignal.promise]);
		}
		return new Response(null, { status: 404 });
	};

	async #acknowledgeFrame(body: unknown): Promise<Response> {
		const request = bridgeProductFrameAcknowledgementRequestSchema.parse(body);
		this.frameAcknowledgements.push(request);
		const handler = this.nextAcknowledgementHandler;
		this.nextAcknowledgementHandler = null;
		if (handler !== null) return handler(request);
		const status = this.nextAcknowledgementStatus;
		this.nextAcknowledgementStatus = 204;
		return new Response(null, { status });
	}

	emitMetadata(frame: BridgeProductMetadataFrame): void {
		const controller = this.#metadataControllers.at(-1);
		if (controller === undefined) throw new Error('Metadata stream is not open.');
		controller.enqueue(encodeBridgeProductMetadataFrame(frame));
	}

	emitMetadataPrefix(frame: BridgeProductMetadataFrame): void {
		const controller = this.#metadataControllers.at(-1);
		if (controller === undefined) throw new Error('Metadata stream is not open.');
		controller.enqueue(encodeBridgeProductMetadataFrame(frame).subarray(0, 2));
	}

	failMetadataReader(error: Error): void {
		const controller = this.#metadataControllers.at(-1);
		if (controller === undefined) throw new Error('Metadata stream is not open.');
		controller.error(error);
	}

	endMetadataStream(): void {
		const controller = this.#metadataControllers.at(-1);
		if (controller === undefined) throw new Error('Metadata stream is not open.');
		controller.close();
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

	requiredMetadataRequest(
		index = this.#metadataRequests.length - 1,
	): BridgeProductMetadataStreamRequest {
		const request = this.#metadataRequests[index];
		if (request === undefined) throw new Error(`Missing metadata request at ${index}.`);
		return request;
	}

	async waitForControlKind(kind: BridgeProductControlRequest['kind'], count = 1): Promise<void> {
		await waitForCondition(
			() => this.controlRequests.filter((request) => request.kind === kind).length >= count,
		);
	}

	async waitForFrameAcknowledgementCount(count: number): Promise<void> {
		await waitForCondition(() => this.frameAcknowledgements.length >= count);
	}

	async waitForMetadataStream(count = 1): Promise<void> {
		await waitForCondition(() => this.#metadataRequests.length >= count);
	}

	shutdown(): void {
		if (this.#closed) return;
		this.#closed = true;
		this.#shutdownSignal.reject(new Error('Test product server is closed.'));
		this.releaseHeldSubscriptionOpen();
		for (const controller of this.#metadataControllers) {
			try {
				controller.close();
			} catch {
				// A deliberately failed physical stream is already terminal.
			}
		}
		this.#metadataControllers = [];
	}

	#openMetadataStream(init?: RequestInit): Response {
		this.metadataFetchCount += 1;
		this.#metadataRequests.push(bridgeProductMetadataStreamRequestSchema.parse(parseBody(init)));
		return new Response(
			new ReadableStream<Uint8Array>({
				cancel: (): void => {
					this.metadataReaderCancelCount += 1;
				},
				start: (controller): void => {
					this.#metadataControllers.push(controller);
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
			case 'workerSession.resync':
				if (this.resyncHandler !== null) return await this.resyncHandler(request);
				return jsonResponse(validatedRetainedResyncResponse(request, identity));
			case 'workerSession.open':
				throw new Error(`Unexpected control request ${request.kind}.`);
		}
		return assertNeverControlRequest(request);
	}
}

function validatedRetainedResyncResponse(
	request: Extract<BridgeProductControlRequest, { kind: 'workerSession.resync' }>,
	identity: {
		readonly paneSessionId: string;
		readonly requestId: string;
		readonly requestSequence: number;
		readonly wireVersion: 2;
		readonly workerInstanceId: string;
	},
): ReturnType<typeof bridgeProductControlResponseSchema.parse> {
	const response = bridgeProductControlResponseSchema.parse({
		...identity,
		kind: 'resync.accepted',
		metadataStreamSequenceBarrier: request.lastAcceptedStreamSequence,
		nextExpectedRequestSequence: request.requestSequence + 1,
		reconciliation: request.activeSubscriptions.map((subscription) => ({
			disposition: 'retained',
			interestRevision: subscription.interestRevision,
			interestSha256: subscription.interestSha256,
			subscriptionId: subscription.subscriptionId,
			subscriptionKind: subscription.subscriptionKind,
			workerDerivationEpoch: subscription.workerDerivationEpoch,
		})),
	});
	assertBridgeProductResyncReconciliationMatchesRequest({ request, response });
	return response;
}

export function metadataAccepted(
	request: BridgeProductMetadataStreamRequest,
	streamSequence: number,
	resumeDisposition: 'resumed' | 'snapshot_required' = 'snapshot_required',
): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(request, streamSequence),
		kind: 'metadataStream.accepted',
		resumeDisposition,
	});
}

export function subscriptionAccepted(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly kind: BridgeProductSubscriptionKind;
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

export function reviewData(props: {
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
				operationCorrelationId: null,
				packageId: 'package-1',
				publicationId: '00000000-0000-7000-8000-000000000001',
				revision: 1,
				sourceIdentity: 'source-1',
			},
			subscriptionKind: 'review.metadata',
		},
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.data',
		operationCorrelationId: null,
		sourceGeneration: 1,
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'review.metadata',
		subscriptionSequence: props.subscriptionSequence,
		workerDerivationEpoch: props.epoch,
	});
}

export function fileSourceAcceptedData(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly sourceGeneration?: number;
	readonly streamSequence: number;
	readonly subscriptionId: string;
	readonly subscriptionSequence?: number;
}): BridgeProductMetadataFrame {
	const sourceGeneration = props.sourceGeneration ?? 1;
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(props.request, props.streamSequence),
		cursor: `source-cursor-${sourceGeneration}`,
		data: {
			event: {
				eventKind: 'file.sourceAccepted',
				source: fileSourceIdentity(sourceGeneration),
			},
			subscriptionKind: 'file.metadata',
		},
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.data',
		operationCorrelationId: null,
		sourceGeneration,
		subscriptionId: props.subscriptionId,
		subscriptionKind: 'file.metadata',
		subscriptionSequence: props.subscriptionSequence ?? 1,
		workerDerivationEpoch: props.epoch,
	});
}

export function subscriptionCancelled(props: {
	readonly epoch: number;
	readonly interestHash: string;
	readonly kind?: BridgeProductSubscriptionKind;
	readonly request: BridgeProductMetadataStreamRequest;
	readonly sourceGeneration?: number;
	readonly streamSequence: number;
	readonly subscriptionId: string;
	readonly subscriptionSequence?: number;
}): BridgeProductMetadataFrame {
	return bridgeProductMetadataFrameSchema.parse({
		...metadataIdentity(props.request, props.streamSequence),
		cursor: null,
		interestRevision: 0,
		interestSha256: props.interestHash,
		kind: 'subscription.cancelled',
		sourceGeneration: props.sourceGeneration ?? 0,
		subscriptionId: props.subscriptionId,
		subscriptionKind: props.kind ?? 'review.metadata',
		subscriptionSequence: props.subscriptionSequence ?? 1,
		workerDerivationEpoch: props.epoch,
	});
}

export function interestBarrier(
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

export function fileSourceConfiguration(): BridgeProductSubscriptionOptions<'file.metadata'>['source'] {
	return {
		cwdScope: null,
		freshness: 'live',
		includeStatuses: true,
		repoId: '00000000-0000-4000-8000-000000000001',
		rootPathToken: 'root-token-1',
		worktreeId: '00000000-0000-4000-8000-000000000002',
	} as const;
}

export function fileSourceIdentity(sourceGeneration = 1): BridgeProductFileSourceIdentity {
	return {
		repoId: '00000000-0000-4000-8000-000000000001',
		rootRevisionToken: null,
		sourceCursor: `source-cursor-${sourceGeneration}`,
		sourceId: `source-${sourceGeneration}`,
		subscriptionGeneration: sourceGeneration,
		worktreeId: '00000000-0000-4000-8000-000000000002',
	} as const;
}

export function emptyInterestHash(kind: string): string {
	const validatedKind = bridgeProductSubscriptionKindSchema.parse(kind);
	switch (validatedKind) {
		case 'file.annotations':
		case 'review.annotations':
			return interestHash({ subscriptionKind: validatedKind });
		case 'file.metadata':
			return interestHash({ interests: [], pathScope: [], subscriptionKind: validatedKind });
		case 'review.metadata':
			return interestHash({ interests: [], subscriptionKind: validatedKind });
	}
	throw new Error('Unsupported Bridge product subscription kind.');
}

export function interestHash(
	state: Parameters<typeof encodeBridgeProductSubscriptionInterestState>[0],
): string {
	return createHash('sha256')
		.update(encodeBridgeProductSubscriptionInterestState(state))
		.digest('hex');
}

export async function waitForCondition(predicate: () => boolean): Promise<void> {
	const deadlineMilliseconds = performance.now() + 2000;
	while (performance.now() < deadlineMilliseconds) {
		if (predicate()) return;
		// eslint-disable-next-line no-await-in-loop -- Yield to actual protocol/crypto work; the deadline bounds failure, not success latency.
		await new Promise<void>((resolve): void => {
			setImmediate(resolve);
		});
	}
	throw new Error('Timed out waiting for the bounded protocol condition.');
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

function assertNeverControlRequest(request: never): never {
	throw new Error(`Unhandled control request: ${JSON.stringify(request)}`);
}
