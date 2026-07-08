import { describe, expect, test, vi } from 'vitest';

import type { BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import { encodeBridgeWorkerReviewIntakeReadyCommand } from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	makeRenderSemantics,
	makeWorkerReviewContentMetadata,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker runtime review intake-ready protocol', () => {
	test('forwards reviewIntakeReady commands to Swift through worker-owned scheme RPC', async () => {
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
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (command): Promise<void> => {
				sentCommands.push(command);
				await schemeRpcCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewIntakeReadyCommand({
				requestId: 'request-review-intake-ready',
				epoch: 3,
				streamId: 'review:pane-1',
				reason: 'bridge-ready',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				method: 'bridge.intakeReady',
				params: {
					protocolId: 'review',
					streamId: 'review:pane-1',
					reason: 'bridge-ready',
				},
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'ready',
			}),
		);
		schemeRpcCompletion.resolve();
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when reviewIntakeReady scheme RPC forwarding fails', async () => {
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: {
				className: 'interactive',
				maxBytes: 512 * 1024,
				maxWindowLines: 50,
			},
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			sendSchemeRpcCommand: async (): Promise<void> => {
				throw new Error('scheme down');
			},
		});

		dispatch.message(
			encodeBridgeWorkerReviewIntakeReadyCommand({
				requestId: 'request-review-intake-ready',
				epoch: 3,
				streamId: 'review:pane-1',
				reason: 'bridge-ready',
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'degraded',
				message: 'Bridge comm worker failed to forward bridge.intakeReady.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-review-intake-ready',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when reviewIntakeReady scheme RPC forwarding never settles', async () => {
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
				contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
				contentRequestDescriptors: [],
				renderSemantics: [makeRenderSemantics({ itemId: 'item-1' })],
				rows: [{ id: 'item-1', parentId: null, index: 0 }],
				schemeRpcTimeoutMilliseconds: 25,
				sendSchemeRpcCommand: async (): Promise<void> => new Promise((): void => {}),
			});

			dispatch.message(
				encodeBridgeWorkerReviewIntakeReadyCommand({
					requestId: 'request-review-intake-ready',
					epoch: 3,
					streamId: 'review:pane-1',
					reason: 'bridge-ready',
				}),
			);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-review-intake-ready',
					status: 'degraded',
				}),
			);

			await vi.advanceTimersByTimeAsync(25);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-review-intake-ready',
					status: 'degraded',
					message: 'Bridge comm worker failed to forward bridge.intakeReady.',
				}),
			);
			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-review-intake-ready',
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
