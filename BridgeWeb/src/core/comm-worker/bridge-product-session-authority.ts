import {
	bridgeProductCallRequestSchema,
	bridgeProductCallResultForMethod,
	bridgeProductSurfaceForCallKind,
	type BridgeProductCallKind,
	type BridgeProductCallRequest,
	type BridgeProductCallResult,
} from './bridge-product-call-contracts.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	type BridgeProductRequestErrorCode,
} from './bridge-product-contract-primitives.js';
import { bridgeProductControlPolicy } from './bridge-product-control-policy.js';
import {
	defaultBridgeProductDeadlineClock,
	type BridgeProductDeadlineClock,
} from './bridge-product-deadline-clock.js';
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
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';

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
}

type BridgeProductControlResponseForKind<
	TResponseKind extends BridgeProductControlResponse['kind'],
> = Extract<BridgeProductControlResponse, { readonly kind: TResponseKind }>;

export type BridgeProductSubscriptionOpenAccepted<TSubscriptionKind extends string> = Omit<
	BridgeProductControlResponseForKind<'subscription.openAccepted'>,
	'subscriptionKind'
> & {
	readonly subscriptionKind: TSubscriptionKind;
};

export type BridgeProductSubscriptionUpdateBatchAccepted<TSubscriptionKind extends string> = Omit<
	BridgeProductControlResponseForKind<'subscription.updateBatchAccepted'>,
	'subscriptionKind'
> & {
	readonly subscriptionKind: TSubscriptionKind;
};

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

export class BridgeProductControlRequestError extends Error {
	readonly code: BridgeProductRequestErrorCode;
	readonly outcome?: ReturnType<typeof bridgeProductOperationResultResponseSchema.parse>['outcome'];
	readonly retryAfterMilliseconds: number | null;
	readonly retryable: boolean;

	constructor(props: {
		readonly code: BridgeProductRequestErrorCode;
		readonly message: string;
		readonly outcome?: ReturnType<
			typeof bridgeProductOperationResultResponseSchema.parse
		>['outcome'];
		readonly retryAfterMilliseconds: number | null;
		readonly retryable: boolean;
	}) {
		super(props.message);
		this.name = 'BridgeProductControlRequestError';
		this.code = props.code;
		if (props.outcome !== undefined) this.outcome = props.outcome;
		this.retryAfterMilliseconds = props.retryAfterMilliseconds;
		this.retryable = props.retryable;
	}
}

export class BridgeProductSessionSuspectError extends Error {
	shouldNotify = true;

	constructor(readonly phase: 'admission' | 'result') {
		super(`Bridge product session ${phase} did not settle within its bounded retry window.`);
		this.name = 'BridgeProductSessionSuspectError';
	}
}

class BridgeProductRequestTransportError extends Error {}

class BridgeProductRequestDeadlineError extends Error {}

export class BridgeProductControlMux {
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly #authority: BridgeProductSessionAuthority;
	readonly #createRequestId: () => string;
	readonly #executeProductRequest: BridgeProductRequestExecutor;
	#nextRequestSequence = 3;
	#didDeclareSessionSuspect = false;
	#pendingAdmission: Promise<void> = Promise.resolve();
	#pendingAdmissionCount = 0;

	constructor(props: BridgeProductControlMuxProps) {
		this.deadlineClock = props.deadlineClock ?? defaultBridgeProductDeadlineClock;
		this.#authority = props.authority;
		this.#createRequestId = props.createRequestId ?? ((): string => crypto.randomUUID());
		this.#executeProductRequest = props.executeProductRequest;
	}

