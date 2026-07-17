import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
	type BridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type {
	BridgeProductCallKind,
	BridgeProductCallRequest,
	BridgeProductCallResult,
} from './bridge-product-call-contracts.js';
import { bridgeProductSurfaceForCallKind } from './bridge-product-call-contracts.js';
import {
	bridgeProductContentDescriptorSchema,
	bridgeProductContentRequestSchema,
	bridgeProductSurfaceForContentKind,
	type BridgeProductContentDescriptor,
	type BridgeProductContentFrameFor,
	type BridgeProductContentKind,
	type BridgeProductContentRequestFor,
	type BridgeProductContentTerminal,
} from './bridge-product-content-contracts.js';
import {
	BridgeProductContentResponseAdmission,
	type BridgeProductContentResponseAdmissionLease,
} from './bridge-product-content-response-admission.js';
import { BridgeProductContentStreamDecoder } from './bridge-product-content-stream-decoder.js';
import {
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_CONTENT_ROUTE,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_STREAM_ROUTE,
} from './bridge-product-contract-primitives.js';
import {
	bridgeProductFrameAcknowledgementRejectedStatusSchema,
	bridgeProductFrameAcknowledgementRequestSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from './bridge-product-frame-acknowledgement-contracts.js';
import {
	BridgeProductMetadataStreamDecoder,
	type BridgeProductMetadataStreamDecoderDiagnostics,
	type BridgeProductMetadataStreamIdentityField,
} from './bridge-product-metadata-stream-decoder.js';
import type {
	BridgeProductControlMux,
	BridgeProductSessionAuthority,
} from './bridge-product-session-authority.js';
import {
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductMetadataFrame,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import {
	bridgeProductSurfaceForSubscriptionKind,
	type BridgeProductSubscriptionKind,
	type BridgeProductSubscriptionOptions,
} from './bridge-product-subscription-contracts.js';
import {
	BridgeProductSubscriptionState,
	type BridgeProductSubscriptionFrameSink,
} from './bridge-product-subscription-state.js';
import type {
	BridgeProductCallOptions,
	BridgeProductContentStream,
	BridgeProductSubscription,
	BridgeProductTransport,
} from './bridge-product-transport-contract.js';

export type BridgeProductSurface = 'file' | 'review';
export type BridgeProductIdentifierPurpose =
	| 'content-request'
	| 'lease'
	| 'metadata-stream'
	| 'subscription'
	| 'subscription-update';

type BridgeProductCallArguments = {
	[TCallKind in BridgeProductCallKind]: readonly [
		method: TCallKind,
		request: BridgeProductCallRequest<TCallKind>,
		options?: BridgeProductCallOptions,
	];
}[BridgeProductCallKind];

type BridgeProductSubscriptionArguments = {
	[TSubscriptionKind in BridgeProductSubscriptionKind]: readonly [
		subscriptionKind: TSubscriptionKind,
		options: BridgeProductSubscriptionOptions<TSubscriptionKind>,
	];
}[BridgeProductSubscriptionKind];

export interface CreateBridgeProductTransportProps {
	readonly authority: BridgeProductSessionAuthority;
	readonly controlMux: Pick<
		BridgeProductControlMux,
		'call' | 'cancelSubscription' | 'openSubscription' | 'updateSubscriptionBatch'
	>;
	readonly createIdentifier?: (purpose: BridgeProductIdentifierPurpose) => string;
	readonly initialWorkerDerivationEpochs?: Readonly<Record<BridgeProductSurface, number>>;
}

export interface BridgeProductTransportSession extends BridgeProductTransport {
	bumpWorkerDerivationEpoch(surface: BridgeProductSurface): number;
	metadataStreamDiagnostics?(): BridgeProductMetadataStreamHealthDiagnostics;
	setPanePresentationFrameSink?(sink: (frame: BridgeProductPanePresentationFrame) => void): void;
	workerDerivationEpoch(surface: BridgeProductSurface): number;
}

export type BridgeProductPanePresentationFrame = Extract<
	BridgeProductMetadataFrame,
	{ readonly kind: 'pane.presentation' }
>;

export interface BridgeProductMetadataStreamHealthDiagnostics {
	readonly acknowledgedFrameCount: number;
	readonly activeSubscriptionCount: number;
	readonly committedFrameCount: number;
	readonly decoderState: BridgeProductMetadataStreamDecoderDiagnostics['state'];
	readonly expectedNextStreamSequence: number;
	readonly failureStage: BridgeProductMetadataStreamFailureStage | null;
	readonly failureCode: BridgeProductMetadataStreamDecoderDiagnostics['failureCode'];
	readonly identityMismatchField: BridgeProductMetadataStreamIdentityField | null;
	readonly lastChunkByteCount: number;
	readonly lastAcknowledgedStreamSequence: number | null;
	readonly lastCommittedFrameKind: BridgeProductMetadataFrame['kind'] | null;
	readonly lastRoutedFrameKind: BridgeProductMetadataFrame['kind'] | null;
	readonly lifecycleState: BridgeProductMetadataStreamLifecycleState;
	readonly peakRetainedByteCount: number;
	readonly pushCount: number;
	readonly readFulfilledCount: number;
	readonly readPending: boolean;
	readonly readRequestCount: number;
	readonly receivedByteCount: number;
	readonly retainedByteCount: number;
	readonly routeFailureCode: BridgeProductMetadataRouteFailureCode | null;
	readonly routedFrameCount: number;
	readonly streamOpenCount: number;
}

export type BridgeProductMetadataStreamFailureStage =
	| 'acknowledgement'
	| 'authority'
	| 'decode'
	| 'fetch'
	| 'finish'
	| 'read'
	| 'route'
	| 'unexpectedEof';

export type BridgeProductMetadataStreamLifecycleState = 'failed' | 'idle' | 'opening' | 'reading';

export type BridgeProductMetadataRouteFailureCode =
	| 'metadata_stream_error'
	| 'subscription_frame_rejected'
	| 'unknown_subscription';

export function createBridgeProductTransport(
	props: CreateBridgeProductTransportProps,
): BridgeProductTransportSession {
	return new BridgeProductTransportSessionImpl(props);
}

class BridgeProductTransportSessionImpl implements BridgeProductTransportSession {
	readonly #authority: BridgeProductSessionAuthority;
	readonly #contentResponseAdmission = new BridgeProductContentResponseAdmission();
	readonly #controlMux: CreateBridgeProductTransportProps['controlMux'];
	readonly #createIdentifier: (purpose: BridgeProductIdentifierPurpose) => string;
	readonly #epochs: Record<BridgeProductSurface, number>;
	#metadataReady: BridgeProductDeferred<void> | null = null;
	#metadataStreamHealthDiagnostics: BridgeProductMetadataStreamHealthDiagnostics = {
		acknowledgedFrameCount: 0,
		activeSubscriptionCount: 0,
		committedFrameCount: 0,
		decoderState: 'open',
		expectedNextStreamSequence: 0,
		failureStage: null,
		failureCode: null,
		identityMismatchField: null,
		lastChunkByteCount: 0,
		lastAcknowledgedStreamSequence: null,
		lastCommittedFrameKind: null,
		lastRoutedFrameKind: null,
		lifecycleState: 'idle',
		peakRetainedByteCount: 0,
		pushCount: 0,
		readFulfilledCount: 0,
		readPending: false,
		readRequestCount: 0,
		receivedByteCount: 0,
		retainedByteCount: 0,
		routeFailureCode: null,
		routedFrameCount: 0,
		streamOpenCount: 0,
	};
	readonly #subscriptions = new Map<string, BridgeProductSubscriptionFrameSink>();
	#panePresentationFrameSink: (frame: BridgeProductPanePresentationFrame) => void =
		ignoreBridgeProductPanePresentationFrame;

	constructor(props: CreateBridgeProductTransportProps) {
		this.#authority = props.authority;
		this.#controlMux = props.controlMux;
		this.#createIdentifier =
			props.createIdentifier ??
			((purpose): string => `${purpose}-${globalThis.crypto.randomUUID()}`);
		this.#epochs = {
			file: props.initialWorkerDerivationEpochs?.file ?? 0,
			review: props.initialWorkerDerivationEpochs?.review ?? 0,
		};
		assertBridgeProductEpoch(this.#epochs.file);
		assertBridgeProductEpoch(this.#epochs.review);
	}

	bumpWorkerDerivationEpoch(surface: BridgeProductSurface): number {
		const nextEpoch = this.#epochs[surface] + 1;
		assertBridgeProductEpoch(nextEpoch);
		this.#epochs[surface] = nextEpoch;
		return nextEpoch;
	}

	metadataStreamDiagnostics(): BridgeProductMetadataStreamHealthDiagnostics {
		return Object.freeze({
			...this.#metadataStreamHealthDiagnostics,
			activeSubscriptionCount: this.#subscriptions.size,
		});
	}

	setPanePresentationFrameSink(sink: (frame: BridgeProductPanePresentationFrame) => void): void {
		this.#panePresentationFrameSink = sink;
	}

	workerDerivationEpoch(surface: BridgeProductSurface): number {
		return this.#epochs[surface];
	}

	async call<TCallArguments extends BridgeProductCallArguments>(
		...arguments_: TCallArguments
	): Promise<BridgeProductCallResult<TCallArguments[0]>> {
		const [method, request, options] = arguments_;
		const surface = bridgeProductSurfaceForCallKind(method);
		return await this.#controlMux.call({
			method,
			request,
			...(options?.signal === undefined ? {} : { signal: options.signal }),
			workerDerivationEpoch: this.workerDerivationEpoch(surface),
		});
	}

	openContent<TContentKind extends BridgeProductContentKind>(
		descriptor: BridgeProductContentDescriptor<TContentKind>,
		abortSignal: AbortSignal,
	): BridgeProductContentStream<TContentKind>;
	openContent(
		descriptor: BridgeProductContentDescriptor<BridgeProductContentKind>,
		abortSignal: AbortSignal,
	): BridgeProductContentStream<BridgeProductContentKind> {
		const parsedDescriptor = bridgeProductContentDescriptorSchema.parse(descriptor);
		const contentRequestId = this.#createIdentifier('content-request');
		const request = bridgeProductContentRequestSchema.parse({
			contentKind: parsedDescriptor.contentKind,
			contentRequestId,
			descriptor: parsedDescriptor,
			kind: 'content.open',
			leaseId: this.#createIdentifier('lease'),
			paneSessionId: this.#authority.bootstrap.paneSessionId,
			wireVersion: this.#authority.bootstrap.wireVersion,
			workerDerivationEpoch: this.workerDerivationEpoch(
				bridgeProductSurfaceForContentKind(parsedDescriptor.contentKind),
			),
			workerInstanceId: this.#authority.bootstrap.workerInstanceId,
		});
		return this.#openValidatedContent(request, abortSignal);
	}

	subscribe<TSubscriptionArguments extends BridgeProductSubscriptionArguments>(
		...arguments_: TSubscriptionArguments
	): BridgeProductSubscription<TSubscriptionArguments[0]> {
		const [subscriptionKind, options] = arguments_;
		const state = this.#createSubscriptionState(subscriptionKind, options);
		this.#subscriptions.set(state.subscriptionId, state);
		state.start();
		return state.publicSubscription;
	}

	#createSubscriptionState<TSubscriptionKind extends BridgeProductSubscriptionKind>(
		subscriptionKind: TSubscriptionKind,
		options: BridgeProductSubscriptionOptions<TSubscriptionKind>,
	): BridgeProductSubscriptionState<TSubscriptionKind> {
		const surface = bridgeProductSurfaceForSubscriptionKind(subscriptionKind);
		return new BridgeProductSubscriptionState({
			controlMux: this.#controlMux,
			createIdentifier: this.#createIdentifier,
			ensureMetadataStream: (): Promise<void> => this.#ensureMetadataStream(),
			initialOptions: options,
			onTerminal: (subscriptionId): void => {
				this.#subscriptions.delete(subscriptionId);
			},
			subscriptionId: this.#createIdentifier('subscription'),
			subscriptionKind,
			workerDerivationEpoch: this.workerDerivationEpoch(surface),
		});
	}

	#ensureMetadataStream(): Promise<void> {
		if (this.#metadataReady !== null) {
			return this.#metadataReady.promise;
		}
		const request = bridgeProductMetadataStreamRequestSchema.parse({
			kind: 'metadataStream.open',
			metadataStreamId: this.#createIdentifier('metadata-stream'),
			paneSessionId: this.#authority.bootstrap.paneSessionId,
			resumeFromStreamSequence: null,
			wireVersion: this.#authority.bootstrap.wireVersion,
			workerInstanceId: this.#authority.bootstrap.workerInstanceId,
		});
		const ready = createBridgeProductDeferred<void>();
		this.#metadataReady = ready;
		const readTask = this.#readMetadataStream(request);
		void readTask.catch((error: unknown): void => {
			ready.reject(error);
			this.#poisonMetadataSession(error);
		});
		return ready.promise;
	}

	async #readMetadataStream(request: BridgeProductMetadataStreamRequest): Promise<void> {
		this.#metadataStreamHealthDiagnostics = {
			...this.#metadataStreamHealthDiagnostics,
			failureStage: null,
			lifecycleState: 'opening',
			routeFailureCode: null,
		};
		try {
			await this.#authority.open;
		} catch (error) {
			this.#recordMetadataStreamFailure('authority');
			throw error;
		}
		let response: Response;
		try {
			response = await fetch(BRIDGE_PRODUCT_STREAM_ROUTE, {
				body: encodeBridgeProductRequestBody(request),
				headers: {
					'Content-Type': 'application/json',
					'X-AgentStudio-Bridge-Product-Capability': this.#authority.capabilityHeader,
				},
				method: 'POST',
			});
		} catch (error) {
			this.#recordMetadataStreamFailure('fetch');
			throw error;
		}
		if (!response.ok || response.body === null) {
			this.#recordMetadataStreamFailure('fetch');
			throw new Error(`Bridge product metadata stream failed with status ${response.status}.`);
		}
		this.#metadataStreamHealthDiagnostics = {
			...this.#metadataStreamHealthDiagnostics,
			lifecycleState: 'reading',
			streamOpenCount: this.#metadataStreamHealthDiagnostics.streamOpenCount + 1,
		};
		const reader = response.body.getReader();
		const decoder = new BridgeProductMetadataStreamDecoder(request);
		try {
			while (true) {
				this.#metadataStreamHealthDiagnostics = {
					...this.#metadataStreamHealthDiagnostics,
					readPending: true,
					readRequestCount: this.#metadataStreamHealthDiagnostics.readRequestCount + 1,
				};
				let chunk: ReadableStreamReadResult<Uint8Array>;
				try {
					// eslint-disable-next-line no-await-in-loop -- Stream chunks are ordered.
					chunk = await reader.read();
				} catch (error) {
					this.#recordMetadataStreamFailure('read');
					throw error;
				}
				this.#metadataStreamHealthDiagnostics = {
					...this.#metadataStreamHealthDiagnostics,
					readFulfilledCount: this.#metadataStreamHealthDiagnostics.readFulfilledCount + 1,
					readPending: false,
				};
				if (chunk.done) {
					try {
						decoder.finish();
					} catch (error) {
						this.#captureMetadataStreamDiagnostics(decoder, 0, false);
						this.#recordMetadataStreamFailure('finish');
						throw error;
					}
					this.#captureMetadataStreamDiagnostics(decoder, 0, false);
					this.#recordMetadataStreamFailure('unexpectedEof');
					throw new Error('Bridge product metadata stream ended unexpectedly.');
				}
				let frames: readonly BridgeProductMetadataFrame[];
				try {
					frames = decoder.push(chunk.value);
				} catch (error) {
					this.#recordMetadataStreamFailure('decode');
					throw error;
				} finally {
					this.#captureMetadataStreamDiagnostics(decoder, chunk.value.byteLength);
				}
				this.#metadataStreamHealthDiagnostics = {
					...this.#metadataStreamHealthDiagnostics,
					committedFrameCount:
						this.#metadataStreamHealthDiagnostics.committedFrameCount + frames.length,
					lastCommittedFrameKind:
						frames.at(-1)?.kind ?? this.#metadataStreamHealthDiagnostics.lastCommittedFrameKind,
				};
				for (const frame of frames) {
					try {
						this.#routeMetadataFrame(frame);
					} catch (error) {
						const routeFailure = bridgeProductMetadataRouteFailure(error);
						this.#recordMetadataStreamFailure('route', routeFailure.routeFailureCode);
						throw routeFailure;
					}
					this.#metadataStreamHealthDiagnostics = {
						...this.#metadataStreamHealthDiagnostics,
						lastRoutedFrameKind: frame.kind,
						routedFrameCount: this.#metadataStreamHealthDiagnostics.routedFrameCount + 1,
					};
					try {
						// eslint-disable-next-line no-await-in-loop -- Native pacing advances only after this exact routed frame is accepted.
						await this.#acknowledgeMetadataFrame(frame);
					} catch (error) {
						this.#recordMetadataStreamFailure('acknowledgement');
						throw error;
					}
				}
			}
		} catch (error) {
			await reader.cancel(error).catch((): void => {});
			throw error;
		} finally {
			reader.releaseLock();
		}
	}

	async #acknowledgeMetadataFrame(frame: BridgeProductMetadataFrame): Promise<void> {
		const request = bridgeProductFrameAcknowledgementRequestSchema.parse({
			kind: 'stream.frameObserved',
			metadataStreamId: frame.metadataStreamId,
			paneSessionId: frame.paneSessionId,
			streamSequence: frame.streamSequence,
			streamKind: 'metadata',
			wireVersion: frame.wireVersion,
			workerInstanceId: frame.workerInstanceId,
		});
		await this.#sendFrameAcknowledgement(request);
		this.#metadataStreamHealthDiagnostics = {
			...this.#metadataStreamHealthDiagnostics,
			acknowledgedFrameCount: this.#metadataStreamHealthDiagnostics.acknowledgedFrameCount + 1,
			lastAcknowledgedStreamSequence: frame.streamSequence,
		};
	}

	async #acknowledgeContentFrame<TContentKind extends BridgeProductContentKind>(
		request: BridgeProductContentRequestFor<TContentKind>,
		frame: BridgeProductContentFrameFor<TContentKind>,
	): Promise<void> {
		const acknowledgement = bridgeProductFrameAcknowledgementRequestSchema.parse({
			contentRequestId: request.contentRequestId,
			contentSequence: frame.header.contentSequence,
			kind: 'stream.frameObserved',
			leaseId: request.leaseId,
			paneSessionId: request.paneSessionId,
			streamKind: 'content',
			wireVersion: request.wireVersion,
			workerInstanceId: request.workerInstanceId,
		});
		await this.#sendFrameAcknowledgement(acknowledgement);
	}

	async #sendFrameAcknowledgement(
		request: BridgeProductFrameAcknowledgementRequest,
	): Promise<void> {
		let response: Response;
		try {
			response = await fetch(BRIDGE_PRODUCT_COMMAND_ROUTE, {
				body: encodeBridgeProductRequestBody(request),
				headers: {
					'Content-Type': 'application/json',
					'X-AgentStudio-Bridge-Product-Capability': this.#authority.capabilityHeader,
				},
				method: 'POST',
			});
		} catch {
			throw new BridgeProductFrameAcknowledgementFailure(
				'request_failed',
				null,
				'Bridge product frame acknowledgement request failed.',
			);
		}
		assertBridgeProductFrameAcknowledgementAccepted(response.status);
	}

	#recordMetadataStreamFailure(
		failureStage: BridgeProductMetadataStreamFailureStage,
		routeFailureCode: BridgeProductMetadataRouteFailureCode | null = null,
	): void {
		this.#metadataStreamHealthDiagnostics = {
			...this.#metadataStreamHealthDiagnostics,
			failureStage,
			lifecycleState: 'failed',
			readPending: false,
			routeFailureCode,
		};
	}

	#captureMetadataStreamDiagnostics(
		decoder: BridgeProductMetadataStreamDecoder,
		chunkByteCount: number,
		recordPush = true,
	): void {
		const diagnostics = decoder.diagnostics;
		this.#metadataStreamHealthDiagnostics = {
			...this.#metadataStreamHealthDiagnostics,
			decoderState: diagnostics.state,
			expectedNextStreamSequence: diagnostics.expectedNextStreamSequence,
			failureCode: diagnostics.failureCode,
			identityMismatchField: diagnostics.identityMismatchField,
			lastChunkByteCount: chunkByteCount,
			peakRetainedByteCount: diagnostics.peakRetainedByteCount,
			pushCount: this.#metadataStreamHealthDiagnostics.pushCount + (recordPush ? 1 : 0),
			receivedByteCount: this.#metadataStreamHealthDiagnostics.receivedByteCount + chunkByteCount,
			retainedByteCount: diagnostics.retainedByteCount,
		};
	}

	#routeMetadataFrame(frame: BridgeProductMetadataFrame): void {
		switch (frame.kind) {
			case 'metadataStream.accepted':
				this.#metadataReady?.resolve();
				return;
			case 'pane.presentation':
				this.#panePresentationFrameSink(frame);
				return;
			case 'metadataStream.error':
				throw new BridgeProductMetadataRouteFailure(
					'metadata_stream_error',
					frame.safeMessage ?? `Bridge product metadata stream failed: ${frame.code}.`,
				);
			case 'content.cancelled':
				return;
			case 'subscription.accepted':
			case 'subscription.cancelled':
			case 'subscription.data':
			case 'subscription.end':
			case 'subscription.interestsCommitted':
			case 'subscription.reset': {
				const subscription = this.#subscriptions.get(frame.subscriptionId);
				if (subscription === undefined) {
					throw new BridgeProductMetadataRouteFailure(
						'unknown_subscription',
						'Bridge product metadata frame references an unknown subscription.',
					);
				}
				try {
					subscription.acceptFrame(frame);
				} catch (error) {
					throw new BridgeProductMetadataRouteFailure(
						'subscription_frame_rejected',
						error instanceof Error
							? error.message
							: 'Bridge product subscription rejected a metadata frame.',
					);
				}
				return;
			}
		}
	}

	#poisonMetadataSession(error: unknown): void {
		for (const subscription of this.#subscriptions.values()) {
			subscription.fail(error);
		}
		this.#subscriptions.clear();
	}

	#openValidatedContent<TContentKind extends BridgeProductContentKind>(
		request: BridgeProductContentRequestFor<TContentKind>,
		abortSignal: AbortSignal,
	): BridgeProductContentStream<TContentKind> {
		const frames = new BridgeProductBoundedAsyncQueue<BridgeProductContentFrameFor<TContentKind>>(
			32,
		);
		const terminal = createBridgeProductDeferred<BridgeProductContentTerminal<TContentKind>>();
		void this.#readContentResponse({ abortSignal, frames, request, terminal });
		return {
			contentKind: request.contentKind,
			contentRequestId: request.contentRequestId,
			frames,
			terminal: terminal.promise,
		};
	}

	async #readContentResponse<TContentKind extends BridgeProductContentKind>(props: {
		readonly abortSignal: AbortSignal;
		readonly frames: BridgeProductBoundedAsyncQueue<BridgeProductContentFrameFor<TContentKind>>;
		readonly request: BridgeProductContentRequestFor<TContentKind>;
		readonly terminal: BridgeProductDeferred<BridgeProductContentTerminal<TContentKind>>;
	}): Promise<void> {
		let reader: ReadableStreamDefaultReader<Uint8Array> | null = null;
		let responseAdmissionLease: BridgeProductContentResponseAdmissionLease | null = null;
		const abortReader = (): void => {
			void reader?.cancel(props.abortSignal.reason).catch((): void => {});
		};
		props.abortSignal.addEventListener('abort', abortReader, { once: true });
		try {
			props.abortSignal.throwIfAborted();
			await this.#authority.open;
			props.abortSignal.throwIfAborted();
			responseAdmissionLease = await this.#contentResponseAdmission.acquire(props.abortSignal);
			props.abortSignal.throwIfAborted();
			const response = await fetch(BRIDGE_PRODUCT_CONTENT_ROUTE, {
				body: encodeBridgeProductRequestBody(props.request),
				headers: {
					'Content-Type': 'application/json',
					'X-AgentStudio-Bridge-Product-Capability': this.#authority.capabilityHeader,
				},
				method: 'POST',
				signal: props.abortSignal,
			});
			if (!response.ok || response.body === null) {
				throw new Error(`Bridge product content stream failed with status ${response.status}.`);
			}
			reader = response.body.getReader();
			const decoder = new BridgeProductContentStreamDecoder(props.request);
			let terminalResult: BridgeProductContentTerminal<TContentKind> | null = null;
			while (true) {
				// eslint-disable-next-line no-await-in-loop -- Stream chunks are ordered.
				const chunk = await reader.read();
				if (chunk.done) break;
				// eslint-disable-next-line no-await-in-loop -- Decoder digest validation is ordered.
				const decoded = await decoder.push(chunk.value);
				for (const frame of decoded.frames) {
					props.frames.push(frame);
					// eslint-disable-next-line no-await-in-loop -- This response advances only after native accepts observation of its exact decoded frame.
					await this.#acknowledgeContentFrame(props.request, frame);
				}
				terminalResult = decoded.terminal ?? terminalResult;
			}
			decoder.finish();
			if (terminalResult === null) {
				throw new Error('Bridge product content stream ended without a terminal result.');
			}
			props.frames.close(true);
			props.terminal.resolve(terminalResult);
		} catch (error) {
			if (reader !== null) await reader.cancel(error).catch((): void => {});
			props.frames.fail(error, true);
			props.terminal.reject(error);
		} finally {
			props.abortSignal.removeEventListener('abort', abortReader);
			reader?.releaseLock();
			responseAdmissionLease?.release();
		}
	}
}

