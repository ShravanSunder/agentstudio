// oxlint-disable unicorn/require-post-message-target-origin -- MessagePort postMessage does not accept a target origin.
import { afterEach, describe, expect, test, vi } from 'vitest';

import { bridgeTelemetryWorkerProducerMessageSchema } from '../telemetry-worker/bridge-telemetry-worker-contracts.js';
import {
	type BridgeCommWorkerPort,
	bootstrapBridgeCommWorkerEntry,
	type BridgeCommWorkerInstalledProductSession,
	createBridgeCommWorkerScopePortAdapter,
	postPreparedBridgeCommWorkerMessage,
	registerBridgeCommWorkerEntry,
	registerInertBridgeCommWorkerPortProtocol,
} from './bridge-comm-worker-entry.js';
import {
	createEntryProductRequestRecorder,
	makeCompletedReviewContentStream,
	makeFetchedReviewContentResource,
	makeReviewContentDescriptor,
	makeReviewPublicationIdentity,
	makeRenderSemantics,
} from './bridge-comm-worker-entry.test-support.js';
import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerSelectCommand,
} from './bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerReviewRuntimeSource } from './bridge-comm-worker-review-source-diff.js';
import {
	createIdleWorktreeAnnotationSubscription,
	createBridgeCommWorkerReviewProductTestSource,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { executeAgentStudioBridgeProductRequest } from './bridge-product-agent-studio-request-executor.js';
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
import type { BridgeProductMetadataApplicationProtocolIdentity } from './bridge-product-metadata-application-protocol.js';
import {
	bridgePaneCommWorkerInstallSchema,
	bridgeProductControlRequestSchema,
	type BridgePaneCommWorkerInstall,
} from './bridge-product-session-contracts.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import { makeBridgeWorkerRenderReceiptIdentity } from './bridge-worker-render-fulfillment.test-support.js';
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
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: 'item-1',
				publicationSequence: 1,
				surface: 'review',
				workerDerivationEpoch: 1,
			}),
			reviewPublicationIdentity: makeReviewPublicationIdentity(),
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
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: 'item-1',
				publicationSequence: 1,
				surface: 'review',
				workerDerivationEpoch: 1,
			}),
			reviewPublicationIdentity: makeReviewPublicationIdentity(),
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
				message: readyHealth('request-1'),
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
		await harness.productPort.waitForCount(1);
		harness.productPort.postMessage(fileActiveViewerModeUpdate('entry-bootstrap', 1));
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
				readyHealth('bootstrap-request-1'),
				readyHealth('request-file-mode-entry-bootstrap'),
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
								state: 'unavailable',
							},
						},
					],
				},
				readyHealth('request-after-bootstrap'),
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

	test('drains required worker samples recorded before telemetry producer install', async () => {
		const globalPort = createRecordingBridgeCommWorkerPort();
		const productChannel = new MessageChannel();
		const productPort = new BridgeWorkerMessagePortRecorder(productChannel.port2);
		const telemetryChannel = new MessageChannel();
		const received: unknown[] = [];
		const barrierReceived = new Promise<void>((resolve): void => {
			telemetryChannel.port2.addEventListener('message', (event: MessageEvent<unknown>): void => {
				const message = bridgeTelemetryWorkerProducerMessageSchema.parse(event.data);
				received.push(message);
				if (message.type === 'producer.barrier.receipt') resolve();
			});
			telemetryChannel.port2.start();
		});
		bootstrapBridgeCommWorkerEntry(globalPort.dispatch.port, {
			installProductSession: (): BridgeCommWorkerInstalledProductSession => ({
				open: Promise.resolve(),
				productTransport: makeUnavailableFileProductTransport(),
			}),
		});
		try {
			globalPort.dispatch.message(makePaneWorkerInstall(productChannel.port1, 1));
			productPort.postMessage(makeBootstrapRequest('bootstrap-before-telemetry'));
			await productPort.waitForCount(1);
			productPort.postMessage(fileActiveViewerModeUpdate('mode-before-telemetry', 1));
			await productPort.waitForCount(2);
			globalPort.dispatch.message({
				type: 'bridgePaneCommWorker.telemetryProducer.install',
				enabledScopes: ['web'],
				preReadyRequiredSampleCapacity: 1,
				preReadyRequiredSampleMaxEncodedBytes: 64 * 1024,
				producerPort: telemetryChannel.port1,
			});
			telemetryChannel.port2.postMessage({
				type: 'producer.ready',
				generation: 1,
				initialSampleCredits: 128,
				initialControlCredits: 4,
			});
			telemetryChannel.port2.postMessage({
				type: 'producer.barrier.request',
				barrierId: 'pre-install-barrier',
				generation: 1,
			});
			await barrierReceived;
			expect(
				received.some(
					(message) =>
						typeof message === 'object' &&
						message !== null &&
						Reflect.get(message, 'type') === 'sample',
				),
			).toBe(true);
			expect(received).toContainEqual(
				expect.objectContaining({
					type: 'loss.summary',
					reason: 'queue_saturated',
					requiredCount: expect.any(Number),
				}),
			);
		} finally {
			productPort.close();
			productChannel.port1.close();
			telemetryChannel.port1.close();
			telemetryChannel.port2.close();
		}
	});

	test('production entry opens Review content through product transport without legacy fetchContent', async () => {
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
			harness.productPort.postMessage(
				encodeBridgeWorkerActiveViewerModeUpdateCommand({
					epoch: 1,
					requestId: 'review-content-active-viewer-mode',
					update: {
						activeSource: null,
						mode: 'review',
						nativeSelectionRequestId: null,
						sequence: 1,
						sessionId: 'review-content-session',
					},
				}),
			);
			await harness.productPort.waitForCount(2);
			await flushBridgeWorkerRuntimeContinuations();
			reviewProductSource.publishSource(makeReviewContentRuntimeSource(), 6);
			await flushBridgeWorkerRuntimeContinuations();
			await harness.productPort.waitForCount(3);
			harness.productPort.postMessage(
				encodeBridgeWorkerSelectCommand({
					requestId: 'review-content-select',
					epoch: 7,
					surface: 'review',
					selectedItemId: 'item-1',
					selectedSource: 'user',
				}),
			);
			await harness.productPort.waitForCount(6);

			// Assert
			expect(openedContentKinds).toEqual(['review.content', 'review.content']);
		} finally {
			reviewProductSource.close();
			harness.close();
		}
	});

	test('carries mark-viewed through the installed capability-bound product session', async () => {
		// Arrange
		const productRequests = createEntryProductRequestRecorder();
		const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(productRequests.respond);
		const globalPort = createRecordingBridgeCommWorkerPort();
		const productChannel = new MessageChannel();
		const productPort = new BridgeWorkerMessagePortRecorder(productChannel.port2);
		registerBridgeCommWorkerEntry(globalPort.dispatch.port, {
			executeProductRequest: executeAgentStudioBridgeProductRequest,
		});
		globalPort.dispatch.message(makePaneWorkerInstall(productChannel.port1));
		// Act
		productChannel.port2.postMessage(makeBootstrapRequest('product-chain-bootstrap'));
		await productPort.waitForCount(1);
		productChannel.port2.postMessage(fileActiveViewerModeUpdate('product-chain', 1));
		await productPort.waitForCount(2);
		productChannel.port2.postMessage(
			encodeBridgeWorkerMarkFileViewedCommand({
				epoch: 4,
				fileId: 'item-1',
				requestId: 'mark-viewed-product-chain',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();
		const messages = await productPort.waitForCount(5);
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
		expect(fetchSpy).toHaveBeenCalledTimes(productRequests.observedBodies.length * 3 + 1);
		expect(productRequests.observedResultReads).toHaveLength(productRequests.observedBodies.length);
		expect(productRequests.observedResultAcknowledgements).toEqual(
			productRequests.observedResultReads,
		);
		expect(productRequests.observedMetadataStreamRequests).toEqual([
			expect.objectContaining({
				kind: 'metadataStream.open',
				resumeFromStreamSequence: null,
				wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			}),
		]);
		expect(productRequests.observedBodies).toEqual([
			expect.objectContaining({ kind: 'workerSession.open', requestSequence: 1 }),
			expect.objectContaining({
				call: expect.objectContaining({ method: 'file.activeViewerMode.update' }),
				kind: 'product.call',
				requestSequence: expect.any(Number),
			}),
			expect.objectContaining({
				call: { method: 'file.source.current', request: {} },
				kind: 'product.call',
				requestSequence: expect.any(Number),
			}),
			expect.objectContaining({
				call: expect.objectContaining({ method: 'review.intake.ready' }),
				kind: 'product.call',
				requestSequence: expect.any(Number),
			}),
			expect.objectContaining({
				call: { method: 'review.markFileViewed', request: { itemId: 'item-1' } },
				kind: 'product.call',
				requestSequence: expect.any(Number),
			}),
		]);
		const controlSequences = productRequests.observedBodies.map(
			(body) => bridgeProductControlRequestSchema.parse(body).requestSequence,
		);
		expect(controlSequences).toEqual([...controlSequences].sort((left, right) => left - right));

		productPort.close();
		productChannel.port1.close();
	});

	test('replays commands that arrived before runtime bootstrap', async () => {
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(fileActiveViewerModeUpdate('before-bootstrap', 1));
		await harness.productPort.waitForCount(1);
		harness.productPort.postMessage(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-before-bootstrap',
				epoch: 3,
				surface: 'review',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await harness.productPort.waitForCount(2);
		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-1'));
		const postedMessages = await harness.productPort.waitForCount(6);

		try {
			expect(harness.globalPostedMessages).toEqual([]);
			expect(postedMessages).toEqual([
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-file-mode-before-bootstrap',
					status: 'degraded',
					message: 'Bridge comm worker command received before bootstrap.',
					transferDescriptors: [],
				},
				{
					wireVersion: 1,
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId: 'request-before-bootstrap',
					status: 'degraded',
					message: 'Bridge comm worker command received before bootstrap.',
					transferDescriptors: [],
				},
				readyHealth('bootstrap-request-1'),
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
								state: 'unavailable',
							},
						},
					],
				},
				readyHealth('request-before-bootstrap'),
				readyHealth('request-file-mode-before-bootstrap'),
			]);
		} finally {
			harness.close();
		}
	});

	test('rejects duplicate bootstrap requests after runtime ownership is installed', async () => {
		const harness = createInstalledBridgeCommWorkerEntryHarness();

		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-1'));
		await harness.productPort.waitForCount(1);
		harness.productPort.postMessage(fileActiveViewerModeUpdate('duplicate-bootstrap', 1));
		await harness.productPort.waitForCount(2);
		harness.productPort.postMessage(makeBootstrapRequest('bootstrap-request-2'));
		const postedMessages = await harness.productPort.waitForCount(3);

		try {
			expect(harness.globalPostedMessages).toEqual([]);
			expect(postedMessages).toEqual([
				readyHealth('bootstrap-request-1'),
				readyHealth('request-file-mode-duplicate-bootstrap'),
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

function readyHealth(requestId: string): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'health',
		requestId,
		status: 'ready',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

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
		advanceWorkerDerivationEpoch: (surface): number => {
			workerDerivationEpochs[surface] += 1;
			return workerDerivationEpochs[surface];
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (
				method === 'file.activeViewerMode.update' ||
				method === 'review.activeViewerMode.update' ||
				method === 'review.intake.ready'
			) {
				return null as never;
			}
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
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The entry harness supports only annotation notification subscriptions.
		subscribe: ((protocol: BridgeProductMetadataApplicationProtocolIdentity): never => {
			const subscriptionKind = protocol.kind;
			if (subscriptionKind === 'file.annotations' || subscriptionKind === 'review.annotations') {
				// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The branch closes over the requested annotation subscription kind.
				return createIdleWorktreeAnnotationSubscription(protocol) as never;
			}
			throw new Error('Entry harness cannot subscribe without a File source.');
		}) as BridgeProductTransportSession['subscribe'],
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

function makePaneWorkerInstall(
	productPort: MessagePort,
	telemetryPreReadyBufferMaxSamples = 128,
): BridgePaneCommWorkerInstall {
	return bridgePaneCommWorkerInstallSchema.parse({
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				admissionRetryCount: 2,
				contentProgressDeadlineMilliseconds: 5_000,
				viewBatchProgressDeadlineMilliseconds: 5_000,
				streamKeepaliveIntervalMilliseconds: 350,
				telemetryPreReadyBufferMaxBytes: 64 * 1024,
				telemetryPreReadyBufferMaxSamples,
				workerSettlementDeadlineMilliseconds: 5_000,
				viewAcknowledgementDeadlineMilliseconds: 4_000,
				viewCreditBytes: 524_288,
				viewCreditParts: 8,
				viewMaximumConsecutiveResnapshots: 3,
				viewMaximumDirtyKeys: 4_096,
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

function fileActiveViewerModeUpdate(requestLabel: string, epoch: number): unknown {
	return encodeBridgeWorkerActiveViewerModeUpdateCommand({
		epoch,
		requestId: `request-file-mode-${requestLabel}`,
		update: {
			activeSource: null,
			mode: 'file',
			nativeSelectionRequestId: null,
			sequence: epoch,
			sessionId: `file-mode-${requestLabel}-session`,
		},
	});
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
		reviewPublicationIdentity: makeReviewPublicationIdentity(),
		rows: [{ id: 'item-1', parentId: null, index: 0 }],
	};
}
