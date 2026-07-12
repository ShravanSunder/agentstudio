import {
	createContext,
	createElement,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useRef,
	useSyncExternalStore,
	type ReactElement,
	type ReactNode,
} from 'react';

import {
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerFileDisplayResyncCommand,
	encodeBridgeWorkerFileQueryUpdateCommand,
	encodeBridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type { BridgeMainFileTreePatchStream } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshot,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	createBridgePaneCommWorkerDispatcher,
	type BridgePaneCommWorkerDispatcher,
} from '../core/comm-worker/bridge-pane-comm-worker-session.js';
import {
	bridgeCommWorkerBootstrapRequestSchema,
	type BridgeCommWorkerBootstrapRequest,
	type BridgeWorkerContentAvailabilityPatchPayload,
	type BridgeWorkerMainToServerMessage,
	type BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerFileQuery } from '../core/comm-worker/bridge-worker-file-query-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { bridgeWorkerPierreRenderPolicy } from '../core/demand/bridge-content-demand-policy.js';
import type { BridgeFileViewerSelectedCodeViewItem } from './bridge-file-viewer-code-view-items.js';
import type { BridgeFileViewerSelection } from './bridge-file-viewer-display-model.js';

const bridgeFileViewerRuntimeTransportFactoryContext =
	createContext<BridgeFileViewerRuntimeTransportFactory | null>(null);

export function BridgeFileViewerRuntimeTransportFactoryProvider(props: {
	readonly children: ReactNode;
	readonly transportFactory: BridgeFileViewerRuntimeTransportFactory;
}): ReactElement {
	return createElement(
		bridgeFileViewerRuntimeTransportFactoryContext.Provider,
		{ value: props.transportFactory },
		props.children,
	);
}

export interface BridgeFileViewerRenderSnapshotController {
	readonly completeFileQueryTransaction: (transactionId: string) => boolean;
	readonly dispatchFileViewQueryFact: (query: BridgeWorkerFileQuery) => void;
	readonly dispatchSelectedFileViewContentRequest: (props: {
		readonly fileId: string;
		readonly selectedSource: 'keyboard' | 'programmatic' | 'user';
	}) => void;
	readonly dispatchVisibleFileViewViewportFact: (props: {
		readonly firstVisibleIndex: number;
		readonly lastVisibleIndex: number;
		readonly visibleItemIds: readonly string[];
	}) => void;
	readonly fileDisplaySnapshot: Pick<
		BridgeMainRenderSnapshot,
		'fileDisplayFreshness' | 'fileItemById' | 'fileQuerySlice' | 'fileStatusSlice' | 'fileTreeSlice'
	>;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
}

