import {
	recordBridgePaneCommWorkerSessionDiagnosticSnapshot,
	recordBridgePaneRuntimeDiagnosticSnapshot,
	type BridgePaneRuntimeDiagnosticSnapshot,
} from '../../foundation/diagnostics/bridge-review-selection-diagnostic.js';
import { bridgeWorkerPierreRenderPolicy } from '../demand/bridge-content-demand-policy.js';
import { encodeBridgeWorkerRenderDispositionCommand } from './bridge-comm-worker-protocol.js';
import type { BridgeMainFileDisplayPatchApplierProps } from './bridge-main-file-display-patch-applier.js';
import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
} from './bridge-main-render-fulfillment-coordinator.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshotStore,
} from './bridge-main-render-snapshot-store.js';
import {
	BridgePaneCommWorkerSession,
	type BridgePaneCommWorkerDispatcher,
	type BridgePaneCommWorkerNativeBootstrap,
	type BridgePaneCommWorkerSessionProps,
	type BridgePaneCommWorkerTelemetryProducerInstall,
} from './bridge-pane-comm-worker-session.js';
import {
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerServerToMainMessage,
} from './bridge-worker-contracts.js';
import {
	createBridgeWorkerRpcClient,
	type BridgePaneSurface,
	type BridgeWorkerRpcClient,
	type BridgeWorkerRpcCommandInput,
} from './bridge-worker-rpc-client.js';
import {
	createBridgeWorkerRpcLifecycleStore,
	type BridgeWorkerRpcLifecycleSnapshot,
	type BridgeWorkerRpcLifecycleStore,
} from './bridge-worker-rpc-lifecycle-store.js';

export interface BridgePaneSessionPort {
	readonly createDispatcher: (props: {
		readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	}) => BridgePaneCommWorkerDispatcher;
	readonly dispose: () => void;
	readonly installNativeBootstrap: (bootstrap: BridgePaneCommWorkerNativeBootstrap) => void;
	readonly installTelemetryProducer?: (
		install: BridgePaneCommWorkerTelemetryProducerInstall,
	) => void;
	readonly setNativeBootstrapRequester?: (requester: (reason: 'workerReplacement') => void) => void;
}

export interface BridgePaneSurfaceLifecycleView {
	readonly getSnapshot: () => BridgeWorkerRpcLifecycleSnapshot;
	readonly getServerSnapshot: () => BridgeWorkerRpcLifecycleSnapshot;
	readonly subscribe: (listener: () => void) => () => void;
}

export interface BridgePaneSurfaceClient {
	readonly lifecycle: BridgePaneSurfaceLifecycleView;
	readonly renderFulfillmentCoordinator: BridgeMainRenderFulfillmentCoordinator;
	readonly renderStore: BridgeMainRenderSnapshotStore;
	readonly send: (command: BridgeWorkerRpcCommandInput) => string;
	readonly subscribeMessages: (
		listener: (message: BridgeWorkerServerToMainMessage) => void,
	) => () => void;
	readonly surface: BridgePaneSurface;
}

export interface BridgePaneClient {
	readonly lifecycle: BridgePaneSurfaceLifecycleView;
	readonly send: (command: BridgeWorkerRpcCommandInput) => string;
	readonly subscribeMessages: (
		listener: (message: BridgeWorkerServerToMainMessage) => void,
	) => () => void;
}

export interface BridgePaneRuntime {
	readonly lifecycleStore: BridgeWorkerRpcLifecycleStore;
	readonly paneClient: BridgePaneClient;
	readonly dispose: () => void;
	readonly installNativeBootstrap: (bootstrap: BridgePaneCommWorkerNativeBootstrap) => void;
	readonly installTelemetryProducer: (
		install: BridgePaneCommWorkerTelemetryProducerInstall,
	) => void;
	readonly setNativeBootstrapRequester: (requester: (reason: 'workerReplacement') => void) => void;
	readonly surfaceClient: (surface: BridgePaneSurface) => BridgePaneSurfaceClient;
}

export interface CreateBridgePaneRuntimeProps {
	readonly lifecycleStoreFactory?: () => BridgeWorkerRpcLifecycleStore;
	readonly recordDiagnosticSnapshot?: (snapshot: BridgePaneRuntimeDiagnosticSnapshot) => void;
	readonly renderStoreFactory?: (
		fileDisplayApplierProps?: BridgeMainFileDisplayPatchApplierProps,
	) => BridgeMainRenderSnapshotStore;
	readonly sessionFactory?: () => BridgePaneSessionPort;
	readonly sessionProps?: BridgePaneCommWorkerSessionProps;
}

