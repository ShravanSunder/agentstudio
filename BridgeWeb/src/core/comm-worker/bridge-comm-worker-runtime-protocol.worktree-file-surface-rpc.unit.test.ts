import { describe, expect, test, vi } from 'vitest';

import type { BridgeRPCCommand } from '../../bridge/bridge-rpc-client.js';
import {
	encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand,
	encodeBridgeWorkerWorktreeFileRequestDescriptorCommand,
} from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker runtime Worktree/File surface RPC protocol', () => {
	test('forwards open-source stream commands and posts a typed result before ready health', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const schemeRpcCompletion = createDeferredUnknown();

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
			sendSchemeRpcCommand: async (command): Promise<unknown> => {
				sentCommands.push(command);
				return await schemeRpcCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand({
				requestId: 'request-worktree-file-open-source',
				epoch: 3,
				sourceSpec: makeWorktreeFileSourceSpec(),
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				id: 'request-worktree-file-open-source',
				method: 'worktreeFileSurface.openSourceStream',
				params: makeWorktreeFileSourceSpec(),
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'worktreeFileOpenSourceStreamResult',
				requestId: 'request-worktree-file-open-source',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-open-source',
				status: 'ready',
			}),
		);

		schemeRpcCompletion.resolve({
			status: 'accepted',
			protocol: 'worktree-file',
			streamId: 'worktree-file:pane-1',
			generation: 4,
		});
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'worktreeFileOpenSourceStreamResult',
				requestId: 'request-worktree-file-open-source',
				outcome: {
					status: 'accepted',
					protocol: 'worktree-file',
					streamId: 'worktree-file:pane-1',
					generation: 4,
				},
			},
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-worktree-file-open-source',
				status: 'ready',
			},
		]);
	});

	test('reports degraded health when open-source stream returns an invalid scheme result', async () => {
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
			sendSchemeRpcCommand: async (): Promise<unknown> => ({
				status: 'accepted',
				protocol: 'worktree-file',
				streamId: 'worktree-file:pane-1',
			}),
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand({
				requestId: 'request-worktree-file-open-source',
				epoch: 3,
				sourceSpec: makeWorktreeFileSourceSpec(),
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-open-source',
				status: 'degraded',
				message: 'Bridge comm worker failed to forward worktreeFileSurface.openSourceStream.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'worktreeFileOpenSourceStreamResult',
				requestId: 'request-worktree-file-open-source',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-open-source',
				status: 'ready',
			}),
		);
	});

	test('reports degraded health when open-source stream forwarding never settles', async () => {
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
				sendSchemeRpcCommand: async (): Promise<unknown> => new Promise((): void => {}),
			});

			dispatch.message(
				encodeBridgeWorkerWorktreeFileOpenSourceStreamCommand({
					requestId: 'request-worktree-file-open-source',
					epoch: 3,
					sourceSpec: makeWorktreeFileSourceSpec(),
				}),
			);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-worktree-file-open-source',
					status: 'degraded',
				}),
			);

			await vi.advanceTimersByTimeAsync(25);
			await flushBridgeWorkerRuntimeContinuations();

			expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-worktree-file-open-source',
					status: 'degraded',
					message: 'Bridge comm worker failed to forward worktreeFileSurface.openSourceStream.',
				}),
			);
			expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
				expect.objectContaining({
					kind: 'health',
					requestId: 'request-worktree-file-open-source',
					status: 'ready',
				}),
			);
		} finally {
			vi.useRealTimers();
		}
	});

	test('forwards descriptor requests and posts ready health after scheme success', async () => {
		const sentCommands: BridgeRPCCommand[] = [];
		const { dispatch, postedMessages } = createRecordingBridgeCommWorkerPort();
		const schemeRpcCompletion = createDeferredUnknown();

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
			sendSchemeRpcCommand: async (command): Promise<unknown> => {
				sentCommands.push(command);
				return await schemeRpcCompletion.promise;
			},
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileRequestDescriptorCommand({
				requestId: 'request-worktree-file-descriptor',
				epoch: 3,
				descriptorRequest: makeWorktreeFileDescriptorRequest(),
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(sentCommands).toEqual([
			{
				id: 'request-worktree-file-descriptor',
				method: 'worktreeFileSurface.requestFileDescriptor',
				params: makeWorktreeFileDescriptorRequest(),
			},
		]);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'ready',
			}),
		);

		schemeRpcCompletion.resolve({});
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toEqual([
			{
				wireVersion: 1,
				direction: 'serverWorkerToMain',
				transferDescriptors: [],
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'ready',
			},
		]);
	});

	test('reports degraded health when descriptor request returns an invalid acknowledgement', async () => {
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
			sendSchemeRpcCommand: async (): Promise<unknown> => ({ accepted: true }),
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileRequestDescriptorCommand({
				requestId: 'request-worktree-file-descriptor',
				epoch: 3,
				descriptorRequest: makeWorktreeFileDescriptorRequest(),
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'degraded',
				message: 'Bridge comm worker failed to forward worktreeFileSurface.requestFileDescriptor.',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'ready',
			}),
		);
	});

	test('preserves descriptor request scheme failure detail in degraded health', async () => {
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
			sendSchemeRpcCommand: async (): Promise<unknown> => {
				throw new Error(
					'Native Worktree/File descriptor request failed: worktree_file.stale_source_generation',
				);
			},
		});

		dispatch.message(
			encodeBridgeWorkerWorktreeFileRequestDescriptorCommand({
				requestId: 'request-worktree-file-descriptor',
				epoch: 3,
				descriptorRequest: makeWorktreeFileDescriptorRequest(),
			}),
		);
		await flushBridgeWorkerRuntimeContinuations();

		expect(postedMessages.map((postedMessage) => postedMessage.message)).toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'degraded',
				message:
					'Bridge comm worker failed to forward worktreeFileSurface.requestFileDescriptor: Native Worktree/File descriptor request failed: worktree_file.stale_source_generation',
			}),
		);
		expect(postedMessages.map((postedMessage) => postedMessage.message)).not.toContainEqual(
			expect.objectContaining({
				kind: 'health',
				requestId: 'request-worktree-file-descriptor',
				status: 'ready',
			}),
		);
	});
});

