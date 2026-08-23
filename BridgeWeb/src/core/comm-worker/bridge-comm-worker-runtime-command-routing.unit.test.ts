import { describe, expect, test } from 'vitest';

import { bridgeCommWorkerSemanticClassForMessage } from './bridge-comm-worker-runtime-command-routing.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerMainToServerMessage,
} from './bridge-worker-contracts.js';

describe('Bridge comm worker semantic command classification', () => {
	test('separates durable annotation actions from annotation demand', () => {
		expect(
			bridgeCommWorkerSemanticClassForMessage(
				annotationMessage({
					body: 'exact durable body',
					editToken: '00000000-0000-7000-8000-000000000011',
					expectedDraftRevision: 2,
					expectedMessageRevision: 3,
					kind: 'draft.flush',
					messageId: '00000000-0000-7000-8000-000000000012',
					sessionId: '00000000-0000-7000-8000-000000000013',
				}),
			),
		).toBe('urgent_action');
		expect(
			bridgeCommWorkerSemanticClassForMessage(
				annotationMessage({
					kind: 'demand.acquire',
					sessionId: '00000000-0000-7000-8000-000000000013',
				}),
			),
		).toBe('demand');
	});

	test('classifies settlement and lifecycle controls independently of telemetry lane', () => {
		expect(bridgeCommWorkerSemanticClassForMessage(renderDispositionMessage())).toBe('settlement');
		expect(
			bridgeCommWorkerSemanticClassForMessage({
				...messageEnvelope('publication-installed'),
				command: 'reviewPublicationInstalled',
				packageId: 'package-installed',
				publicationId: '00000000-0000-7000-8000-000000000021',
				reviewGeneration: 7,
				revision: 3,
				sourceIdentity: 'source-installed',
			}),
		).toBe('lifecycle_control');
	});
});

function annotationMessage(
	operation: Extract<
		BridgeWorkerMainToServerMessage,
		{ readonly command: 'annotationCommand' }
	>['operation'],
): Extract<BridgeWorkerMainToServerMessage, { readonly command: 'annotationCommand' }> {
	return {
		...messageEnvelope('annotation'),
		command: 'annotationCommand',
		operation,
		surface: 'fileView',
	};
}

function renderDispositionMessage(): Extract<
	BridgeWorkerMainToServerMessage,
	{ readonly command: 'renderDisposition' }
> {
	return {
		...messageEnvelope('render-disposition'),
		command: 'renderDisposition',
		receipts: [
			{
				attemptId: '00000000-0000-7000-8000-000000000031',
				disposition: 'queued',
				itemId: 'item-1',
				kind: 'render.disposition',
				operationCorrelationId: null,
				paneSessionId: '00000000-0000-7000-8000-000000000032',
				publicationId: '00000000-0000-7000-8000-000000000033',
				publicationSequence: 1,
				receivedAtMilliseconds: 100,
				submissionId: '00000000-0000-7000-8000-000000000034',
				surface: 'review',
				windowKey: 'window-1',
				workerDerivationEpoch: 2,
				workerInstanceId: '00000000-0000-7000-8000-000000000035',
			},
		],
	};
}

function messageEnvelope(requestId: string): {
	readonly direction: 'mainToServerWorker';
	readonly epoch: number;
	readonly kind: 'command';
	readonly requestId: string;
	readonly transferDescriptors: readonly [];
	readonly wireVersion: typeof BRIDGE_WORKER_WIRE_VERSION;
} {
	return {
		direction: 'mainToServerWorker' as const,
		epoch: 1,
		kind: 'command' as const,
		requestId,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
}
