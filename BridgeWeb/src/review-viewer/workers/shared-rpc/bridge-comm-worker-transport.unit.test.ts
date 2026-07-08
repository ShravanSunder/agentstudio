import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerActiveViewerModeUpdateCommand,
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerSelectCommand,
} from '../../../core/comm-worker/bridge-comm-worker-protocol.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerServerToMainMessage,
} from '../../../core/comm-worker/bridge-worker-contracts.js';
import {
	bridgeReviewCommWorkerDefaultScriptUrl,
	createBridgeReviewCommWorkerTransportDispatcher,
} from './bridge-comm-worker-transport.js';
import { RecordingBridgeCommWorker } from './bridge-comm-worker-transport.test-support.js';

describe('Bridge comm worker transport dispatcher', () => {
	test('loads the packaged worker asset and buffers commands until bootstrap is ready', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		let clockMs = 100;
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			now: () => {
				const value = clockMs;
				clockMs += 7;
				return value;
			},
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();

		expect(bridgeReviewCommWorkerDefaultScriptUrl).toBe(
			'agentstudio://app/assets/bridge-comm-worker.js',
		);
		expect(worker.postedMessages).toEqual([makeBootstrapRequest()]);

		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();

		expect(worker.postedMessages).toEqual([
			makeBootstrapRequest(),
			expect.objectContaining({
				kind: 'command',
				command: 'select',
				requestId: 'request-select',
				issuedAtMilliseconds: 100,
			}),
		]);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
		]);

		dispatcher.dispose();

		expect(worker.terminateCount).toBe(1);
	});

	test('publishes degraded health and clears queued commands when worker startup fails', async () => {
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => {
				throw new Error('asset fetch failed');
			},
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();

		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for queued mark-viewed commands when worker startup fails', async () => {
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => {
				throw new Error('asset fetch failed');
			},
		});

		dispatcher.dispatch(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed',
				epoch: 1,
				fileId: 'item-1',
			}),
		);
		await flushTransportMicrotasks();

		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-mark-viewed',
				status: 'degraded',
				message: 'Bridge comm worker transport failed before review.markFileViewed delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for queued metadata-interest commands when worker startup fails', async () => {
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => {
				throw new Error('asset fetch failed');
			},
		});

		dispatcher.dispatch(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest',
				epoch: 1,
				request: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 3,
					itemIds: ['item-1'],
					lane: 'foreground',
				},
			}),
		);
		await flushTransportMicrotasks();

		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-metadata-interest',
				status: 'degraded',
				message:
					'Bridge comm worker transport failed before bridge.metadata_interest.update delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for queued active-viewer-mode commands when worker startup fails', async () => {
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => {
				throw new Error('asset fetch failed');
			},
		});

		dispatcher.dispatch(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode',
				epoch: 1,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 2,
					mode: 'review',
					activeSource: null,
				},
			}),
		);
		await flushTransportMicrotasks();

		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-active-viewer-mode',
				status: 'degraded',
				message:
					'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('treats degraded bootstrap health as terminal for queued commands', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'degraded',
			message: 'Bridge comm worker runtime was already bootstrapped.',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();

		expect(worker.postedMessages).toEqual([makeBootstrapRequest()]);
		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker runtime was already bootstrapped.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for queued active-viewer-mode commands when bootstrap degrades', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode-queued',
				epoch: 1,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 2,
					mode: 'review',
					activeSource: null,
				},
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'degraded',
			message: 'Bridge comm worker runtime was already bootstrapped.',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker runtime was already bootstrapped.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-active-viewer-mode-queued',
				status: 'degraded',
				message:
					'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes one degraded health event when bootstrap postMessage throws', async () => {
		const worker = new RecordingBridgeCommWorker();
		worker.throwOnNextPostMessage = true;
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for invalid worker messages', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({ kind: 'not-a-worker-event' });
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport received invalid worker message.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for worker error events', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitError();
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for in-flight mark-viewed commands when a ready worker fails', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-ready',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();

		dispatcher.dispatch(
			encodeBridgeWorkerMarkFileViewedCommand({
				requestId: 'request-mark-viewed-after-ready',
				epoch: 2,
				fileId: 'item-2',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitError();
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-mark-viewed-after-ready',
				status: 'degraded',
				message: 'Bridge comm worker transport failed before review.markFileViewed delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for in-flight metadata-interest commands when a ready worker fails', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-ready',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();

		dispatcher.dispatch(
			encodeBridgeWorkerMetadataInterestUpdateCommand({
				requestId: 'request-metadata-interest-after-ready',
				epoch: 2,
				request: {
					protocol: 'review',
					streamId: 'stream-1',
					generation: 3,
					itemIds: ['item-2'],
					lane: 'visible',
				},
			}),
		);
		await flushTransportMicrotasks();
		worker.emitError();
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-metadata-interest-after-ready',
				status: 'degraded',
				message:
					'Bridge comm worker transport failed before bridge.metadata_interest.update delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for in-flight active-viewer-mode commands when a ready worker fails', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-ready',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();

		dispatcher.dispatch(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode-after-ready',
				epoch: 2,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 3,
					mode: 'file',
					activeSource: {
						protocol: 'worktree-file',
						streamId: 'worktree-file:pane-1',
						generation: 4,
					},
				},
			}),
		);
		await flushTransportMicrotasks();
		worker.emitError();
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-active-viewer-mode-after-ready',
				status: 'degraded',
				message:
					'Bridge comm worker transport lost confirmation after bridge.activeViewerMode.update dispatch.',
				deliveryStatus: 'unknownAfterDispatch',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health when command postMessage throws after bootstrap', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-ready',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();
		worker.throwOnNextPostMessage = true;

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-after-ready',
				epoch: 2,
				selectedItemId: 'item-2',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
		]);
	});

	test('classifies active-viewer-mode postMessage throw as definite pre-delivery failure', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerSelectCommand({
				requestId: 'request-select-before-ready',
				epoch: 1,
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		await flushTransportMicrotasks();
		worker.emitMessage({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'bootstrap-request',
			status: 'ready',
			transferDescriptors: [],
		});
		await flushTransportMicrotasks();
		worker.throwOnNextPostMessage = true;

		dispatcher.dispatch(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode-after-ready',
				epoch: 2,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 3,
					mode: 'file',
					activeSource: {
						protocol: 'worktree-file',
						streamId: 'worktree-file:pane-1',
						generation: 4,
					},
				},
			}),
		);
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-active-viewer-mode-after-ready',
				status: 'degraded',
				message:
					'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('classifies queued active-viewer-mode flush postMessage throw as definite pre-delivery failure', async () => {
		const worker = new RecordingBridgeCommWorker();
		const publishedMessages: BridgeWorkerServerToMainMessage[] = [];
		const dispatcher = createBridgeReviewCommWorkerTransportDispatcher({
			bootstrapRequest: makeBootstrapRequest(),
			publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]): void => {
				publishedMessages.push(...messages);
			},
			workerFactory: async (): Promise<Worker> => worker,
		});

		dispatcher.dispatch(
			encodeBridgeWorkerActiveViewerModeUpdateCommand({
				requestId: 'request-active-viewer-mode-queued',
				epoch: 1,
				update: {
					sessionId: 'active-viewer-session',
					sequence: 2,
					mode: 'file',
					activeSource: {
						protocol: 'worktree-file',
						streamId: 'worktree-file:pane-1',
						generation: 4,
					},
				},
			}),
		);
		await flushTransportMicrotasks();
		worker.throwOnNextPostMessage = true;

		expect((): void => {
			worker.emitMessage({
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			});
		}).not.toThrow();
		await flushTransportMicrotasks();

		expect(worker.terminateCount).toBe(1);
		expect(publishedMessages).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'ready',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'bootstrap-request',
				status: 'degraded',
				message: 'Bridge comm worker transport failed during bootstrap.',
				transferDescriptors: [],
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				kind: 'health',
				requestId: 'request-active-viewer-mode-queued',
				status: 'degraded',
				message:
					'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.',
				transferDescriptors: [],
			},
		]);
	});
});

function makeBootstrapRequest(): BridgeCommWorkerBootstrapRequest {
	return {
		schemaVersion: 1,
		method: 'bridgeCommWorker.bootstrap',
		requestId: 'bootstrap-request',
		runtime: {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 400,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
		},
	};
}

async function flushTransportMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}
