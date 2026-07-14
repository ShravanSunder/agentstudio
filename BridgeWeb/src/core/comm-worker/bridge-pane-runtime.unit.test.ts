import { describe, expect, test, vi } from 'vitest';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshotStore,
} from './bridge-main-render-snapshot-store.js';
import type {
	BridgePaneCommWorkerDispatcher,
	BridgePaneCommWorkerNativeBootstrap,
} from './bridge-pane-comm-worker-session.js';
import type { BridgePaneSessionPort } from './bridge-pane-runtime.js';
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
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import type { BridgeWorkerRpcCommandInput } from './bridge-worker-rpc-client.js';
import {
	createBridgeWorkerRpcLifecycleStore,
	type BridgeWorkerRpcLifecycleStore,
} from './bridge-worker-rpc-lifecycle-store.js';

describe('Bridge pane runtime', () => {
	test('owns one pane session and lifecycle store with stable isolated surface clients', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		let activeDispatcherCount = 0;
		const dispatcherDispose = vi.fn((): void => {
			activeDispatcherCount -= 1;
		});
		const dispatcherDispatch = vi.fn<(message: BridgeWorkerMainToServerMessage) => void>();
		const createDispatcher = vi.fn(
			(_props: {
				readonly publishWorkerMessages: (
					messages: readonly BridgeWorkerServerToMainMessage[],
				) => void;
			}): BridgePaneCommWorkerDispatcher => {
				activeDispatcherCount += 1;
				return { dispatch: dispatcherDispatch, dispose: dispatcherDispose };
			},
		);
		const installNativeBootstrap =
			vi.fn<(bootstrap: BridgePaneCommWorkerNativeBootstrap) => void>();
		const sessionDispose = vi.fn();
		const session: BridgePaneSessionPort = {
			createDispatcher,
			dispose: sessionDispose,
			installNativeBootstrap,
		};
		const sessionFactory = vi.fn((): BridgePaneSessionPort => session);
		const lifecycleStores: BridgeWorkerRpcLifecycleStore[] = [];
		const lifecycleStoreFactory = vi.fn((): BridgeWorkerRpcLifecycleStore => {
			const store = createBridgeWorkerRpcLifecycleStore();
			lifecycleStores.push(store);
			return store;
		});
		const renderStores: BridgeMainRenderSnapshotStore[] = [];
		const renderStoreFactory = vi.fn((): BridgeMainRenderSnapshotStore => {
			const store = createBridgeMainRenderSnapshotStore();
			renderStores.push(store);
			return store;
		});
		const runtime = createBridgePaneRuntime({
			lifecycleStoreFactory,
			renderStoreFactory,
			sessionFactory,
		});

		// Act
		const fileClientFirst = runtime.surfaceClient('fileView');
		const reviewClientFirst = runtime.surfaceClient('review');
		const fileClientSecond = runtime.surfaceClient('fileView');
		const reviewClientSecond = runtime.surfaceClient('review');

		// Assert
		expect(sessionFactory).toHaveBeenCalledOnce();
		expect(sessionFactory).toHaveBeenCalledWith();
		expect(createDispatcher).toHaveBeenCalledOnce();
		expect(activeDispatcherCount).toBe(1);
		expect(lifecycleStoreFactory).toHaveBeenCalledOnce();
		expect(renderStoreFactory).toHaveBeenCalledTimes(2);
		expect(runtime.lifecycleStore).toBe(lifecycleStores[0]);
		expect(fileClientFirst).toBe(fileClientSecond);
		expect(reviewClientFirst).toBe(reviewClientSecond);
		expect(fileClientFirst).not.toBe(reviewClientFirst);
		expect(fileClientFirst.renderStore).toBe(renderStores[0]);
		expect(reviewClientFirst.renderStore).toBe(renderStores[1]);
		expect(fileClientFirst.renderStore).not.toBe(reviewClientFirst.renderStore);
		expect(fileClientFirst.lifecycle).not.toBe(reviewClientFirst.lifecycle);
		expect(fileClientFirst).not.toHaveProperty('installNativeBootstrap');
		expect(fileClientFirst).not.toHaveProperty('productCapability');
		expect(fileClientFirst).not.toHaveProperty('bootstrap');
		expect(reviewClientFirst).not.toHaveProperty('installNativeBootstrap');
		expect(reviewClientFirst).not.toHaveProperty('productCapability');
		expect(reviewClientFirst).not.toHaveProperty('bootstrap');
		runtime.dispose();
	});

	test('accepts one native capability claim and tears down the pane exactly once', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		let activeDispatcherCount = 0;
		const dispatcherDispose = vi.fn((): void => {
			activeDispatcherCount -= 1;
		});
		const sessionDispose = vi.fn();
		const installNativeBootstrap =
			vi.fn<(bootstrap: BridgePaneCommWorkerNativeBootstrap) => void>();
		const session: BridgePaneSessionPort = {
			createDispatcher: (): BridgePaneCommWorkerDispatcher => {
				activeDispatcherCount += 1;
				return { dispatch: vi.fn(), dispose: dispatcherDispose };
			},
			dispose: sessionDispose,
			installNativeBootstrap,
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});
		const fileClient = runtime.surfaceClient('fileView');
		const firstBootstrap = makeNativeBootstrap('worker-instance-1');
		const secondBootstrap = makeNativeBootstrap('worker-instance-2');

		// Act
		runtime.installNativeBootstrap(firstBootstrap);
		let secondClaimError: unknown;
		try {
			runtime.installNativeBootstrap(secondBootstrap);
		} catch (error: unknown) {
			secondClaimError = error;
		}
		runtime.dispose();
		runtime.dispose();

		// Assert
		expect(installNativeBootstrap).toHaveBeenCalledOnce();
		expect(installNativeBootstrap).toHaveBeenCalledWith(firstBootstrap);
		expect(String(secondClaimError)).toMatch(/already|installed|claim/u);
		expect(secondBootstrap.productCapability.byteLength).toBe(
			BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
		);
		expect(dispatcherDispose).toHaveBeenCalledOnce();
		expect(sessionDispose).toHaveBeenCalledOnce();
		expect(activeDispatcherCount).toBe(0);
		expect(() => fileClient.send(makeFileCommand())).toThrow(/disposed/u);
		expect(runtime.lifecycleStore.getSnapshot().requestsById).toEqual({});
	});

	test('allows native capability installation to retry after the session rejects an attempt', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		const firstBootstrap = makeNativeBootstrap('worker-instance-rejected');
		const replacementBootstrap = makeNativeBootstrap('worker-instance-replacement');
		const installNativeBootstrap = vi
			.fn<(bootstrap: BridgePaneCommWorkerNativeBootstrap) => void>()
			.mockImplementationOnce((): never => {
				throw new Error('native bootstrap rejected');
			});
		const session: BridgePaneSessionPort = {
			createDispatcher: (): BridgePaneCommWorkerDispatcher => ({
				dispatch: vi.fn(),
				dispose: vi.fn(),
			}),
			dispose: vi.fn(),
			installNativeBootstrap,
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});

		// Act
		expect(() => runtime.installNativeBootstrap(firstBootstrap)).toThrow(
			'native bootstrap rejected',
		);
		const retryInstallation = (): void => runtime.installNativeBootstrap(replacementBootstrap);

		// Assert
		expect(retryInstallation).not.toThrow();
		expect(installNativeBootstrap).toHaveBeenCalledTimes(2);
		expect(installNativeBootstrap).toHaveBeenLastCalledWith(replacementBootstrap);
		runtime.dispose();
	});

	test('exposes one stable pane client for mode commands without granting surface authority', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		const dispatch = vi.fn<(message: BridgeWorkerMainToServerMessage) => void>();
		const session: BridgePaneSessionPort = {
			createDispatcher: (): BridgePaneCommWorkerDispatcher => ({ dispatch, dispose: vi.fn() }),
			dispose: vi.fn(),
			installNativeBootstrap: vi.fn(),
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});

		// Act / Assert
		expect(runtime).toMatchObject({ paneClient: expect.any(Object) });
		expect(runtime).toHaveProperty('paneClient.send', expect.any(Function));
		expect(runtime).not.toHaveProperty('paneClient.renderStore');
		expect(runtime).not.toHaveProperty('paneClient.installNativeBootstrap');
		expect(dispatch).not.toHaveBeenCalled();
		runtime.dispose();
	});

	test('routes File render-store resync through one stable File RPC client request', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		const dispatchedMessages: BridgeWorkerMainToServerMessage[] = [];
		let publishWorkerMessages:
			| ((messages: readonly BridgeWorkerServerToMainMessage[]) => void)
			| undefined;
		const session: BridgePaneSessionPort = {
			createDispatcher: (props): BridgePaneCommWorkerDispatcher => {
				publishWorkerMessages = props.publishWorkerMessages;
				return {
					dispatch: (message): void => {
						dispatchedMessages.push(message);
					},
					dispose: vi.fn(),
				};
			},
			dispose: vi.fn(),
			installNativeBootstrap: vi.fn(),
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});
		const fileClient = runtime.surfaceClient('fileView');
		fileClient.subscribeMessages((message): void => {
			if (message.kind === 'fileDisplayPatch') {
				fileClient.renderStore.applyFileDisplayPatchEvent(message);
			}
		});
		const queryPatch = makeFileQueryPatchEvent({
			epoch: 7,
			sequence: 11,
			transactionId: 'file-query-7',
		});

		// Act
		publishWorkerMessages?.([queryPatch]);
		fileClient.renderStore.completeFileQueryTransaction('wrong-query');
		fileClient.renderStore.completeFileQueryTransaction('wrong-query-again');

		// Assert
		expect(dispatchedMessages).toEqual([
			{
				command: 'fileDisplayResync',
				direction: 'mainToServerWorker',
				epoch: 7,
				kind: 'command',
				reason: 'acknowledgementMismatch',
				requestId: 'bridge-fileView-rpc-1',
				transactionId: 'file-query-7',
				transferDescriptors: [],
				wireVersion: 1,
			},
		]);
		runtime.dispose();
	});

	test('delivers each surface patch once without applying it and seals delivery on dispose', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		let publishWorkerMessages:
			| ((messages: readonly BridgeWorkerServerToMainMessage[]) => void)
			| undefined;
		const session: BridgePaneSessionPort = {
			createDispatcher: (props): BridgePaneCommWorkerDispatcher => {
				publishWorkerMessages = props.publishWorkerMessages;
				return { dispatch: vi.fn(), dispose: vi.fn() };
			},
			dispose: vi.fn(),
			installNativeBootstrap: vi.fn(),
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});
		const fileClient = runtime.surfaceClient('fileView');
		const deliveredMessages: BridgeWorkerServerToMainMessage[] = [];
		fileClient.subscribeMessages((message): void => {
			deliveredMessages.push(message);
		});
		const firstPatch = makeFileStatusPatchEvent({ epoch: 3, sequence: 21, state: 'stale' });
		const postDisposePatch = makeFileStatusPatchEvent({
			epoch: 4,
			sequence: 22,
			state: 'stale',
		});

		// Act / Assert: transport delivery is notification-only.
		publishWorkerMessages?.([firstPatch]);
		expect(deliveredMessages).toEqual([firstPatch]);
		expect(fileClient.renderStore.getSnapshot().fileStatusSlice).toBeNull();

		// Act / Assert: the surface controller is the single application owner.
		fileClient.renderStore.applyFileDisplayPatchEvent(firstPatch);
		expect(fileClient.renderStore.getSnapshot().fileStatusSlice).toEqual({ state: 'stale' });

		// Act / Assert: teardown seals subscriptions and retained state.
		runtime.dispose();
		publishWorkerMessages?.([postDisposePatch]);
		expect(deliveredMessages).toEqual([firstPatch]);
		expect(fileClient.renderStore.getSnapshot().fileStatusSlice).toBeNull();
	});

	test('teardown clears pending lifecycle listeners and retained display state', async () => {
		// Arrange
		const { createBridgePaneRuntime } = await loadBridgePaneRuntimeModule();
		const session: BridgePaneSessionPort = {
			createDispatcher: (): BridgePaneCommWorkerDispatcher => ({
				dispatch: vi.fn(),
				dispose: vi.fn(),
			}),
			dispose: vi.fn(),
			installNativeBootstrap: vi.fn(),
		};
		const runtime = createBridgePaneRuntime({
			sessionFactory: (): BridgePaneSessionPort => session,
		});
		const fileClient = runtime.surfaceClient('fileView');
		const lifecycleListener = vi.fn();
		fileClient.lifecycle.subscribe(lifecycleListener);
		fileClient.renderStore.setLocalSelection({
			selectedItemId: 'retained-file',
			source: 'user',
		});
		fileClient.send(makeFileCommandInput());
		lifecycleListener.mockClear();

		// Act
		runtime.dispose();
		runtime.lifecycleStore.startRequest({
			command: 'fileQueryUpdate',
			requestId: 'post-dispose-probe',
			surface: 'fileView',
		});

		// Assert
		expect(lifecycleListener).not.toHaveBeenCalled();
		expect(runtime.lifecycleStore.getSnapshot().requestsById).toEqual({});
		expect(fileClient.renderStore.getSnapshot().selectionSlice).toEqual({
			selectedItemId: null,
			source: null,
		});
	});
});

