import { bridgeProductAckHTTPFailureOutcome } from './bridge-product-ack-failure-classification.js';
import {
	bridgeProductCallRequestSchema,
	bridgeProductCallResultForMethod,
	bridgeProductSurfaceForCallKind,
	type BridgeProductCallKind,
	type BridgeProductCallRequest,
	type BridgeProductCallResult,
} from './bridge-product-call-contracts.js';
import { bridgeProductCallIsMutation } from './bridge-product-call-mutation-classification.js';
import {
	BridgeProductResponseSizeLimitError,
	BridgeProductRequestTransportError,
	postBridgeProductAdmissionBody,
	postBridgeProductCommandBody,
} from './bridge-product-command-post.js';
import { BridgeProductControlAdmissionQueue } from './bridge-product-control-admission-queue.js';
import { BridgeProductControlRequestError } from './bridge-product-control-request-error.js';
import { assertBridgeProductResponseCorrelation } from './bridge-product-control-response-correlation.js';
import {
	defaultBridgeProductDeadlineClock,
	type BridgeProductDeadlineClock,
} from './bridge-product-deadline-clock.js';
import {
	bridgeProductOperationLateOutcomeAcknowledgementSchema,
	bridgeProductOperationObservationRequestSchema,
	bridgeProductOperationObservationResponseSchema,
	type BridgeProductOperationObservationResponse,
} from './bridge-product-operation-observation-wire-contracts.js';
import {
	bridgeProductAdmissionResponseSchema,
	bridgeProductOperationResultAcknowledgedResponseSchema,
	bridgeProductOperationResultAcknowledgementSchema,
	bridgeProductOperationResultRequestSchema,
	bridgeProductOperationResultResponseSchema,
	type BridgeProductOperationAdmittedResponse,
} from './bridge-product-operation-wire-contracts.js';
import type { BridgeProductRequestExecutor } from './bridge-product-request-executor.js';
import {
	assertBridgeProductResyncReconciliationMatchesRequest,
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	encodeBridgeProductCapabilityHeader,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductSessionBootstrap,
} from './bridge-product-session-contracts.js';
import {
	BridgeProductStrictJSONError,
	parseBridgeProductStrictJSON,
} from './bridge-product-strict-json.js';
import {
	viewResnapshotAdmission,
	viewScopeAdmission,
	type ViewResnapshotAdmissionProps,
	type ViewScopeAdmissionProps,
} from './bridge-product-view-control-admission.js';
import type { BridgeWorkerAckAttemptOutcome } from './bridge-worker-contracts.js';

export interface BridgeProductSessionAuthorityInstallInput {
	readonly bootstrap: BridgeProductSessionBootstrap;
	readonly productCapability: ArrayBuffer;
}

export interface BridgeProductSessionAuthority {
	readonly bootstrap: BridgeProductSessionBootstrap;
	readonly capabilityHeader: string;
	readonly open: Promise<void>;
}

export interface BridgeProductControlMuxProps {
	readonly authority: BridgeProductSessionAuthority;
	readonly createRequestId?: () => string;
	readonly deadlineClock?: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly onSessionSuspect?: (
		reason: 'resultAcknowledgementExhausted',
		ackAttemptOutcomes: readonly BridgeWorkerAckAttemptOutcome[],
	) => void;
}

type BridgeProductControlResponseForKind<
	TResponseKind extends BridgeProductControlResponse['kind'],
> = Extract<BridgeProductControlResponse, { readonly kind: TResponseKind }>;

export type BridgeProductSubscriptionOpenAccepted =
	BridgeProductControlResponseForKind<'subscription.openAccepted'>;

export type BridgeProductSubscriptionCancelAccepted<TSubscriptionKind extends string> = Omit<
	BridgeProductControlResponseForKind<'subscription.cancelAccepted'>,
	'subscriptionKind'
> & {
	readonly subscriptionKind: TSubscriptionKind;
};

interface BridgeProductControlAdmissionIdentity {
	readonly paneSessionId: string;
	readonly requestId: string;
	readonly requestSequence: number;
	readonly wireVersion: BridgeProductSessionBootstrap['wireVersion'];
	readonly workerInstanceId: string;
}
interface BridgeProductControlAdmissionProps<TResult> {
	readonly acceptResponse: (
		response: BridgeProductControlResponse,
		request: BridgeProductControlRequest,
	) => TResult;
	readonly buildRequest: (
		identity: BridgeProductControlAdmissionIdentity,
	) => BridgeProductControlRequest;
	readonly requestErrorFallback?: (code: string) => string;
	readonly signal?: AbortSignal;
}

export interface BridgeProductLateOutcomeObservation {
	readonly actionResult: unknown;
	readonly evidence: Extract<
		BridgeProductOperationObservationResponse,
		{ kind: 'operation.lateOutcome' }
	>;
	readonly acknowledge: () => Promise<void>;
}