function ignoreBridgeProductPanePresentationFrame(
	_frame: BridgeProductPanePresentationFrame,
): void {}

class BridgeProductMetadataRouteFailure extends Error {
	readonly routeFailureCode: BridgeProductMetadataRouteFailureCode;

	constructor(routeFailureCode: BridgeProductMetadataRouteFailureCode, message: string) {
		super(message);
		this.name = 'BridgeProductMetadataRouteFailure';
		this.routeFailureCode = routeFailureCode;
	}
}

function bridgeProductMetadataRouteFailure(error: unknown): BridgeProductMetadataRouteFailure {
	return error instanceof BridgeProductMetadataRouteFailure
		? error
		: new BridgeProductMetadataRouteFailure(
				'subscription_frame_rejected',
				error instanceof Error ? error.message : 'Bridge product metadata frame routing failed.',
			);
}

function encodeBridgeProductRequestBody(request: object): ArrayBuffer {
	const body = new TextEncoder().encode(JSON.stringify(request));
	if (body.byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES) {
		throw new Error('Bridge product request exceeds its body ceiling.');
	}
	return Uint8Array.from(body).buffer;
}

function assertBridgeProductFrameAcknowledgementAccepted(status: number): asserts status is 204 {
	if (status === 204) return;
	const rejectedStatus = bridgeProductFrameAcknowledgementRejectedStatusSchema.safeParse(status);
	if (rejectedStatus.success) {
		throw new BridgeProductFrameAcknowledgementFailure(
			'rejected_status',
			rejectedStatus.data,
			`Bridge product frame acknowledgement was rejected with status ${rejectedStatus.data}.`,
		);
	}
	throw new BridgeProductFrameAcknowledgementFailure(
		'unsupported_status',
		status,
		`Bridge product frame acknowledgement returned unsupported status ${status}.`,
	);
}

type BridgeProductFrameAcknowledgementFailureCode =
	| 'rejected_status'
	| 'request_failed'
	| 'unsupported_status';

class BridgeProductFrameAcknowledgementFailure extends Error {
	readonly failureCode: BridgeProductFrameAcknowledgementFailureCode;
	readonly status: number | null;

	constructor(
		failureCode: BridgeProductFrameAcknowledgementFailureCode,
		status: number | null,
		message: string,
	) {
		super(message);
		this.name = 'BridgeProductFrameAcknowledgementFailure';
		this.failureCode = failureCode;
		this.status = status;
	}
}

function assertBridgeProductEpoch(epoch: number): void {
	if (!Number.isSafeInteger(epoch) || epoch < 0) {
		throw new Error('Bridge product derivation epochs must be nonnegative safe integers.');
	}
}
