import { describe, expect, test } from 'vitest';

import { createBridgeProductDeferred } from './bridge-product-async-queue.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';
import type { BridgeProductRequestExecutor } from './bridge-product-request-executor.js';
import {
	BridgeProductControlMux,
	type BridgeProductSessionAuthority,
} from './bridge-product-session-authority.js';
import {
	bridgeProductControlRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductControlResponse,
	type BridgeProductResyncReconciliationOutcome,
} from './bridge-product-session-contracts.js';

type ActiveSubscriptions = Extract<
	BridgeProductControlRequest,
	{ kind: 'workerSession.resync' }
>['activeSubscriptions'];
type ResyncRequest = Extract<BridgeProductControlRequest, { kind: 'workerSession.resync' }>;
type ResyncResponse = Extract<BridgeProductControlResponse, { kind: 'resync.accepted' }>;

const firstInterestSha256 = '1a71797cab8ed23c72233b7706b166a33049e4e87dfbc55b9e252f9c1843eca6';
const secondInterestSha256 = '2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd';

describe('Bridge product control mux resync', () => {
	test('exposes the strict worker-session resync operation', () => {
		const mux = createControlMux(async (): Promise<Response> => new Response(null));

		expect('resync' in mux).toBe(true);
	});

	test.each(canonicalReconciliationOutcomes())(
		'accepts a canonical $disposition reconciliation response',
		async (outcome) => {
			const activeSubscriptions = oneActiveSubscription();
			const mux = createControlMux(async (_route, requestInit): Promise<Response> => {
				const request = requireResyncRequest(requestInit);
				return responseWithJSON(resyncAcceptedResponse(request, [outcome]));
			});

			await expect(
				mux.resync({
					readActiveSubscriptions: () => activeSubscriptions,
					readLastAcceptedStreamSequence: () => 12,
				}),
			).resolves.toMatchObject({
				kind: 'resync.accepted',
				metadataStreamSequenceBarrier: 12,
				nextExpectedRequestSequence: 3,
				reconciliation: [outcome],
			});
		},
	);

	test('rejects a correlated response whose kind is not resync.accepted', async () => {
		await expectRejectedResyncResponse(
			(request) => ({
				...responseIdentity(request),
				kind: 'workerSession.accepted',
				result: null,
			}),
			/resync\.accepted/iu,
		);
	});

	test('rejects a response with a noncontiguous next request sequence', async () => {
		await expectRejectedResyncResponse(
			(request) => ({
				...resyncAcceptedResponse(request, [
					retainedOutcome(requireArrayItem(oneActiveSubscription(), 0, 'active subscription')),
				]),
				nextExpectedRequestSequence: request.requestSequence + 2,
			}),
			/unexpected next request sequence/iu,
		);
	});

	test('rejects a metadata barrier behind the claimed accepted sequence', async () => {
		await expectRejectedResyncResponse(
			(request) => ({
				...resyncAcceptedResponse(request, [
					retainedOutcome(requireArrayItem(oneActiveSubscription(), 0, 'active subscription')),
				]),
				metadataStreamSequenceBarrier: request.lastAcceptedStreamSequence - 1,
			}),
			/metadata barrier precedes/iu,
		);
	});

	test('rejects positional reconciliation identity mismatch', async () => {
		const activeSubscriptions = twoActiveSubscriptions();
		const mux = createControlMux(async (_route, requestInit): Promise<Response> => {
			const request = requireResyncRequest(requestInit);
			return responseWithJSON(
				resyncAcceptedResponse(request, [
					retainedOutcome(requireArrayItem(activeSubscriptions, 1, 'second active subscription')),
					retainedOutcome(requireArrayItem(activeSubscriptions, 0, 'first active subscription')),
				]),
			);
		});

		await expect(
			mux.resync({
				readActiveSubscriptions: () => activeSubscriptions,
				readLastAcceptedStreamSequence: () => 12,
			}),
		).rejects.toThrow(/order or identity/iu);
	});

	test.each([
		['interest hash', { interestSha256: secondInterestSha256 }],
		['interest revision', { interestRevision: 8 }],
	] satisfies readonly [string, Readonly<Record<string, string | number>>][])(
		'rejects a retained reconciliation with a mismatched %s',
		async (_field, mismatch) => {
			await expectRejectedResyncResponse(
				(request) => ({
					...resyncAcceptedResponse(request, [
						retainedOutcome(requireArrayItem(oneActiveSubscription(), 0, 'active subscription')),
					]),
					reconciliation: [
						{
							...retainedOutcome(
								requireArrayItem(oneActiveSubscription(), 0, 'active subscription'),
							),
							...mismatch,
						},
					],
				}),
				/retained reconciliation/iu,
			);
		},
	);

	test('captures resync state only after a held prior control settles', async () => {
		const heldCallResponse = createBridgeProductDeferred<Response>();
		const heldCallStarted = createBridgeProductDeferred<void>();
		const admittedRequests: BridgeProductControlRequest[] = [];
		const requestIds = ['held-call', 'resync-after-held-call'];
		const executeProductRequest: BridgeProductRequestExecutor = async (
			_route,
			requestInit,
		): Promise<Response> => {
			const request = requireControlRequest(requestInit);
			admittedRequests.push(request);
			if (request.kind === 'product.call') {
				heldCallStarted.resolve();
				return await heldCallResponse.promise;
			}
			if (request.kind === 'workerSession.resync') {
				return responseWithJSON(
					resyncAcceptedResponse(request, request.activeSubscriptions.map(retainedOutcome)),
				);
			}
			throw new Error(`Unexpected control request ${request.kind}.`);
		};
		const mux = createControlMux(executeProductRequest, requestIds);
		let activeSubscriptions = oneActiveSubscription();
		let lastAcceptedStreamSequence = 4;
		let activeSubscriptionReadCount = 0;
		let streamSequenceReadCount = 0;
		const heldCall = mux.call({
			method: 'review.markFileViewed',
			request: { itemId: 'review-item-1' },
			workerDerivationEpoch: 3,
		});
		await heldCallStarted.promise;
		const resync = mux.resync({
			readActiveSubscriptions: (): ActiveSubscriptions => {
				activeSubscriptionReadCount += 1;
				return activeSubscriptions;
			},
			readLastAcceptedStreamSequence: (): number => {
				streamSequenceReadCount += 1;
				return lastAcceptedStreamSequence;
			},
		});

		expect(activeSubscriptionReadCount).toBe(0);
		expect(streamSequenceReadCount).toBe(0);
		activeSubscriptions = twoActiveSubscriptions();
		lastAcceptedStreamSequence = 9;
		heldCallResponse.resolve(
			responseWithJSON({
				...responseIdentity(
					requireProductCallRequest(requireArrayItem(admittedRequests, 0, 'held request')),
				),
				call: { method: 'review.markFileViewed', result: null },
				kind: 'call.completed',
			}),
		);

		await expect(heldCall).resolves.toBeNull();
		await expect(resync).resolves.toMatchObject({ nextExpectedRequestSequence: 4 });
		expect(activeSubscriptionReadCount).toBe(1);
		expect(streamSequenceReadCount).toBe(1);
		const resyncRequest = requireResyncRequestValue(
			requireArrayItem(admittedRequests, 1, 'resync request'),
		);
		expect(resyncRequest).toMatchObject({
			activeSubscriptions,
			lastAcceptedRequestSequence: 2,
			lastAcceptedStreamSequence: 9,
			requestSequence: 3,
		});
	});

	test('retries an ambiguous resync failure with identical request bytes', async () => {
		const requestBodies: Uint8Array[] = [];
		let attemptCount = 0;
		const mux = createControlMux(async (_route, requestInit): Promise<Response> => {
			const body = requireUint8Array(requestInit.body);
			requestBodies.push(Uint8Array.from(body));
			attemptCount += 1;
			if (attemptCount === 1) throw new Error('ambiguous resync transport failure');
			const request = requireResyncRequest(requestInit);
			return responseWithJSON(
				resyncAcceptedResponse(request, [
					retainedOutcome(requireArrayItem(oneActiveSubscription(), 0, 'active subscription')),
				]),
			);
		});

		await expect(
			mux.resync({
				readActiveSubscriptions: oneActiveSubscription,
				readLastAcceptedStreamSequence: () => 12,
			}),
		).resolves.toMatchObject({ kind: 'resync.accepted' });
		expect(requestBodies).toHaveLength(2);
		expect([...requireArrayItem(requestBodies, 0, 'first resync attempt')]).toEqual([
			...requireArrayItem(requestBodies, 1, 'second resync attempt'),
		]);
	});
});