export function createBridgePaneRuntime(
	props: CreateBridgePaneRuntimeProps = {},
): BridgePaneRuntime {
	const lifecycleStore = (props.lifecycleStoreFactory ?? createBridgeWorkerRpcLifecycleStore)();
	const renderStoreFactory = props.renderStoreFactory ?? createBridgeMainRenderSnapshotStore;
	const session =
		props.sessionFactory?.() ?? createDefaultBridgePaneSessionPort(props.sessionProps);
	const recordDiagnosticSnapshot =
		props.recordDiagnosticSnapshot ?? recordBridgePaneRuntimeDiagnosticSnapshot;
	const rpcClients = new Map<BridgePaneSurface | 'pane', BridgeWorkerRpcClient>();
	const surfaceClients = new Map<BridgePaneSurface, BridgePaneSurfaceClient>();
	const renderFulfillmentCoordinators = new Set<BridgeMainRenderFulfillmentCoordinator>();
	const renderStores = new Set<BridgeMainRenderSnapshotStore>();
	let isDisposed = false;
	let nativeBootstrapInstalled = false;
	let nativeBootstrapReplacementRequested = false;
	let nativeBootstrapInstallAcceptedCount = 0;
	let nativeBootstrapInstallAttemptCount = 0;
	let nativeBootstrapInstallRejectedCount = 0;
	let nextRequestSequence = 0;
	let fileRpcClient: BridgeWorkerRpcClient | null = null;
	let latestFileDisplayEpoch = 0;

	const publishDiagnosticSnapshot = (): void => {
		try {
			recordDiagnosticSnapshot({
				nativeBootstrapInstallAcceptedCount,
				nativeBootstrapInstallAttemptCount,
				nativeBootstrapInstallRejectedCount,
			});
		} catch {
			// Diagnostics are observational and cannot own the pane runtime lifecycle.
		}
	};
	publishDiagnosticSnapshot();

	const dispatcher = session.createDispatcher({
		publishWorkerMessages: (messages): void => {
			for (const message of messages) {
				for (const client of rpcClients.values()) client.receive(message);
			}
		},
	});

	for (const surface of ['fileView', 'review'] as const) {
		const renderStore = renderStoreFactory(
			surface === 'fileView'
				? {
						requestResync: (request): void => {
							if (fileRpcClient === null) {
								throw new Error('Bridge pane runtime File RPC client is not installed.');
							}
							fileRpcClient.send({
								command: 'fileDisplayResync',
								epoch: latestFileDisplayEpoch,
								reason: request.reason,
								transactionId: request.transactionId,
							});
						},
					}
				: undefined,
		);
		renderStores.add(renderStore);
		const rpcClient = createBridgeWorkerRpcClient({
			dispatch: dispatcher.dispatch,
			lifecycleStore,
			requestIdFactory: (): string => {
				nextRequestSequence += 1;
				return `bridge-${surface}-rpc-${nextRequestSequence}`;
			},
			surface,
		});
		if (surface === 'fileView') {
			fileRpcClient = rpcClient;
			rpcClient.subscribe((message): void => {
				if (message.kind === 'fileDisplayPatch') latestFileDisplayEpoch = message.epoch;
			});
		}
		rpcClients.set(surface, rpcClient);
		const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
			sendDisposition: (receipt): void => {
				rpcClient.send(
					encodeBridgeWorkerRenderDispositionCommand({
						epoch: receipt.workerDerivationEpoch,
						receipt,
						requestId: 'bridge-main-render-fulfillment',
					}),
				);
			},
		});
		renderFulfillmentCoordinators.add(renderFulfillmentCoordinator);
		surfaceClients.set(surface, {
			lifecycle: createBridgePaneSurfaceLifecycleView({ lifecycleStore, rpcClient }),
			renderFulfillmentCoordinator,
			renderStore,
			send: rpcClient.send,
			subscribeMessages: rpcClient.subscribe,
			surface,
		});
	}
	const paneRpcClient = createBridgeWorkerRpcClient({
		dispatch: dispatcher.dispatch,
		lifecycleStore,
		requestIdFactory: (): string => {
			nextRequestSequence += 1;
			return `bridge-pane-rpc-${nextRequestSequence}`;
		},
		surface: 'pane',
	});
	rpcClients.set('pane', paneRpcClient);
	const paneClient: BridgePaneClient = {
		lifecycle: createBridgePaneSurfaceLifecycleView({ lifecycleStore, rpcClient: paneRpcClient }),
		send: paneRpcClient.send,
		subscribeMessages: paneRpcClient.subscribe,
	};

	return {
		lifecycleStore,
		paneClient,
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			for (const coordinator of renderFulfillmentCoordinators) coordinator.dispose();
			for (const client of rpcClients.values()) client.dispose();
			for (const renderStore of renderStores) renderStore.dispose();
			lifecycleStore.dispose();
			rpcClients.clear();
			renderFulfillmentCoordinators.clear();
			surfaceClients.clear();
			renderStores.clear();
			dispatcher.dispose();
			session.dispose();
		},
		installNativeBootstrap: (bootstrap): void => {
			nativeBootstrapInstallAttemptCount += 1;
			try {
				if (isDisposed) throw new Error('Bridge pane runtime is disposed.');
				if (nativeBootstrapInstalled && !nativeBootstrapReplacementRequested) {
					throw new Error('Bridge pane runtime native capability claim was already installed.');
				}
				session.installNativeBootstrap(bootstrap);
				nativeBootstrapInstalled = true;
				nativeBootstrapReplacementRequested = false;
				nativeBootstrapInstallAcceptedCount += 1;
			} catch (error: unknown) {
				nativeBootstrapInstallRejectedCount += 1;
				publishDiagnosticSnapshot();
				throw error;
			}
			publishDiagnosticSnapshot();
		},
		installTelemetryProducer: (install): void => {
			if (isDisposed) {
				install.producerPort.close();
				return;
			}
			if (session.installTelemetryProducer === undefined) {
				install.producerPort.close();
				throw new Error('Bridge pane runtime session cannot install a telemetry producer.');
			}
			session.installTelemetryProducer(install);
		},
		setNativeBootstrapRequester: (requester): void => {
			if (isDisposed) return;
			if (session.setNativeBootstrapRequester === undefined) {
				throw new Error('Bridge pane runtime session cannot install a native bootstrap requester.');
			}
			session.setNativeBootstrapRequester((reason): void => {
				if (isDisposed) return;
				nativeBootstrapReplacementRequested = true;
				requester(reason);
			});
		},
		surfaceClient: (surface): BridgePaneSurfaceClient => {
			const client = surfaceClients.get(surface);
			if (client === undefined) throw new Error('Bridge pane runtime is disposed.');
			return client;
		},
	};
}