async function loadBridgePaneRuntimeModule(): Promise<typeof import('./bridge-pane-runtime.js')> {
	return await vi.importActual<typeof import('./bridge-pane-runtime.js')>(
		'./bridge-pane-runtime.js',
	);
}

function makeNativeBootstrap(workerInstanceId: string): BridgePaneCommWorkerNativeBootstrap {
	return {
		bootstrap: {
			kind: 'productSession.bootstrap',
			paneSessionId: 'pane-session-1',
			policy: {
				maximumContentBytes: BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
				maximumMetadataFrameBytes: BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
				maximumQueuedStreamBytes: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
				maximumQueuedStreamFrames: BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
				maximumRequestBodyBytes: BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
				terminalFrameReserve: BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
			},
			wireVersion: BRIDGE_PRODUCT_WIRE_VERSION,
			workerInstanceId,
		},
		productCapability: new ArrayBuffer(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH),
	};
}

function makeFileCommand(): BridgeWorkerMainToServerMessage {
	return {
		command: 'fileQueryUpdate',
		direction: 'mainToServerWorker',
		epoch: 1,
		kind: 'command',
		query: { filterMode: 'all', searchMode: 'text', searchText: '' },
		requestId: 'file-request-1',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function makeFileCommandInput(): BridgeWorkerRpcCommandInput {
	return {
		command: 'fileQueryUpdate',
		epoch: 1,
		query: { filterMode: 'all', searchMode: 'text', searchText: '' },
	};
}

function makeFileQueryPatchEvent(props: {
	readonly epoch: number;
	readonly sequence: number;
	readonly transactionId: string;
}): BridgeWorkerFileDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: props.epoch,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					filterMode: 'all',
					projectedRowCount: 0,
					searchError: null,
					searchMode: 'text',
					searchText: '',
					totalRowCount: 0,
				},
				slice: 'fileQuery',
			},
		],
		projectionRevision: props.sequence,
		queryTransaction: {
			batchCount: 1,
			batchIndex: 0,
			phase: 'batch',
			transactionId: props.transactionId,
		},
		sequence: props.sequence,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function makeFileStatusPatchEvent(props: {
	readonly epoch: number;
	readonly sequence: number;
	readonly state: 'stale';
}): BridgeWorkerFileDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: props.epoch,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: { state: props.state },
				slice: 'fileStatus',
			},
		],
		projectionRevision: props.sequence,
		sequence: props.sequence,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	};
}
