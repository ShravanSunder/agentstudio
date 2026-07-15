// oxlint-disable unicorn/require-post-message-target-origin -- MessagePort postMessage does not accept a target origin.
import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	type BridgeCommWorkerPort,
	bootstrapBridgeCommWorkerEntry,
	type BridgeCommWorkerInstalledProductSession,
	createBridgeCommWorkerScopePortAdapter,
	postPreparedBridgeCommWorkerMessage,
	registerInertBridgeCommWorkerPortProtocol,
} from './bridge-comm-worker-entry.js';
import {
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	createBridgeCommWorkerReviewProductTestSource,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgeProductReviewContentDescriptor } from './bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';
import {
	bridgePaneCommWorkerInstallSchema,
	bridgeProductControlRequestSchema,
	bridgeProductMetadataStreamRequestSchema,
	type BridgePaneCommWorkerInstall,
	type BridgeProductMetadataStreamRequest,
} from './bridge-product-session-contracts.js';
import type { BridgeProductContentStream } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerReviewRenderSemantics,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerFetchedReviewContentResource } from './bridge-worker-review-content-fetch.js';
import { prepareBridgeWorkerReviewContentRenderJobEvent } from './bridge-worker-review-content-ready.js';

interface PostedBridgeWorkerMessage {
	readonly message: BridgeWorkerServerToMainMessage;
	readonly transferList: readonly Transferable[] | undefined;
}

interface InstalledBridgeCommWorkerEntryHarness {
	readonly close: () => void;
	readonly globalPostedMessages: readonly PostedBridgeWorkerMessage[];
	readonly globalStarted: () => boolean;
	readonly productPort: BridgeWorkerMessagePortRecorder;
}

