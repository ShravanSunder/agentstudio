import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerViewportCommand,
} from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import {
	BridgeProductBoundedAsyncQueue,
	createBridgeProductDeferred,
} from './bridge-product-async-queue.js';
import type {
	BridgeProductMetadataApplicationProtocolIdentity,
	BridgeProductMetadataDataFrame,
} from './bridge-product-metadata-application-protocol.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeProductWorktreeAnnotationEvent } from './bridge-product-worktree-annotation-contracts.js';
import type { BridgeProductAnnotationOutputContentDescriptor } from './bridge-product-worktree-annotation-output-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerMainToServerMessage,
} from './bridge-worker-contracts.js';

const annotationWorktreeId = '00000000-0000-7000-8000-000000000001';

type AnnotationMetadataFrame = BridgeProductMetadataDataFrame<BridgeProductWorktreeAnnotationEvent>;

describe('Bridge comm worker annotation runtime protocol', () => {
	test('calls inspection before content open and transfers the exact correlated output bytes once', async () => {
		const exactBytes = new TextEncoder().encode('# Exact annotation output\n').buffer;
		const descriptor = annotationOutputDescriptor({ byteLength: exactBytes.byteLength });
		const operationOrder: string[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productTransport = createAnnotationProductTransport({
			calledMethods: [],
			fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			inspection: { descriptor, exactBytes, operationOrder },
			reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			subscribedKinds: [],
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport,
		});
		dispatch.message(annotationOutputInspectCommand('fileView', descriptor.attemptId));
		await flushBridgeWorkerRuntimeContinuations();

		expect(operationOrder).toEqual(['file.annotations.output.inspect', 'content.open']);
		const inspectionPublication = postedMessages.find(
			({ message }) => message.kind === 'annotationOutputInspection',
		);
		if (inspectionPublication?.message.kind !== 'annotationOutputInspection') {
			throw new Error('Expected one annotation output inspection publication.');
		}
		expect(inspectionPublication.message).toMatchObject({
			descriptor,
			requestId: 'annotation-output-inspect-request',
			transferDescriptors: [
				{
					byteLength: exactBytes.byteLength,
					fieldPath: ['exactBytes'],
					messageKind: 'annotationOutputInspection',
					mode: 'transfer',
				},
			],
		});
		expect(new Uint8Array(inspectionPublication.message.exactBytes)).toEqual(
			new Uint8Array(exactBytes),
		);
		expect(inspectionPublication.transferList).toEqual([exactBytes]);
	});

	test('rejects a cross-surface output descriptor before content open', async () => {
		const exactBytes = new Uint8Array([1, 2, 3]).buffer;
		const descriptor = annotationOutputDescriptor({
			byteLength: exactBytes.byteLength,
			surface: 'review',
		});
		const operationOrder: string[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport: createAnnotationProductTransport({
				calledMethods: [],
				fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
				inspection: { descriptor, exactBytes, operationOrder },
				reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
				subscribedKinds: [],
			}),
		});
		dispatch.message(annotationOutputInspectCommand('fileView', descriptor.attemptId));
		await flushBridgeWorkerRuntimeContinuations();

		expect(operationOrder).toEqual(['file.annotations.output.inspect']);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'annotation-output-inspect-request',
				status: 'degraded',
			}),
		);
	});

	test('rejects content whose transport-observed digest does not match the descriptor', async () => {
		const exactBytes = new Uint8Array([1, 2, 3]).buffer;
		const descriptor = annotationOutputDescriptor({ byteLength: exactBytes.byteLength });
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport: createAnnotationProductTransport({
				calledMethods: [],
				fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
				inspection: {
					descriptor,
					exactBytes,
					observedSha256: 'b'.repeat(64),
					operationOrder: [],
				},
				reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
				subscribedKinds: [],
			}),
		});
		dispatch.message(annotationOutputInspectCommand('fileView', descriptor.attemptId));
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'annotation-output-inspect-request',
				status: 'degraded',
			}),
		);
		expect(postedMessages.map(({ message }) => message.kind)).not.toContain(
			'annotationOutputInspection',
		);
	});

	test('opens one paired subscription and preserves surface and native correlation', async () => {
		const fileAnnotationEvents = new BridgeProductBoundedAsyncQueue<AnnotationMetadataFrame>(8);
		const reviewAnnotationEvents = new BridgeProductBoundedAsyncQueue<AnnotationMetadataFrame>(8);
		const subscribedKinds: string[] = [];
		const calledMethods: string[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productTransport = createAnnotationProductTransport({
			calledMethods,
			fileAnnotationEvents,
			reviewAnnotationEvents,
			subscribedKinds,
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport,
		});
		fileAnnotationEvents.push(annotationProjectionEvent(11, 'file.annotations'));
		reviewAnnotationEvents.push(annotationProjectionEvent(22, 'review.annotations'));
		dispatch.message(annotationCommand('fileView', 'file-worker-request'));
		dispatch.message(annotationCommand('review', 'review-worker-request'));
		await flushBridgeWorkerRuntimeContinuations();

		expect(subscribedKinds.filter((kind) => kind === 'file.annotations')).toEqual([
			'file.annotations',
		]);
		expect(subscribedKinds.filter((kind) => kind === 'review.annotations')).toEqual([
			'review.annotations',
		]);
		expect(calledMethods).toContain('file.annotations.command');
		expect(calledMethods).toContain('review.annotations.command');
		expect(postedMessages.map(({ message }) => message.kind)).not.toContain(
			'annotationProjectionConvergence',
		);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				productRequestId: 'file.annotations.command-product-request',
				requestId: 'file-worker-request',
				surface: 'fileView',
			}),
		);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				productRequestId: 'review.annotations.command-product-request',
				requestId: 'review-worker-request',
				surface: 'review',
			}),
		);
	});

	test('publishes a committed native catalog as bounded FIFO staging on the existing port', async () => {
		const fileAnnotationEvents = new BridgeProductBoundedAsyncQueue<AnnotationMetadataFrame>(8);
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport: createAnnotationProductTransport({
				calledMethods: [],
				fileAnnotationEvents,
				reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
				subscribedKinds: [],
			}),
		});

		for (const frame of annotationCatalogFrames(7, 'file.annotations')) {
			fileAnnotationEvents.push(frame);
		}
		await flushBridgeWorkerRuntimeContinuations();

		const staging = postedMessages
			.map(({ message }) => message)
			.filter((message) => message.kind === 'annotationCatalogStaging');
		expect(staging.map((message) => message.transfer.kind)).toEqual([
			'catalog.begin',
			'catalog.window',
			'catalog.commit',
		]);
		expect(staging.every((message) => message.surface === 'fileView')).toBe(true);
		expect(staging.at(-1)).toMatchObject({
			authority: {
				subscriptionId: 'annotation-subscription',
				workerDerivationEpoch: 1,
				worktreeId: annotationWorktreeId,
			},
			operationCorrelationId: 'a'.repeat(64),
		});
	});

	test('combines active File source authority with annotation invalidation to start projection query', async () => {
		// Arrange
		const fileAnnotationEvents = new BridgeProductBoundedAsyncQueue<AnnotationMetadataFrame>(8);
		const calledMethods: string[] = [];
		const projectionQueryStarted = createBridgeProductDeferred<void>();
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport: createAnnotationProductTransport({
				calledMethods,
				fileAnnotationEvents,
				onCalledMethod: (method): void => {
					if (method === 'file.annotations.projection.query') {
						projectionQueryStarted.resolve();
					}
				},
				reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(8),
				subscribedKinds: [],
			}),
		});

		// Act
		for (const catalogFrame of annotationCatalogFrames(1, 'file.annotations')) {
			fileAnnotationEvents.push(catalogFrame);
		}
		dispatch.message(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				epoch: 1,
				requestId: 'file-active-source-request',
				update: {
					activeSource: {
						generation: 3,
						protocol: 'worktree-file',
						streamId: 'file-source-1',
					},
					mode: 'file',
					nativeSelectionRequestId: null,
					sequence: 1,
					sessionId: 'active-viewer-session-1',
				},
			}),
		);
		await projectionQueryStarted.promise;
		await flushBridgeWorkerRuntimeContinuations();

		// Assert
		expect(calledMethods).toContain('file.activeViewerMode.update');
		expect(calledMethods).toContain('file.annotations.projection.query');
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationProjectionConvergence',
				state: { kind: 'refreshing' },
				surface: 'fileView',
			}),
		);
	});

	test('forwards annotations after unrelated File viewer epochs advance', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productTransport = createAnnotationProductTransport({
			calledMethods: [],
			fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			subscribedKinds: [],
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport,
		});
		dispatch.message(
			encodeBridgeWorkerViewportCommand({
				epoch: 2,
				firstVisibleIndex: 0,
				lastVisibleIndex: 0,
				phase: 'settled',
				requestId: 'file-viewport-newer-than-rendered-annotation',
				surface: 'fileView',
				visibleItemIds: [],
			}),
		);
		dispatch.message(annotationCommand('fileView', 'file-annotation-from-rendered-source', 1));
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				requestId: 'file-annotation-from-rendered-source',
				surface: 'fileView',
			}),
		);
	});

	test('rejects an older annotation epoch within the same surface', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productTransport = createAnnotationProductTransport({
			calledMethods: [],
			fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			subscribedKinds: [],
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport,
		});
		dispatch.message(annotationCommand('fileView', 'current-file-annotation', 2));
		dispatch.message(annotationCommand('fileView', 'stale-file-annotation', 1));
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				requestId: 'current-file-annotation',
				surface: 'fileView',
			}),
		);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				message: 'Bridge comm worker rejected stale epoch 1 after 2.',
				requestId: 'stale-file-annotation',
				status: 'degraded',
			}),
		);
		expect(postedMessages.map(({ message }) => message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				requestId: 'stale-file-annotation',
			}),
		);
	});

	test('tracks File and Review annotation epochs independently', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productTransport = createAnnotationProductTransport({
			calledMethods: [],
			fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			subscribedKinds: [],
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport,
		});
		dispatch.message(annotationCommand('fileView', 'newer-file-annotation', 4));
		dispatch.message(annotationCommand('review', 'older-review-annotation', 1));
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				requestId: 'newer-file-annotation',
				surface: 'fileView',
			}),
		);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				requestId: 'older-review-annotation',
				surface: 'review',
			}),
		);
	});

	test('reports a typed degraded result when the native annotation command fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const productTransport = createAnnotationProductTransport({
			calledMethods: [],
			fileAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			failingAnnotationMethod: 'review.annotations.command',
			reviewAnnotationEvents: new BridgeProductBoundedAsyncQueue(1),
			subscribedKinds: [],
		});

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			productTransport,
		});
		dispatch.message(annotationCommand('review', 'review-failure-request'));
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				message: 'Bridge comm worker failed to forward review.annotations.command.',
				requestId: 'review-failure-request',
				status: 'degraded',
			}),
		);
		expect(postedMessages.map(({ message }) => message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'annotationCommandAccepted',
				requestId: 'review-failure-request',
			}),
		);
	});
});

