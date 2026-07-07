import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgeTelemetryBatchSchema,
	type BridgeTelemetryBatch,
} from '../../foundation/telemetry/bridge-telemetry-event.js';
import {
	type BridgeCommWorkerPort,
	bootstrapBridgeCommWorkerEntry,
	createBridgeCommWorkerScopePortAdapter,
	postPreparedBridgeCommWorkerMessage,
	registerInertBridgeCommWorkerPortProtocol,
} from './bridge-comm-worker-entry.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import { prepareBridgeWorkerReviewContentRenderJobEvent } from './bridge-worker-review-content-ready.js';

interface PostedBridgeWorkerMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

function assertPreparedEntryPostRejectsSyntheticMessages(port: BridgeCommWorkerPort): void {
	const syntheticPreparedMessage = {
		message: {
			kind: 'pierreRenderJob',
			transferDescriptors: [],
		},
		transferList: [],
	};
	// @ts-expect-error Entry posting accepts only schema-derived server-to-main worker DTOs.
	postPreparedBridgeCommWorkerMessage(port, syntheticPreparedMessage);
}

function assertBrowserMessagePortMatchesEntryPort(port: MessagePort): BridgeCommWorkerPort {
	return port;
}

describe('Bridge comm worker entry', () => {
	afterEach(() => {
		vi.restoreAllMocks();
		vi.useRealTimers();
	});

	test('posts prepared review content-ready worker messages as structured CodeView payloads', () => {
		const postedMessages: PostedBridgeWorkerMessage[] = [];
		const port: BridgeCommWorkerPort = {
			postMessage: (
				message: BridgeWorkerServerToMainMessage,
				transferList?: Transferable[],
			): void => {
				postedMessages.push({ message, transferList });
			},
			addEventListener: (): void => {},
		};
		const preparedMessage = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:base',
					role: 'base',
					text: 'base content\n',
				}),
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:head',
					role: 'head',
					text: 'head content\n',
				}),
			],
			semantics: makeRenderSemantics(),
		});
		if (preparedMessage === null) {
			throw new Error('Expected review content-ready render job.');
		}

		postPreparedBridgeCommWorkerMessage(port, preparedMessage);

		expect(postedMessages).toEqual([
			{
				message: preparedMessage.message,
				transferList: [],
			},
		]);
		expect(postedMessages[0]?.transferList).not.toBe(preparedMessage.transferList);
		expect(preparedMessage.message.job.payload.kind).toBe('codeViewDiffItem');
		expect(preparedMessage.message.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: preparedMessage.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
		expect(typeof assertPreparedEntryPostRejectsSyntheticMessages).toBe('function');
		expect(typeof assertBrowserMessagePortMatchesEntryPort).toBe('function');
	});

	test('forwards structured prepared messages through the worker scope adapter', () => {
		const postedMessages: PostedBridgeWorkerMessage[] = [];
		const scope = {
			postMessage: (
				message: BridgeWorkerServerToMainMessage,
				transferList?: Transferable[],
			): void => {
				postedMessages.push({ message, transferList });
			},
			addEventListener: (): void => {},
		};
		const preparedMessage = prepareBridgeWorkerReviewContentRenderJobEvent({
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			resources: [
				makeFetchedReviewContentResource({
					contentHash: 'sha256:item-1:file',
					role: 'file',
					text: 'file content\n',
				}),
			],
			semantics: makeRenderSemantics({
				changeKind: 'modified',
				contentLineCountsByRole: { file: 80 },
				itemKind: 'file',
			}),
		});
		if (preparedMessage === null) {
			throw new Error('Expected review content-ready render job.');
		}

		postPreparedBridgeCommWorkerMessage(
			createBridgeCommWorkerScopePortAdapter(scope),
			preparedMessage,
		);

		expect(postedMessages).toEqual([
			{
				message: preparedMessage.message,
				transferList: [],
			},
		]);
		expect(preparedMessage.message.job.payload.kind).toBe('codeViewFileItem');
		expect(preparedMessage.message.transferDescriptors).toEqual([
			{
				messageKind: 'pierreRenderJob',
				fieldPath: ['job', 'payload'],
				byteLength: preparedMessage.message.job.payloadByteLength,
				mode: 'clone',
			},
		]);
	});

	test('preserves inert ready health replies on the one-argument post path', () => {
		const { dispatch, postedMessages, started } = createRecordingBridgeCommWorkerPort();
		registerInertBridgeCommWorkerPortProtocol(dispatch.port);

		dispatch.message({
			wireVersion: 1,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-1',
			epoch: 0,
			transferDescriptors: [],
			selectedItemId: 'item-1',
			selectedSource: 'user',
		});

		expect(started()).toBe(true);
		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-1',
					status: 'ready',
					transferDescriptors: [],
				},
				transferList: undefined,
			},
		]);
	});

	test('preserves inert degraded health replies for invalid messages', () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerInertBridgeCommWorkerPortProtocol(dispatch.port);

		dispatch.message({ kind: 'not-a-bridge-worker-message' });

		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					status: 'degraded',
					message: 'Bridge comm worker received invalid message.',
					transferDescriptors: [],
				},
				transferList: undefined,
			},
		]);
	});

	test('degrades commands received before runtime bootstrap', () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		bootstrapBridgeCommWorkerEntry(dispatch.port);

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-before-bootstrap',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(postedMessages).toEqual([
			{
				message: {
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-before-bootstrap',
					status: 'degraded',
					message: 'Bridge comm worker command received before bootstrap.',
					transferDescriptors: [],
				},
				transferList: undefined,
			},
		]);
	});

	test('bootstraps the runtime protocol before accepting commands', () => {
		const { dispatch, postedMessages, started } = createRecordingBridgeCommWorkerPort();
		bootstrapBridgeCommWorkerEntry(dispatch.port);

		dispatch.message(makeBootstrapRequest('bootstrap-request-1'));
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-after-bootstrap',
				epoch: 2,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);

		expect(started()).toBe(true);
		expect(postedMessages.map((posted) => posted.message)).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request-1',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'slicePatch',
				epoch: 2,
				sequence: 1,
				transferDescriptors: [],
				patches: [
					{
						slice: 'selection',
						operation: 'upsert',
						payload: {
							selectedItemId: 'item-1',
						},
					},
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: {
							state: 'loading',
						},
					},
				],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-after-bootstrap',
				status: 'ready',
				transferDescriptors: [],
			},
		]);
	});

	test('bootstraps worker telemetry and flushes worker task samples through the scheme endpoint', () => {
		vi.useFakeTimers();
		const flushedBatches: BridgeTelemetryBatch[] = [];
		const fetchSpy = vi
			.spyOn(globalThis, 'fetch')
			.mockImplementation((input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
				expect(input).toBe('agentstudio://telemetry/batch');
				if (typeof init?.body !== 'string') {
					throw new Error('Expected telemetry batch body to be serialized JSON.');
				}
				flushedBatches.push(bridgeTelemetryBatchSchema.parse(JSON.parse(init.body)));
				return Promise.resolve(new Response(null, { status: 204 }));
			});
		const { dispatch } = createRecordingBridgeCommWorkerPort();
		bootstrapBridgeCommWorkerEntry(dispatch.port);

		dispatch.message(makeBootstrapRequestWithTelemetry('bootstrap-request-telemetry'));
		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-after-telemetry-bootstrap',
				epoch: 2,
				issuedAtMilliseconds: 0,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		vi.runOnlyPendingTimers();

		expect(fetchSpy).toHaveBeenCalledTimes(1);
		expect(flushedBatches[0]?.samples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.worker.task',
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.worker.command': 'select',
					'agentstudio.bridge.worker.task_kind': 'message_handler',
				}),
			}),
		);
	});

	test('replays commands that arrived before runtime bootstrap', () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		bootstrapBridgeCommWorkerEntry(dispatch.port);

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-before-bootstrap',
				epoch: 3,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		dispatch.message(makeBootstrapRequest('bootstrap-request-1'));

		expect(postedMessages.map((posted) => posted.message)).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-before-bootstrap',
				status: 'degraded',
				message: 'Bridge comm worker command received before bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request-1',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'slicePatch',
				epoch: 3,
				sequence: 1,
				transferDescriptors: [],
				patches: [
					{
						slice: 'selection',
						operation: 'upsert',
						payload: {
							selectedItemId: 'item-1',
						},
					},
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: 'item-1',
						payload: {
							state: 'loading',
						},
					},
				],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-before-bootstrap',
				status: 'ready',
				transferDescriptors: [],
			},
		]);
	});

	test('rejects duplicate bootstrap requests after runtime ownership is installed', () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		bootstrapBridgeCommWorkerEntry(dispatch.port);

		dispatch.message(makeBootstrapRequest('bootstrap-request-1'));
		dispatch.message(makeBootstrapRequest('bootstrap-request-2'));

		expect(postedMessages.map((posted) => posted.message)).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request-1',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request-2',
				status: 'degraded',
				message: 'Bridge comm worker runtime was already bootstrapped.',
				transferDescriptors: [],
			},
		]);
	});
});