	get diagnosticSnapshot(): { readonly pendingAdmissionCount: number } {
		return { pendingAdmissionCount: this.#pendingAdmissionCount };
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
	}): Promise<BridgeProductSubscriptionOpenAccepted<TSubscriptionOpen['subscriptionKind']>> {
		return this.#admit({
			acceptResponse: (
				response,
			): BridgeProductSubscriptionOpenAccepted<TSubscriptionOpen['subscriptionKind']> => {
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
				return { ...response, subscriptionKind: props.subscription.subscriptionKind };
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

	updateSubscriptionBatch<TSubscriptionDelta extends { readonly subscriptionKind: string }>(props: {
		readonly baseInterestRevision: number;
		readonly baseInterestSha256: string;
		readonly batchCount: number;
		readonly batchIndex: number;
		readonly delta: TSubscriptionDelta;
		readonly signal?: AbortSignal;
		readonly subscriptionId: string;
		readonly targetInterestRevision: number;
		readonly targetInterestSha256: string;
		readonly totalDeltaItemCount: number;
		readonly updateId: string;
		readonly workerDerivationEpoch: number;
	}): Promise<
		BridgeProductSubscriptionUpdateBatchAccepted<TSubscriptionDelta['subscriptionKind']>
	> {
		return this.#admit({
			acceptResponse: (
				response,
			): BridgeProductSubscriptionUpdateBatchAccepted<TSubscriptionDelta['subscriptionKind']> => {
				if (response.kind !== 'subscription.updateBatchAccepted') {
					throw new Error(
						'Bridge product subscription update did not return subscription.updateBatchAccepted.',
					);
				}
				const expectedDisposition =
					props.batchIndex + 1 === props.batchCount ? 'committed' : 'staged';
				if (
					response.subscriptionId !== props.subscriptionId ||
					response.subscriptionKind !== props.delta.subscriptionKind ||
					response.batchIndex !== props.batchIndex ||
					response.disposition !== expectedDisposition ||
					response.targetInterestRevision !== props.targetInterestRevision ||
					response.targetInterestSha256 !== props.targetInterestSha256 ||
					response.updateId !== props.updateId
				) {
					throw new Error('Bridge product subscription update result does not match its request.');
				}
				return { ...response, subscriptionKind: props.delta.subscriptionKind };
			},
			buildRequest: (identity): BridgeProductControlRequest => {
				return bridgeProductControlRequestSchema.parse({
					...identity,
					baseInterestRevision: props.baseInterestRevision,
					baseInterestSha256: props.baseInterestSha256,
					batchCount: props.batchCount,
					batchIndex: props.batchIndex,
					delta: props.delta,
					kind: 'subscription.updateBatch',
					subscriptionId: props.subscriptionId,
					subscriptionKind: props.delta.subscriptionKind,
					targetInterestRevision: props.targetInterestRevision,
					targetInterestSha256: props.targetInterestSha256,
					totalDeltaItemCount: props.totalDeltaItemCount,
					updateId: props.updateId,
					workerDerivationEpoch: props.workerDerivationEpoch,
				});
			},
			...(props.signal === undefined ? {} : { signal: props.signal }),
		});
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
		const admission = this.#enqueue(
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
						});
					}
					const finalResponse = bridgeProductControlResponseSchema.parse(operationResult.result);
					assertBridgeProductResponseCorrelation({ request, response: finalResponse });
					return props.acceptResponse(finalResponse, request);
				} finally {
					await this.#enqueue(async (): Promise<void> => {
						const acknowledgement = bridgeProductOperationResultAcknowledgementSchema.parse({
							kind: 'operation.resultAcknowledgement',
							operationId: response.operationId,
							paneSessionId: this.#authority.bootstrap.paneSessionId,
							requestId: this.#createRequestId(),
							requestSequence: this.#nextRequestSequence,
							wireVersion: this.#authority.bootstrap.wireVersion,
							workerInstanceId: this.#authority.bootstrap.workerInstanceId,
						});
						const acknowledged = await postBridgeProductResultAcknowledgement({
							acknowledgement,
							capabilityHeader: this.#authority.capabilityHeader,
							deadlineClock: this.deadlineClock,
							executeProductRequest: this.#executeProductRequest,
						});
						if (acknowledged.operationId !== response.operationId) {
							throw new Error('Bridge product operation acknowledgement did not match its result.');
						}
						this.#nextRequestSequence += 1;
					});
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

	#admitEscape<TResult>(props: BridgeProductControlAdmissionProps<TResult>): Promise<TResult> {
		return this.#enqueue(async (): Promise<TResult> => {
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
		}).catch((error: unknown): never => {
			if (error instanceof BridgeProductSessionSuspectError) {
				error.shouldNotify = !this.#didDeclareSessionSuspect;
				this.#didDeclareSessionSuspect = true;
			}
			throw error;
		});
	}

	#enqueue<TResult>(operation: () => Promise<TResult>): Promise<TResult> {
		this.#pendingAdmissionCount += 1;
		const result = this.#pendingAdmission.then(operation, operation);
		this.#pendingAdmission = result.then(
			(): void => {
				this.#pendingAdmissionCount -= 1;
			},
			(): void => {
				this.#pendingAdmissionCount -= 1;
			},
		);
		return result;
	}
}

