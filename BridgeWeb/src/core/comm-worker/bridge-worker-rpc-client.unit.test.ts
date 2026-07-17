import { describe, expect, test, vi } from 'vitest';

import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerRpcCommandInput } from './bridge-worker-rpc-client.js';
import { createBridgeWorkerRpcLifecycleStore } from './bridge-worker-rpc-lifecycle-store.js';

describe('Bridge worker RPC client', () => {
	test('owns request identity and timeout while sharing one pane lifecycle store', async () => {
		// Arrange
		vi.useFakeTimers();
		try {
			const { createBridgeWorkerRpcClient } = await loadBridgeWorkerRpcClientModule();
			const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
			const dispatched: BridgeWorkerMainToServerMessage[] = [];
			const fileClient = createBridgeWorkerRpcClient({
				dispatch: (message): void => {
					dispatched.push(message);
				},
				lifecycleStore,
				requestIdFactory: (): string => 'file-request-1',
				requestTimeoutMilliseconds: 100,
				surface: 'fileView',
			});
			const reviewClient = createBridgeWorkerRpcClient({
				dispatch: (message): void => {
					dispatched.push(message);
				},
				lifecycleStore,
				requestIdFactory: (): string => 'review-request-1',
				requestTimeoutMilliseconds: 100,
				surface: 'review',
			});

			// Act
			const fileRequestId = fileClient.send(makeFileCommandInput());
			const reviewRequestId = reviewClient.send(makeReviewCommandInput());
			const crossSurfaceSend = (): string => fileClient.send(makeReviewCommandInput());
			await vi.advanceTimersByTimeAsync(100);

			// Assert
			expect(fileRequestId).toBe('file-request-1');
			expect(reviewRequestId).toBe('review-request-1');
			expect(dispatched).toEqual([
				expect.objectContaining({
					command: 'fileQueryUpdate',
					requestId: 'file-request-1',
				}),
				expect.objectContaining({
					command: 'reviewInvalidate',
					requestId: 'review-request-1',
				}),
			]);
			expect(crossSurfaceSend).toThrow(/surface|fileView|review/u);
			expect(dispatched).toHaveLength(2);
			expect(lifecycleStore.getSnapshot().requestsById).toMatchObject({
				'file-request-1': { command: 'fileQueryUpdate', state: 'timed_out' },
				'review-request-1': { command: 'reviewInvalidate', state: 'timed_out' },
			});
			expect(Object.keys(fileClient.getLifecycleSnapshot().requestsById)).toEqual([
				'file-request-1',
			]);
			expect(Object.keys(reviewClient.getLifecycleSnapshot().requestsById)).toEqual([
				'review-request-1',
			]);
			expect(fileClient).not.toHaveProperty('renderStore');
			expect(fileClient).not.toHaveProperty('productCapability');
			expect(fileClient).not.toHaveProperty('bootstrap');
			expect(fileClient).not.toHaveProperty('installNativeBootstrap');
			fileClient.dispose();
			reviewClient.dispose();
			expect(vi.getTimerCount()).toBe(0);
		} finally {
			vi.useRealTimers();
		}
	});

	test('routes only matching surface traffic plus pane lifecycle events', async () => {
		// Arrange
		const { createBridgeWorkerRpcClient } = await loadBridgeWorkerRpcClientModule();
		const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
		const fileClient = createBridgeWorkerRpcClient({
			dispatch: vi.fn(),
			lifecycleStore,
			requestIdFactory: (): string => 'file-request-1',
			requestTimeoutMilliseconds: 100,
			surface: 'fileView',
		});
		const reviewClient = createBridgeWorkerRpcClient({
			dispatch: vi.fn(),
			lifecycleStore,
			requestIdFactory: (): string => 'review-request-1',
			requestTimeoutMilliseconds: 100,
			surface: 'review',
		});
		const fileMessages: BridgeWorkerServerToMainMessage[] = [];
		const reviewMessages: BridgeWorkerServerToMainMessage[] = [];
		fileClient.subscribe((message): void => {
			fileMessages.push(message);
		});
		reviewClient.subscribe((message): void => {
			reviewMessages.push(message);
		});
		const filePatch = makeFilePatch();
		const reviewPatch = makeReviewPatch();
		const paneHealth = makePaneHealth();

		// Act
		const fileAcceptance = [
			fileClient.receive(filePatch),
			fileClient.receive(reviewPatch),
			fileClient.receive(paneHealth),
		];
		const reviewAcceptance = [
			reviewClient.receive(filePatch),
			reviewClient.receive(reviewPatch),
			reviewClient.receive(paneHealth),
		];

		// Assert
		expect(fileAcceptance).toEqual([true, false, true]);
		expect(reviewAcceptance).toEqual([false, true, true]);
		expect(fileMessages).toEqual([filePatch, paneHealth]);
		expect(reviewMessages).toEqual([reviewPatch, paneHealth]);
		expect(fileClient.getLifecycleSnapshot().requestsById).toEqual({});
		expect(reviewClient.getLifecycleSnapshot().requestsById).toEqual({});
		fileClient.dispose();
		reviewClient.dispose();
	});

	test('rolls back lifecycle and timeout ownership when synchronous dispatch throws', async () => {
		// Arrange
		vi.useFakeTimers();
		try {
			const { createBridgeWorkerRpcClient } = await loadBridgeWorkerRpcClientModule();
			const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
			const client = createBridgeWorkerRpcClient({
				dispatch: (): never => {
					throw new Error('dispatcher rejected synchronously');
				},
				lifecycleStore,
				requestIdFactory: (): string => 'rejected-request-1',
				requestTimeoutMilliseconds: 100,
				surface: 'fileView',
			});

			// Act
			expect(() => client.send(makeFileCommandInput())).toThrow(
				'dispatcher rejected synchronously',
			);

			// Assert
			expect(lifecycleStore.getSnapshot().requestsById).toEqual({});
			expect(vi.getTimerCount()).toBe(0);
			client.dispose();
		} finally {
			vi.useRealTimers();
		}
	});

	test('rejects surface-dependent interaction commands without an explicit target', async () => {
		// Arrange
		const { createBridgeWorkerRpcClient } = await loadBridgeWorkerRpcClientModule();
		const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
		const dispatch = vi.fn<(message: BridgeWorkerMainToServerMessage) => void>();
		const fileClient = createBridgeWorkerRpcClient({
			dispatch,
			lifecycleStore,
			requestIdFactory: (): string => 'untargeted-select-1',
			requestTimeoutMilliseconds: 100,
			surface: 'fileView',
		});
		const untargetedSelect = {
			command: 'select',
			epoch: 1,
			selectedItemId: 'shared-id',
			selectedSource: 'user',
		} as BridgeWorkerRpcCommandInput;

		// Act / Assert
		expect(() => fileClient.send(untargetedSelect)).toThrow(/explicit surface target/u);
		expect(dispatch).not.toHaveBeenCalled();
		expect(lifecycleStore.getSnapshot().requestsById).toEqual({});
		fileClient.dispose();
	});

	test('routes render disposition commands only through the receipt surface client', async () => {
		const { createBridgeWorkerRpcClient } = await loadBridgeWorkerRpcClientModule();
		const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
		const dispatch = vi.fn<(message: BridgeWorkerMainToServerMessage) => void>();
		const fileClient = createBridgeWorkerRpcClient({
			dispatch,
			lifecycleStore,
			requestIdFactory: (): string => 'file-disposition-1',
			surface: 'fileView',
		});
		const reviewClient = createBridgeWorkerRpcClient({
			dispatch,
			lifecycleStore,
			requestIdFactory: (): string => 'review-disposition-1',
			surface: 'review',
		});
		const reviewDisposition = makeReviewRenderDispositionCommandInput();

		expect(() => fileClient.send(reviewDisposition)).toThrow(/targets review, not fileView/u);
		expect(reviewClient.send(reviewDisposition)).toBe('review-disposition-1');
		expect(dispatch).toHaveBeenCalledOnce();
		expect(dispatch.mock.calls[0]?.[0]).toMatchObject({
			command: 'renderDisposition',
			receipt: { surface: 'review' },
		});
		fileClient.dispose();
		reviewClient.dispose();
	});

	test('routes Review projection intent only through the Review surface client', async () => {
		// Arrange
		const { createBridgeWorkerRpcClient } = await loadBridgeWorkerRpcClientModule();
		const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
		const dispatch = vi.fn<(message: BridgeWorkerMainToServerMessage) => void>();
		const fileClient = createBridgeWorkerRpcClient({
			dispatch,
			lifecycleStore,
			requestIdFactory: (): string => 'file-projection-1',
			surface: 'fileView',
		});
		const reviewClient = createBridgeWorkerRpcClient({
			dispatch,
			lifecycleStore,
			requestIdFactory: (): string => 'review-projection-1',
			surface: 'review',
		});
		const projectionIntent = makeReviewProjectionCommandInput();

		// Act / Assert
		expect(() => fileClient.send(projectionIntent)).toThrow(/does not belong to fileView/u);
		expect(reviewClient.send(projectionIntent)).toBe('review-projection-1');
		expect(dispatch).toHaveBeenCalledOnce();
		expect(dispatch.mock.calls[0]?.[0]).toMatchObject({
			command: 'reviewProjectionUpdate',
			query: { fileClassFilter: 'source', gitStatusFilter: 'added' },
		});
		fileClient.dispose();
		reviewClient.dispose();
	});
});

