import {
	bridgeProductCallRequestSchema,
	bridgeProductSurfaceForCallKind,
	type BridgeProductCallKind,
	type BridgeProductCallRequest,
	type BridgeProductCallResult,
	type BridgeProductCallResultWire,
} from './bridge-product-call-contracts.js';
import {
	BRIDGE_PRODUCT_COMMAND_ROUTE,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
} from './bridge-product-contract-primitives.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductControlResponseSchema,
	encodeBridgeProductCapabilityHeader,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductSessionBootstrap,
} from './bridge-product-session-contracts.js';
import { parseBridgeProductStrictJSON } from './bridge-product-strict-json.js';
import {
	bridgeProductSurfaceForSubscriptionKind,
	type BridgeProductSubscriptionInterestDeltaWire,
	type BridgeProductSubscriptionKind,
	type BridgeProductSubscriptionOpenWire,
} from './bridge-product-subscription-contracts.js';

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
}

type BridgeProductControlResponseForKind<
	TResponseKind extends BridgeProductControlResponse['kind'],
> = Extract<BridgeProductControlResponse, { readonly kind: TResponseKind }>;

type BridgeProductSubscriptionOpenForKind<TSubscriptionKind extends BridgeProductSubscriptionKind> =
	Extract<BridgeProductSubscriptionOpenWire, { readonly subscriptionKind: TSubscriptionKind }>;

type BridgeProductSubscriptionDeltaForKind<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = Extract<
	BridgeProductSubscriptionInterestDeltaWire,
	{ readonly subscriptionKind: TSubscriptionKind }
>;

export type BridgeProductSubscriptionOpenAccepted<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = Omit<BridgeProductControlResponseForKind<'subscription.openAccepted'>, 'subscriptionKind'> & {
	readonly subscriptionKind: TSubscriptionKind;
};

export type BridgeProductSubscriptionUpdateBatchAccepted<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = Omit<
	BridgeProductControlResponseForKind<'subscription.updateBatchAccepted'>,
	'subscriptionKind'
> & {
	readonly subscriptionKind: TSubscriptionKind;
};

export type BridgeProductSubscriptionCancelAccepted<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = Omit<BridgeProductControlResponseForKind<'subscription.cancelAccepted'>, 'subscriptionKind'> & {
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
	readonly acceptResponse: (response: BridgeProductControlResponse) => TResult;
	readonly buildRequest: (
		identity: BridgeProductControlAdmissionIdentity,
	) => BridgeProductControlRequest;
	readonly requestErrorFallback?: (code: string) => string;
	readonly signal?: AbortSignal;
}

export class BridgeProductControlMux {
	readonly #authority: BridgeProductSessionAuthority;
	readonly #createRequestId: () => string;
	#nextRequestSequence = 2;
	#pendingAdmission: Promise<void> = Promise.resolve();

	constructor(props: BridgeProductControlMuxProps) {
		this.#authority = props.authority;
		this.#createRequestId = props.createRequestId ?? ((): string => crypto.randomUUID());
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

	openSubscription<TSubscriptionKind extends BridgeProductSubscriptionKind>(props: {
		readonly signal?: AbortSignal;
		readonly subscription: BridgeProductSubscriptionOpenForKind<TSubscriptionKind>;
		readonly subscriptionId: string;
		readonly workerDerivationEpoch: number;
	}): Promise<BridgeProductSubscriptionOpenAccepted<TSubscriptionKind>> {
		return this.#admit({
			acceptResponse: (response): BridgeProductSubscriptionOpenAccepted<TSubscriptionKind> => {
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
				bridgeProductSurfaceForSubscriptionKind(props.subscription.subscriptionKind);
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

	updateSubscriptionBatch<TSubscriptionKind extends BridgeProductSubscriptionKind>(props: {
		readonly baseInterestRevision: number;
		readonly baseInterestSha256: string;
		readonly batchCount: number;
		readonly batchIndex: number;
		readonly delta: BridgeProductSubscriptionDeltaForKind<TSubscriptionKind>;
		readonly signal?: AbortSignal;
		readonly subscriptionId: string;
		readonly targetInterestRevision: number;
		readonly targetInterestSha256: string;
		readonly totalDeltaItemCount: number;
		readonly updateId: string;
		readonly workerDerivationEpoch: number;
	}): Promise<BridgeProductSubscriptionUpdateBatchAccepted<TSubscriptionKind>> {
		return this.#admit({
			acceptResponse: (
				response,
			): BridgeProductSubscriptionUpdateBatchAccepted<TSubscriptionKind> => {
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
				bridgeProductSurfaceForSubscriptionKind(props.delta.subscriptionKind);
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

	cancelSubscription<TSubscriptionKind extends BridgeProductSubscriptionKind>(props: {
		readonly signal?: AbortSignal;
		readonly subscriptionId: string;
		readonly subscriptionKind: TSubscriptionKind;
		readonly workerDerivationEpoch: number;
	}): Promise<BridgeProductSubscriptionCancelAccepted<TSubscriptionKind>> {
		return this.#admit({
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
				bridgeProductSurfaceForSubscriptionKind(props.subscriptionKind);
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

	#admit<TResult>(props: BridgeProductControlAdmissionProps<TResult>): Promise<TResult> {
		return this.#enqueue(async (): Promise<TResult> => {
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
				request,
				...(props.signal === undefined ? {} : { signal: props.signal }),
			});
			assertBridgeProductResponseCorrelation({ request, response });
			this.#nextRequestSequence += 1;
			if (response.kind === 'request.error') {
				throw new Error(
					response.safeMessage ??
						props.requestErrorFallback?.(response.code) ??
						`Bridge product control request was rejected with ${response.code}.`,
				);
			}
			return props.acceptResponse(response);
		});
	}

	#enqueue<TResult>(operation: () => Promise<TResult>): Promise<TResult> {
		const result = this.#pendingAdmission.then(operation, operation);
		this.#pendingAdmission = result.then(
			(): void => {},
			(): void => {},
		);
		return result;
	}
}