export { BridgeProductControlRequestError } from './bridge-product-control-request-error.js';

export class BridgeProductSessionSuspectError extends Error {
	shouldNotify = true;

	constructor(readonly phase: 'admission' | 'result') {
		super(`Bridge product session ${phase} did not settle within its bounded retry window.`);
		this.name = 'BridgeProductSessionSuspectError';
	}
}

class BridgeProductRequestDeadlineError extends Error {}

class BridgeProductAckAttemptTransportError extends BridgeProductRequestTransportError {
	constructor(readonly outcome: BridgeWorkerAckAttemptOutcome) {
		super('Bridge acknowledgement reply ambiguous.');
	}
}

export class BridgeProductControlMux {
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly #authority: BridgeProductSessionAuthority;
	readonly #createRequestId: () => string;
	readonly #executeProductRequest: BridgeProductRequestExecutor;
	readonly #onSessionSuspect:
		| ((
				reason: 'resultAcknowledgementExhausted',
				ackAttemptOutcomes: readonly BridgeWorkerAckAttemptOutcome[],
		  ) => void)
		| undefined;
	#nextRequestSequence = 3;
	#didDeclareSessionSuspect = false;
	readonly #admissionQueue = new BridgeProductControlAdmissionQueue();
	readonly #pendingAcknowledgements = new Set<Promise<void>>();
	readonly #acknowledgementIdleWaiters: Array<() => void> = [];

	constructor(props: BridgeProductControlMuxProps) {
		this.deadlineClock = props.deadlineClock ?? defaultBridgeProductDeadlineClock;
		this.#authority = props.authority;
		this.#createRequestId = props.createRequestId ?? ((): string => crypto.randomUUID());
		this.#executeProductRequest = props.executeProductRequest;
		this.#onSessionSuspect = props.onSessionSuspect;
	}

	get diagnosticSnapshot(): {
		readonly pendingAdmissionCount: number;
		readonly pendingAcknowledgementCount: number;
	} {
		return {
			pendingAdmissionCount: this.#admissionQueue.pendingCount,
			pendingAcknowledgementCount: this.#pendingAcknowledgements.size,
		};
	}

	async waitForAcknowledgementsQuiescent(): Promise<void> {
		if (this.#pendingAcknowledgements.size === 0) return;
		await new Promise<void>((resolve) => this.#acknowledgementIdleWaiters.push(resolve));
	}

	call<TCallKind extends BridgeProductCallKind>(props: {
		readonly method: TCallKind;
		readonly request: BridgeProductCallRequest<TCallKind>;
		readonly signal?: AbortSignal;
		readonly workerDerivationEpoch: number;
	}): Promise<BridgeProductCallResult<TCallKind>> {
		return this.#admit({
			acceptResponse: (response): BridgeProductCallResult<TCallKind> => {
				if (response.kind !== 'call.completed') {
					throw new Error('Bridge product call did not return call.completed.');
				}
				if (response.call.method !== props.method) {
					throw new Error('Bridge product call result does not match its issued method.');
				}
				bridgeProductSurfaceForCallKind(props.method);
				return bridgeProductCallResultForMethod(props.method, response.call);
			},
			buildRequest: (identity): BridgeProductControlRequest =>
				bridgeProductControlRequestSchema.parse({
					...identity,
					call: bridgeProductCallRequestSchema.parse({
						method: props.method,
						request: props.request,
					}),
					kind: 'product.call',
					workerDerivationEpoch: props.workerDerivationEpoch,
				}),
			requestErrorFallback: (code): string => `Bridge product call was rejected with ${code}.`,
			...(props.signal === undefined ? {} : { signal: props.signal }),
		});
	}