export function useBridgeFileViewerRenderSnapshotController(props: {
	readonly selection: BridgeFileViewerSelection | null;
}): BridgeFileViewerRenderSnapshotController {
	const runtimeTransportFactory = useContext(bridgeFileViewerRuntimeTransportFactoryContext);
	const requestSequenceRef = useRef(0);
	const workerEpochRef = useRef(0);
	const runtimeDispatcherRef = useRef<BridgeFileViewerRuntimeProtocolDispatcher | null>(null);
	const renderSnapshotStore = useMemo(
		() =>
			createBridgeMainRenderSnapshotStore({
				requestResync: (request): void => {
					runtimeDispatcherRef.current?.dispatch(
						encodeBridgeWorkerFileDisplayResyncCommand({
							epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
							reason: request.reason,
							requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
							transactionId: request.transactionId,
						}),
					);
				},
			}),
		[],
	);
	const renderSnapshot = useSyncExternalStore(
		renderSnapshotStore.subscribe,
		renderSnapshotStore.getSnapshot,
		renderSnapshotStore.getServerSnapshot,
	);
	const publishWorkerMessages = useCallback(
		(messages: readonly BridgeWorkerServerToMainMessage[]): void => {
			applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
				messages,
				renderSnapshotStore,
			});
		},
		[renderSnapshotStore],
	);
	const runtimeDispatcher = useMemo(
		(): BridgeFileViewerRuntimeProtocolDispatcher =>
			createBridgeFileViewerRuntimeProtocolDispatcher({
				publishWorkerMessages,
				...(runtimeTransportFactory === null ? {} : { transportFactory: runtimeTransportFactory }),
			}),
		[publishWorkerMessages, runtimeTransportFactory],
	);
	useEffect((): (() => void) => {
		runtimeDispatcherRef.current = runtimeDispatcher;
		return (): void => {
			if (runtimeDispatcherRef.current === runtimeDispatcher) {
				runtimeDispatcherRef.current = null;
			}
			runtimeDispatcher.dispose();
		};
	}, [runtimeDispatcher]);

	const dispatchSelectedFileViewContentRequest = useCallback(
		(dispatchProps: {
			readonly fileId: string;
			readonly selectedSource: 'keyboard' | 'programmatic' | 'user';
		}): void => {
			renderSnapshotStore.setLocalSelection({
				selectedItemId: dispatchProps.fileId,
				source: dispatchProps.selectedSource,
			});
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerSelectCommand({
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					selectedItemId: dispatchProps.fileId,
					selectedSource: dispatchProps.selectedSource,
				}),
			);
		},
		[renderSnapshotStore, runtimeDispatcher],
	);
	const dispatchFileViewQueryFact = useCallback(
		(query: BridgeWorkerFileQuery): void => {
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerFileQueryUpdateCommand({
					...query,
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
				}),
			);
		},
		[runtimeDispatcher],
	);
	const dispatchVisibleFileViewViewportFact = useCallback(
		(dispatchProps: {
			readonly firstVisibleIndex: number;
			readonly lastVisibleIndex: number;
			readonly visibleItemIds: readonly string[];
		}): void => {
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerViewportCommand({
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					firstVisibleIndex: dispatchProps.firstVisibleIndex,
					lastVisibleIndex: dispatchProps.lastVisibleIndex,
					phase: 'settled',
					visibleItemIds: dispatchProps.visibleItemIds,
				}),
			);
		},
		[runtimeDispatcher],
	);
	const selectedCodeViewItem = selectedBridgeFileViewerCodeViewItemForSnapshot({
		renderSnapshot,
		selection: props.selection,
	});
	const selectedContentAvailability =
		props.selection === null
			? null
			: (renderSnapshot.contentAvailabilityById[props.selection.fileId] ?? null);

	return useMemo(
		(): BridgeFileViewerRenderSnapshotController => ({
			completeFileQueryTransaction: renderSnapshotStore.completeFileQueryTransaction,
			dispatchFileViewQueryFact,
			dispatchSelectedFileViewContentRequest,
			dispatchVisibleFileViewViewportFact,
			fileDisplaySnapshot: {
				fileDisplayFreshness: renderSnapshot.fileDisplayFreshness,
				fileItemById: renderSnapshot.fileItemById,
				fileQuerySlice: renderSnapshot.fileQuerySlice,
				fileStatusSlice: renderSnapshot.fileStatusSlice,
				fileTreeSlice: renderSnapshot.fileTreeSlice,
			},
			selectedContentAvailability,
			selectedCodeViewItem,
			fileTreePatchStream: renderSnapshotStore.fileTreePatchStream,
		}),
		[
			dispatchSelectedFileViewContentRequest,
			dispatchFileViewQueryFact,
			dispatchVisibleFileViewViewportFact,
			renderSnapshotStore.completeFileQueryTransaction,
			renderSnapshotStore.fileTreePatchStream,
			renderSnapshot.fileDisplayFreshness,
			renderSnapshot.fileItemById,
			renderSnapshot.fileQuerySlice,
			renderSnapshot.fileStatusSlice,
			renderSnapshot.fileTreeSlice,
			selectedCodeViewItem,
			selectedContentAvailability,
		],
	);
}

export interface BridgeFileViewerRuntimeProtocolDispatcher {
	readonly dispatch: (message: BridgeWorkerMainToServerMessage) => void;
	readonly dispose: () => void;
}

export interface CreateBridgeFileViewerRuntimeProtocolDispatcherProps {
	readonly bootstrapRequestId?: string;
	readonly bridgeDemandRank?: BridgeWorkerDemandRank;
	readonly budget?: BridgeWorkerPierreRenderBudget;
	readonly maxPreparationSliceMs?: number;
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	readonly transportFactory?: BridgeFileViewerRuntimeTransportFactory;
}

export type BridgeFileViewerRuntimeTransportFactory = (props: {
	readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
}) => BridgePaneCommWorkerDispatcher;

export function createBridgeFileViewerRuntimeProtocolDispatcher(
	props: CreateBridgeFileViewerRuntimeProtocolDispatcherProps,
): BridgeFileViewerRuntimeProtocolDispatcher {
	const transport = (props.transportFactory ?? createBridgePaneCommWorkerDispatcher)({
		bootstrapRequest: bridgeCommWorkerBootstrapRequestSchema.parse({
			schemaVersion: 1,
			method: 'bridgeCommWorker.bootstrap',
			requestId: props.bootstrapRequestId ?? 'file-viewer-worker-bootstrap',
			runtime: {
				bridgeDemandRank: props.bridgeDemandRank ?? bridgeFileViewerRuntimeInteractiveDemandRank,
				budget: props.budget ?? bridgeFileViewerRuntimeInteractiveBudget,
				contentItems: [],
				contentRequestDescriptors: [],
				renderSemantics: [],
				rows: [],
				...(props.maxPreparationSliceMs === undefined
					? {}
					: { maxPreparationSliceMs: props.maxPreparationSliceMs }),
			},
		}),
		publishWorkerMessages: props.publishWorkerMessages,
	});
	return transport;
}

const bridgeFileViewerRuntimeInteractiveDemandRank: BridgeWorkerDemandRank = {
	lane: 'selected',
	priority: 0,
};

const bridgeFileViewerRuntimeInteractiveBudget: BridgeWorkerPierreRenderBudget = {
	...bridgeWorkerPierreRenderPolicy.fileViewSelectedRenderBudget,
};

