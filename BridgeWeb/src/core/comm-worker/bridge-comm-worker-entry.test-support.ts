import type { BridgeProductReviewContentDescriptor } from './bridge-product-content-contracts.js';
import {
	bridgeProductOperationResultAcknowledgementSchema,
	bridgeProductOperationResultRequestSchema,
} from './bridge-product-operation-wire-contracts.js';
import {
	bridgeProductControlRequestSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgeProductControlRequest,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type {
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewPublicationIdentity,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';

export interface MakeFetchedReviewContentResourceProps {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly text: string;
}

export function makeReviewContentDescriptor(props: {
	readonly role: BridgeProductReviewContentDescriptor['role'];
	readonly text: string;
}): BridgeProductReviewContentDescriptor {
	const byteLength = new TextEncoder().encode(props.text).byteLength;
	return {
		contentDigest: {
			algorithm: 'fixture-preview',
			authority: 'provisional',
			value: `item-1:${props.role}:generation-4`,
		},
		contentKind: 'review.content',
		declaredByteLength: byteLength,
		descriptorId: `descriptor-item-1-${props.role}`,
		encoding: 'utf-8',
		endpointId: `endpoint-${props.role}`,
		expectedSha256: null,
		handleId: `handle-item-1-${props.role}`,
		isBinary: false,
		itemId: 'item-1',
		language: 'swift',
		maximumBytes: byteLength,
		mimeType: 'text/plain',
		packageId: 'package-1',
		reviewGeneration: 4,
		role: props.role,
		sourceIdentity: 'source-1',
		wholeByteLength: byteLength,
		window: { kind: 'byteRange', maximumBytes: byteLength, startByte: 0 },
	};
}

export function makeRenderSemantics(
	overrides: Partial<BridgeWorkerReviewRenderSemantics> = {},
): BridgeWorkerReviewRenderSemantics {
	return {
		itemId: 'item-1',
		itemKind: 'diff',
		changeKind: 'modified',
		displayPath: 'Sources/App/item-1.swift',
		basePath: 'Sources/App/item-1.swift',
		headPath: 'Sources/App/item-1.swift',
		language: 'swift',
		contentLineCountsByRole: { base: 100, head: 80 },
		...overrides,
	};
}

export interface EntryProductRequestRecorder {
	readonly observedBodies: BridgeProductControlRequest[];
	readonly observedMetadataStreamRequests: BridgeProductMetadataStreamRequest[];
	readonly observedResultReads: string[];
	readonly observedResultAcknowledgements: string[];
	readonly respond: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
}

export function createEntryProductRequestRecorder(): EntryProductRequestRecorder {
	const observedBodies: BridgeProductControlRequest[] = [];
	const observedMetadataStreamRequests: BridgeProductMetadataStreamRequest[] = [];
	const observedResultReads: string[] = [];
	const observedResultAcknowledgements: string[] = [];
	const operationResults = new Map<string, object>();
	let nextOperationId = 1;
	return {
		observedBodies,
		observedMetadataStreamRequests,
		observedResultReads,
		observedResultAcknowledgements,
		respond: async (_input, init): Promise<Response> => {
			if (init?.body instanceof ArrayBuffer) {
				observedMetadataStreamRequests.push(
					bridgeProductMetadataStreamRequestSchema.parse(
						JSON.parse(new TextDecoder().decode(init.body)),
					),
				);
				throw new Error('Metadata stream is intentionally unavailable in this test.');
			}
			if (!(init?.body instanceof Uint8Array)) {
				throw new Error('Expected encoded Bridge product request bytes.');
			}
			const command: unknown = JSON.parse(new TextDecoder().decode(init.body));
			if (typeof command !== 'object' || command === null || !('kind' in command)) {
				throw new Error('Expected a typed product command.');
			}
			if (command.kind === 'operation.result') {
				const read = bridgeProductOperationResultRequestSchema.parse(command);
				observedResultReads.push(read.operationId);
				const result = operationResults.get(read.operationId);
				if (result === undefined) throw new Error('Read requested an unknown operation.');
				return entryProductJSONResponse({
					failureCode: null,
					kind: 'operation.result',
					operationId: read.operationId,
					outcome: 'succeeded',
					result,
				});
			}
			if (command.kind === 'operation.resultAcknowledgement') {
				const acknowledgement = bridgeProductOperationResultAcknowledgementSchema.parse(command);
				observedResultAcknowledgements.push(acknowledgement.operationId);
				operationResults.delete(acknowledgement.operationId);
				return entryProductJSONResponse({
					...acknowledgement,
					kind: 'operation.resultAcknowledged',
				});
			}
			const request = bridgeProductControlRequestSchema.parse(command);
			observedBodies.push(request);
			const result = entryProductFinalResponse(request);
			const operationId = `entry-operation-${nextOperationId++}`;
			operationResults.set(operationId, result);
			return entryProductJSONResponse({
				paneSessionId: request.paneSessionId,
				workerInstanceId: request.workerInstanceId,
				wireVersion: request.wireVersion,
				requestId: request.requestId,
				requestSequence: request.requestSequence,
				kind: 'operation.admitted',
				operationId,
				waitKind: 'ordinary',
			});
		},
	};
}

function entryProductFinalResponse(request: BridgeProductControlRequest): object {
	const identity = {
		paneSessionId: request.paneSessionId,
		workerInstanceId: request.workerInstanceId,
		wireVersion: request.wireVersion,
		requestId: request.requestId,
		requestSequence: request.requestSequence,
	};
	if (request.kind === 'workerSession.open') {
		return { ...identity, kind: 'workerSession.accepted', result: null };
	}
	if (request.kind !== 'product.call') throw new Error('Unexpected product control kind.');
	if (request.call.method === 'file.source.current') {
		return {
			...identity,
			kind: 'call.completed',
			call: {
				method: 'file.source.current',
				result: { reason: 'no-file-source-authority', status: 'unavailable' },
			},
		};
	}
	return {
		...identity,
		kind: 'call.completed',
		call: { method: request.call.method, result: null },
	};
}

function entryProductJSONResponse(body: object): Response {
	return new Response(JSON.stringify(body));
}

export function makeReviewPublicationIdentity(revision = 1): BridgeWorkerReviewPublicationIdentity {
	return {
		packageId: `review-package-${revision}`,
		publicationId: `00000000-0000-7000-8000-${revision.toString().padStart(12, '0')}`,
		reviewGeneration: revision,
		revision,
		sourceIdentity: `review-source-${revision}`,
	};
}

export function makeFetchedReviewContentResource(
	props: MakeFetchedReviewContentResourceProps,
): BridgeWorkerFetchedReviewContentResource {
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		descriptorId: `descriptor-item-1-${props.role}`,
		language: 'swift',
		byteLength: textBytes.byteLength,
		observedSha256: props.role === 'base' ? 'a'.repeat(64) : 'b'.repeat(64),
		requestId: `content-request-item-1-${props.role}`,
		sourceGeneration: 7,
		sourceIdentity: 'review-source-1',
		sourcePosition: 'whole',
		text: props.text,
		textBytes,
	};
}

export function makeCompletedReviewContentStream(
	descriptor: BridgeProductReviewContentDescriptor,
): BridgeProductContentStream<'review.content'> {
	const bytes = new TextEncoder().encode(
		descriptor.role === 'base' ? 'base body' : 'head body',
	).buffer;
	return {
		contentKind: 'review.content',
		contentRequestId: `content-request-${descriptor.role}`,
		frames: emptyReviewContentFrames(),
		terminal: Promise.resolve({
			bytes,
			contentKind: 'review.content',
			descriptorId: descriptor.descriptorId,
			endOfSource: true,
			kind: 'complete',
			observedByteLength: bytes.byteLength,
			observedSha256: 'a'.repeat(64),
		}),
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}

export function expectedReviewMetadataUnavailablePatch(): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		reviewPublicationIdentity: null,
		patches: [
			{
				operation: 'failed',
				payload: { error: 'metadataUnavailable', status: 'failed' },
				slice: 'reviewSource',
			},
			...expectedEmptyReviewProjectionResetPatches(),
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function expectedEmptyReviewProjectionResetPatches(): readonly BridgeWorkerReviewDisplayPatch[] {
	return [
		{
			operation: 'batch',
			payload: { items: [], operations: [], reset: true, startIndex: 0 },
			slice: 'reviewItem',
		},
		{
			operation: 'batch',
			payload: { reset: true, windows: [{ rows: [], startIndex: 0 }] },
			slice: 'reviewTree',
		},
	];
}
