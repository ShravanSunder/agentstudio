import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';
import type { BridgeProductDeadlineClock } from './bridge-product-deadline-clock.js';
import {
	bridgeProductOperationResultAcknowledgementSchema,
	bridgeProductOperationResultRequestSchema,
} from './bridge-product-operation-wire-contracts.js';
import type { BridgeProductRequestExecutor } from './bridge-product-request-executor.js';
import {
	BridgeProductControlMux,
	BridgeProductSessionAuthorityStore,
} from './bridge-product-session-authority.js';
import {
	bridgeProductControlRequestSchema,
	type BridgeProductSessionBootstrap,
} from './bridge-product-session-contracts.js';

const commandSchema = z.union([
	bridgeProductControlRequestSchema,
	bridgeProductOperationResultRequestSchema,
	bridgeProductOperationResultAcknowledgementSchema,
]);
const clock: BridgeProductDeadlineClock = { schedule: () => (): void => {} };
const bootstrap: BridgeProductSessionBootstrap = {
	kind: 'productSession.bootstrap',
	paneSessionId: 'pane-result-ack',
	policy: {
		admissionRetryCount: 2,
		contentProgressDeadlineMilliseconds: 5_000,
		viewBatchProgressDeadlineMilliseconds: 5_000,
		maximumContentBytes: 2 * 1024 * 1024,
		maximumMetadataFrameBytes: 128 * 1024,
		maximumQueuedStreamBytes: 4 * 1024 * 1024,
		maximumQueuedStreamFrames: 64,
		maximumRequestBodyBytes: 256 * 1024,
		terminalFrameReserve: 1,
		telemetryPreReadyBufferMaxBytes: 64 * 1024,
		telemetryPreReadyBufferMaxSamples: 128,
		workerSettlementDeadlineMilliseconds: 5_000,
		viewAcknowledgementDeadlineMilliseconds: 4_000,
		viewCreditBytes: 524_288,
		viewCreditParts: 8,
		viewMaximumConsecutiveResnapshots: 3,
		viewMaximumDirtyKeys: 4_096,
	},
	wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
	workerInstanceId: 'worker-result-ack',
};

function jsonResponse(value: object): Response {
	return new Response(JSON.stringify(value), {
		headers: { 'Content-Type': 'application/json' },
		status: 200,
	});
}

function createExecutor(props: {
	readonly acknowledgementBodies: string[];
	readonly loseAcknowledgements: boolean;
}): BridgeProductRequestExecutor {
	return async (_route, requestInit): Promise<Response> => {
		if (!(requestInit.body instanceof Uint8Array)) throw new Error('Expected encoded body.');
		const body = new TextDecoder().decode(requestInit.body);
		const command = commandSchema.parse(JSON.parse(body));
		if (command.kind === 'operation.result') {
			const opening = command.operationId === 'operation-open';
			return jsonResponse({
				failureCode: null,
				kind: 'operation.result',
				operationId: command.operationId,
				outcome: 'succeeded',
				result: opening
					? {
							kind: 'workerSession.accepted',
							requestId: 'worker-session-open-1',
							requestSequence: 1,
							result: null,
							...sessionIdentity,
						}
					: {
							call: { method: 'review.markFileViewed', result: null },
							kind: 'call.completed',
							requestId: 'request-1',
							requestSequence: 3,
							...sessionIdentity,
						},
			});
		}
		if (command.kind === 'operation.resultAcknowledgement') {
			if (command.operationId === 'operation-save') {
				props.acknowledgementBodies.push(body);
				if (props.loseAcknowledgements) return new Response('lost', { status: 502 });
			}
			return jsonResponse({ ...command, kind: 'operation.resultAcknowledged' });
		}
		return jsonResponse({
			kind: 'operation.admitted',
			operationId: command.kind === 'workerSession.open' ? 'operation-open' : 'operation-save',
			waitKind: 'ordinary',
			requestId: command.requestId,
			requestSequence: command.requestSequence,
			...sessionIdentity,
		});
	};
}

const sessionIdentity = {
	paneSessionId: bootstrap.paneSessionId,
	wireVersion: bootstrap.wireVersion,
	workerInstanceId: bootstrap.workerInstanceId,
} as const;

async function callOnSession(props: {
	readonly acknowledgementBodies: string[];
	readonly loseAcknowledgements: boolean;
	readonly onSessionSuspect?: (reason: 'admissionReplyExhausted') => void;
}): Promise<BridgeProductControlMux> {
	const executeProductRequest = createExecutor(props);
	const authority = new BridgeProductSessionAuthorityStore(executeProductRequest, clock).install({
		bootstrap,
		productCapability: new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH),
	});
	const mux = new BridgeProductControlMux({
		authority,
		createRequestId: (): string => 'request-1',
		deadlineClock: clock,
		executeProductRequest,
		...(props.onSessionSuspect === undefined ? {} : { onSessionSuspect: props.onSessionSuspect }),
	});
	await authority.open;
	await expect(
		mux.call({
			method: 'review.markFileViewed',
			request: { itemId: 'review-item-1' },
			workerDerivationEpoch: 1,
		}),
	).resolves.toBeNull();
	return mux;
}

describe('Bridge product result acknowledgement owner', () => {
	test('exhausted exact ack replay declares suspect once after delivering success', async () => {
		const acknowledgementBodies: string[] = [];
		const suspectReasons: string[] = [];
		const oldSession = await callOnSession({
			acknowledgementBodies,
			loseAcknowledgements: true,
			onSessionSuspect: (reason): void => {
				suspectReasons.push(reason);
			},
		});
		await oldSession.waitForAcknowledgementsQuiescent();
		expect(acknowledgementBodies).toHaveLength(bootstrap.policy.admissionRetryCount + 1);
		expect(new Set(acknowledgementBodies).size).toBe(1);
		expect(suspectReasons).toEqual(['admissionReplyExhausted']);
		expect(oldSession.diagnosticSnapshot.pendingAcknowledgementCount).toBe(0);

		const successorBodies: string[] = [];
		const successor = await callOnSession({
			acknowledgementBodies: successorBodies,
			loseAcknowledgements: false,
		});
		await successor.waitForAcknowledgementsQuiescent();
		expect(successorBodies).toHaveLength(1);
	});
});
