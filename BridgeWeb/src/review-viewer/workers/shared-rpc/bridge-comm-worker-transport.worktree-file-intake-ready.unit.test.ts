import { describe, expect, test } from 'vitest';

import {
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerWorktreeFileIntakeReadyCommand,
} from '../../../core/comm-worker/bridge-comm-worker-protocol.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerWorktreeFileIntakeReadyCommand,
	BridgeWorkerServerToMainMessage,
} from '../../../core/comm-worker/bridge-worker-contracts.js';
import { createBridgeReviewCommWorkerTransportDispatcher } from './bridge-comm-worker-transport.js';
import { RecordingBridgeCommWorker } from './bridge-comm-worker-transport.test-support.js';

describe('Bridge comm worker transport Worktree/File intake-ready failures', () => {
	test('publishes degraded health for queued Worktree/File intake-ready commands when worker startup fails', async () => {
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

		dispatcher.dispatch(makeWorktreeFileIntakeReadyCommand('request-worktree-file-intake-ready'));
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
				requestId: 'request-worktree-file-intake-ready',
				status: 'degraded',
				message: 'Bridge comm worker transport failed before bridge.intakeReady delivery.',
				transferDescriptors: [],
			},
		]);
	});

	test('publishes degraded health for in-flight Worktree/File intake-ready commands when a ready worker fails', async () => {
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
		dispatcher.dispatch(makeWorktreeFileIntakeReadyCommand('request-after-ready'));
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
				requestId: 'request-after-ready',
				status: 'degraded',
				message: 'Bridge comm worker transport failed before bridge.intakeReady delivery.',
				transferDescriptors: [],
			},
		]);
	});
});

function makeWorktreeFileIntakeReadyCommand(
	requestId: string,
): BridgeWorkerWorktreeFileIntakeReadyCommand {
	return encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
		requestId,
		epoch: 4,
		generation: 4,
		streamId: 'worktree-file:pane-1',
	});
}

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