const activeInstalledEntryHarnesses = new Set<InstalledBridgeCommWorkerEntryHarness>();

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
		for (const harness of activeInstalledEntryHarnesses) {
			harness.close();
		}
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
			publicationSequence: 1,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({ itemId: 'item-1', publicationSequence: 1, surface: 'review', workerDerivationEpoch: 1 }),
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
			workerDerivationEpoch: 1,
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
				messageKind: 'reviewPierreRenderJob',
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
			publicationSequence: 1,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({ itemId: 'item-1', publicationSequence: 1, surface: 'review', workerDerivationEpoch: 1 }),
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
			workerDerivationEpoch: 1,
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
				messageKind: 'reviewPierreRenderJob',
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
			surface: 'review',
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

	test('degrades commands received before runtime bootstrap', async () => {
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-before-bootstrap',
				epoch: 1,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		const postedMessages = await harness.productPort.waitForCount(1);

		try {
			expect(harness.globalPostedMessages).toEqual([]);
			expect(postedMessages).toEqual([
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-before-bootstrap',
					status: 'degraded',
					message: 'Bridge comm worker command received before bootstrap.',
					transferDescriptors: [],
				},
			]);
		} finally {
			harness.close();
		}
	});

	test('bootstraps the runtime protocol before accepting commands', async () => {
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-1'));
		await harness.productPort.waitForCount(2);
		harness.productPort.postMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-after-bootstrap',
				epoch: 2,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		const postedMessages = await harness.productPort.waitForCount(4);

		try {
			expect(harness.globalStarted()).toBe(true);
			expect(harness.globalPostedMessages).toEqual([]);
			expect(postedMessages).toEqual([
				expectedReviewMetadataUnavailablePatch(),
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
					sequence: 2,
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
								state: 'unavailable',
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
		} finally {
			harness.close();
		}
	});

	test('does not construct a comm-worker telemetry network fallback', async () => {
		const fetchSpy = vi.spyOn(globalThis, 'fetch');
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-telemetry'));
		await harness.productPort.waitForCount(1);
		harness.productPort.postMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-after-telemetry-bootstrap',
				epoch: 2,
				issuedAtMilliseconds: 0,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await harness.productPort.waitForCount(3);

		try {
			expect(harness.globalPostedMessages).toEqual([]);
			expect(fetchSpy).not.toHaveBeenCalled();
		} finally {
			harness.close();
		}
	});

	test('production entry opens Review content through product transport without legacy fetchContent', async () => {
		// Arrange
		const openedContentKinds: string[] = [];
		const reviewProductSource = createBridgeCommWorkerReviewProductTestSource();
		const productTransport: BridgeProductTransportSession = {
			...reviewProductSource.productTransport,
			openContent: (descriptor): never => {
				openedContentKinds.push(descriptor.contentKind);
				if (descriptor.contentKind !== 'review.content') {
					throw new Error(`Unexpected typed content kind ${descriptor.contentKind}.`);
				}
				return makeCompletedReviewContentStream(descriptor) as never;
			},
		};
		const harness = createInstalledBridgeCommWorkerEntryHarness(productTransport);

		try {
			// Act
			harness.productPort.postMessage(makeBootstrapRequest('review-content-bootstrap'));
			await harness.productPort.waitForCount(1);
			await flushBridgeWorkerRuntimeContinuations();
			reviewProductSource.publishSource(makeReviewContentRuntimeSource(), 6);
			await flushBridgeWorkerRuntimeContinuations();
			await harness.productPort.waitForCount(2);
			harness.productPort.postMessage(
				encodeBridgeWorkerSelectCommand({
					requestId: 'review-content-select',
					epoch: 7,
					surface: 'review',
					selectedItemId: 'item-1',
					selectedSource: 'user',
				}),
			);
			await harness.productPort.waitForCount(5);

			// Assert
			expect(openedContentKinds).toEqual(['review.content', 'review.content']);
		} finally {
			reviewProductSource.close();
			harness.close();
		}
	});

	test('carries mark-viewed through the installed capability-bound product session', async () => {
		// Arrange
		const observedBodies: unknown[] = [];
		const observedMetadataStreamRequests: BridgeProductMetadataStreamRequest[] = [];
		const fetchSpy = vi
			.spyOn(globalThis, 'fetch')
			.mockImplementation(
				async (_input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
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
					const request = bridgeProductControlRequestSchema.parse(
						JSON.parse(new TextDecoder().decode(init.body)),
					);
					observedBodies.push(request);
					return new Response(
						JSON.stringify(
							request.kind === 'workerSession.open'
								? {
										paneSessionId: request.paneSessionId,
										workerInstanceId: request.workerInstanceId,
										wireVersion: request.wireVersion,
										requestId: request.requestId,
										requestSequence: request.requestSequence,
										kind: 'workerSession.accepted',
										result: null,
									}
								: request.kind === 'product.call' && request.call.method === 'file.source.current'
									? {
											paneSessionId: request.paneSessionId,
											workerInstanceId: request.workerInstanceId,
											wireVersion: request.wireVersion,
											requestId: request.requestId,
											requestSequence: request.requestSequence,
											kind: 'call.completed',
											call: {
												method: 'file.source.current',
												result: {
													reason: 'no-file-source-authority',
													status: 'unavailable',
												},
											},
										}
									: {
											paneSessionId: request.paneSessionId,
											workerInstanceId: request.workerInstanceId,
											wireVersion: request.wireVersion,
											requestId: request.requestId,
											requestSequence: request.requestSequence,
											kind: 'call.completed',
											call: { method: 'review.markFileViewed', result: null },
										},
						),
					);
				},
			);
		const globalPort = createRecordingBridgeCommWorkerPort();
		const productChannel = new MessageChannel();
		const productPort = new BridgeWorkerMessagePortRecorder(productChannel.port2);
		bootstrapBridgeCommWorkerEntry(globalPort.dispatch.port);
		globalPort.dispatch.message(makePaneWorkerInstall(productChannel.port1));

		// Act
		productChannel.port2.postMessage(makeBootstrapRequest('product-chain-bootstrap'));
		await productPort.waitForCount(2);
		productChannel.port2.postMessage(
			encodeBridgeWorkerMarkFileViewedCommand({
				epoch: 4,
				fileId: 'item-1',
				requestId: 'mark-viewed-product-chain',
			}),
		);
		const messages = await productPort.waitForCount(3);

		// Assert
		expect(
			messages.find(
				(message) => message.kind === 'health' && message.requestId === 'mark-viewed-product-chain',
			),
		).toMatchObject({
			kind: 'health',
			requestId: 'mark-viewed-product-chain',
			status: 'ready',
		});
		expect(fetchSpy).toHaveBeenCalledTimes(4);
		expect(observedMetadataStreamRequests).toEqual([
			expect.objectContaining({
				kind: 'metadataStream.open',
				resumeFromStreamSequence: null,
				wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			}),
		]);
		expect(observedBodies).toEqual([
			expect.objectContaining({ kind: 'workerSession.open', requestSequence: 1 }),
			expect.objectContaining({
				call: { method: 'file.source.current', request: {} },
				kind: 'product.call',
				requestSequence: 2,
			}),
			expect.objectContaining({
				call: { method: 'review.markFileViewed', request: { itemId: 'item-1' } },
				kind: 'product.call',
				requestSequence: 3,
			}),
		]);

		productPort.close();
		productChannel.port1.close();
	});

	test('replays commands that arrived before runtime bootstrap', async () => {
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-before-bootstrap',
				epoch: 3,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await harness.productPort.waitForCount(1);
		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-1'));
		const postedMessages = await harness.productPort.waitForCount(5);

		try {
			expect(harness.globalPostedMessages).toEqual([]);
			expect(postedMessages).toEqual([
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-before-bootstrap',
					status: 'degraded',
					message: 'Bridge comm worker command received before bootstrap.',
					transferDescriptors: [],
				},
				expectedReviewMetadataUnavailablePatch(),
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
					sequence: 2,
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
								state: 'unavailable',
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
		} finally {
			harness.close();
		}
	});

	test('rejects duplicate bootstrap requests after runtime ownership is installed', async () => {
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-1'));
		await harness.productPort.waitForCount(2);
		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-2'));
		const postedMessages = await harness.productPort.waitForCount(3);

		try {
			expect(harness.globalPostedMessages).toEqual([]);
			expect(postedMessages).toEqual([
				expectedReviewMetadataUnavailablePatch(),
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
		} finally {
			harness.close();
		}
	});
});

function createInstalledBridgeCommWorkerEntryHarness(
	productTransport: BridgeProductTransportSession = makeUnavailableFileProductTransport(),
): InstalledBridgeCommWorkerEntryHarness {
	const globalPort = createRecordingBridgeCommWorkerPort();
	const productChannel = new MessageChannel();
	const productPort = new BridgeWorkerMessagePortRecorder(productChannel.port2);
	let didClose = false;
	bootstrapBridgeCommWorkerEntry(globalPort.dispatch.port, {
		installProductSession: (input): BridgeCommWorkerInstalledProductSession => {
			const open = Promise.resolve();
			void input;
			return {
				open,
				productTransport,
			};
		},
	});
	globalPort.dispatch.message(makePaneWorkerInstall(productChannel.port1));
	const harness: InstalledBridgeCommWorkerEntryHarness = {
		close: (): void => {
			if (didClose) {
				return;
			}
			didClose = true;
			productPort.close();
			productChannel.port1.close();
			activeInstalledEntryHarnesses.delete(harness);
		},
		globalPostedMessages: globalPort.postedMessages,
		globalStarted: globalPort.started,
		productPort,
	};
	activeInstalledEntryHarnesses.add(harness);
	return harness;
}

function makeUnavailableFileProductTransport(): BridgeProductTransportSession {
	const workerDerivationEpochs = { file: 0, review: 0 };
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			workerDerivationEpochs[surface] += 1;
			return workerDerivationEpochs[surface];
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method !== 'file.source.current') {
				throw new Error(`Unexpected product call in entry harness: ${method}.`);
			}
			return {
				reason: 'no-file-source-authority',
				status: 'unavailable',
			} as never;
		},
		openContent: (): never => {
			throw new Error('Entry harness cannot open content without a File source.');
		},
		subscribe: (): never => {
			throw new Error('Entry harness cannot subscribe without a File source.');
		},
		workerDerivationEpoch: (surface): number => workerDerivationEpochs[surface],
	};
}

