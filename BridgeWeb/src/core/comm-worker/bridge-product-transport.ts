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
import { BridgeProductContentStreamDecoder } from './bridge-product-content-stream-decoder.js';
import {
	BRIDGE_PRODUCT_CONTENT_ROUTE,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_STREAM_ROUTE,
} from './bridge-product-contract-primitives.js';
import { BridgeProductMetadataStreamDecoder } from './bridge-product-metadata-stream-decoder.js';
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
	workerDerivationEpoch(surface: BridgeProductSurface): number;
}

export function createBridgeProductTransport(
	props: CreateBridgeProductTransportProps,
): BridgeProductTransportSession {
	return new BridgeProductTransportSessionImpl(props);
}

class BridgeProductTransportSessionImpl implements BridgeProductTransportSession {
	readonly #authority: BridgeProductSessionAuthority;
	readonly #controlMux: CreateBridgeProductTransportProps['controlMux'];
	readonly #createIdentifier: (purpose: BridgeProductIdentifierPurpose) => string;
	readonly #epochs: Record<BridgeProductSurface, number>;
	#metadataReady: BridgeProductDeferred<void> | null = null;
	readonly #subscriptions = new Map<string, BridgeProductSubscriptionFrameSink>();

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
		await this.#authority.open;
		const response = await fetch(BRIDGE_PRODUCT_STREAM_ROUTE, {
			body: encodeBridgeProductRequestBody(request),
			headers: {
				'Content-Type': 'application/json',
				'X-AgentStudio-Bridge-Product-Capability': this.#authority.capabilityHeader,
			},
			method: 'POST',
		});
		if (!response.ok || response.body === null) {
			throw new Error(`Bridge product metadata stream failed with status ${response.status}.`);
		}
		const reader = response.body.getReader();
		const decoder = new BridgeProductMetadataStreamDecoder(request);
		try {
			while (true) {
				// eslint-disable-next-line no-await-in-loop -- Stream chunks are ordered.
				const chunk = await reader.read();
				if (chunk.done) break;
				for (const frame of decoder.push(chunk.value)) {
					this.#routeMetadataFrame(frame);
				}
			}
			decoder.finish();
			throw new Error('Bridge product metadata stream ended unexpectedly.');
		} finally {
			reader.releaseLock();
		}
	}

	#routeMetadataFrame(frame: BridgeProductMetadataFrame): void {
		switch (frame.kind) {
			case 'metadataStream.accepted':
				this.#metadataReady?.resolve();
				return;
			case 'metadataStream.error':
				throw new Error(
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
					throw new Error('Bridge product metadata frame references an unknown subscription.');
				}
				subscription.acceptFrame(frame);
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
		const abortReader = (): void => {
			void reader?.cancel(props.abortSignal.reason).catch((): void => {});
		};
		props.abortSignal.addEventListener('abort', abortReader, { once: true });
		try {
			props.abortSignal.throwIfAborted();
			await this.#authority.open;
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
				for (const frame of decoded.frames) props.frames.push(frame);
				terminalResult = decoded.terminal ?? terminalResult;
			}
			decoder.finish();
			if (terminalResult === null) {
				throw new Error('Bridge product content stream ended without a terminal result.');
			}
			props.frames.close(true);
			props.terminal.resolve(terminalResult);
		} catch (error) {
			props.frames.fail(error, true);
			props.terminal.reject(error);
		} finally {
			props.abortSignal.removeEventListener('abort', abortReader);
			reader?.releaseLock();
		}
	}
}

function encodeBridgeProductRequestBody(request: object): ArrayBuffer {
	const body = new TextEncoder().encode(JSON.stringify(request));
	if (body.byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES) {
		throw new Error('Bridge product request exceeds its body ceiling.');
	}
	return Uint8Array.from(body).buffer;
}

function assertBridgeProductEpoch(epoch: number): void {
	if (!Number.isSafeInteger(epoch) || epoch < 0) {
		throw new Error('Bridge product derivation epochs must be nonnegative safe integers.');
	}
}
