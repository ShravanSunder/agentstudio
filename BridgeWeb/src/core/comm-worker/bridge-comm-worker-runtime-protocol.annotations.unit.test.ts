import { describe, expect, test } from 'vitest';

import { encodeBridgeWorkerViewportCommand } from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';
import { BridgeProductBoundedAsyncQueue } from './bridge-product-async-queue.js';
import type { BridgeProductSubscriptionEvent } from './bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from './bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from './bridge-product-transport.js';
import type { BridgeProductWorktreeAnnotationEvent } from './bridge-product-worktree-annotation-contracts.js';
import type { BridgeProductAnnotationOutputContentDescriptor } from './bridge-product-worktree-annotation-output-contracts.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerMainToServerMessage,
} from './bridge-worker-contracts.js';

const annotationWorktreeId = '00000000-0000-7000-8000-000000000001';

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
		const fileAnnotationEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'file.annotations'>
		>(8);
		const reviewAnnotationEvents = new BridgeProductBoundedAsyncQueue<
			BridgeProductSubscriptionEvent<'review.annotations'>
		>(8);
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
		fileAnnotationEvents.push(annotationProjectionEvent(11));
		reviewAnnotationEvents.push(annotationProjectionEvent(22));
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
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				event: expect.objectContaining({ payload: expect.objectContaining({ revision: 11 }) }),
				kind: 'annotationProjection',
				surface: 'fileView',
			}),
		);
		expect(postedMessages.map(({ message }) => message)).toContainEqual(
			expect.objectContaining({
				event: expect.objectContaining({ payload: expect.objectContaining({ revision: 22 }) }),
				kind: 'annotationProjection',
				surface: 'review',
			}),
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
		surface,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
	} as const;
}

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
): Extract<BridgeProductWorktreeAnnotationEvent, { readonly eventKind: 'projection.state' }> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes: [],
			outputHistory: [],
			recoveryStatus: 'available',
			revision,
			sessions: [],
			worktreeId: annotationWorktreeId,
		},
	} as const;
}

function createAnnotationProductTransport(props: {
	readonly calledMethods: string[];
	readonly failingAnnotationMethod?: 'file.annotations.command' | 'review.annotations.command';
	readonly fileAnnotationEvents: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'file.annotations'>
	>;
	readonly reviewAnnotationEvents: BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.annotations'>
	>;
	readonly inspection?: {
		readonly descriptor: BridgeProductAnnotationOutputContentDescriptor;
		readonly exactBytes: ArrayBuffer;
		readonly observedSha256?: string;
		readonly operationOrder: string[];
	};
	readonly subscribedKinds: string[];
}): BridgeProductTransportSession {
	const reviewMetadataEvents = new BridgeProductBoundedAsyncQueue<
		BridgeProductSubscriptionEvent<'review.metadata'>
	>(1);
	const subscription = <
		TSubscriptionKind extends 'file.annotations' | 'review.annotations' | 'review.metadata',
	>(
		subscriptionKind: TSubscriptionKind,
		events: BridgeProductSubscription<TSubscriptionKind>['events'],
	): BridgeProductSubscription<TSubscriptionKind> => ({
		cancel: async (): Promise<void> => {},
		events,
		subscriptionId: `${subscriptionKind}-subscription`,
		subscriptionKind,
		update: async (): Promise<void> => {},
	});
	return {
		bumpWorkerDerivationEpoch: (): number => 1,
		call: (async (method: string): Promise<unknown> => {
			props.calledMethods.push(method);
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
				return { kind: 'accepted', requestId: `${method}-product-request` };
			}
			return null;
		}) as BridgeProductTransportSession['call'],
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
		subscribe: ((subscriptionKind: string): unknown => {
			props.subscribedKinds.push(subscriptionKind);
			switch (subscriptionKind) {
				case 'file.annotations':
					return subscription(subscriptionKind, props.fileAnnotationEvents);
				case 'review.annotations':
					return subscription(subscriptionKind, props.reviewAnnotationEvents);
				case 'review.metadata':
					return subscription(subscriptionKind, reviewMetadataEvents);
				default:
					throw new Error(`Unexpected subscription ${subscriptionKind}.`);
			}
		}) as BridgeProductTransportSession['subscribe'],
		workerDerivationEpoch: (): number => 1,
	};
}
