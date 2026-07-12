import type { IncomingMessage, ServerResponse } from 'node:http';

import { bridgeProductContentRequestSchema } from '../../src/core/comm-worker/bridge-product-content-contracts.js';
import { BridgeProductContentFrameEncoder } from '../../src/core/comm-worker/bridge-product-content-frame-codec.js';
import { BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES } from '../../src/core/comm-worker/bridge-product-contract-primitives.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
} from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import { parseBridgeProductStrictJSON } from '../../src/core/comm-worker/bridge-product-strict-json.js';
import type { BridgeProductSubscriptionEvent } from '../../src/core/comm-worker/bridge-product-subscription-contracts.js';
import { BridgeProductDevFileAdapter } from './bridge-product-dev-file-adapter.js';
import {
	bridgeProductDevContentAcceptedHeader,
	bridgeProductDevControlIdentity,
	bridgeProductDevFileInterestState,
	bridgeProductDevInterestHash,
	bridgeProductDevRequestError,
	bridgeProductDevRequestMatchesSession,
	emptyBridgeProductDevFileInterestState,
	isBridgeProductDevExactRetry,
	openBridgeProductDevMetadataWriter,
	reconcileBridgeProductDevFileSession,
	type BridgeProductDevFileSession,
	type BridgeProductDevFileSubscription,
} from './bridge-product-dev-file-session.js';
import {
	bridgeProductDevCapabilityFromRequest,
	bridgeProductDevRequestFailureStatus,
	bridgeProductDevSafeErrorMessage,
	encodeBridgeProductDevJSON,
	readBridgeProductDevBoundedRequestBody,
	requireBridgeProductDevPost,
	writeBridgeProductDevError,
	writeBridgeProductDevJSONBytes,
	writeBridgeProductDevResponseChunk,
} from './bridge-product-dev-http.js';
import {
	BridgeProductDevMetadataWriter,
	type BridgeProductDevSubscriptionFrameIdentity,
	type BridgeProductDevSubscriptionFramePayload,
} from './bridge-product-dev-metadata-writer.js';
import type { BridgeWorktreeDevProvider } from './bridge-worktree-dev-provider.js';

export interface BridgeProductDevFileCarrierProps {
	readonly getProvider: (requestUrl: string | null) => Promise<BridgeWorktreeDevProvider>;
}

export interface BridgeProductDevFileCarrierRequestProps {
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}

export class BridgeProductDevFileCarrier {
	readonly #getProvider: BridgeProductDevFileCarrierProps['getProvider'];
	readonly #sessionsByCapability = new Map<string, BridgeProductDevFileSession>();

	constructor(props: BridgeProductDevFileCarrierProps) {
		this.#getProvider = props.getProvider;
	}