async function loadBridgeWorkerRpcClientModule(): Promise<
	typeof import('./bridge-worker-rpc-client.js')
> {
	return await vi.importActual<typeof import('./bridge-worker-rpc-client.js')>(
		'./bridge-worker-rpc-client.js',
	);
}

function makeFileCommandInput(): BridgeWorkerRpcCommandInput {
	return {
		command: 'fileQueryUpdate',
		epoch: 7,
		query: { filterMode: 'all', searchMode: 'text', searchText: 'Bridge' },
	};
}

function makeReviewCommandInput(): BridgeWorkerRpcCommandInput {
	return {
		command: 'reviewInvalidate',
		epoch: 11,
		itemIds: ['item-1'],
		pathHints: ['Sources/App.swift'],
		reason: 'sourceChanged',
		scope: 'items',
	};
}

function makeReviewProjectionCommandInput(): BridgeWorkerRpcCommandInput {
	return {
		command: 'reviewProjectionUpdate',
		epoch: 11,
		query: { fileClassFilter: 'source', gitStatusFilter: 'added' },
	};
}

function makeReviewRenderDispositionCommandInput(): BridgeWorkerRpcCommandInput {
	return {
		command: 'renderDisposition',
		epoch: 5,
		receipt: {
			attemptId: 'attempt-review-8',
			disposition: 'queued',
			itemId: 'item-1',
			kind: 'render.disposition',
			paneSessionId: 'pane-session-1',
			publicationId: 'publication-review-8',
			publicationSequence: 8,
			receivedAtMilliseconds: 42,
			submissionId: 'submission-review-8',
			surface: 'review',
			windowKey: 'window-review-8',
			workerDerivationEpoch: 5,
			workerInstanceId: 'worker-instance-1',
		},
	};
}

function makeFilePatch(): BridgeWorkerServerToMainMessage {
	return bridgeWorkerServerToMainMessageSchema.parse({
		direction: 'serverWorkerToMain',
		epoch: 7,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: { state: 'stale' },
				slice: 'fileStatus',
			},
		],
		projectionRevision: 1,
		sequence: 1,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	});
}

function makeReviewPatch(): BridgeWorkerServerToMainMessage {
	return bridgeWorkerServerToMainMessageSchema.parse({
		direction: 'serverWorkerToMain',
		epoch: 11,
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
	});
}

function makePaneHealth(): BridgeWorkerServerToMainMessage {
	return bridgeWorkerServerToMainMessageSchema.parse({
		direction: 'serverWorkerToMain',
		kind: 'health',
		message: 'pane worker is ready',
		status: 'ready',
		transferDescriptors: [],
		wireVersion: 1,
	});
}