function annotationCommand(
	surface: 'fileView' | 'review',
	requestId: string,
	epoch = 1,
): Extract<BridgeWorkerMainToServerMessage, { readonly command: 'annotationCommand' }> {
	return {
		command: 'annotationCommand',
		direction: 'mainToServerWorker',
		epoch,
		kind: 'command',
		operation: { kind: 'session.discover' },
		requestId,
		...(surface === 'review' ? { reviewPublicationIdentity } : {}),
		surface,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	} as const;
}

const reviewPublicationIdentity = {
	packageId: 'package-installed',
	publicationId: '00000000-0000-7000-8000-000000000031',
	reviewGeneration: 7,
	revision: 3,
	sourceIdentity: 'source-installed',
} as const;

function annotationOutputInspectCommand(
	surface: 'fileView' | 'review',
	attemptId: string,
): unknown {
	return {
		attemptId,
		command: 'annotationOutputInspect',
		direction: 'mainToServerWorker',
		epoch: 1,
		kind: 'command',
		requestId: 'annotation-output-inspect-request',
		surface,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	};
}

function annotationOutputDescriptor(props: {
	readonly byteLength: number;
	readonly surface?: 'file' | 'review';
}): BridgeProductAnnotationOutputContentDescriptor {
	return {
		attemptId: '00000000-0000-7000-8000-000000000031',
		contentKind: 'annotation.output',
		contentType: 'text/markdown; charset=utf-8',
		declaredByteLength: props.byteLength,
		descriptorId: 'annotation-output-descriptor-1',
		encoding: 'utf-8',
		expectedSha256: 'a'.repeat(64),
		formatVersion: 1,
		maximumBytes: props.byteLength,
		outputKind: 'clipboard_markdown',
		surface: props.surface ?? 'file',
	};
}