	readonly handleCommandRequest = async (
		props: BridgeProductDevFileCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		const capability = bridgeProductDevCapabilityFromRequest(props.request);
		if (capability === null) {
			writeBridgeProductDevError(props.response, 401, 'Unauthorized');
			return;
		}
		try {
			const body = await readBridgeProductDevBoundedRequestBody(props.request);
			const request = bridgeProductControlRequestSchema.parse(parseBridgeProductStrictJSON(body));
			const existingSession = this.#sessionsByCapability.get(capability);
			if (existingSession === undefined) {
				await this.#openSession({ body, capability, props, request });
				return;
			}
			if (isBridgeProductDevExactRetry(existingSession, request, body)) {
				writeBridgeProductDevJSONBytes(props.response, existingSession.cachedResponseBody);
				return;
			}
			if (!bridgeProductDevRequestMatchesSession(request, existingSession)) {
				writeBridgeProductDevError(props.response, 401, 'Unauthorized');
				return;
			}
			if (request.requestSequence !== existingSession.lastAcceptedRequestSequence + 1) {
				this.#writeControlResponse(
					props.response,
					bridgeProductDevRequestError(
						request,
						existingSession.lastAcceptedRequestSequence + 1,
						'sequence_conflict',
					),
				);
				return;
			}
			const response = await this.#handleControl(existingSession, request);
			this.#acceptControlRequest(existingSession, request, body, response);
			writeBridgeProductDevJSONBytes(props.response, existingSession.cachedResponseBody);
		} catch (error: unknown) {
			writeBridgeProductDevError(
				props.response,
				bridgeProductDevRequestFailureStatus(error),
				bridgeProductDevSafeErrorMessage(error),
			);
		}
	};

	readonly handleStreamRequest = async (
		props: BridgeProductDevFileCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		const session = this.#authenticatedSession(props.request);
		if (session === null) {
			writeBridgeProductDevError(props.response, 401, 'Unauthorized');
			return;
		}
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
		} catch (error: unknown) {
			if (!props.response.headersSent) {
				writeBridgeProductDevError(
					props.response,
					bridgeProductDevRequestFailureStatus(error),
					bridgeProductDevSafeErrorMessage(error),
				);
			} else if (!props.response.destroyed) {
				props.response.destroy(error instanceof Error ? error : undefined);
			}
		}
	};

	readonly handleContentRequest = async (
		props: BridgeProductDevFileCarrierRequestProps,
	): Promise<void> => {
		if (!requireBridgeProductDevPost(props)) return;
		const session = this.#authenticatedSession(props.request);
		if (session === null) {
			writeBridgeProductDevError(props.response, 401, 'Unauthorized');
			return;
		}
		try {
			const request = bridgeProductContentRequestSchema.parse(
				parseBridgeProductStrictJSON(await readBridgeProductDevBoundedRequestBody(props.request)),
			);
			if (request.contentKind !== 'file.content') {
				writeBridgeProductDevError(props.response, 400, 'Unsupported content kind');
				return;
			}
			if (!bridgeProductDevRequestMatchesSession(request, session)) {
				writeBridgeProductDevError(props.response, 401, 'Unauthorized');
				return;
			}
			const content = session.adapter.content(request.descriptor);
			if (content === null) {
				writeBridgeProductDevError(props.response, 404, 'Unknown content descriptor');
				return;
			}
			props.response.statusCode = 200;
			props.response.setHeader('Content-Type', 'application/octet-stream');
			const encoder = new BridgeProductContentFrameEncoder(request);
			await writeBridgeProductDevResponseChunk(
				props.response,
				encoder.encode({
					header: bridgeProductDevContentAcceptedHeader(request),
					payload: new Uint8Array(),
				}),
			);
			let contentSequence = 1;
			for (
				let offsetBytes = 0;
				offsetBytes < content.bytes.byteLength;
				offsetBytes += BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES
			) {
				if (props.response.destroyed) return;
				const payload = content.bytes.slice(
					offsetBytes,
					offsetBytes + BRIDGE_PRODUCT_MAXIMUM_CONTENT_DATA_PAYLOAD_BYTES,
				);
				// oxlint-disable-next-line no-await-in-loop -- Content frames preserve offset order and backpressure.
				await writeBridgeProductDevResponseChunk(
					props.response,
					encoder.encode({
						header: { contentSequence, kind: 'content.data', offsetBytes },
						payload,
					}),
				);
				contentSequence += 1;
			}
			await writeBridgeProductDevResponseChunk(
				props.response,
				encoder.encode({
					header: {
						contentSequence,
						endOfSource: content.endOfSource,
						kind: 'content.end',
						observedByteLength: content.bytes.byteLength,
						observedSha256: content.descriptor.expectedSha256,
					},
					payload: new Uint8Array(),
				}),
			);
			encoder.finish();
			props.response.end();
		} catch (error: unknown) {
			if (!props.response.headersSent) {
				writeBridgeProductDevError(
					props.response,
					bridgeProductDevRequestFailureStatus(error),
					bridgeProductDevSafeErrorMessage(error),
				);
			} else if (!props.response.destroyed) {
				props.response.destroy(error instanceof Error ? error : undefined);
			}
		}
	};

	async #openSession(props: {
		readonly body: Uint8Array;
		readonly capability: string;
		readonly props: BridgeProductDevFileCarrierRequestProps;
		readonly request: BridgeProductControlRequest;
	}): Promise<void> {
		if (props.request.kind !== 'workerSession.open' || props.request.requestSequence !== 1) {
			writeBridgeProductDevError(props.props.response, 401, 'Unauthorized');
			return;
		}
		const providerContext = props.props.request.headers.referer ?? props.props.request.url ?? null;
		const provider = await this.#getProvider(providerContext);
		const response = bridgeProductControlResponseSchema.parse({
			...bridgeProductDevControlIdentity(props.request),
			kind: 'workerSession.accepted',
			result: null,
		});
		const session: BridgeProductDevFileSession = {
			adapter: new BridgeProductDevFileAdapter(provider),
			awaitingResync: false,
			cachedRequestBody: Uint8Array.from(props.body),
			cachedResponseBody: encodeBridgeProductDevJSON(response),
			lastAcceptedRequestSequence: 1,
			lastClosedMetadataStreamSequence: null,
			metadataWriter: null,
			paneSessionId: props.request.paneSessionId,
			source: null,
			subscription: null,
			resyncResumeFromStreamSequence: null,
			workerInstanceId: props.request.workerInstanceId,
		};
		this.#sessionsByCapability.set(props.capability, session);
		writeBridgeProductDevJSONBytes(props.props.response, session.cachedResponseBody);
	}

	async #handleControl(
		session: BridgeProductDevFileSession,
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
				return await this.#handleCall(session, request);
			case 'subscription.open':
				return await this.#openSubscription(session, request);
			case 'subscription.updateBatch':
				return await this.#updateSubscription(session, request);
			case 'subscription.cancel':
				return await this.#cancelSubscription(session, request);
			case 'workerSession.resync':
				return reconcileBridgeProductDevFileSession(session, request);
			case 'workerSession.open':
				return bridgeProductDevRequestError(
					request,
					session.lastAcceptedRequestSequence + 1,
					'sequence_conflict',
				);
		}
		throw new Error('Unsupported Bridge product dev control request.');
	}

	async #handleCall(
		session: BridgeProductDevFileSession,
		request: Extract<BridgeProductControlRequest, { readonly kind: 'product.call' }>,
	): Promise<BridgeProductControlResponse> {
		if (request.call.method === 'file.source.current') {
			session.source ??= await session.adapter.loadSource();
			return bridgeProductControlResponseSchema.parse({
				...bridgeProductDevControlIdentity(request),
				call: {
					method: request.call.method,
					result: { source: session.source.configuration, status: 'available' },
				},
				kind: 'call.completed',
			});
		}
		if (request.call.method === 'file.activeViewerMode.update') {
			return bridgeProductControlResponseSchema.parse({
				...bridgeProductDevControlIdentity(request),
				call: { method: request.call.method, result: null },
				kind: 'call.completed',
			});
		}
		return bridgeProductDevRequestError(
			request,
			session.lastAcceptedRequestSequence + 1,
			'unsupported_call',
		);
	}

	async #openSubscription(
		session: BridgeProductDevFileSession,
		request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.open' }>,
	): Promise<BridgeProductControlResponse> {
		if (
			request.subscription.subscriptionKind !== 'file.metadata' ||
			session.subscription !== null ||
			session.metadataWriter === null
		) {
			return bridgeProductDevRequestError(
				request,
				session.lastAcceptedRequestSequence + 1,
				'unsupported_subscription',
			);
		}
		session.source ??= await session.adapter.loadSource();
		if (
			JSON.stringify(request.subscription.source) !== JSON.stringify(session.source.configuration)
		) {
			return bridgeProductDevRequestError(
				request,
				session.lastAcceptedRequestSequence + 1,
				'invalid_request',
			);
		}
		const emptyInterestState = emptyBridgeProductDevFileInterestState();
		const subscription: BridgeProductDevFileSubscription = {
			interestHash: bridgeProductDevInterestHash(emptyInterestState),
			interestLanesByPath: new Map(),
			interestRevision: 0,
			pathScope: new Set(),
			sequence: 0,
			subscriptionId: request.subscriptionId,
			workerDerivationEpoch: request.workerDerivationEpoch,
		};
		session.subscription = subscription;
		const response = bridgeProductControlResponseSchema.parse({
			...bridgeProductDevControlIdentity(request),
			interestRevision: 0,
			interestSha256: subscription.interestHash,
			kind: 'subscription.openAccepted',
			subscriptionId: subscription.subscriptionId,
			subscriptionKind: 'file.metadata',
		});
		await this.#writeSubscriptionFrame(session, subscription, {
			kind: 'subscription.accepted',
		});
		const initialDataWrites = [
			this.#writeSubscriptionData(session, subscription, {
				eventKind: 'file.sourceAccepted',
				source: session.source.identity,
			}),
			...session.source.treeEvents.map((event) =>
				this.#writeSubscriptionData(session, subscription, event),
			),
		];
		void Promise.all(initialDataWrites).catch((): void => {});
		return response;
	}

	async #updateSubscription(
		session: BridgeProductDevFileSession,
		request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.updateBatch' }>,
	): Promise<BridgeProductControlResponse> {
		const subscription = session.subscription;
		if (
			subscription === null ||
			request.subscriptionKind !== 'file.metadata' ||
			request.subscriptionId !== subscription.subscriptionId ||
			request.workerDerivationEpoch !== subscription.workerDerivationEpoch ||
			request.batchCount !== 1 ||
			request.batchIndex !== 0 ||
			request.baseInterestRevision !== subscription.interestRevision ||
			request.baseInterestSha256 !== subscription.interestHash
		) {
			return bridgeProductDevRequestError(
				request,
				session.lastAcceptedRequestSequence + 1,
				'invalid_request',
			);
		}
		const nextInterestLanesByPath = new Map(subscription.interestLanesByPath);
		const nextPathScope = new Set(subscription.pathScope);
		for (const path of request.delta.removePaths) nextInterestLanesByPath.delete(path);
		for (const addition of request.delta.add) {
			nextInterestLanesByPath.set(addition.path, addition.lane);
		}
		for (const path of request.delta.removePathScope) nextPathScope.delete(path);
		for (const path of request.delta.addPathScope) nextPathScope.add(path);
		const targetState = bridgeProductDevFileInterestState({
			interestLanesByPath: nextInterestLanesByPath,
			pathScope: nextPathScope,
		});
		const targetHash = bridgeProductDevInterestHash(targetState);
		if (targetHash !== request.targetInterestSha256) {
			return bridgeProductDevRequestError(
				request,
				session.lastAcceptedRequestSequence + 1,
				'invalid_request',
			);
		}
		subscription.interestLanesByPath.clear();
		for (const [path, lane] of nextInterestLanesByPath) {
			subscription.interestLanesByPath.set(path, lane);
		}
		subscription.pathScope.clear();
		for (const path of nextPathScope) subscription.pathScope.add(path);
		subscription.interestRevision = request.targetInterestRevision;
		subscription.interestHash = targetHash;
		const response = bridgeProductControlResponseSchema.parse({
			...bridgeProductDevControlIdentity(request),
			batchIndex: 0,
			disposition: 'committed',
			kind: 'subscription.updateBatchAccepted',
			subscriptionId: subscription.subscriptionId,
			subscriptionKind: 'file.metadata',
			targetInterestRevision: request.targetInterestRevision,
			targetInterestSha256: targetHash,
			updateId: request.updateId,
		});
		await this.#writeSubscriptionFrame(session, subscription, {
			kind: 'subscription.interestsCommitted',
			updateId: request.updateId,
		});
		void this.#writeDemandedDescriptors(session, subscription, request.delta.add);
		return response;
	}

	async #writeDemandedDescriptors(
		session: BridgeProductDevFileSession,
		subscription: BridgeProductDevFileSubscription,
		additions: readonly { readonly path: string }[],
	): Promise<void> {
		try {
			for (const addition of additions) {
				// oxlint-disable-next-line no-await-in-loop -- Descriptor events preserve demand order.
				const descriptorEvent = await session.adapter.loadDescriptor(addition.path);
				if (session.subscription !== subscription) return;
				// oxlint-disable-next-line no-await-in-loop -- Metadata backpressure preserves descriptor order.
				await this.#writeSubscriptionData(session, subscription, descriptorEvent);
			}
		} catch {
			const metadataWriter = session.metadataWriter;
			if (metadataWriter === null) return;
			try {
				await metadataWriter.writeMetadataFrame({
					code: 'internal',
					kind: 'metadataStream.error',
					retryable: false,
					safeMessage: null,
				});
			} catch {
				// The stream may already be closed by the original descriptor failure.
			} finally {
				metadataWriter.end();
			}
		}
	}

	async #cancelSubscription(
		session: BridgeProductDevFileSession,
		request: Extract<BridgeProductControlRequest, { readonly kind: 'subscription.cancel' }>,
	): Promise<BridgeProductControlResponse> {
		const subscription = session.subscription;
		if (
			subscription === null ||
			request.subscriptionKind !== 'file.metadata' ||
			request.subscriptionId !== subscription.subscriptionId
		) {
			return bridgeProductDevRequestError(
				request,
				session.lastAcceptedRequestSequence + 1,
				'invalid_request',
			);
		}
		const response = bridgeProductControlResponseSchema.parse({
			...bridgeProductDevControlIdentity(request),
			kind: 'subscription.cancelAccepted',
			subscriptionId: subscription.subscriptionId,
			subscriptionKind: 'file.metadata',
		});
		await this.#writeSubscriptionFrame(session, subscription, {
			kind: 'subscription.cancelled',
		});
		session.subscription = null;
		return response;
	}

	#writeSubscriptionData(
		session: BridgeProductDevFileSession,
		subscription: BridgeProductDevFileSubscription,
		event: BridgeProductSubscriptionEvent<'file.metadata'>,
	): Promise<void> {
		return this.#writeSubscriptionFrame(session, subscription, {
			data: { event, subscriptionKind: 'file.metadata' },
			kind: 'subscription.data',
		});
	}

	#writeSubscriptionFrame(
		session: BridgeProductDevFileSession,
		subscription: BridgeProductDevFileSubscription,
		frame: BridgeProductDevSubscriptionFramePayload,
	): Promise<void> {
		return this.#requiredMetadataWriter(session).writeSubscriptionFrame(
			this.#subscriptionFrameIdentity(session, subscription),
			subscription,
			frame,
		);
	}

	#subscriptionFrameIdentity(
		session: BridgeProductDevFileSession,
		subscription: BridgeProductDevFileSubscription,
	): BridgeProductDevSubscriptionFrameIdentity {
		return {
			cursor: session.source?.identity.sourceCursor ?? null,
			interestRevision: subscription.interestRevision,
			interestSha256: subscription.interestHash,
			sourceGeneration: session.source?.identity.subscriptionGeneration ?? 0,
			subscriptionId: subscription.subscriptionId,
			subscriptionKind: 'file.metadata',
			workerDerivationEpoch: subscription.workerDerivationEpoch,
		};
	}

	#requiredMetadataWriter(session: BridgeProductDevFileSession): BridgeProductDevMetadataWriter {
		const metadataWriter = session.metadataWriter;
		if (metadataWriter === null || metadataWriter.response.destroyed) {
			throw new Error('Bridge product dev metadata stream is unavailable.');
		}
		return metadataWriter;
	}

	#authenticatedSession(request: IncomingMessage): BridgeProductDevFileSession | null {
		const capability = bridgeProductDevCapabilityFromRequest(request);
		return capability === null ? null : (this.#sessionsByCapability.get(capability) ?? null);
	}

	#acceptControlRequest(
		session: BridgeProductDevFileSession,
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
}

export function createBridgeProductDevFileCarrier(
	props: BridgeProductDevFileCarrierProps,
): BridgeProductDevFileCarrier {
	return new BridgeProductDevFileCarrier(props);
}