class BridgeWorkerMessagePortRecorder {
	readonly #messages: BridgeWorkerServerToMainMessage[] = [];
	readonly #port: MessagePort;
	readonly #waiters: Array<{
		readonly count: number;
		readonly resolve: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	}> = [];

	constructor(port: MessagePort) {
		this.#port = port;
		this.#port.addEventListener('message', (event: MessageEvent<unknown>): void => {
			this.#messages.push(bridgeWorkerServerToMainMessageSchema.parse(event.data));
			this.#resolveWaiters();
		});
		this.#port.start();
	}

	postMessage(message: unknown): void {
		this.#port.postMessage(message);
	}

	waitForCount(count: number): Promise<readonly BridgeWorkerServerToMainMessage[]> {
		if (this.#messages.length >= count) {
			return Promise.resolve([...this.#messages]);
		}
		return new Promise((resolve): void => {
			this.#waiters.push({ count, resolve });
		});
	}

	close(): void {
		this.#port.close();
	}

	#resolveWaiters(): void {
		for (let index = this.#waiters.length - 1; index >= 0; index -= 1) {
			const waiter = this.#waiters[index];
			if (waiter !== undefined && this.#messages.length >= waiter.count) {
				this.#waiters.splice(index, 1);
				waiter.resolve([...this.#messages]);
			}
		}
	}
}

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

function makePaneWorkerInstall(productPort: MessagePort): BridgePaneCommWorkerInstall {
	return bridgePaneCommWorkerInstallSchema.parse({
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId: 'worker-instance-1',
		},
		kind: 'bridgePaneCommWorker.install',
		productCapability: new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH),
		productPort,
	});
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

function expectedReviewMetadataUnavailablePatch(): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'failed',
				payload: { error: 'metadataUnavailable', status: 'failed' },
				slice: 'reviewSource',
			},
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
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
		},
	};
}

function makeReviewContentRuntimeSource(): BridgeCommWorkerReviewRuntimeSource {
	return {
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
		contentRequestDescriptors: [
			makeReviewContentDescriptor({ role: 'base', text: 'base body' }),
			makeReviewContentDescriptor({ role: 'head', text: 'head body' }),
		],
		renderSemantics: [
			{
				basePath: 'Sources/App/item-1.swift',
				changeKind: 'modified',
				contentLineCountsByRole: { base: 1, head: 1 },
				displayPath: 'Sources/App/item-1.swift',
				headPath: 'Sources/App/item-1.swift',
				itemId: 'item-1',
				itemKind: 'diff',
				language: 'swift',
			},
		],
		rows: [{ id: 'item-1', parentId: null, index: 0 }],
	};
}

function makeReviewContentDescriptor(props: {
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

function makeCompletedReviewContentStream(
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
			observedSha256: 'a'.repeat(64),
		}),
	};
}

async function* emptyReviewContentFrames(): AsyncIterable<never> {}
