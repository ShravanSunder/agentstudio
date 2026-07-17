import { randomBytes, randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';

import {
	bridgeProductContentRequestSchema,
	type BridgeProductContentRequest,
} from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	bridgeProductDevBootstrapRequestSchema,
	BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE,
	encodeBridgeProductDevBootstrapDelivery,
	type BridgeProductDevBootstrapDelivery,
	type BridgeProductDevBootstrapRequest,
} from '../../src/core/comm-worker/bridge-product-dev-bootstrap.js';
import {
	bridgeProductFrameAcknowledgementRequestSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from '../../src/core/comm-worker/bridge-product-frame-acknowledgement-contracts.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	bridgeProductSessionBootstrapSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductSessionBootstrap,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import { parseBridgeProductStrictJSON } from '../../src/core/comm-worker/bridge-product-strict-json.js';
import { handleBridgeProductDevCall } from './bridge-product-dev-call-handler.js';
import {
	BridgeProductDevContentProducer,
	type BridgeProductDevContentPayload,
} from './bridge-product-dev-content-producer.js';
import { BridgeProductDevFileAdapter } from './bridge-product-dev-file-adapter.js';
import {
	bridgeProductDevCapabilityFromRequest,
	bridgeProductDevRequestFailureStatus,
	bridgeProductDevSafeErrorMessage,
	encodeBridgeProductDevJSON,
	readBridgeProductDevBoundedRequestBody,
	requireBridgeProductDevJSONMediaType,
	requireBridgeProductDevPost,
	writeBridgeProductDevEmpty,
	writeBridgeProductDevError,
	writeBridgeProductDevJSONBytes,
} from './bridge-product-dev-http.js';
import {
	BridgeProductDevReviewAdapter,
	type BridgeProductDevReviewAdapterPort,
} from './bridge-product-dev-review-adapter.js';
import {
	bridgeProductDevControlIdentity,
	bridgeProductDevRequestError,
	bridgeProductDevRequestMatchesSession,
	isBridgeProductDevExactRetry,
	openBridgeProductDevMetadataWriter,
	reconcileBridgeProductDevSession,
	retireBridgeProductDevSession,
	type BridgeProductDevSession,
} from './bridge-product-dev-session.js';
import { handleBridgeProductDevSubscriptionControl } from './bridge-product-dev-subscription-handler.js';
import type {
	BridgeWorktreeDevProvider,
	BridgeWorktreeDevProviderConfig,
} from './bridge-worktree-dev-provider.js';

const bridgeProductDevMaximumContentProducerCount = 16;

export interface BridgeProductDevCarrierProps {
	readonly createReviewAdapter?: (
		config: Pick<BridgeWorktreeDevProviderConfig, 'baseRef' | 'worktreeRoot'>,
	) => BridgeProductDevReviewAdapterPort;
	readonly getFileProvider: (requestUrl: string | null) => Promise<BridgeWorktreeDevProvider>;
	readonly getReviewSourceConfig: (
		requestUrl: string | null,
	) => Promise<Pick<BridgeWorktreeDevProviderConfig, 'baseRef' | 'worktreeRoot'>>;
}

export interface BridgeProductDevCarrierRequestProps {
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}

export interface BridgeProductDevCarrierSnapshot {
	readonly leases: number;
	readonly pendingSessions: number;
	readonly producers: number;
	readonly responses: number;
	readonly sessions: number;
	readonly subscriptions: number;
	readonly waiters: number;
}

export class BridgeProductDevCarrier {
	readonly #getFileProvider: BridgeProductDevCarrierProps['getFileProvider'];
	readonly #getReviewSourceConfig: BridgeProductDevCarrierProps['getReviewSourceConfig'];
	readonly #createReviewAdapter: NonNullable<BridgeProductDevCarrierProps['createReviewAdapter']>;
	readonly #pendingBootstrapsByCapability = new Map<string, BridgeProductSessionBootstrap>();
	readonly #sessionsByCapability = new Map<string, BridgeProductDevSession>();
	#workerSequence = 0;

	constructor(props: BridgeProductDevCarrierProps) {
		this.#getFileProvider = props.getFileProvider;
		this.#getReviewSourceConfig = props.getReviewSourceConfig;
		this.#createReviewAdapter =
			props.createReviewAdapter ??
			((config): BridgeProductDevReviewAdapter => new BridgeProductDevReviewAdapter(config));
	}

	readonly handleCommandRequest = async (
		props: BridgeProductDevCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		const capability = bridgeProductDevCapabilityFromRequest(props.request);
		if (capability === null || !this.#isRegisteredCapability(capability)) {
			writeBridgeProductDevError(props.response, 401, 'Unauthorized');
			return;
		}
		if (!requireBridgeProductDevJSONMediaType(props)) return;
		try {
			const body = await readBridgeProductDevBoundedRequestBody(props.request);
			const decoded = parseBridgeProductStrictJSON(body);
			const acknowledgement = bridgeProductFrameAcknowledgementRequestSchema.safeParse(decoded);
			if (acknowledgement.success) {
				this.#handleFrameObservation({
					acknowledgement: acknowledgement.data,
					capability,
					response: props.response,
				});
				return;
			}
			if (isFrameObservationPackage(decoded)) {
				writeBridgeProductDevError(props.response, 400, 'Invalid Bridge product request');
				return;
			}
			const request = bridgeProductControlRequestSchema.parse(decoded);
			const existingSession = this.#sessionsByCapability.get(capability);
			if (existingSession === undefined) {
				this.#openSession({ body, capability, props, request });
				return;
			}
			await this.#enqueueControl(existingSession, async (): Promise<void> => {
				await this.#processControlRequest({ body, props, request, session: existingSession });
			});
		} catch (error: unknown) {
			writeBridgeProductDevError(
				props.response,
				bridgeProductDevRequestFailureStatus(error),
				bridgeProductDevSafeErrorMessage(error),
			);
		}
	};

	readonly handleStreamRequest = async (
		props: BridgeProductDevCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		const session = this.#authenticatedSession(props.request);
		if (session === null) {
			writeBridgeProductDevError(props.response, 401, 'Unauthorized');
			return;
		}
		if (!requireBridgeProductDevJSONMediaType(props)) return;
		try {
			const request = bridgeProductMetadataStreamRequestSchema.parse(
				parseBridgeProductStrictJSON(await readBridgeProductDevBoundedRequestBody(props.request)),
			);
			const metadataWriter = openBridgeProductDevMetadataWriter({
				request,
				response: props.response,
				session,
			});
			if (metadataWriter === null) {
				writeBridgeProductDevError(props.response, 409, 'Metadata stream conflict');
				return;
			}
			props.response.statusCode = 200;
			props.response.setHeader('Content-Type', 'application/octet-stream');
			props.response.flushHeaders();
			await metadataWriter.writeMetadataFrame({
				kind: 'metadataStream.accepted',
				resumeDisposition: 'snapshot_required',
			});
			await metadataWriter.writeMetadataFrame({
				activityRevision: 1,
				kind: 'pane.presentation',
				nativeActivity: 'foreground',
				refreshingLanes: [],
			});
		} catch (error: unknown) {
			this.#handleStreamingError(props.response, error);
		}
	};

	readonly handleContentRequest = async (
		props: BridgeProductDevCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		const session = this.#authenticatedSession(props.request);
		if (session === null) {
			writeBridgeProductDevError(props.response, 401, 'Unauthorized');
			return;
		}
		if (!requireBridgeProductDevJSONMediaType(props)) return;
		try {
			const request = bridgeProductContentRequestSchema.parse(
				parseBridgeProductStrictJSON(await readBridgeProductDevBoundedRequestBody(props.request)),
			);
			if (!bridgeProductDevRequestMatchesSession(request, session)) {
				writeBridgeProductDevError(props.response, 401, 'Unauthorized');
				return;
			}
			if (
				session.contentProducersByRequestId.has(request.contentRequestId) ||
				session.contentProducersByRequestId.size >= bridgeProductDevMaximumContentProducerCount
			) {
				writeBridgeProductDevError(props.response, 409, 'Content response conflict');
				return;
			}
			const content = await this.#loadContent(session, request);
			if (content === null) {
				writeBridgeProductDevError(props.response, 404, 'Unknown content descriptor');
				return;
			}
			props.response.statusCode = 200;
			props.response.setHeader('Content-Type', 'application/octet-stream');
			const producer = new BridgeProductDevContentProducer({ request, response: props.response });
			session.contentProducersByRequestId.set(request.contentRequestId, producer);
			props.response.once('close', (): void => {
				producer.cancel();
				if (session.contentProducersByRequestId.get(request.contentRequestId) === producer) {
					session.contentProducersByRequestId.delete(request.contentRequestId);
				}
			});
			try {
				await producer.start(content);
			} finally {
				if (session.contentProducersByRequestId.get(request.contentRequestId) === producer) {
					session.contentProducersByRequestId.delete(request.contentRequestId);
				}
			}
		} catch (error: unknown) {
			this.#handleStreamingError(props.response, error);
		}
	};

	readonly handleBootstrapRequest = async (
		props: BridgeProductDevCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		if (!requireBridgeProductDevJSONMediaType(props)) return;
		try {
			const request = bridgeProductDevBootstrapRequestSchema.parse(
				parseBridgeProductStrictJSON(await readBridgeProductDevBoundedRequestBody(props.request)),
			);
			const delivery = this.issueBootstrap(request);
			const envelope = encodeBridgeProductDevBootstrapDelivery(delivery);
			new Uint8Array(delivery.productCapability).fill(0);
			props.response.statusCode = 200;
			props.response.setHeader('Cache-Control', 'no-store');
			props.response.setHeader('Content-Type', BRIDGE_PRODUCT_DEV_BOOTSTRAP_RESPONSE_MEDIA_TYPE);
			props.response.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
			props.response.end(envelope, (): void => {
				envelope.fill(0);
			});
		} catch (error: unknown) {
			writeBridgeProductDevError(
				props.response,
				bridgeProductDevRequestFailureStatus(error),
				bridgeProductDevSafeErrorMessage(error),
			);
		}
	};

	issueBootstrap(request: BridgeProductDevBootstrapRequest): BridgeProductDevBootstrapDelivery {
		this.#workerSequence = (this.#workerSequence + 1) % Number.MAX_SAFE_INTEGER;
		const paneSessionId =
			request.reason === 'initial' ? `vite-dev-pane-${randomUUID()}` : request.paneSessionId;
		if (request.reason === 'workerReplacement') {
			if (!this.#hasPaneAuthority(paneSessionId)) {
				throw new Error('Bridge product dev replacement pane is not registered.');
			}
			this.#retirePaneAuthorities(paneSessionId);
		}
		const bootstrap = bridgeProductSessionBootstrapSchema.parse({
			kind: 'productSession.bootstrap',
			paneSessionId,
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: `vite-dev-worker-${this.#workerSequence.toString(36)}`,
		});
		const capabilityBytes = randomBytes(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH);
		const capability = capabilityBytes.toString('base64url');
		this.#pendingBootstrapsByCapability.set(capability, bootstrap);
		return {
			bootstrap,
			productCapability: Uint8Array.from(capabilityBytes).buffer,
		};
	}

	dispose(): void {
		for (const session of this.#sessionsByCapability.values())
			retireBridgeProductDevSession(session);
		this.#sessionsByCapability.clear();
		this.#pendingBootstrapsByCapability.clear();
	}

	snapshot(): BridgeProductDevCarrierSnapshot {
		let producers = 0;
		let responses = 0;
		let subscriptions = 0;
		let waiters = 0;
		for (const session of this.#sessionsByCapability.values()) {
			subscriptions += session.subscriptionsById.size;
			producers += session.contentProducersByRequestId.size;
			responses += session.metadataWriter === null ? 0 : 1;
			waiters += session.metadataWriter?.snapshot().waiterCount ?? 0;
			for (const producer of session.contentProducersByRequestId.values()) {
				const producerSnapshot = producer.snapshot();
				responses += producerSnapshot.responseCount;
				waiters += producerSnapshot.waiterCount;
			}
		}
		return {
			leases: producers,
			pendingSessions: this.#pendingBootstrapsByCapability.size,
			producers,
			responses,
			sessions: this.#sessionsByCapability.size,
			subscriptions,
			waiters,
		};
	}

	#openSession(props: {
		readonly body: Uint8Array;
		readonly capability: string;
		readonly props: BridgeProductDevCarrierRequestProps;
		readonly request: BridgeProductControlRequest;
	}): void {
		const pendingBootstrap = this.#pendingBootstrapsByCapability.get(props.capability);
		if (
			pendingBootstrap === undefined ||
			props.request.kind !== 'workerSession.open' ||
			props.request.requestSequence !== 1 ||
			props.request.paneSessionId !== pendingBootstrap.paneSessionId ||
			props.request.workerInstanceId !== pendingBootstrap.workerInstanceId ||
			props.request.wireVersion !== pendingBootstrap.wireVersion
		) {
			writeBridgeProductDevError(props.props.response, 401, 'Unauthorized');
			return;
		}
		const providerContext = props.props.request.headers.referer ?? props.props.request.url ?? null;
		let fileAdapterPromise: Promise<BridgeProductDevFileAdapter> | null = null;
		let reviewAdapterPromise: Promise<BridgeProductDevReviewAdapterPort> | null = null;
		const response = bridgeProductControlResponseSchema.parse({
			...bridgeProductDevControlIdentity(props.request),
			kind: 'workerSession.accepted',
			result: null,
		});
		const session: BridgeProductDevSession = {
			abortController: new AbortController(),
			awaitingResync: false,
			cachedRequestBody: Uint8Array.from(props.body),
			cachedResponseBody: encodeBridgeProductDevJSON(response),
			capability: props.capability,
			contentProducersByRequestId: new Map(),
			fileSource: null,
			lastAcceptedRequestSequence: 1,
			lastClosedMetadataStreamSequence: null,
			loadFileAdapter: (): Promise<BridgeProductDevFileAdapter> => {
				fileAdapterPromise ??= this.#getFileProvider(providerContext).then(
					(provider): BridgeProductDevFileAdapter => new BridgeProductDevFileAdapter(provider),
				);
				return fileAdapterPromise;
			},
			loadReviewAdapter: (): Promise<BridgeProductDevReviewAdapterPort> => {
				reviewAdapterPromise ??= this.#getReviewSourceConfig(providerContext).then(
					(config): BridgeProductDevReviewAdapterPort => this.#createReviewAdapter(config),
				);
				return reviewAdapterPromise;
			},
			metadataWriter: null,
			paneSessionId: props.request.paneSessionId,
			pendingControl: Promise.resolve(),
			resyncResumeFromStreamSequence: null,
			reviewSource: null,
			subscriptionsById: new Map(),
			workerInstanceId: props.request.workerInstanceId,
		};
		this.#pendingBootstrapsByCapability.delete(props.capability);
		this.#sessionsByCapability.set(props.capability, session);
		writeBridgeProductDevJSONBytes(props.props.response, session.cachedResponseBody);
	}

	async #processControlRequest(props: {
		readonly body: Uint8Array;
		readonly props: BridgeProductDevCarrierRequestProps;
		readonly request: BridgeProductControlRequest;
		readonly session: BridgeProductDevSession;
	}): Promise<void> {
		if (isBridgeProductDevExactRetry(props.session, props.request, props.body)) {
			writeBridgeProductDevJSONBytes(props.props.response, props.session.cachedResponseBody);
			return;
		}
		if (!bridgeProductDevRequestMatchesSession(props.request, props.session)) {
			writeBridgeProductDevError(props.props.response, 401, 'Unauthorized');
			return;
		}
		if (props.request.requestSequence !== props.session.lastAcceptedRequestSequence + 1) {
			this.#writeControlResponse(
				props.props.response,
				bridgeProductDevRequestError(
					props.request,
					props.session.lastAcceptedRequestSequence + 1,
					'sequence_conflict',
				),
			);
			return;
		}
		const response = await this.#handleControl(props.session, props.request);
		this.#acceptControlRequest(props.session, props.request, props.body, response);
		writeBridgeProductDevJSONBytes(props.props.response, props.session.cachedResponseBody);
	}

	async #handleControl(
		session: BridgeProductDevSession,
		request: BridgeProductControlRequest,
	): Promise<BridgeProductControlResponse> {
		if (session.awaitingResync && request.kind !== 'workerSession.resync') {
			return bridgeProductDevRequestError(
				request,
				session.lastAcceptedRequestSequence + 1,
				'resync_required',
			);
		}
		switch (request.kind) {
			case 'product.call':
				return await handleBridgeProductDevCall(session, request);
			case 'subscription.open':
			case 'subscription.updateBatch':
			case 'subscription.cancel':
				return await handleBridgeProductDevSubscriptionControl(session, request);
			case 'workerSession.resync':
				return reconcileBridgeProductDevSession(session, request);
			case 'workerSession.open':
				return bridgeProductDevRequestError(
					request,
					session.lastAcceptedRequestSequence + 1,
					'sequence_conflict',
				);
		}
		throw new Error('Bridge product dev control request kind is unsupported.');
	}

	#handleFrameObservation(props: {
		readonly acknowledgement: BridgeProductFrameAcknowledgementRequest;
		readonly capability: string;
		readonly response: ServerResponse;
	}): void {
		const session = this.#sessionsByCapability.get(props.capability);
		if (
			session === undefined ||
			props.acknowledgement.paneSessionId !== session.paneSessionId ||
			props.acknowledgement.workerInstanceId !== session.workerInstanceId
		) {
			writeBridgeProductDevError(props.response, 409, 'Frame observation rejected');
			return;
		}
		const disposition =
			props.acknowledgement.streamKind === 'metadata'
				? session.metadataWriter?.observe(props.acknowledgement)
				: session.contentProducersByRequestId
						.get(props.acknowledgement.contentRequestId)
						?.observe(props.acknowledgement);
		if (disposition === 'accepted' || disposition === 'idempotentReplay') {
			writeBridgeProductDevEmpty(props.response, 204);
			return;
		}
		writeBridgeProductDevError(props.response, 409, 'Frame observation rejected');
	}

	async #loadContent(
		session: BridgeProductDevSession,
		request: BridgeProductContentRequest,
	): Promise<BridgeProductDevContentPayload | null> {
		return request.contentKind === 'file.content'
			? await (
					await session.loadFileAdapter()
				).loadContent(request.descriptor, session.abortController.signal)
			: await (
					await session.loadReviewAdapter()
				).loadContent(request.descriptor, session.abortController.signal);
	}

	#retirePaneAuthorities(paneSessionId: string): void {
		for (const [capability, bootstrap] of this.#pendingBootstrapsByCapability) {
			if (bootstrap.paneSessionId === paneSessionId) {
				this.#pendingBootstrapsByCapability.delete(capability);
			}
		}
		for (const [capability, session] of this.#sessionsByCapability) {
			if (session.paneSessionId !== paneSessionId) continue;
			retireBridgeProductDevSession(session);
			this.#sessionsByCapability.delete(capability);
		}
	}

	#isRegisteredCapability(capability: string): boolean {
		return (
			this.#pendingBootstrapsByCapability.has(capability) ||
			this.#sessionsByCapability.has(capability)
		);
	}

	#hasPaneAuthority(paneSessionId: string): boolean {
		for (const bootstrap of this.#pendingBootstrapsByCapability.values()) {
			if (bootstrap.paneSessionId === paneSessionId) return true;
		}
		for (const session of this.#sessionsByCapability.values()) {
			if (session.paneSessionId === paneSessionId) return true;
		}
		return false;
	}

	#authenticatedSession(request: IncomingMessage): BridgeProductDevSession | null {
		const capability = bridgeProductDevCapabilityFromRequest(request);
		return capability === null ? null : (this.#sessionsByCapability.get(capability) ?? null);
	}

	#enqueueControl(session: BridgeProductDevSession, operation: () => Promise<void>): Promise<void> {
		const result = session.pendingControl.then(operation, operation);
		session.pendingControl = result.catch((): void => {});
		return result;
	}

	#acceptControlRequest(
		session: BridgeProductDevSession,
		request: BridgeProductControlRequest,
		body: Uint8Array,
		response: BridgeProductControlResponse,
	): void {
		session.lastAcceptedRequestSequence = request.requestSequence;
		session.cachedRequestBody = Uint8Array.from(body);
		session.cachedResponseBody = encodeBridgeProductDevJSON(response);
	}

	#writeControlResponse(response: ServerResponse, value: BridgeProductControlResponse): void {
		writeBridgeProductDevJSONBytes(
			response,
			encodeBridgeProductDevJSON(bridgeProductControlResponseSchema.parse(value)),
		);
	}

	#handleStreamingError(response: ServerResponse, error: unknown): void {
		if (!response.headersSent) {
			writeBridgeProductDevError(
				response,
				bridgeProductDevRequestFailureStatus(error),
				bridgeProductDevSafeErrorMessage(error),
			);
		} else if (!response.destroyed) {
			response.destroy();
		}
	}
}

export function createBridgeProductDevCarrier(
	props: BridgeProductDevCarrierProps,
): BridgeProductDevCarrier {
	return new BridgeProductDevCarrier(props);
}

function isFrameObservationPackage(value: unknown): boolean {
	return (
		typeof value === 'object' &&
		value !== null &&
		'kind' in value &&
		value.kind === 'stream.frameObserved'
	);
}