	openSubscription<TSubscriptionOpen extends { readonly subscriptionKind: string }>(props: {
		readonly signal?: AbortSignal;
		readonly subscription: TSubscriptionOpen;
		readonly subscriptionId: string;
		readonly workerDerivationEpoch: number;
	}): Promise<BridgeProductSubscriptionOpenAccepted> {
		return this.#admit({
			acceptResponse: (response): BridgeProductSubscriptionOpenAccepted => {
				if (response.kind !== 'subscription.openAccepted') {
					throw new Error(
						'Bridge product subscription open did not return subscription.openAccepted.',
					);
				}
				if (
					response.subscriptionId !== props.subscriptionId ||
					response.subscriptionKind !== props.subscription.subscriptionKind
				) {
					throw new Error('Bridge product subscription open result does not match its request.');
				}
				return response;
			},
			buildRequest: (identity): BridgeProductControlRequest => {
				return bridgeProductControlRequestSchema.parse({
					...identity,
					kind: 'subscription.open',
					subscription: props.subscription,
					subscriptionId: props.subscriptionId,
					workerDerivationEpoch: props.workerDerivationEpoch,
				});
			},
			...(props.signal === undefined ? {} : { signal: props.signal }),
		});
	}

	setViewScope(
		props: ViewScopeAdmissionProps,
	): Promise<BridgeProductControlResponseForKind<'subscription.scopeAccepted'>> {
		return this.#admit(viewScopeAdmission(props));
	}

	resnapshotView(
		props: ViewResnapshotAdmissionProps,
	): Promise<BridgeProductControlResponseForKind<'subscription.resnapshotAccepted'>> {
		return this.#admit(viewResnapshotAdmission(props));
	}

	cancelSubscription<TSubscriptionKind extends string>(props: {
		readonly signal?: AbortSignal;
		readonly subscriptionId: string;
		readonly subscriptionKind: TSubscriptionKind;
		readonly workerDerivationEpoch: number;
	}): Promise<BridgeProductSubscriptionCancelAccepted<TSubscriptionKind>> {
		return this.#admitEscape({
			acceptResponse: (response): BridgeProductSubscriptionCancelAccepted<TSubscriptionKind> => {
				if (response.kind !== 'subscription.cancelAccepted') {
					throw new Error(
						'Bridge product subscription cancel did not return subscription.cancelAccepted.',
					);
				}
				if (
					response.subscriptionId !== props.subscriptionId ||
					response.subscriptionKind !== props.subscriptionKind
				) {
					throw new Error('Bridge product subscription cancel result does not match its request.');
				}
				return { ...response, subscriptionKind: props.subscriptionKind };
			},
			buildRequest: (identity): BridgeProductControlRequest => {
				return bridgeProductControlRequestSchema.parse({
					...identity,
					kind: 'subscription.cancel',
					subscriptionId: props.subscriptionId,
					subscriptionKind: props.subscriptionKind,
					workerDerivationEpoch: props.workerDerivationEpoch,
				});
			},
			...(props.signal === undefined ? {} : { signal: props.signal }),
		});
	}

	resync(props: {
		readonly readActiveSubscriptions: () => Extract<
			BridgeProductControlRequest,
			{ kind: 'workerSession.resync' }
		>['activeSubscriptions'];
		readonly readLastAcceptedStreamSequence: () => number;
	}): Promise<Extract<BridgeProductControlResponse, { kind: 'resync.accepted' }>> {
		return this.#admit({
			acceptResponse: (
				response,
				request,
			): Extract<BridgeProductControlResponse, { kind: 'resync.accepted' }> => {
				if (response.kind !== 'resync.accepted' || request.kind !== 'workerSession.resync') {
					throw new Error('Bridge product session resync did not return resync.accepted.');
				}
				if (response.nextExpectedRequestSequence !== request.requestSequence + 1) {
					throw new Error(
						'Bridge product session resync returned an unexpected next request sequence.',
					);
				}
				if (response.metadataStreamSequenceBarrier < request.lastAcceptedStreamSequence) {
					throw new Error(
						'Bridge product session resync metadata barrier precedes the claimed stream sequence.',
					);
				}
				assertBridgeProductResyncReconciliationMatchesRequest({ request, response });
				return response;
			},
			buildRequest: (identity): BridgeProductControlRequest =>
				bridgeProductControlRequestSchema.parse({
					...identity,
					activeSubscriptions: props.readActiveSubscriptions(),
					kind: 'workerSession.resync',
					lastAcceptedRequestSequence: identity.requestSequence - 1,
					lastAcceptedStreamSequence: props.readLastAcceptedStreamSequence(),
				}),
		});
	}

	#admit<TResult>(props: BridgeProductControlAdmissionProps<TResult>): Promise<TResult> {
		const admission = this.#admissionQueue.enqueue(
			async (): Promise<{
				readonly request: BridgeProductControlRequest;
				readonly response: BridgeProductOperationAdmittedResponse;
			}> => {
				props.signal?.throwIfAborted();
				await this.#authority.open;
				props.signal?.throwIfAborted();
				const request = props.buildRequest({
					paneSessionId: this.#authority.bootstrap.paneSessionId,
					requestId: this.#createRequestId(),
					requestSequence: this.#nextRequestSequence,
					wireVersion: this.#authority.bootstrap.wireVersion,
					workerInstanceId: this.#authority.bootstrap.workerInstanceId,
				});
				const response = await postBridgeProductControlRequestWithExactRetry({
					policy: this.#authority.bootstrap.policy,
					capabilityHeader: this.#authority.capabilityHeader,
					deadlineClock: this.deadlineClock,
					executeProductRequest: this.#executeProductRequest,
					request,
					...(props.signal === undefined ? {} : { signal: props.signal }),
				});
				assertBridgeProductResponseCorrelation({ request, response });
				if (response.kind === 'request.error') {
					// Admission rejection may leave the sequence unconsumed; only native knows its floor.
					this.#nextRequestSequence =
						response.nextExpectedRequestSequence ?? this.#nextRequestSequence;
					throw new BridgeProductControlRequestError({
						code: response.code,
						message:
							response.safeMessage ??
							props.requestErrorFallback?.(response.code) ??
							`Bridge product control request was rejected with ${response.code}.`,
						retryAfterMilliseconds: response.retryAfterMilliseconds,
						retryable: response.retryable,
					});
				}
				this.#nextRequestSequence += 1;
				return { request, response };
			},
		);
		return admission
			.then(async ({ request, response }): Promise<TResult> => {
				const operationResult = await postBridgeProductOperationResult({
					bootstrap: this.#authority.bootstrap,
					capabilityHeader: this.#authority.capabilityHeader,
					deadlineClock: this.deadlineClock,
					executeProductRequest: this.#executeProductRequest,
					operationId: response.operationId,
					waitKind: response.waitKind,
				});
				try {
					if (operationResult.outcome !== 'succeeded') {
						throw new BridgeProductControlRequestError({
							code: operationResult.failureCode ?? 'internal',
							message: `Bridge product operation settled as ${operationResult.outcome}.`,
							outcome: operationResult.outcome,
							retryAfterMilliseconds: null,
							retryable: operationResult.outcome === 'outcomeUnknown',
							...(operationResult.outcome === 'outcomeUnknown' &&
							request.kind === 'product.call' &&
							bridgeProductCallIsMutation(request.call.method)
								? {
										observeLateOutcome: (): Promise<BridgeProductLateOutcomeObservation> =>
											this.#observeLateOutcome({
												operationId: response.operationId,
												request,
												acceptResponse: props.acceptResponse,
											}),
									}
								: {}),
						});
					}
					const finalResponse = bridgeProductControlResponseSchema.parse(operationResult.result);
					assertBridgeProductResponseCorrelation({ request, response: finalResponse });
					return props.acceptResponse(finalResponse, request);
				} finally {
					// Reading a known result settles the caller. Ack failure may make this
					// session suspect, but cannot replace that outcome with a failure.
					this.#scheduleResultAcknowledgement(response.operationId);
				}
			})
			.catch((error: unknown): never => {
				if (error instanceof BridgeProductSessionSuspectError) {
					error.shouldNotify = !this.#didDeclareSessionSuspect;
					this.#didDeclareSessionSuspect = true;
				}
				throw error;
			});
	}

	#scheduleResultAcknowledgement(operationId: string): void {
		const ackAttemptOutcomes: BridgeWorkerAckAttemptOutcome[] = [];
		const acknowledgement = this.#admissionQueue.enqueue(async (): Promise<void> => {
			const request = bridgeProductOperationResultAcknowledgementSchema.parse({
				kind: 'operation.resultAcknowledgement',
				operationId,
				paneSessionId: this.#authority.bootstrap.paneSessionId,
				requestId: this.#createRequestId(),
				requestSequence: this.#nextRequestSequence,
				wireVersion: this.#authority.bootstrap.wireVersion,
				workerInstanceId: this.#authority.bootstrap.workerInstanceId,
			});
			const response = await postBridgeProductResultAcknowledgement({
				policy: this.#authority.bootstrap.policy,
				acknowledgement: request,
				capabilityHeader: this.#authority.capabilityHeader,
				deadlineClock: this.deadlineClock,
				executeProductRequest: this.#executeProductRequest,
				recordAttemptFailure: (outcome): void => {
					ackAttemptOutcomes.push(outcome);
				},
			});
			if (response.operationId !== operationId) {
				throw new BridgeProductRequestTransportError('Bridge product acknowledgement mismatched.');
			}
			this.#nextRequestSequence += 1;
		}, 'escape');
		this.#pendingAcknowledgements.add(acknowledgement);
		void acknowledgement
			.catch((): void => {
				if (this.#didDeclareSessionSuspect) return;
				this.#didDeclareSessionSuspect = true;
				try {
					this.#onSessionSuspect?.('resultAcknowledgementExhausted', ackAttemptOutcomes);
				} catch {
					// The old worker may already be fenced; the delivered outcome stays final.
				}
			})
			.finally((): void => {
				this.#pendingAcknowledgements.delete(acknowledgement);
				if (this.#pendingAcknowledgements.size !== 0) return;
				for (const resume of this.#acknowledgementIdleWaiters.splice(0)) resume();
			});
	}

	async #observeLateOutcome<TResult>(props: {
		readonly operationId: string;
		readonly request: BridgeProductControlRequest;
		readonly acceptResponse: (
			response: BridgeProductControlResponse,
			request: BridgeProductControlRequest,
		) => TResult;
	}): Promise<BridgeProductLateOutcomeObservation> {
		for (;;) {
			const observed = await postBridgeProductOperationObservation({
				bootstrap: this.#authority.bootstrap,
				capabilityHeader: this.#authority.capabilityHeader,
				deadlineClock: this.deadlineClock,
				executeProductRequest: this.#executeProductRequest,
				operationId: props.operationId,
				after: 1,
			});
			if (observed.kind === 'operation.stillUnknown') continue;
			let actionResult: TResult | null = null;
			if (observed.outcome === 'succeeded') {
				const response = bridgeProductControlResponseSchema.parse(observed.result);
				assertBridgeProductResponseCorrelation({ request: props.request, response });
				actionResult = props.acceptResponse(response, props.request);
			}
			return {
				actionResult,
				evidence: observed,
				acknowledge: (): Promise<void> =>
					this.#admissionQueue.enqueue(async (): Promise<void> => {
						const acknowledgement = bridgeProductOperationLateOutcomeAcknowledgementSchema.parse({
							kind: 'operation.lateOutcomeAcknowledgement',
							operationId: props.operationId,
							paneSessionId: this.#authority.bootstrap.paneSessionId,
							requestId: this.#createRequestId(),
							requestSequence: this.#nextRequestSequence,
							revision: observed.revision,
							wireVersion: this.#authority.bootstrap.wireVersion,
							workerInstanceId: this.#authority.bootstrap.workerInstanceId,
						});
						await postBridgeProductExactAdmissionWithRetry({
							policy: this.#authority.bootstrap.policy,
							deadlineClock: this.deadlineClock,
							run: async (signal): Promise<void> => {
								await postBridgeProductCommandBody({
									body: acknowledgement,
									capabilityHeader: this.#authority.capabilityHeader,
									executeProductRequest: this.#executeProductRequest,
									signal,
								});
							},
						});
						this.#nextRequestSequence += 1;
					}, 'escape'),
			};
		}
	}

	#admitEscape<TResult>(props: BridgeProductControlAdmissionProps<TResult>): Promise<TResult> {
		return this.#admissionQueue
			.enqueue(async (): Promise<TResult> => {
				props.signal?.throwIfAborted();
				await this.#authority.open;
				const request = props.buildRequest({
					paneSessionId: this.#authority.bootstrap.paneSessionId,
					requestId: this.#createRequestId(),
					requestSequence: this.#nextRequestSequence,
					wireVersion: this.#authority.bootstrap.wireVersion,
					workerInstanceId: this.#authority.bootstrap.workerInstanceId,
				});
				const response = await postBridgeProductEscapeControlRequest({
					policy: this.#authority.bootstrap.policy,
					capabilityHeader: this.#authority.capabilityHeader,
					deadlineClock: this.deadlineClock,
					executeProductRequest: this.#executeProductRequest,
					request,
					...(props.signal === undefined ? {} : { signal: props.signal }),
				});
				assertBridgeProductResponseCorrelation({ request, response });
				if (response.kind === 'request.error') {
					this.#nextRequestSequence =
						response.nextExpectedRequestSequence ?? this.#nextRequestSequence;
					throw new BridgeProductControlRequestError({
						code: response.code,
						message: response.safeMessage ?? `Bridge product escape control was rejected.`,
						retryAfterMilliseconds: response.retryAfterMilliseconds,
						retryable: response.retryable,
					});
				}
				this.#nextRequestSequence += 1;
				return props.acceptResponse(response, request);
			}, 'escape')
			.catch((error: unknown): never => {
				if (error instanceof BridgeProductSessionSuspectError) {
					error.shouldNotify = !this.#didDeclareSessionSuspect;
					this.#didDeclareSessionSuspect = true;
				}
				throw error;
			});
	}
}