async function postBridgeProductControlRequestWithExactRetry(props: {
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductAdmissionResponseSchema.parse>> {
	return await postBridgeProductExactAdmissionWithRetry({
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
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly run: (signal: AbortSignal) => Promise<TResult>;
	readonly signal?: AbortSignal;
}): Promise<TResult> {
	for (let attempt = 0; attempt <= bridgeProductControlPolicy.admissionRetryCount; attempt += 1) {
		try {
			return await withBridgeProductDeadline({
				clock: props.deadlineClock,
				delayMilliseconds: bridgeProductControlPolicy.workerSettlementDeadlineMilliseconds,
				run: props.run,
				...(props.signal === undefined ? {} : { signal: props.signal }),
			});
		} catch (error: unknown) {
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
	const responseBytes = await postBridgeProductCommandBody({
		body: props.request,
		capabilityHeader: props.capabilityHeader,
		executeProductRequest: props.executeProductRequest,
		...(props.signal === undefined ? {} : { signal: props.signal }),
	});
	return bridgeProductAdmissionResponseSchema.parse(parseBridgeProductStrictJSON(responseBytes));
}

async function postBridgeProductEscapeControlRequest(props: {
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductControlResponseSchema.parse>> {
	return await postBridgeProductExactAdmissionWithRetry({
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
	const readResponse = (signal: AbortSignal): Promise<Uint8Array> =>
		postBridgeProductCommandBody({
			body: request,
			capabilityHeader: props.capabilityHeader,
			executeProductRequest: props.executeProductRequest,
			signal,
		});
	let responseBytes: Uint8Array;
	try {
		responseBytes =
			props.waitKind === 'human'
				? await readResponse(props.signal ?? new AbortController().signal)
				: await withBridgeProductDeadline({
						clock: props.deadlineClock,
						delayMilliseconds: bridgeProductControlPolicy.workerSettlementDeadlineMilliseconds,
						run: readResponse,
						...(props.signal === undefined ? {} : { signal: props.signal }),
					});
	} catch (error: unknown) {
		if (error instanceof BridgeProductRequestDeadlineError) {
			throw new BridgeProductSessionSuspectError('result');
		}
		throw error;
	}
	const result = bridgeProductOperationResultResponseSchema.parse(
		parseBridgeProductStrictJSON(responseBytes),
	);
	if (result.operationId !== props.operationId) {
		throw new Error('Bridge product operation result did not match its admission.');
	}
	return result;
}

async function postBridgeProductResultAcknowledgement(props: {
	readonly acknowledgement: ReturnType<
		typeof bridgeProductOperationResultAcknowledgementSchema.parse
	>;
	readonly capabilityHeader: string;
	readonly deadlineClock: BridgeProductDeadlineClock;
	readonly executeProductRequest: BridgeProductRequestExecutor;
}): Promise<ReturnType<typeof bridgeProductOperationResultAcknowledgedResponseSchema.parse>> {
	return await postBridgeProductExactAdmissionWithRetry({
		deadlineClock: props.deadlineClock,
		run: async (
			signal,
		): Promise<ReturnType<typeof bridgeProductOperationResultAcknowledgedResponseSchema.parse>> => {
			const responseBytes = await postBridgeProductCommandBody({
				body: props.acknowledgement,
				capabilityHeader: props.capabilityHeader,
				executeProductRequest: props.executeProductRequest,
				signal,
			});
			const response = bridgeProductOperationResultAcknowledgedResponseSchema.parse(
				parseBridgeProductStrictJSON(responseBytes),
			);
			if (
				response.operationId !== props.acknowledgement.operationId ||
				response.requestSequence !== props.acknowledgement.requestSequence ||
				response.requestId !== props.acknowledgement.requestId
			) {
				throw new Error('Bridge product operation acknowledgement did not match its request.');
			}
			return response;
		},
	});
}

async function postBridgeProductCommandBody(props: {
	readonly body: object;
	readonly capabilityHeader: string;
	readonly executeProductRequest: BridgeProductRequestExecutor;
	readonly signal?: AbortSignal;
}): Promise<Uint8Array> {
	const body = new TextEncoder().encode(JSON.stringify(props.body));
	if (body.byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES) {
		throw new Error('Bridge product control request exceeds the encoded body limit.');
	}
	let response: Response;
	try {
		response = await props.executeProductRequest('command', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'X-AgentStudio-Bridge-Product-Capability': props.capabilityHeader,
			},
			body,
			signal: props.signal ?? null,
		});
	} catch {
		props.signal?.throwIfAborted();
		throw new BridgeProductRequestTransportError('Bridge product command transport failed.');
	}
	if (!response.ok) {
		throw new Error(`Bridge product control request failed with status ${response.status}.`);
	}
	const responseBytes = await readBridgeProductControlResponseBytes(response);
	return responseBytes;
}

function assertBridgeProductResponseCorrelation(props: {
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly response:
		| ReturnType<typeof bridgeProductControlResponseSchema.parse>
		| ReturnType<typeof bridgeProductAdmissionResponseSchema.parse>;
}): void {
	if (
		props.response.wireVersion !== props.request.wireVersion ||
		props.response.paneSessionId !== props.request.paneSessionId ||
		props.response.workerInstanceId !== props.request.workerInstanceId ||
		props.response.requestId !== props.request.requestId ||
		props.response.requestSequence !== props.request.requestSequence
	) {
		throw new Error('Bridge product response does not match its issued request.');
	}
}

async function readBridgeProductControlResponseBytes(response: Response): Promise<Uint8Array> {
	if (response.body === null) {
		throw new Error('Bridge product control response did not expose a body stream.');
	}
	const reader = response.body.getReader();
	const responseBytes = new Uint8Array(BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES);
	let responseByteLength = 0;
	try {
		while (true) {
			// oxlint-disable-next-line eslint/no-await-in-loop -- Response chunks must be consumed in order.
			const chunk = await reader.read();
			if (chunk.done) {
				break;
			}
			if (chunk.value.byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES - responseByteLength) {
				// oxlint-disable-next-line eslint/no-await-in-loop -- Cancel must settle before releasing the reader lock.
				await reader.cancel().catch((): void => {});
				throw new Error('Bridge product control response exceeds the encoded body limit.');
			}
			responseBytes.set(chunk.value, responseByteLength);
			responseByteLength += chunk.value.byteLength;
		}
	} finally {
		reader.releaseLock();
	}
	return responseBytes.slice(0, responseByteLength);
}
