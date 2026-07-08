import { describe, expect, test, vi } from 'vitest';

import type { BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import { encodeBridgeWorkerWorktreeFileIntakeReadyCommand } from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker runtime Worktree/File intake-ready protocol', () => {
	test('forwards worktreeFileIntakeReady commands to Swift through worker-owned scheme RPC', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const schemeRpcCompletion = createDeferredVoid();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
			sendSchemeRpcCommand: async (command): Promise<void> => {
				sentCommands.push(command);
				await schemeRpcCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
				requestId: 'request-worktree-file-intake-ready',
				epoch: 3,
				generation: 4,
				streamId: 'worktree-file:pane-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'worktree-file',
					streamId: 'worktree-file:pane-1',
					generation: 4,
				},
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-intake-ready',
				status: 'ready',
			}),
		);
		schemeRpcCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-intake-ready',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when worktreeFileIntakeReady scheme RPC forwarding fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [],
			contentRequestDescriptors: [],
			renderSemantics: [],
			rows: [],
			sendSchemeRpcCommand: async (): Promise<void> => {
				throw new Error('scheme down');
			},
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
				requestId: 'request-worktree-file-intake-ready',
				epoch: 3,
				generation: 4,
				streamId: 'worktree-file:pane-1',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-intake-ready',
				status: 'degraded',
				message: 'Bridge comm worker failed to forward bridge.intakeReady.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-intake-ready',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when worktreeFileIntakeReady scheme RPC forwarding never settles', async () => {
		vi.useFakeTimers();
		try {
			const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

			registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				budget: {
					className: 'interactive',
					maxBytes: 512 * 1024,
					maxWindowLines: 50,
				},
				contentItems: [],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [],
				schemeRpcTimeoutMilliseconds: 25,
				sendSchemeRpcCommand: async (): Promise<void> => new Promise((): void => {}),
			});

			dispatch.message(
				encodeBridgeWorkerWorktreeFileIntakeReadyCommand({
					requestId: 'request-worktree-file-intake-ready',
					epoch: 3,
					generation: 4,
					streamId: 'worktree-file:pane-1',
				}),
			);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-worktree-file-intake-ready',
					status: 'degraded',
				}),
			);

			await vi.advanceTimersByTimeAsync(25);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-worktree-file-intake-ready',
					status: 'degraded',
					message: 'Bridge comm worker failed to forward bridge.intakeReady.',
				}),
			);
			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-worktree-file-intake-ready',
					status: 'ready',
				}),
			);
		} finally {
			vi.useRealTimers();
		}
	});
});

function createDeferredVoid(): { readonly promise: Promise<void>; readonly resolve: () => void } {
	let resolvePromise: (() => void) | null = null;
	const promise = new Promise<void>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (): void => {
			if (resolvePromise === null) {
				throw new Error('Deferred promise resolver was not initialized.');
			}
			resolvePromise();
		},
	};
}