function createRecordingBridgeCommWorkerPort(): {
	readonly dispatch: {
		readonly message: (data: unknown) => void;
		readonly port: BridgeCommWorkerPort;
	};
	readonly postedMessages: PostedBridgeWorkerMessage[];
	readonly started: () => boolean;
} {
	const postedMessages: PostedBridgeWorkerMessage[] = [];
	const eventTarget = new EventTarget();
	let didStart = false;
	return {
		dispatch: {
			message: (data: unknown): void => {
				eventTarget.dispatchEvent(new MessageEvent('message', { data }));
			},
			port: {
				postMessage: (
					message: BridgeWorkerServerToMainMessage,
					transferList?: Transferable[],
				): void => {
					postedMessages.push({ message, transferList });
				},
				addEventListener: (
					type: 'message',
					nextListener: (event: MessageEvent<unknown>) => void,
				): void => {
					expect(type).toBe('message');
					eventTarget.addEventListener(type, (event: Event): void => {
						if (event instanceof MessageEvent) {
							nextListener(event);
						}
					});
				},
				dispatchEvent: (event: Event): boolean => eventTarget.dispatchEvent(event),
				start: (): void => {
					didStart = true;
				},
			},
		},
		postedMessages,
		started: (): boolean => didStart,
	};
}

function makeRenderSemantics(
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

function makeFetchedReviewContentResource(props: {
	readonly contentHash: string;
	readonly role: BridgeWorkerFetchedReviewContentResource['role'];
	readonly text: string;
}): BridgeWorkerFetchedReviewContentResource {
	const textBytes = new TextEncoder().encode(props.text).buffer;
	return {
		itemId: 'item-1',
		role: props.role,
		contentHash: props.contentHash,
		contentHashAlgorithm: 'fixture-preview',
		language: 'swift',
		byteLength: textBytes.byteLength,
		text: props.text,
		textBytes,
	};
}

function makeBootstrapRequest(requestId: string): BridgeCommWorkerBootstrapRequest {
	return {
		schemaVersion: 1,
		method: 'bridgeCommWorker.bootstrap',
		requestId,
		runtime: {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
			contentItems: [
				{
					itemId: 'item-1',
					path: 'Sources/App/item-1.swift',
					language: 'swift',
					cacheKey: 'item-1:base|item-1:head',
					sizeBytes: 104,
					availableContentRoles: ['base', 'head'],
					contentLineCountsByRole: { base: 10, head: 12 },
				},
			],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
		},
	};
}

function makeBootstrapRequestWithTelemetry(requestId: string): BridgeCommWorkerBootstrapRequest {
	const request = makeBootstrapRequest(requestId);
	return {
		...request,
		runtime: {
			...request.runtime,
			telemetryConfig: {
				enabledScopes: ['web'],
				endpointUrl: 'agentstudio://telemetry/batch',
				maxEncodedBatchBytes: 16_384,
				maxSamplesPerBatch: 8,
				minimumFlushIntervalMilliseconds: 250,
				scenario: 'bridge-worker-runtime',
			},
		},
	};
}