function createDefaultBridgePaneSessionPort(
	props: BridgePaneCommWorkerSessionProps = {},
): BridgePaneSessionPort {
	const session = new BridgePaneCommWorkerSession({
		...props,
		recordDiagnosticSnapshot:
			props.recordDiagnosticSnapshot ?? recordBridgePaneCommWorkerSessionDiagnosticSnapshot,
	});
	const bootstrapRequest = createPaneOwnedBridgeCommWorkerBootstrapRequest();
	return {
		createDispatcher: (dispatcherProps): BridgePaneCommWorkerDispatcher =>
			session.createDispatcher({
				bootstrapRequest,
				publishWorkerMessages: dispatcherProps.publishWorkerMessages,
			}),
		dispose: (): void => session.dispose(),
		installNativeBootstrap: (bootstrap): void => session.installNativeBootstrap(bootstrap),
		installTelemetryProducer: (install): void => session.installTelemetryProducer(install),
		setNativeBootstrapRequester: (requester): void =>
			session.setNativeBootstrapRequester(requester),
	};
}

function createPaneOwnedBridgeCommWorkerBootstrapRequest(): BridgeCommWorkerBootstrapRequest {
	return {
		method: 'bridgeCommWorker.bootstrap',
		requestId: 'pane-runtime-bootstrap',
		runtime: {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: bridgeWorkerPierreRenderPolicy.reviewInteractiveRenderBudget,
		},
		schemaVersion: 1,
	};
}

function createBridgePaneSurfaceLifecycleView(props: {
	readonly lifecycleStore: BridgeWorkerRpcLifecycleStore;
	readonly rpcClient: BridgeWorkerRpcClient;
}): BridgePaneSurfaceLifecycleView {
	return {
		getSnapshot: props.rpcClient.getLifecycleSnapshot,
		getServerSnapshot: props.rpcClient.getLifecycleSnapshot,
		subscribe: (listener): (() => void) => {
			let previousSnapshot = props.rpcClient.getLifecycleSnapshot();
			return props.lifecycleStore.subscribe((): void => {
				const nextSnapshot = props.rpcClient.getLifecycleSnapshot();
				if (nextSnapshot.requestsById === previousSnapshot.requestsById) return;
				if (bridgeWorkerRpcSnapshotsEqual(previousSnapshot, nextSnapshot)) return;
				previousSnapshot = nextSnapshot;
				listener();
			});
		},
	};
}

function bridgeWorkerRpcSnapshotsEqual(
	left: BridgeWorkerRpcLifecycleSnapshot,
	right: BridgeWorkerRpcLifecycleSnapshot,
): boolean {
	const leftEntries = Object.entries(left.requestsById);
	const rightEntries = Object.entries(right.requestsById);
	if (leftEntries.length !== rightEntries.length) return false;
	return leftEntries.every(([requestId, request], index): boolean => {
		const rightEntry = rightEntries[index];
		return rightEntry?.[0] === requestId && rightEntry[1] === request;
	});
}