async function expectRejectedResyncResponse(
	createResponse: (request: ResyncRequest) => unknown,
	expectedError: RegExp,
): Promise<void> {
	const mux = createControlMux(async (_route, requestInit): Promise<Response> => {
		const request = requireResyncRequest(requestInit);
		return responseWithJSON(createResponse(request));
	});
	await expect(
		mux.resync({
			readActiveSubscriptions: oneActiveSubscription,
			readLastAcceptedStreamSequence: () => 12,
		}),
	).rejects.toThrow(expectedError);
}

function oneActiveSubscription(): ActiveSubscriptions {
	return [
		{
			interestRevision: 7,
			interestSha256: firstInterestSha256,
			subscriptionId: 'review-subscription-1',
			subscriptionKind: 'review.metadata',
			workerDerivationEpoch: 3,
		},
	];
}

function twoActiveSubscriptions(): ActiveSubscriptions {
	return [
		...oneActiveSubscription(),
		{
			interestRevision: 2,
			interestSha256: secondInterestSha256,
			subscriptionId: 'file-subscription-1',
			subscriptionKind: 'file.metadata',
			workerDerivationEpoch: 5,
		},
	];
}

function canonicalReconciliationOutcomes(): readonly BridgeProductResyncReconciliationOutcome[] {
	const activeSubscription = requireArrayItem(oneActiveSubscription(), 0, 'active subscription');
	return [
		retainedOutcome(activeSubscription),
		{
			disposition: 'reset',
			interestRevision: 8,
			interestSha256: secondInterestSha256,
			reason: 'interest_mismatch',
			subscriptionId: activeSubscription.subscriptionId,
			subscriptionKind: activeSubscription.subscriptionKind,
			workerDerivationEpoch: activeSubscription.workerDerivationEpoch,
		},
		{
			disposition: 'cancelled',
			priorWorkerDerivationEpoch: activeSubscription.workerDerivationEpoch,
			reason: 'native_revoked',
			subscriptionId: activeSubscription.subscriptionId,
			subscriptionKind: activeSubscription.subscriptionKind,
		},
		{
			disposition: 'reopenRequired',
			reason: 'snapshot_required',
			requiredWorkerDerivationEpoch: activeSubscription.workerDerivationEpoch,
			subscriptionId: activeSubscription.subscriptionId,
			subscriptionKind: activeSubscription.subscriptionKind,
		},
	];
}

