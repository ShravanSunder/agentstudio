import { uuidv7 } from 'uuidv7';

import {
	createBridgeProductDeferred,
	type BridgeProductDeferred,
} from './bridge-product-async-queue.js';
import { installBridgeProductBatchDelivery } from './bridge-product-batch-delivery.js';
import {
	BridgeProductBatchFrameRouter,
	type BridgeProductBatchFrameSinks,
} from './bridge-product-batch-frame-router.js';
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
} from './bridge-product-content-contracts.js';
import { BridgeProductContentResponseAdmission } from './bridge-product-content-response-admission.js';
import { readBridgeProductContentResponse } from './bridge-product-content-response-reader.js';
import { openBridgeProductContentStream } from './bridge-product-content-stream-opening.js';
import { type BridgeProductSurface } from './bridge-product-contract-primitives.js';
import {
	defaultBridgeProductDeadlineClock,
	type BridgeProductDeadlineClock,
} from './bridge-product-deadline-clock.js';
import {
	bridgeProductFrameAcknowledgementRequestSchema,
	type BridgeProductFrameAcknowledgementRequest,
} from './bridge-product-frame-acknowledgement-contracts.js';
import { sendBridgeProductFrameAcknowledgement } from './bridge-product-frame-acknowledgement.js';
import type {
	BridgeProductMetadataApplicationProtocol,
	BridgeProductMetadataApplicationRegistry,
} from './bridge-product-metadata-application-protocol.js';
import {
	BridgeProductMetadataRouteFailure,
	bridgeProductMetadataRouteFailure,
	type BridgeProductMetadataRouteFailureCode,
} from './bridge-product-metadata-route-failure.js';
import {
	BridgeProductMetadataStreamDecoder,
	type BridgeProductMetadataStreamDecoderDiagnostics,
	type BridgeProductMetadataStreamIdentityField,
} from './bridge-product-metadata-stream-decoder.js';
import { encodeBridgeProductRequestBody } from './bridge-product-request-body.js';
import type { BridgeProductRequestExecutor } from './bridge-product-request-executor.js';
import {
	BridgeProductControlRequestError,
	type BridgeProductControlMux,
	type BridgeProductSessionAuthority,
} from './bridge-product-session-authority.js';
import {
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductMetadataFrame,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import {
	BridgeProductSubscriptionFrameFailure,
	bridgeProductSubscriptionOperationFailureCode,
} from './bridge-product-subscription-frame-failure.js';
import {
	BridgeProductSubscriptionEpochRetiredError,
	BridgeProductSubscriptionState,
	type BridgeProductSubscriptionFrameSink,
} from './bridge-product-subscription-state.js';
import { BridgeProductSurfaceEpochAuthority } from './bridge-product-surface-epoch-authority.js';
import type {
	BridgeProductCallOptions,
	BridgeProductContentStream,
	BridgeProductTransport,
} from './bridge-product-transport-contract.js';
import {
	ignoreBridgeProductPanePresentationFrame,
	ignoreBridgeProductPaneSurfaceSelectionFrame,
} from './bridge-product-transport-default-sinks.js';
import type { ViewResnapshotAdmissionProps } from './bridge-product-view-control-admission.js';
import type { BridgeProductViewScopeRequest } from './bridge-product-view-control-wire-contracts.js';
import { bridgeProductInitialViewOpening } from './bridge-product-view-opening.js';
import { BridgeProductViewScopeOwner } from './bridge-product-view-scope-owner.js';
import type { BridgeProductViewScopeSettlement } from './bridge-product-view-scope-owner.js';

export type BridgeProductIdentifierPurpose =
	| 'content-request'
	| 'lease'
	| 'metadata-stream'
	| 'subscription';

type BridgeProductCallArguments = {
	[TCallKind in BridgeProductCallKind]: readonly [
		method: TCallKind,
		request: BridgeProductCallRequest<TCallKind>,
		options?: BridgeProductCallOptions,
	];
}[BridgeProductCallKind];

export interface CreateBridgeProductTransportProps {
	readonly authority: BridgeProductSessionAuthority;
	readonly controlMux: Pick<
		BridgeProductControlMux,
		| 'call'
		| 'cancelSubscription'
		| 'openSubscription'
		| 'resnapshotView'
		| 'resync'
		| 'setViewScope'
	>;
	readonly createIdentifier?: (purpose: BridgeProductIdentifierPurpose) => string;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly deadlineClock?: BridgeProductDeadlineClock;
	readonly initialWorkerDerivationEpochs?: Readonly<Partial<Record<BridgeProductSurface, number>>>;
	readonly maximumConcurrentContentResponses?: number;
	readonly metadataApplicationRegistry: BridgeProductMetadataApplicationRegistry;
	/** Maximum time an exact frame observation acknowledgement may remain pending. */
	readonly frameAcknowledgementTimeoutMilliseconds?: number;
}

export interface BridgeProductTransportSession extends BridgeProductTransport {
	setViewScopeForSubscription?(props: {
		readonly scope: BridgeProductViewScopeRequest['scope'];
		readonly subscriptionId: string;
	}): Promise<BridgeProductViewScopeSettlement>;
	setBatchFrameSinks?(sinks: BridgeProductBatchFrameSinks): void;
	resnapshotView?(
		props: ViewResnapshotAdmissionProps,
	): ReturnType<BridgeProductControlMux['resnapshotView']>;
	/**
	 * Advances the surface to a new worker derivation epoch and returns it. Every
	 * subscription admitted on that surface at an older epoch ends for its consumer
	 * with `BridgeProductSubscriptionEpochRetiredError` and is released: its cancel
	 * is sent at its own epoch, because native refuses stale-epoch controls once its
	 * surface floor advances. Admissions and calls on the surface wait only for
	 * native's cancel acknowledgements, never for a frame. Content opens are not
	 * held; one at the new epoch may advance native's floor first, in which case
	 * native ends the older subscriptions itself with an `epoch_retired` reset.
	 */
	advanceWorkerDerivationEpoch(surface: BridgeProductSurface): number;
	metadataStreamDiagnostics?(): BridgeProductMetadataStreamHealthDiagnostics;
	setPanePresentationFrameSink?(sink: (frame: BridgeProductPanePresentationFrame) => void): void;
	setPaneSurfaceSelectionFrameSink?(
		sink: (frame: BridgeProductPaneSurfaceSelectionFrame) => void,
	): void;
	workerDerivationEpoch(surface: BridgeProductSurface): number;
}

export type BridgeProductPanePresentationFrame = Extract<
	BridgeProductMetadataFrame,
	{ readonly kind: 'pane.presentation' }
>;

export type BridgeProductPaneSurfaceSelectionFrame = Extract<
	BridgeProductMetadataFrame,
	{ readonly kind: 'pane.surfaceSelectionRequested' }
>;

export interface BridgeProductMetadataStreamHealthDiagnostics {
	readonly lastSubscriptionTermination: {
		readonly subscriptionId: string;
		readonly outcome: 'terminal' | 'failed';
		readonly reason: BridgeProductMetadataRouteFailureCode | null;
	} | null;
	readonly routeFailureSubscriptionId: string | null;
	readonly activeSubscriptionCount: number;
	readonly committedFrameCount: number;
	readonly decoderState: BridgeProductMetadataStreamDecoderDiagnostics['state'];
	readonly expectedNextStreamSequence: number;
	readonly failureStage: BridgeProductMetadataStreamFailureStage | null;
	readonly failureCode: BridgeProductMetadataStreamDecoderDiagnostics['failureCode'];
	readonly identityMismatchField: BridgeProductMetadataStreamIdentityField | null;
	readonly lastChunkByteCount: number;
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
	| 'authority'
	| 'decode'
	| 'fetch'
	| 'finish'
	| 'read'
	| 'route'
	| 'unexpectedEof';

export type BridgeProductMetadataStreamLifecycleState = 'failed' | 'idle' | 'opening' | 'reading';
export type { BridgeProductMetadataRouteFailureCode } from './bridge-product-metadata-route-failure.js';

export function createBridgeProductTransport(
	props: CreateBridgeProductTransportProps,
): BridgeProductTransportSession {
	return new BridgeProductTransportSessionImpl(props);
}

class BridgeProductTransportSessionImpl implements BridgeProductTransportSession {
	readonly #authority: BridgeProductSessionAuthority;
	readonly #contentResponseAdmission: BridgeProductContentResponseAdmission;
	readonly #controlMux: CreateBridgeProductTransportProps['controlMux'];
	readonly #createIdentifier: (purpose: BridgeProductIdentifierPurpose) => string;
	readonly #epochAuthority: BridgeProductSurfaceEpochAuthority;
	/**
	 * Ids the worker ended locally while native may still send their frames. They
	 * drain until native's terminal instead of failing the shared stream.
	 */
	readonly #drainingSubscriptionIds = new Set<string>();
	readonly #executeProductRequest: BridgeProductRequestExecutor;
	readonly #deadlineClock: BridgeProductDeadlineClock;
	readonly #metadataApplicationRegistry: BridgeProductMetadataApplicationRegistry;
	readonly #frameAcknowledgementTimeoutMilliseconds: number;
	#metadataReady: BridgeProductDeferred<void> | null = null;
	#physicalMetadataReady: BridgeProductDeferred<void> | null = null;
	#metadataRecoveryInFlight = false;
	#lastRoutedStreamSequence: number | null = null;
	#metadataRecoveryAttemptedSinceProgress = false;
	#metadataStreamHealthDiagnostics: BridgeProductMetadataStreamHealthDiagnostics = {
		lastSubscriptionTermination: null,
		routeFailureSubscriptionId: null,
		activeSubscriptionCount: 0,
		committedFrameCount: 0,
		decoderState: 'open',
		expectedNextStreamSequence: 0,
		failureStage: null,
		failureCode: null,
		identityMismatchField: null,
		lastChunkByteCount: 0,
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
	readonly #batchFrameRouter = new BridgeProductBatchFrameRouter();
	readonly #viewScopeOwner: BridgeProductViewScopeOwner;
	#panePresentationFrameSink: (frame: BridgeProductPanePresentationFrame) => void =
		ignoreBridgeProductPanePresentationFrame;
	#paneSurfaceSelectionFrameSink: (frame: BridgeProductPaneSurfaceSelectionFrame) => void =
		ignoreBridgeProductPaneSurfaceSelectionFrame;

	constructor(props: CreateBridgeProductTransportProps) {
		this.#authority = props.authority;
		this.#controlMux = props.controlMux;
		this.#createIdentifier =
			props.createIdentifier ?? ((purpose): string => `${purpose}-${uuidv7()}`);
		this.#viewScopeOwner = new BridgeProductViewScopeOwner({
			controlMux: props.controlMux,
			createIdentifier: (): string => this.#createIdentifier('subscription'),
		});
		this.#executeProductRequest = props.executeProductRequest;
		this.#deadlineClock = props.deadlineClock ?? defaultBridgeProductDeadlineClock;
		this.#metadataApplicationRegistry = props.metadataApplicationRegistry;
		this.#frameAcknowledgementTimeoutMilliseconds =
			props.frameAcknowledgementTimeoutMilliseconds ?? 5000;
		if (
			!Number.isSafeInteger(this.#frameAcknowledgementTimeoutMilliseconds) ||
			this.#frameAcknowledgementTimeoutMilliseconds <= 0
		) {
			throw new Error('Bridge frame acknowledgement timeout must be a positive safe integer.');
		}
		this.#contentResponseAdmission = new BridgeProductContentResponseAdmission(
			props.maximumConcurrentContentResponses,
		);
		this.#epochAuthority = new BridgeProductSurfaceEpochAuthority(
			props.initialWorkerDerivationEpochs,
		);
	}

	advanceWorkerDerivationEpoch(surface: BridgeProductSurface): number {
		return this.#epochAuthority.advance(surface, (nextEpoch): readonly Promise<void>[] => {
			const retirement = new BridgeProductSubscriptionEpochRetiredError({
				nextWorkerDerivationEpoch: nextEpoch,
				surface,
			});
			return [...this.#subscriptions.values()]
				.filter((subscription): boolean => subscription.surface === surface)
				.map(
					(subscription): Promise<void> =>
						subscription.retireBeforeWorkerDerivationEpochAdvance(retirement),
				);
		});
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

	setBatchFrameSinks(sinks: BridgeProductBatchFrameSinks): void {
		installBridgeProductBatchDelivery({
			authority: this.#authority,
			deadlineClock: this.#deadlineClock,
			executeProductRequest: this.#executeProductRequest,
			router: this.#batchFrameRouter,
			sinks,
		});
	}

	resnapshotView(
		props: ViewResnapshotAdmissionProps,
	): ReturnType<BridgeProductControlMux['resnapshotView']> {
		return this.#controlMux.resnapshotView(props);
	}

	setViewScopeForSubscription(props: {
		readonly scope: BridgeProductViewScopeRequest['scope'];
		readonly subscriptionId: string;
	}): Promise<BridgeProductViewScopeSettlement> {
		return this.#viewScopeOwner.setScope(props);
	}

	setPaneSurfaceSelectionFrameSink(
		sink: (frame: BridgeProductPaneSurfaceSelectionFrame) => void,
	): void {
		this.#paneSurfaceSelectionFrameSink = sink;
	}

	workerDerivationEpoch(surface: BridgeProductSurface): number {
		return this.#epochAuthority.current(surface);
	}

	async call<TCallArguments extends BridgeProductCallArguments>(
		...arguments_: TCallArguments
	): Promise<BridgeProductCallResult<TCallArguments[0]>> {
		const [method, request, options] = arguments_;
		const surface = bridgeProductSurfaceForCallKind(method);
		return await this.#epochAuthority.admitAt(
			surface,
			(workerDerivationEpoch): Promise<BridgeProductCallResult<TCallArguments[0]>> =>
				this.#controlMux.call({
					method,
					request,
					...(options?.signal === undefined ? {} : { signal: options.signal }),
					workerDerivationEpoch,
				}),
		);
	}

	openContent<TContentKind extends BridgeProductContentKind>(
		descriptor: BridgeProductContentDescriptor<TContentKind>,
		abortSignal: AbortSignal,
		operationCorrelationId?: string | null,
	): BridgeProductContentStream<TContentKind>;
	openContent(
		descriptor: BridgeProductContentDescriptor<BridgeProductContentKind>,
		abortSignal: AbortSignal,
		operationCorrelationId: string | null = null,
	): BridgeProductContentStream<BridgeProductContentKind> {
		const parsedDescriptor = bridgeProductContentDescriptorSchema.parse(descriptor);
		const contentRequestId = this.#createIdentifier('content-request');
		const request = bridgeProductContentRequestSchema.parse({
			contentKind: parsedDescriptor.contentKind,
			contentRequestId,
			descriptor: parsedDescriptor,
			kind: 'content.open',
			leaseId: this.#createIdentifier('lease'),
			operationCorrelationId,
			paneSessionId: this.#authority.bootstrap.paneSessionId,
			wireVersion: this.#authority.bootstrap.wireVersion,
			workerDerivationEpoch: this.workerDerivationEpoch(
				bridgeProductSurfaceForContentKind(parsedDescriptor.contentKind, parsedDescriptor),
			),
			workerInstanceId: this.#authority.bootstrap.workerInstanceId,
		});
		return this.#openValidatedContent(request, abortSignal);
	}

	subscribe<TKind extends string, TOptions, TOpen extends { readonly subscriptionKind: TKind }>(
		protocol: BridgeProductMetadataApplicationProtocol<TKind, TOptions, TOpen>,
		options: TOptions,
	): {
		readonly events: AsyncIterable<never>;
		readonly subscriptionId: string;
		readonly subscriptionKind: TKind;
		cancel(): Promise<void>;
	} {
		this.#metadataApplicationRegistry.requireProtocol(protocol);
		const state = this.#createSubscriptionState(protocol, options);
		this.#subscriptions.set(state.subscriptionId, state);
		state.start();
		return state.publicSubscription;
	}

	#createSubscriptionState<
		TKind extends string,
		TOptions,
		TOpen extends { readonly subscriptionKind: TKind },
	>(
		protocol: BridgeProductMetadataApplicationProtocol<TKind, TOptions, TOpen>,
		options: TOptions,
	): BridgeProductSubscriptionState<TKind, TOptions, TOpen> {
		const onOpened = bridgeProductInitialViewOpening(this.#viewScopeOwner, protocol.kind);
		return new BridgeProductSubscriptionState<TKind, TOptions, TOpen>({
			controlMux: this.#controlMux,
			ensureMetadataStream: (): Promise<void> => this.#ensureMetadataStream(),
			initialOptions: options,
			...(onOpened === undefined ? {} : { onOpened }),
			onTerminal: (subscriptionId, error, drainUntilNativeTerminal): void => {
				this.#viewScopeOwner.retire(subscriptionId);
				if (
					error !== undefined &&
					this.#metadataStreamHealthDiagnostics.lifecycleState === 'reading' &&
					this.#metadataStreamHealthDiagnostics.routeFailureCode === null
				) {
					this.#metadataStreamHealthDiagnostics = {
						...this.#metadataStreamHealthDiagnostics,
						routeFailureCode:
							error instanceof BridgeProductControlRequestError
								? `subscription_control_${error.code}`
								: bridgeProductSubscriptionOperationFailureCode(error),
					};
				}
				this.#subscriptions.delete(subscriptionId);
				this.#batchFrameRouter.retireSubscription(subscriptionId);
				if (drainUntilNativeTerminal === true) this.#drainingSubscriptionIds.add(subscriptionId);
				if (this.#metadataStreamHealthDiagnostics.lifecycleState === 'reading') {
					this.#metadataStreamHealthDiagnostics = {
						...this.#metadataStreamHealthDiagnostics,
						lastSubscriptionTermination: {
							subscriptionId,
							outcome: error === undefined ? 'terminal' : 'failed',
							reason: this.#metadataStreamHealthDiagnostics.routeFailureCode,
						},
					};
				}
			},
			protocol,
			readWorkerDerivationEpochAtAdmission: (): number =>
				this.workerDerivationEpoch(protocol.surface),
			admitAtWorkerDerivationEpoch: <TAdmission>(
				admit: (workerDerivationEpoch: number) => TAdmission,
			): Promise<TAdmission> => this.#epochAuthority.admitAt(protocol.surface, admit),
			subscriptionId: this.#createIdentifier('subscription'),
		});
	}

	#ensureMetadataStream(): Promise<void> {
		if (this.#metadataReady !== null) {
			return this.#metadataReady.promise;
		}
		return this.#openMetadataStream(null);
	}

	#openMetadataStream(resumeFromStreamSequence: number | null): Promise<void> {
		const request = bridgeProductMetadataStreamRequestSchema.parse({
			kind: 'metadataStream.open',
			metadataStreamId: this.#createIdentifier('metadata-stream'),
			paneSessionId: this.#authority.bootstrap.paneSessionId,
			resumeFromStreamSequence,
			wireVersion: this.#authority.bootstrap.wireVersion,
			workerInstanceId: this.#authority.bootstrap.workerInstanceId,
		});
		const ready = createBridgeProductDeferred<void>();
		this.#physicalMetadataReady = ready;
		if (this.#metadataReady === null) this.#metadataReady = ready;
		const readTask = this.#readMetadataStream(request);
		void readTask.catch((error: unknown): void => {
			if (this.#physicalMetadataReady !== ready) return;
			this.#physicalMetadataReady = null;
			if (!this.#metadataRecoveryInFlight) {
				this.#metadataReady = null;
			}
			ready.reject(error);
			if (
				!this.#metadataRecoveryInFlight &&
				this.#lastRoutedStreamSequence !== null &&
				(this.#metadataStreamHealthDiagnostics.failureStage === 'read' ||
					this.#metadataStreamHealthDiagnostics.failureStage === 'unexpectedEof' ||
					(this.#metadataStreamHealthDiagnostics.failureStage === 'finish' &&
						this.#metadataStreamHealthDiagnostics.failureCode === 'truncated_frame')) &&
				this.#subscriptions.size > 0 &&
				!this.#metadataRecoveryAttemptedSinceProgress
			) {
				void this.#recoverMetadataStream().catch((recoveryError: unknown): void => {
					this.#poisonMetadataSession(recoveryError);
				});
				return;
			}
			this.#poisonMetadataSession(error);
		});
		return ready.promise;
	}

	async #recoverMetadataStream(): Promise<void> {
		const lastRoutedStreamSequence = this.#lastRoutedStreamSequence;
		if (lastRoutedStreamSequence === null) {
			throw new Error('Metadata reconciliation requires a received stream cursor.');
		}
		this.#metadataRecoveryInFlight = true;
		const recoveryReady = createBridgeProductDeferred<void>();
		void recoveryReady.promise.catch((): void => {});
		this.#metadataRecoveryAttemptedSinceProgress = true;
		this.#metadataReady = recoveryReady;
		try {
			const response = await this.#controlMux.resync({
				readActiveSubscriptions: () =>
					[...this.#subscriptions.values()].flatMap((subscription) => {
						const claim = subscription.reconciliationClaim();
						return claim === null ? [] : [claim];
					}),
				readLastAcceptedStreamSequence: () => lastRoutedStreamSequence,
			});
			// Native reconciled every claimed id and revoked the rest; the replacement
			// stream carries no frames for ids ended locally on the old one.
			this.#drainingSubscriptionIds.clear();
			await Promise.all(
				response.reconciliation.map(async (outcome): Promise<void> => {
					const subscription = this.#subscriptions.get(outcome.subscriptionId);
					if (subscription !== undefined) await subscription.applyReconciliation(outcome);
				}),
			);
			await this.#openMetadataStream(response.metadataStreamSequenceBarrier);
			const retainedSubscriptionIds = new Set(
				response.reconciliation.flatMap((outcome) =>
					outcome.disposition === 'retained' ? [outcome.subscriptionId] : [],
				),
			);
			await Promise.all(
				[...retainedSubscriptionIds].map((subscriptionId) =>
					this.#viewScopeOwner.resnapshot(subscriptionId),
				),
			);
			recoveryReady.resolve();
		} catch (error) {
			recoveryReady.reject(error);
			if (this.#metadataReady === recoveryReady) this.#metadataReady = null;
			throw error;
		} finally {
			this.#metadataRecoveryInFlight = false;
		}
	}

	async #readMetadataStream(request: BridgeProductMetadataStreamRequest): Promise<void> {
		this.#metadataStreamHealthDiagnostics = {
			...this.#metadataStreamHealthDiagnostics,
			failureStage: null,
			lifecycleState: 'opening',
		};
		try {
			await this.#authority.open;
		} catch (error) {
			this.#recordMetadataStreamFailure('authority');
			throw error;
		}
		let response: Response;
		try {
			response = await this.#executeProductRequest('stream', {
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
						if (
							'subscriptionId' in frame &&
							this.#metadataStreamHealthDiagnostics.routeFailureSubscriptionId === null
						) {
							this.#metadataStreamHealthDiagnostics = {
								...this.#metadataStreamHealthDiagnostics,
								routeFailureSubscriptionId: frame.subscriptionId,
							};
						}
						this.#recordMetadataStreamFailure('route', routeFailure.routeFailureCode);
						throw routeFailure;
					}
					this.#metadataStreamHealthDiagnostics = {
						...this.#metadataStreamHealthDiagnostics,
						lastRoutedFrameKind: frame.kind,
						routeFailureSubscriptionId: frame.kind.startsWith('subscription.batch')
							? null
							: this.#metadataStreamHealthDiagnostics.routeFailureSubscriptionId,
						routeFailureCode: frame.kind.startsWith('subscription.batch')
							? null
							: this.#metadataStreamHealthDiagnostics.routeFailureCode,
						routedFrameCount: this.#metadataStreamHealthDiagnostics.routedFrameCount + 1,
					};
					this.#lastRoutedStreamSequence = frame.streamSequence;
					// Opening and pane-control replay do not establish subscription progress.
					if (frame.kind.startsWith('subscription.batch')) {
						this.#metadataRecoveryAttemptedSinceProgress = false;
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
		await sendBridgeProductFrameAcknowledgement({
			deadlineClock: this.#deadlineClock,
			capabilityHeader: this.#authority.capabilityHeader,
			executeProductRequest: this.#executeProductRequest,
			request,
			timeoutMilliseconds: this.#frameAcknowledgementTimeoutMilliseconds,
		});
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
			routeFailureCode: this.#metadataStreamHealthDiagnostics.routeFailureCode ?? routeFailureCode,
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
				this.#physicalMetadataReady?.resolve();
				return;
			case 'pane.presentation':
				this.#panePresentationFrameSink(frame);
				return;
			case 'pane.surfaceSelectionRequested':
				this.#paneSurfaceSelectionFrameSink(frame);
				return;
			case 'metadataStream.error':
				throw new BridgeProductMetadataRouteFailure(
					'metadata_stream_error',
					frame.safeMessage ?? `Bridge product metadata stream failed: ${frame.code}.`,
				);
			case 'content.cancelled':
				return;
			case 'subscription.batchBegin':
			case 'subscription.batchPart':
			case 'subscription.batchComplete':
				if (!this.#subscriptions.has(frame.subscriptionId)) {
					if (this.#drainingSubscriptionIds.has(frame.subscriptionId)) return;
					throw new BridgeProductMetadataRouteFailure(
						'unknown_subscription',
						'Bridge product batch references an unknown subscription.',
					);
				}
				this.#batchFrameRouter.accept(frame);
				return;
			case 'subscription.accepted':
			case 'subscription.cancelled':
			case 'subscription.end':
			case 'subscription.reset': {
				const subscription = this.#subscriptions.get(frame.subscriptionId);
				if (subscription === undefined) {
					if (this.#drainingSubscriptionIds.has(frame.subscriptionId)) {
						if (
							frame.kind === 'subscription.cancelled' ||
							frame.kind === 'subscription.end' ||
							frame.kind === 'subscription.reset'
						) {
							this.#drainingSubscriptionIds.delete(frame.subscriptionId);
						}
						return;
					}
					throw new BridgeProductMetadataRouteFailure(
						'unknown_subscription',
						'Bridge product metadata frame references an unknown subscription.',
					);
				}
				try {
					subscription.acceptFrame(frame);
				} catch (error) {
					throw new BridgeProductMetadataRouteFailure(
						error instanceof BridgeProductSubscriptionFrameFailure
							? error.routeFailureCode
							: 'subscription_frame_rejected',
						error instanceof Error
							? error.message
							: 'Bridge product subscription rejected a metadata frame.',
					);
				}
				if (
					frame.kind === 'subscription.cancelled' ||
					frame.kind === 'subscription.end' ||
					frame.kind === 'subscription.reset'
				)
					this.#batchFrameRouter.retireSubscription(frame.subscriptionId);
				return;
			}
		}
	}

	#poisonMetadataSession(error: unknown): void {
		for (const subscription of this.#subscriptions.values()) {
			subscription.fail(error);
		}
		this.#subscriptions.clear();
		this.#drainingSubscriptionIds.clear();
		this.#batchFrameRouter.clear();
	}

	#openValidatedContent<TContentKind extends BridgeProductContentKind>(
		request: BridgeProductContentRequestFor<TContentKind>,
		abortSignal: AbortSignal,
	): BridgeProductContentStream<TContentKind> {
		return openBridgeProductContentStream({
			abortSignal,
			readResponse: (opening) =>
				readBridgeProductContentResponse({
					acknowledgeFrame: (request, frame) => this.#acknowledgeContentFrame(request, frame),
					authority: this.#authority,
					clock: this.#deadlineClock,
					executeProductRequest: this.#executeProductRequest,
					opening,
					responseAdmission: this.#contentResponseAdmission,
				}),
			request,
		});
	}
}