function annotationProjectionEvent(
	revision: number,
	subscriptionKind: 'file.annotations' | 'review.annotations',
): AnnotationMetadataFrame {
	return {
		data: {
			authority: {
				applicationSourceGeneration: revision,
				worktreeId: annotationWorktreeId,
			},
			kind: 'annotation.controlChanged',
			reason: 'discovery',
		},
		metadataStreamId: 'annotation-metadata-stream',
		operationCorrelationId: 'a'.repeat(64),
		sourceGeneration: revision,
		streamSequence: 1,
		subscriptionId: 'annotation-subscription',
		subscriptionKind,
		subscriptionSequence: 1,
		workerDerivationEpoch: 1,
	};
}

function annotationCatalogFrames(
	revision: number,
	subscriptionKind: 'file.annotations' | 'review.annotations',
): readonly AnnotationMetadataFrame[] {
	const authority = {
		applicationSourceGeneration: revision,
		worktreeId: annotationWorktreeId,
	} as const;
	const transferId = `annotation-catalog-${revision}`;
	const events: readonly BridgeProductWorktreeAnnotationEvent[] = [
		{
			authority,
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: revision,
				expectedEntryCount: 1,
				kind: 'catalog.begin',
				transferId,
			},
		},
		{
			authority,
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: revision,
				entries: [
					{
						kind: 'session',
						semanticRevision: 1,
						sessionId: '00000000-0000-7000-8000-000000000011',
					},
				],
				kind: 'catalog.window',
				transferId,
				windowOrdinal: 0,
			},
		},
		{
			authority,
			kind: 'annotation.catalog',
			transfer: {
				catalogRevision: revision,
				entryCount: 1,
				kind: 'catalog.commit',
				transferId,
				windowCount: 1,
			},
		},
	];
	return events.map((event, index) => ({
		data: event,
		metadataStreamId: 'annotation-metadata-stream',
		operationCorrelationId: 'a'.repeat(64),
		sourceGeneration: revision,
		streamSequence: index + 1,
		subscriptionId: 'annotation-subscription',
		subscriptionKind,
		subscriptionSequence: index + 1,
		workerDerivationEpoch: 1,
	}));
}