function makeWorktreeFileSourceSpec(): {
	readonly clientRequestId: string;
	readonly repoId: string;
	readonly worktreeId: string;
	readonly rootPathToken: string;
	readonly includeStatuses: true;
	readonly includeComments: false;
	readonly includeAgentComms: false;
	readonly freshness: 'live';
} {
	return {
		clientRequestId: 'client-open-1',
		repoId: 'repo-1',
		worktreeId: 'worktree-1',
		rootPathToken: 'root-token-1',
		includeStatuses: true,
		includeComments: false,
		includeAgentComms: false,
		freshness: 'live',
	};
}

function makeWorktreeFileDescriptorRequest(): {
	readonly sourceIdentity: {
		readonly sourceId: string;
		readonly repoId: string;
		readonly worktreeId: string;
		readonly subscriptionGeneration: number;
		readonly sourceCursor: string;
	};
	readonly rowId: string;
	readonly path: string;
	readonly fileId: string;
	readonly lane: 'foreground';
} {
	return {
		sourceIdentity: {
			sourceId: 'source-1',
			repoId: 'repo-1',
			worktreeId: 'worktree-1',
			subscriptionGeneration: 4,
			sourceCursor: 'cursor-1',
		},
		rowId: 'row-1',
		path: 'Sources/App/File.swift',
		fileId: 'file-1',
		lane: 'foreground',
	};
}

function createDeferredUnknown(): {
	readonly promise: Promise<unknown>;
	readonly resolve: (result: unknown) => void;
} {
	let resolvePromise: ((result: unknown) => void) | null = null;
	const promise = new Promise<unknown>((resolve): void => {
		resolvePromise = resolve;
	});
	return {
		promise,
		resolve: (result: unknown): void => {
			if (resolvePromise === null) {
				throw new Error('Deferred promise resolver was not initialized.');
			}
			resolvePromise(result);
		},
	};
}