async function postBridgeProductControlRequestWithExactRetry(props: {
	readonly capabilityHeader: string;
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductControlResponseSchema.parse>> {
	try {
		return await postBridgeProductControlRequest(props);
	} catch (error: unknown) {
		props.signal?.throwIfAborted();
		return await postBridgeProductControlRequest(props).catch((): never => {
			throw error;
		});
	}
}

export class BridgeProductSessionAuthorityStore {
	#installedAuthority: BridgeProductSessionAuthority | null = null;

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
			request,
		}).then((response): void => {
			if (response.kind !== 'workerSession.accepted') {
				throw new Error('Bridge product session open was not accepted.');
			}
			if (
				response.wireVersion !== request.wireVersion ||
				response.paneSessionId !== request.paneSessionId ||
				response.workerInstanceId !== request.workerInstanceId ||
				response.requestId !== request.requestId ||
				response.requestSequence !== request.requestSequence
			) {
				throw new Error('Bridge product session acceptance does not match its issued request.');
			}
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
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly signal?: AbortSignal;
}): Promise<ReturnType<typeof bridgeProductControlResponseSchema.parse>> {
	const body = new TextEncoder().encode(JSON.stringify(props.request));
	if (body.byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES) {
		throw new Error('Bridge product control request exceeds the encoded body limit.');
	}
	const response = await fetch(BRIDGE_PRODUCT_COMMAND_ROUTE, {
		method: 'POST',
		headers: {
			'Content-Type': 'application/json',
			'X-AgentStudio-Bridge-Product-Capability': props.capabilityHeader,
		},
		body,
		signal: props.signal ?? null,
	});
	if (!response.ok) {
		throw new Error(`Bridge product control request failed with status ${response.status}.`);
	}
	const responseBytes = await readBridgeProductControlResponseBytes(response);
	return bridgeProductControlResponseSchema.parse(parseBridgeProductStrictJSON(responseBytes));
}

function assertBridgeProductResponseCorrelation(props: {
	readonly request: ReturnType<typeof bridgeProductControlRequestSchema.parse>;
	readonly response: ReturnType<typeof bridgeProductControlResponseSchema.parse>;
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

function bridgeProductCallResultForMethod<TCallKind extends BridgeProductCallKind>(
	method: TCallKind,
	call: BridgeProductCallResultWire,
): BridgeProductCallResult<TCallKind> {
	switch (method) {
		case 'file.source.current':
			if (call.method !== 'file.source.current') {
				throw new Error('Bridge product File source call returned a cross-wired result.');
			}
			return call.result;
		case 'file.activeViewerMode.update':
		case 'review.activeViewerMode.update':
		case 'review.markFileViewed':
			if (call.result !== null) {
				throw new Error('Bridge product null-result call returned a non-null result.');
			}
			return null;
		default:
			return assertNeverBridgeProductCallKind(method);
	}
}

function assertNeverBridgeProductCallKind(callKind: never): never {
	throw new Error(`Unhandled Bridge product call kind: ${String(callKind)}`);
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