async function postBridgeProductControlRequestWithExactRetry(props: {
	readonly policy: BridgeProductSessionBootstrap['policy'];
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductAdmissionResponseSchema.parse>> {
	return await postBridgeProductExactAdmissionWithRetry({
		policy: props.policy,
		deadlineClock: props.deadlineClock,
		run: (signal): Promise<ReturnType<typeof bridgeProductAdmissionResponseSchema.parse>> =>
			postBridgeProductControlRequest({
				capabilityHeader: props.capabilityHeader,
				executeProductRequest: props.executeProductRequest,
				request: props.request,
				signal,
			}),
		...(props.signal === undefined ? {} : { signal: props.signal }),
	});
}

async function postBridgeProductExactAdmissionWithRetry<TResult>(props: {
	readonly policy: BridgeProductSessionBootstrap['policy'];
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly onAttemptFailure?: (error: unknown) => void;
	readonly run: (signal: AbortSignal) => Promise<TResult>;
	readonly signal?: AbortSignal;
}): Promise<TResult> {
	for (let attempt = 0; attempt <= props.policy.admissionRetryCount; attempt += 1) {
		try {
			return await withBridgeProductDeadline({
				clock: props.deadlineClock,
				delayMilliseconds: props.policy.workerSettlementDeadlineMilliseconds,
				run: props.run,
				...(props.signal === undefined ? {} : { signal: props.signal }),
			});
		} catch (error: unknown) {
			props.onAttemptFailure?.(error);
			props.signal?.throwIfAborted();
			if (
				!(error instanceof BridgeProductRequestDeadlineError) &&
				!(error instanceof BridgeProductRequestTransportError)
			)
				throw error;
		}
	}
	throw new BridgeProductSessionSuspectError('admission');
}

async function withBridgeProductDeadline<TResult>(props: {
	readonly clock: BridgeProductDeadlineClock;
	readonly delayMilliseconds: number;
	readonly run: (signal: AbortSignal) => Promise<TResult>;
	readonly signal?: AbortSignal;
}): Promise<TResult> {
	props.signal?.throwIfAborted();
	const controller = new AbortController();
	const abortForCaller = (): void => controller.abort(props.signal?.reason);
	props.signal?.addEventListener('abort', abortForCaller, { once: true });
	let cancelDeadline = (): void => {};
	const deadline = new Promise<never>((_resolve, reject): void => {
		cancelDeadline = props.clock.schedule(props.delayMilliseconds, (): void => {
			controller.abort();
			reject(new BridgeProductRequestDeadlineError());
		});
	});
	try {
		return await Promise.race([props.run(controller.signal), deadline]);
	} finally {
		cancelDeadline();
		props.signal?.removeEventListener('abort', abortForCaller);
	}
}

export class BridgeProductSessionAuthorityStore {
	readonly #deadlineClock: BridgeProductDeadlineClock;
	readonly #executeProductRequest: BridgeProductRequestExecutor;
	#installedAuthority: BridgeProductSessionAuthority | null = null;

	constructor(
		executeProductRequest: BridgeProductRequestExecutor,
		deadlineClock: BridgeProductDeadlineClock = defaultBridgeProductDeadlineClock,
	) {
		this.#executeProductRequest = executeProductRequest;
		this.#deadlineClock = deadlineClock;
	}

	readonly install = (
		input: BridgeProductSessionAuthorityInstallInput,
	): BridgeProductSessionAuthority => {
		if (this.#installedAuthority !== null) {
			throw new Error('Bridge product session authority was already installed.');
		}
		const capabilityHeader = encodeBridgeProductCapabilityHeader(input.productCapability);
		new Uint8Array(input.productCapability).fill(0);
		const request = bridgeProductControlRequestSchema.parse({
			kind: 'workerSession.open',
			paneSessionId: input.bootstrap.paneSessionId,
			request: null,
			requestId: 'worker-session-open-1',
			requestSequence: 1,
			wireVersion: input.bootstrap.wireVersion,
			workerInstanceId: input.bootstrap.workerInstanceId,
		});
		const open = postBridgeProductControlRequestWithExactRetry({
			policy: input.bootstrap.policy,
			capabilityHeader,
			deadlineClock: this.#deadlineClock,
			executeProductRequest: this.#executeProductRequest,
			request,
		}).then(async (admission): Promise<void> => {
			assertBridgeProductResponseCorrelation({ request, response: admission });
			if (admission.kind !== 'operation.admitted') {
				throw new Error('Bridge product session open was refused.');
			}
			const operationResult = await postBridgeProductOperationResult({
				bootstrap: input.bootstrap,
				capabilityHeader,
				deadlineClock: this.#deadlineClock,
				executeProductRequest: this.#executeProductRequest,
				operationId: admission.operationId,
				waitKind: admission.waitKind,
			});
			if (operationResult.outcome !== 'succeeded') {
				throw new Error(`Bridge product session open settled as ${operationResult.outcome}.`);
			}
			const response = bridgeProductControlResponseSchema.parse(operationResult.result);
			assertBridgeProductResponseCorrelation({ request, response });
			if (response.kind !== 'workerSession.accepted') {
				throw new Error('Bridge product session open did not return workerSession.accepted.');
			}
			const acknowledgement = bridgeProductOperationResultAcknowledgementSchema.parse({
				kind: 'operation.resultAcknowledgement',
				operationId: admission.operationId,
				paneSessionId: input.bootstrap.paneSessionId,
				requestId: 'worker-session-open-result-ack-2',
				requestSequence: 2,
				wireVersion: input.bootstrap.wireVersion,
				workerInstanceId: input.bootstrap.workerInstanceId,
			});
			await postBridgeProductResultAcknowledgement({
				policy: input.bootstrap.policy,
				acknowledgement,
				capabilityHeader,
				deadlineClock: this.#deadlineClock,
				executeProductRequest: this.#executeProductRequest,
			});
		});
		void open.catch((): void => {});
		this.#installedAuthority = {
			bootstrap: input.bootstrap,
			capabilityHeader,
			open,
		};
		return this.#installedAuthority;
	};

	get installedAuthority(): BridgeProductSessionAuthority {
		if (this.#installedAuthority === null) {
			throw new Error('Bridge product session authority is not installed.');
		}
		return this.#installedAuthority;
	}
}

async function postBridgeProductControlRequest(props: {
	readonly capabilityHeader: string;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductAdmissionResponseSchema.parse>> {
	const response = await postBridgeProductAdmissionBody({
		body: props.request,
		capabilityHeader: props.capabilityHeader,
		executeProductRequest: props.executeProductRequest,
		...(props.signal === undefined ? {} : { signal: props.signal }),
	});
	try {
		const admitted = bridgeProductAdmissionResponseSchema.parse(
			parseBridgeProductStrictJSON(response.bytes),
		);
		if (response.status >= 400 && admitted.kind !== 'request.error') {
			throw new Error('A client refusal must carry request.error.');
		}
		return admitted;
	} catch {
		throw new BridgeProductRequestTransportError('Bridge product admission reply was unparseable.');
	}
}

async function postBridgeProductEscapeControlRequest(props: {
	readonly policy: BridgeProductSessionBootstrap['policy'];
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductControlResponseSchema.parse>> {
	return await postBridgeProductExactAdmissionWithRetry({
		policy: props.policy,
		deadlineClock: props.deadlineClock,
		run: async (signal): Promise<ReturnType<typeof bridgeProductControlResponseSchema.parse>> => {
			const responseBytes = await postBridgeProductCommandBody({
				body: props.request,
				capabilityHeader: props.capabilityHeader,
				executeProductRequest: props.executeProductRequest,
				signal,
			});
			return bridgeProductControlResponseSchema.parse(parseBridgeProductStrictJSON(responseBytes));
		},
		...(props.signal === undefined ? {} : { signal: props.signal }),
	});
}

async function postBridgeProductOperationObservation(props: {
	readonly after: number;
	readonly bootstrap: BridgeProductSessionBootstrap;
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly operationId: string;
}): Promise<BridgeProductOperationObservationResponse> {
	const request = bridgeProductOperationObservationRequestSchema.parse({
		after: props.after,
		kind: 'operation.observe',
		operationId: props.operationId,
		paneSessionId: props.bootstrap.paneSessionId,
		wireVersion: props.bootstrap.wireVersion,
		workerInstanceId: props.bootstrap.workerInstanceId,
	});
	const response = await postBridgeProductOutcomeReadWithRetry({
		bootstrap: props.bootstrap,
		deadlineClock: props.deadlineClock,
		run: async (signal) => {
			try {
				const responseBytes = await postBridgeProductCommandBody({
					body: request,
					capabilityHeader: props.capabilityHeader,
					executeProductRequest: props.executeProductRequest,
					signal,
				});
				return bridgeProductOperationObservationResponseSchema.parse(
					parseBridgeProductStrictJSON(responseBytes),
				);
			} catch (error: unknown) {
				if (error instanceof BridgeProductResponseSizeLimitError) throw error;
				signal.throwIfAborted();
				throw new BridgeProductRequestTransportError('Bridge observation reply unreadable.');
			}
		},
	});
	if (response.operationId !== props.operationId) {
		throw new Error('Bridge product observation did not match its admitted operation.');
	}
	if (
		(response.kind === 'operation.stillUnknown' && response.revision !== props.after) ||
		(response.kind === 'operation.lateOutcome' && response.revision <= props.after)
	) {
		throw new Error('Bridge product observation returned an invalid evidence revision.');
	}
	return response;
}

async function postBridgeProductOperationResult(props: {
	readonly bootstrap: BridgeProductSessionBootstrap;
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly operationId: string;
	readonly signal?: AbortSignal;
	readonly waitKind: BridgeProductOperationAdmittedResponse['waitKind'];
}): Promise<ReturnType<typeof bridgeProductOperationResultResponseSchema.parse>> {
	const request = bridgeProductOperationResultRequestSchema.parse({
		kind: 'operation.result',
		operationId: props.operationId,
		paneSessionId: props.bootstrap.paneSessionId,
		wireVersion: props.bootstrap.wireVersion,
		workerInstanceId: props.bootstrap.workerInstanceId,
	});
	const result = await postBridgeProductOutcomeReadWithRetry({
		bootstrap: props.bootstrap,
		deadlineClock: props.deadlineClock,
		...(props.signal === undefined ? {} : { signal: props.signal }),
		waitKind: props.waitKind,
		run: async (signal) => {
			try {
				const responseBytes = await postBridgeProductCommandBody({
					body: request,
					capabilityHeader: props.capabilityHeader,
					executeProductRequest: props.executeProductRequest,
					signal,
				});
				return bridgeProductOperationResultResponseSchema.parse(
					parseBridgeProductStrictJSON(responseBytes),
				);
			} catch (error: unknown) {
				if (error instanceof BridgeProductResponseSizeLimitError) throw error;
				signal.throwIfAborted();
				throw new BridgeProductRequestTransportError('Bridge product result reply was unreadable.');
			}
		},
	});
	if (result.operationId !== props.operationId) {
		throw new Error('Bridge product operation result did not match its admission.');
	}
	return result;
}

async function postBridgeProductOutcomeReadWithRetry<TResult>(props: {
	readonly bootstrap: BridgeProductSessionBootstrap;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly run: (signal: AbortSignal) => Promise<TResult>;
	readonly signal?: AbortSignal;
	readonly waitKind?: BridgeProductOperationAdmittedResponse['waitKind'];
}): Promise<TResult> {
	for (let attempt = 0; attempt <= props.bootstrap.policy.admissionRetryCount; attempt += 1) {
		try {
			return props.waitKind === 'human'
				? await props.run(props.signal ?? new AbortController().signal)
				: await withBridgeProductDeadline({
						clock: props.deadlineClock,
						delayMilliseconds: props.bootstrap.policy.workerSettlementDeadlineMilliseconds,
						run: props.run,
						...(props.signal === undefined ? {} : { signal: props.signal }),
					});
		} catch (error: unknown) {
			props.signal?.throwIfAborted();
			if (error instanceof BridgeProductRequestDeadlineError) continue;
			if (error instanceof BridgeProductRequestTransportError) continue;
			throw error;
		}
	}
	throw new BridgeProductSessionSuspectError('result');
}

async function postBridgeProductResultAcknowledgement(props: {
	readonly policy: BridgeProductSessionBootstrap['policy'];
	readonly acknowledgement: ReturnType<
		typeof bridgeProductOperationResultAcknowledgementSchema.parse
	>;
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly recordAttemptFailure?: (outcome: BridgeWorkerAckAttemptOutcome) => void;
}): Promise<ReturnType<typeof bridgeProductOperationResultAcknowledgedResponseSchema.parse>> {
	return await postBridgeProductExactAdmissionWithRetry({
		policy: props.policy,
		deadlineClock: props.deadlineClock,
		onAttemptFailure: (error): void => {
			props.recordAttemptFailure?.(bridgeProductAckAttemptOutcome(error));
		},
		run: async (
			signal,
		): Promise<ReturnType<typeof bridgeProductOperationResultAcknowledgedResponseSchema.parse>> => {
			const observedReply: { response: Response | null } = { response: null };
			try {
				const responseBytes = await postBridgeProductCommandBody({
					body: props.acknowledgement,
					capabilityHeader: props.capabilityHeader,
					executeProductRequest: props.executeProductRequest,
					observeResponse: (response): void => {
						observedReply.response = response;
					},
					signal,
				});
				const parsed = bridgeProductOperationResultAcknowledgedResponseSchema.safeParse(
					parseBridgeProductStrictJSON(responseBytes),
				);
				if (!parsed.success) {
					throw new BridgeProductAckAttemptTransportError({ kind: 'parseFailure' });
				}
				const response = parsed.data;
				if (
					response.operationId !== props.acknowledgement.operationId ||
					response.requestSequence !== props.acknowledgement.requestSequence ||
					response.requestId !== props.acknowledgement.requestId
				) {
					throw new BridgeProductAckAttemptTransportError({ kind: 'identityMismatch' });
				}
				return response;
			} catch (error: unknown) {
				if (
					error instanceof BridgeProductResponseSizeLimitError ||
					error instanceof BridgeProductAckAttemptTransportError
				)
					throw error;
				signal.throwIfAborted();
				if (observedReply.response !== null && !observedReply.response.ok) {
					throw new BridgeProductAckAttemptTransportError(
						await bridgeProductAckHTTPFailureOutcome(observedReply.response, props.acknowledgement),
					);
				}
				throw new BridgeProductAckAttemptTransportError({
					kind: error instanceof BridgeProductStrictJSONError ? 'parseFailure' : 'transportFailure',
				});
			}
		},
	});
}

function bridgeProductAckAttemptOutcome(error: unknown): BridgeWorkerAckAttemptOutcome {
	if (error instanceof BridgeProductRequestDeadlineError) return { kind: 'deadlineExpired' };
	if (error instanceof BridgeProductAckAttemptTransportError) return error.outcome;
	if (error instanceof BridgeProductResponseSizeLimitError) return { kind: 'responseSizeLimit' };
	return { kind: 'transportFailure' };
}