function retainedOutcome(
	activeSubscription: ActiveSubscriptions[number],
): BridgeProductResyncReconciliationOutcome {
	return {
		disposition: 'retained',
		interestRevision: activeSubscription.interestRevision,
		interestSha256: activeSubscription.interestSha256,
		subscriptionId: activeSubscription.subscriptionId,
		subscriptionKind: activeSubscription.subscriptionKind,
		workerDerivationEpoch: activeSubscription.workerDerivationEpoch,
	};
}

function resyncAcceptedResponse(
	request: ResyncRequest,
	reconciliation: readonly BridgeProductResyncReconciliationOutcome[],
): ResyncResponse {
	return {
		...responseIdentity(request),
		kind: 'resync.accepted',
		metadataStreamSequenceBarrier: request.lastAcceptedStreamSequence,
		nextExpectedRequestSequence: request.requestSequence + 1,
		reconciliation,
	};
}

function responseIdentity(request: BridgeProductControlRequest): {
	readonly paneSessionId: string;
	readonly requestId: string;
	readonly requestSequence: number;
	readonly wireVersion: 2;
	readonly workerInstanceId: string;
} {
	return {
		paneSessionId: request.paneSessionId,
		requestId: request.requestId,
		requestSequence: request.requestSequence,
		wireVersion: request.wireVersion,
		workerInstanceId: request.workerInstanceId,
	};
}

function createControlMux(
	executeProductRequest: BridgeProductRequestExecutor,
	requestIds: string[] = ['resync-request-1'],
): BridgeProductControlMux {
	const authority: BridgeProductSessionAuthority = {
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: 'worker-instance-1',
		},
		capabilityHeader: 'private-capability',
		open: Promise.resolve(),
	};
	return new BridgeProductControlMux({
		authority,
		createRequestId: (): string => requireShiftedValue(requestIds),
		executeProductRequest,
	});
}

function requireControlRequest(requestInit: RequestInit): BridgeProductControlRequest {
	return bridgeProductControlRequestSchema.parse(
		JSON.parse(new TextDecoder().decode(requireUint8Array(requestInit.body))),
	);
}

function requireResyncRequest(requestInit: RequestInit): ResyncRequest {
	return requireResyncRequestValue(requireControlRequest(requestInit));
}

function requireResyncRequestValue(request: BridgeProductControlRequest): ResyncRequest {
	if (request.kind !== 'workerSession.resync') {
		throw new Error(`Expected workerSession.resync, received ${request.kind}.`);
	}
	return request;
}

function requireProductCallRequest(
	request: BridgeProductControlRequest,
): Extract<BridgeProductControlRequest, { kind: 'product.call' }> {
	if (request.kind !== 'product.call') throw new Error('Expected held product.call request.');
	return request;
}

function requireArrayItem<TValue>(
	values: readonly TValue[],
	index: number,
	description: string,
): TValue {
	const value = values[index];
	if (value === undefined) throw new Error(`Missing ${description} at index ${index}.`);
	return value;
}

function requireUint8Array(value: BodyInit | null | undefined): Uint8Array {
	if (!(value instanceof Uint8Array)) throw new Error('Expected encoded Uint8Array request body.');
	return value;
}

function requireShiftedValue(values: string[]): string {
	const value = values.shift();
	if (value === undefined) throw new Error('Test request id queue was exhausted.');
	return value;
}

function responseWithJSON(value: unknown): Response {
	return new Response(JSON.stringify(value), { status: 200 });
}