export function applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
}): void {
	for (const message of props.messages) {
		switch (message.kind) {
			case 'fileDisplayPatch': {
				const currentFreshness = props.renderSnapshotStore.getSnapshot().fileDisplayFreshness;
				if (
					bridgeFileDisplayEventIsAccepted(currentFreshness, message) &&
					(message.epoch > (currentFreshness?.epoch ?? message.epoch) ||
						message.patches.some(
							(patch): boolean => patch.slice === 'fileTree' && patch.operation === 'reset',
						))
				) {
					props.renderSnapshotStore.applySnapshotUpdate({
						codeViewItemPatches: [{ operation: 'reset' }],
						workerPatches: [
							{ operation: 'reset', slice: 'contentAvailability' },
							{ operation: 'reset', slice: 'rowPaint' },
						],
					});
				}
				props.renderSnapshotStore.applyFileDisplayPatchEvent(message);
				break;
			}
			case 'slicePatch': {
				break;
			}
			case 'fileRenderPatch':
				if (bridgeFilePublicationMatchesDisplayEpoch(props.renderSnapshotStore, message)) {
					props.renderSnapshotStore.applySnapshotUpdate({ workerPatches: message.patches });
				}
				break;
			case 'filePierreRenderJob':
				if (
					bridgeFilePublicationMatchesDisplayEpoch(props.renderSnapshotStore, message) &&
					message.job.payload.item.type === 'file' &&
					bridgeFileViewerItemIdBelongsToSnapshot(props.renderSnapshotStore, message.job.itemId)
				) {
					props.renderSnapshotStore.setWorkerCodeViewItem({
						item: message.job.payload.item,
						itemId: message.job.itemId,
					});
				}
				break;
			case 'health':
				if (message.status === 'degraded') {
					const snapshot = props.renderSnapshotStore.getSnapshot();
					const selectedItemId = snapshot.selectionSlice.selectedItemId;
					const selectedAvailability =
						selectedItemId === null ? undefined : snapshot.contentAvailabilityById[selectedItemId];
					if (selectedItemId !== null && selectedAvailability?.state !== 'ready') {
						props.renderSnapshotStore.applyWorkerPatch({
							itemId: selectedItemId,
							operation: 'upsert',
							payload: { reason: 'load_failed', state: 'failed' },
							slice: 'contentAvailability',
						});
					}
				}
				break;
			case 'pierreRenderJob':
			case 'subscription':
				break;
			default:
				assertNeverBridgeFileViewerWorkerServerMessage(message);
		}
	}
}

function bridgeFileDisplayEventIsAccepted(
	current: BridgeMainRenderSnapshot['fileDisplayFreshness'],
	event: Extract<BridgeWorkerServerToMainMessage, { readonly kind: 'fileDisplayPatch' }>,
): boolean {
	if (current === null || event.epoch > current.epoch) {
		return true;
	}
	return (
		event.epoch === current.epoch &&
		event.sequence > current.sequence &&
		event.projectionRevision > current.projectionRevision
	);
}

function bridgeFilePublicationMatchesDisplayEpoch(
	store: BridgeMainRenderSnapshotStore,
	publication: Extract<
		BridgeWorkerServerToMainMessage,
		{ readonly kind: 'filePierreRenderJob' | 'fileRenderPatch' }
	>,
): boolean {
	return store.getSnapshot().fileDisplayFreshness?.epoch === publication.workerDerivationEpoch;
}

function bridgeFileViewerItemIdBelongsToSnapshot(
	store: BridgeMainRenderSnapshotStore,
	itemId: string,
): boolean {
	const snapshot = store.getSnapshot();
	return (
		snapshot.fileItemById.get(itemId) !== undefined ||
		snapshot.selectionSlice.selectedItemId === itemId
	);
}

function nextBridgeFileViewerWorkerRequestId(requestSequenceRef: { current: number }): string {
	requestSequenceRef.current += 1;
	return `file-viewer-worker-command-${requestSequenceRef.current}`;
}

function nextBridgeFileViewerWorkerEpoch(workerEpochRef: { current: number }): number {
	workerEpochRef.current += 1;
	return workerEpochRef.current;
}

function assertNeverBridgeFileViewerWorkerServerMessage(_message: never): never {
	throw new Error('Unhandled File View bridge worker server message.');
}

export function selectedBridgeFileViewerCodeViewItemForSnapshot(props: {
	readonly renderSnapshot: BridgeMainRenderSnapshot;
	readonly selection: BridgeFileViewerSelection | null;
}): BridgeFileViewerSelectedCodeViewItem | null {
	if (props.selection === null) {
		return null;
	}
	const item = props.renderSnapshot.codeViewItemsById[props.selection.fileId];
	const displayItem = props.renderSnapshot.fileItemById.get(props.selection.fileId);
	if (
		displayItem === undefined ||
		displayItem.displayPath !== props.selection.path ||
		item === undefined ||
		item.type !== 'file' ||
		item.bridgeMetadata.itemId !== props.selection.fileId ||
		item.bridgeMetadata.displayPath !== props.selection.path ||
		!item.bridgeMetadata.contentRoles.includes('file')
	) {
		return null;
	}
	return item;
}