function createAnnotationProductTransport(props: {
	readonly calledMethods: string[];
	readonly failingAnnotationMethod?: 'file.annotations.command' | 'review.annotations.command';
	readonly fileAnnotationEvents: BridgeProductBoundedAsyncQueue<AnnotationMetadataFrame>;
	readonly reviewAnnotationEvents: BridgeProductBoundedAsyncQueue<AnnotationMetadataFrame>;
	readonly inspection?: {
		readonly descriptor: BridgeProductAnnotationOutputContentDescriptor;
		readonly exactBytes: ArrayBuffer;
		readonly observedSha256?: string;
		readonly operationOrder: string[];
	};
	readonly onCalledMethod?: ((method: string) => void) | undefined;
	readonly subscribedKinds: string[];
}): BridgeProductTransportSession {
	const reviewMetadataEvents = new BridgeProductBoundedAsyncQueue<
		BridgeProductMetadataDataFrame<never>
	>(1);
	return {
		bumpWorkerDerivationEpoch: (): number => 1,
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The annotation runtime test double implements only the call variants exercised by this suite.
		call: (async (method: string): Promise<unknown> => {
			props.calledMethods.push(method);
			props.onCalledMethod?.(method);
			if (
				method === 'file.annotations.output.inspect' ||
				method === 'review.annotations.output.inspect'
			) {
				props.inspection?.operationOrder.push(method);
				return { descriptor: props.inspection?.descriptor };
			}
			if (method === props.failingAnnotationMethod) throw new Error('native annotation failure');
			if (method === 'file.source.current') {
				return { reason: 'no-file-source-authority', status: 'unavailable' };
			}
			if (method === 'file.annotations.command' || method === 'review.annotations.command') {
				return {
					kind: 'completed',
					outcome: {
						requestId: `${method}-product-request`,
						sessionId: null,
						status: { kind: 'committed' },
						surface: method === 'file.annotations.command' ? 'file' : 'review',
					},
				};
			}
			return null;
		}) as BridgeProductTransportSession['call'],
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The annotation runtime test double opens only annotation output descriptors.
		openContent: ((descriptor: BridgeProductAnnotationOutputContentDescriptor): unknown => {
			if (props.inspection === undefined) {
				throw new Error('Content is outside the annotation runtime protocol test.');
			}
			props.inspection.operationOrder.push('content.open');
			return {
				contentKind: 'annotation.output',
				contentRequestId: 'annotation-output-content-request',
				frames: (async function* (): AsyncIterable<never> {})(),
				terminal: Promise.resolve({
					bytes: props.inspection.exactBytes,
					contentKind: 'annotation.output',
					descriptorId: descriptor.descriptorId,
					endOfSource: true,
					kind: 'complete',
					observedSha256: props.inspection.observedSha256 ?? descriptor.expectedSha256,
				}),
			};
		}) as BridgeProductTransportSession['openContent'],
		setPanePresentationFrameSink: (): void => {},
		// oxlint-disable-next-line typescript/no-unsafe-type-assertion -- The annotation runtime test double closes over its three supported subscription kinds.
		subscribe: ((protocol: BridgeProductMetadataApplicationProtocolIdentity): unknown => {
			const subscriptionKind = protocol.kind;
			props.subscribedKinds.push(subscriptionKind);
			switch (subscriptionKind) {
				case 'file.annotations':
					return annotationTestSubscription(subscriptionKind, props.fileAnnotationEvents);
				case 'review.annotations':
					return annotationTestSubscription(subscriptionKind, props.reviewAnnotationEvents);
				case 'review.metadata':
					return annotationTestSubscription(subscriptionKind, reviewMetadataEvents);
				default:
					throw new Error(`Unexpected subscription ${subscriptionKind}.`);
			}
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (): number => 1,
	};
}

function annotationTestSubscription<TEvent>(
	subscriptionKind: 'file.annotations' | 'review.annotations' | 'review.metadata',
	events: AsyncIterable<BridgeProductMetadataDataFrame<TEvent>>,
): {
	readonly events: AsyncIterable<BridgeProductMetadataDataFrame<TEvent>>;
	readonly subscriptionId: string;
	readonly subscriptionKind: string;
	cancel(): Promise<void>;
	update(): Promise<void>;
} {
	return {
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId: `${subscriptionKind}-subscription`,
		subscriptionKind,
		update: async (): Promise<void> => {},
	};
}
