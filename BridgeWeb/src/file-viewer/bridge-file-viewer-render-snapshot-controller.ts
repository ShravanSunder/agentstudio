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

import { parseBridgeResourceUrl } from '../bridge/bridge-resource-url.js';
import {
	encodeBridgeWorkerFileViewSourceUpdateCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerRow } from '../core/comm-worker/bridge-comm-worker-store.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshot,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerFileViewContentMetadata,
	BridgeWorkerFileViewContentRequestDescriptor,
	BridgeWorkerMainToServerMessage,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	bridgeCommWorkerBootstrapRequestSchema,
	bridgeWorkerFileViewContentMetadataSchema,
	bridgeWorkerFileViewContentRequestDescriptorSchema,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { bridgeWorkerPierreRenderPolicy } from '../core/demand/bridge-content-demand-policy.js';
import {
	canFetchWorktreeFileDescriptorContent,
	type WorktreeFileDescriptor,
	type WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	createBridgeReviewCommWorkerTransportDispatcher,
	type BridgeReviewCommWorkerTransportDispatcher,
} from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.js';
import { type BridgeFileViewerSelectedCodeViewItem } from './bridge-file-viewer-code-view-items.js';
import type {
	BridgeFileViewerOpenState,
	BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

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
	readonly dispatchVisibleFileViewViewportFact: (
		props: DispatchVisibleFileViewViewportFactProps,
	) => void;
	readonly dispatchSelectedFileViewContentRequest: (
		props: DispatchSelectedFileViewContentRequestProps,
	) => void;
	readonly publishOpenFileLoadingState: (descriptor: WorktreeFileDescriptor) => void;
	readonly publishOpenFileRefreshingState: (descriptor: WorktreeFileDescriptor) => void;
	readonly publishOpenFileTerminalState: (props: {
		readonly descriptor: WorktreeFileDescriptor;
		readonly state: 'failed' | 'stale' | 'unavailable';
	}) => void;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly selectedReadyCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly synchronizeFileViewSource: (renderState: BridgeFileViewerRenderState) => void;
}

export function useBridgeFileViewerRenderSnapshotController(props: {
	readonly isActiveRef: { readonly current: boolean };
	readonly openFileState: BridgeFileViewerOpenState;
	readonly renderState: BridgeFileViewerRenderState;
}): BridgeFileViewerRenderSnapshotController {
	const runtimeTransportFactory = useContext(bridgeFileViewerRuntimeTransportFactoryContext);
	const renderSnapshotStore = useMemo(() => createBridgeMainRenderSnapshotStore(), []);
	const renderSnapshot = useSyncExternalStore(
		renderSnapshotStore.subscribe,
		renderSnapshotStore.getSnapshot,
		renderSnapshotStore.getServerSnapshot,
	);
	const selectedCodeViewItem = selectedBridgeFileViewerCodeViewItemForSnapshot({
		openFileState: props.openFileState,
		renderSnapshot,
	});
	const selectedReadyCodeViewItem = selectedBridgeFileViewerReadyCodeViewItemForSnapshot({
		openFileState: props.openFileState,
		renderSnapshot,
	});
	const selectedContentAvailability =
		props.openFileState.status === 'idle' ||
		renderSnapshot.selectionSlice.selectedItemId !== props.openFileState.descriptor.fileId
			? null
			: (renderSnapshot.contentAvailabilityById[props.openFileState.descriptor.fileId] ?? null);
	const minimumSelectedSlicePatchEpochRef = useRef(0);
	const requestSequenceRef = useRef(0);
	const workerEpochRef = useRef(0);
	const synchronizedFileViewSourceRef = useRef<{
		readonly dispatcher: BridgeFileViewerRuntimeProtocolDispatcher;
		readonly renderState: BridgeFileViewerRenderState;
	} | null>(null);
	const publishWorkerMessages = useCallback(
		(messages: readonly BridgeWorkerServerToMainMessage[]): void => {
			if (!props.isActiveRef.current) {
				return;
			}
			applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
				minimumAcceptedSlicePatchEpoch: minimumSelectedSlicePatchEpochRef.current,
				messages,
				renderSnapshotStore,
			});
		},
		[props.isActiveRef, renderSnapshotStore],
	);
	const runtimeDispatcher = useMemo(
		(): BridgeFileViewerRuntimeProtocolDispatcher =>
			createBridgeFileViewerRuntimeProtocolDispatcher({
				publishWorkerMessages,
				...(runtimeTransportFactory === null ? {} : { transportFactory: runtimeTransportFactory }),
			}),
		[publishWorkerMessages, runtimeTransportFactory],
	);
	useEffect(
		(): (() => void) => (): void => {
			runtimeDispatcher.dispose();
		},
		[runtimeDispatcher],
	);
	const synchronizeFileViewSource = useCallback(
		(renderState: BridgeFileViewerRenderState): number | null => {
			const synchronizedSource = synchronizedFileViewSourceRef.current;
			if (
				synchronizedSource?.dispatcher === runtimeDispatcher &&
				synchronizedSource.renderState.descriptors === renderState.descriptors &&
				synchronizedSource.renderState.treeRows === renderState.treeRows
			) {
				return null;
			}
			const sourceUpdateEpoch = nextBridgeFileViewerWorkerEpoch(workerEpochRef);
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerFileViewSourceUpdateCommand({
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					epoch: sourceUpdateEpoch,
					contentItems: bridgeCommWorkerContentItemsFromFileViewRenderState(renderState),
					contentRequestDescriptors:
						bridgeCommWorkerContentRequestDescriptorsFromFileViewRenderState(renderState),
					rows: bridgeCommWorkerRowsFromFileViewRenderState(renderState),
				}),
			);
			synchronizedFileViewSourceRef.current = {
				dispatcher: runtimeDispatcher,
				renderState,
			};
			return sourceUpdateEpoch;
		},
		[runtimeDispatcher],
	);
	useEffect((): void => {
		synchronizeFileViewSource(props.renderState);
	}, [props.renderState, synchronizeFileViewSource]);
	const dispatchSelectedFileViewContentRequest = useCallback(
		(dispatchProps: DispatchSelectedFileViewContentRequestProps): void => {
			const synchronizedSourceUpdateEpoch = synchronizeFileViewSource(dispatchProps.renderState);
			renderSnapshotStore.setLocalSelection({
				selectedItemId: dispatchProps.descriptor.fileId,
				source: dispatchProps.selectedSource,
			});
			const selectedEpoch = nextBridgeFileViewerWorkerEpoch(workerEpochRef);
			minimumSelectedSlicePatchEpochRef.current = bridgeFileViewerMinimumSelectedSlicePatchEpoch({
				selectedEpoch,
				synchronizedSourceUpdateEpoch,
			});
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerSelectCommand({
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					epoch: selectedEpoch,
					selectedItemId: dispatchProps.descriptor.fileId,
					selectedSource: dispatchProps.selectedSource,
				}),
			);
		},
		[renderSnapshotStore, runtimeDispatcher, synchronizeFileViewSource],
	);
	const dispatchVisibleFileViewViewportFact = useCallback(
		(dispatchProps: DispatchVisibleFileViewViewportFactProps): void => {
			synchronizeFileViewSource(dispatchProps.renderState);
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerViewportCommand({
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					firstVisibleIndex: dispatchProps.firstVisibleIndex,
					lastVisibleIndex: dispatchProps.lastVisibleIndex,
					phase: 'settled',
					visibleItemIds: dispatchProps.visibleItemIds,
				}),
			);
		},
		[runtimeDispatcher, synchronizeFileViewSource],
	);
	const publishOpenFileLoadingState = useCallback(
		(descriptor: WorktreeFileDescriptor): void => {
			publishBridgeFileViewerLoadingStateToSnapshotStore({
				descriptor,
				renderSnapshotStore,
			});
		},
		[renderSnapshotStore],
	);
	const publishOpenFileRefreshingState = useCallback(
		(descriptor: WorktreeFileDescriptor): void => {
			publishBridgeFileViewerRefreshingStateToSnapshotStore({
				descriptor,
				renderSnapshotStore,
			});
		},
		[renderSnapshotStore],
	);
	const publishOpenFileTerminalState = useCallback(
		(terminalState: {
			readonly descriptor: WorktreeFileDescriptor;
			readonly state: 'failed' | 'stale' | 'unavailable';
		}): void => {
			renderSnapshotStore.applySnapshotUpdate({
				localSelection: {
					selectedItemId: terminalState.descriptor.fileId,
					source: 'programmatic',
				},
			});
		},
		[renderSnapshotStore],
	);

	return useMemo(
		(): BridgeFileViewerRenderSnapshotController => ({
			dispatchVisibleFileViewViewportFact,
			dispatchSelectedFileViewContentRequest,
			publishOpenFileLoadingState,
			publishOpenFileRefreshingState,
			publishOpenFileTerminalState,
			selectedContentAvailability,
			selectedCodeViewItem,
			selectedReadyCodeViewItem,
			synchronizeFileViewSource,
		}),
		[
			dispatchVisibleFileViewViewportFact,
			dispatchSelectedFileViewContentRequest,
			publishOpenFileLoadingState,
			publishOpenFileRefreshingState,
			publishOpenFileTerminalState,
			selectedContentAvailability,
			selectedCodeViewItem,
			selectedReadyCodeViewItem,
			synchronizeFileViewSource,
		],
	);
}

export interface DispatchSelectedFileViewContentRequestProps {
	readonly descriptor: WorktreeFileDescriptor;
	readonly renderState: BridgeFileViewerRenderState;
	readonly selectedSource: 'keyboard' | 'programmatic' | 'user';
}

export interface DispatchVisibleFileViewViewportFactProps {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly renderState: BridgeFileViewerRenderState;
	readonly visibleItemIds: readonly string[];
}

export interface BridgeFileViewerRuntimeProtocolDispatcher {
	readonly dispatch: (message: BridgeWorkerMainToServerMessage) => void;
	readonly dispatchSelectedFileViewContentRequest: (
		props: DispatchSelectedFileViewContentRequestCommandProps,
	) => void;
	readonly dispose: () => void;
}

export interface DispatchSelectedFileViewContentRequestCommandProps {
	readonly epoch: number;
	readonly requestId: string;
	readonly selectedItemId: string;
	readonly selectedSource: 'keyboard' | 'programmatic' | 'user';
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
}) => BridgeReviewCommWorkerTransportDispatcher;

export function createBridgeFileViewerRuntimeProtocolDispatcher(
	props: CreateBridgeFileViewerRuntimeProtocolDispatcherProps,
): BridgeFileViewerRuntimeProtocolDispatcher {
	const transport = (props.transportFactory ?? createBridgeReviewCommWorkerTransportDispatcher)({
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
	return {
		dispatch: transport.dispatch,
		dispatchSelectedFileViewContentRequest: (
			dispatchProps: DispatchSelectedFileViewContentRequestCommandProps,
		): void => {
			transport.dispatch(
				encodeBridgeWorkerSelectCommand({
					epoch: dispatchProps.epoch,
					requestId: dispatchProps.requestId,
					selectedItemId: dispatchProps.selectedItemId,
					selectedSource: dispatchProps.selectedSource,
				}),
			);
		},
		dispose: transport.dispose,
	};
}

const bridgeFileViewerRuntimeInteractiveDemandRank: BridgeWorkerDemandRank = {
	lane: 'selected',
	priority: 0,
};

const bridgeFileViewerRuntimeInteractiveBudget: BridgeWorkerPierreRenderBudget = {
	...bridgeWorkerPierreRenderPolicy.interactiveRenderBudget,
};

export function bridgeCommWorkerContentItemsFromFileViewRenderState(
	renderState: BridgeFileViewerRenderState,
): readonly BridgeWorkerFileViewContentMetadata[] {
	return renderState.descriptors.map((descriptor) =>
		bridgeWorkerFileViewContentMetadataFromDescriptor(descriptor),
	);
}

export function bridgeCommWorkerContentRequestDescriptorsFromFileViewRenderState(
	renderState: BridgeFileViewerRenderState,
): readonly BridgeWorkerFileViewContentRequestDescriptor[] {
	return renderState.descriptors.flatMap(
		(descriptor): BridgeWorkerFileViewContentRequestDescriptor[] => {
			if (!canFetchWorktreeFileDescriptorContent(descriptor)) {
				return [];
			}
			if (descriptor.contentDescriptor.ref.expectedResourceKind !== 'worktree.fileContent') {
				return [];
			}
			return [bridgeWorkerFileViewContentRequestDescriptorFromDescriptor(descriptor)];
		},
	);
}

export function bridgeCommWorkerRowsFromFileViewRenderState(
	renderState: BridgeFileViewerRenderState,
): readonly BridgeCommWorkerRow[] {
	return renderState.treeRows.map((row, index) => ({
		id: bridgeCommWorkerRowIdFromWorktreeRow(row),
		parentId: null,
		index,
	}));
}

export function applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore(props: {
	readonly minimumAcceptedSlicePatchEpoch?: number;
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
}): void {
	for (const message of props.messages) {
		switch (message.kind) {
			case 'slicePatch':
				if (
					props.minimumAcceptedSlicePatchEpoch !== undefined &&
					message.epoch < props.minimumAcceptedSlicePatchEpoch
				) {
					break;
				}
				for (const patch of message.patches) {
					props.renderSnapshotStore.applyWorkerPatch(patch);
				}
				break;
			case 'health':
				if (message.status === 'degraded') {
					failSelectedFileViewContentRequestFromWorkerHealth(props.renderSnapshotStore);
				}
				break;
			case 'subscription':
				break;
			case 'pierreRenderJob':
				props.renderSnapshotStore.setWorkerCodeViewItem({
					itemId: message.job.itemId,
					item: message.job.payload.item,
				});
				break;
			default:
				assertNeverBridgeFileViewerWorkerServerMessage(message);
		}
	}
}

function failSelectedFileViewContentRequestFromWorkerHealth(
	renderSnapshotStore: BridgeMainRenderSnapshotStore,
): void {
	const selectedItemId = renderSnapshotStore.getSnapshot().selectionSlice.selectedItemId;
	if (selectedItemId === null) {
		return;
	}
	renderSnapshotStore.applySnapshotUpdate({
		workerPatches: [
			{
				slice: 'rowPaint',
				operation: 'delete',
				itemId: selectedItemId,
			},
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: selectedItemId,
				payload: { state: 'failed' },
			},
		],
	});
}

function bridgeWorkerFileViewContentMetadataFromDescriptor(
	descriptor: WorktreeFileDescriptor,
): BridgeWorkerFileViewContentMetadata {
	return bridgeWorkerFileViewContentMetadataSchema.parse({
		itemId: descriptor.fileId,
		path: descriptor.path,
		language: descriptor.language ?? null,
		cacheKey: bridgeFileViewerContentCacheKeyForDescriptor(descriptor),
		sizeBytes: descriptor.sizeBytes,
		contentHandle: descriptor.contentHandle,
		descriptorId: descriptor.contentDescriptor.ref.descriptorId,
		...(descriptor.contentHash === undefined ? {} : { contentHash: descriptor.contentHash }),
		virtualizedExtentKind: descriptor.virtualizedExtentKind,
		...(descriptor.lineCount === undefined ? {} : { lineCount: descriptor.lineCount }),
		isBinary: descriptor.isBinary,
		canFetchContent: canFetchWorktreeFileDescriptorContent(descriptor),
	});
}

function bridgeWorkerFileViewContentRequestDescriptorFromDescriptor(
	descriptor: WorktreeFileDescriptor,
): BridgeWorkerFileViewContentRequestDescriptor {
	return bridgeWorkerFileViewContentRequestDescriptorSchema.parse({
		itemId: descriptor.fileId,
		path: descriptor.path,
		handleId: descriptor.contentHandle,
		descriptorId: descriptor.contentDescriptor.ref.descriptorId,
		resourceKind: 'worktree.fileContent',
		resourceUrl: bridgeFileViewerCanonicalContentResourceUrlForDescriptor(descriptor),
		...(descriptor.contentHash === undefined
			? {}
			: {
					contentHash: descriptor.contentHash,
					contentHashAlgorithm: bridgeFileViewerContentHashAlgorithmForDescriptor(descriptor),
				}),
		language: descriptor.language ?? null,
		sizeBytes: descriptor.sizeBytes,
		maxBytes: descriptor.contentDescriptor.descriptor.content.maxBytes,
		isBinary: descriptor.isBinary,
	});
}

function bridgeCommWorkerRowIdFromWorktreeRow(row: WorktreeTreeRowMetadata): string {
	return row.fileId ?? row.rowId ?? row.path;
}

function bridgeFileViewerContentCacheKeyForDescriptor(descriptor: WorktreeFileDescriptor): string {
	return descriptor.contentHash === undefined
		? `${descriptor.contentHandle}:unknown`
		: `${descriptor.contentHandle}:${descriptor.contentHash}`;
}

function bridgeFileViewerContentHashAlgorithmForDescriptor(
	descriptor: WorktreeFileDescriptor,
): string {
	const integrity = descriptor.contentDescriptor.descriptor.content.integrity;
	return integrity?.kind === 'wholeHash' ? integrity.algorithm : 'sha256';
}

function bridgeFileViewerCanonicalContentResourceUrlForDescriptor(
	descriptor: WorktreeFileDescriptor,
): string {
	const parsedResourceUrl = parseBridgeResourceUrl(
		descriptor.contentDescriptor.descriptor.resourceUrl,
	);
	if (
		parsedResourceUrl?.kind === 'worktreeResource' &&
		parsedResourceUrl.resourceKind === 'worktree.fileContent' &&
		parsedResourceUrl.resourceId === descriptor.contentDescriptor.ref.descriptorId
	) {
		return parsedResourceUrl.canonicalUrl;
	}
	return [
		'agentstudio://resource/worktree-file/worktree.fileContent/',
		encodeURIComponent(descriptor.contentDescriptor.ref.descriptorId),
		'?cursor=',
		encodeURIComponent(descriptor.sourceIdentity.sourceCursor),
		'&generation=',
		encodeURIComponent(String(descriptor.sourceIdentity.subscriptionGeneration)),
	].join('');
}

export function bridgeFileViewerMinimumSelectedSlicePatchEpoch(props: {
	readonly selectedEpoch: number;
	readonly synchronizedSourceUpdateEpoch: number | null;
}): number {
	return props.synchronizedSourceUpdateEpoch ?? props.selectedEpoch;
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

export function publishBridgeFileViewerRefreshingStateToSnapshotStore(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
}): void {
	props.renderSnapshotStore.applySnapshotUpdate({
		localSelection: {
			selectedItemId: props.descriptor.fileId,
			source: 'programmatic',
		},
		workerPatches: [
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: props.descriptor.fileId,
				payload: { state: 'loading' },
			},
		],
	});
}

export function publishBridgeFileViewerLoadingStateToSnapshotStore(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
}): void {
	props.renderSnapshotStore.applySnapshotUpdate({
		localSelection: {
			selectedItemId: props.descriptor.fileId,
			source: 'programmatic',
		},
		codeViewItemPatches: [
			{
				operation: 'delete',
				itemId: props.descriptor.fileId,
			},
		],
		workerPatches: [
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: props.descriptor.fileId,
				payload: { state: 'loading' },
			},
		],
	});
}

export function publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore(props: {
	readonly item: BridgeFileViewerSelectedCodeViewItem;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
	readonly source: 'keyboard' | 'programmatic' | 'user';
}): void {
	props.renderSnapshotStore.applySnapshotUpdate({
		localSelection: {
			selectedItemId: props.item.bridgeMetadata.itemId,
			source: props.source,
		},
		codeViewItemPatches: [
			{
				operation: 'upsert',
				itemId: props.item.bridgeMetadata.itemId,
				item: props.item,
			},
		],
	});
}

export function selectedBridgeFileViewerCodeViewItemForSnapshot(props: {
	readonly openFileState: BridgeFileViewerOpenState;
	readonly renderSnapshot: BridgeMainRenderSnapshot;
}): BridgeFileViewerSelectedCodeViewItem | null {
	if (
		props.openFileState.status === 'idle' ||
		props.openFileState.status === 'failed' ||
		props.openFileState.status === 'unavailable'
	) {
		return null;
	}
	const descriptor = props.openFileState.descriptor;
	if (props.renderSnapshot.selectionSlice.selectedItemId !== descriptor.fileId) {
		return null;
	}
	const item = props.renderSnapshot.codeViewItemsById[descriptor.fileId];
	if (
		item === undefined ||
		item.type !== 'file' ||
		item.bridgeMetadata.itemId !== descriptor.fileId ||
		item.bridgeMetadata.displayPath !== descriptor.path ||
		!item.bridgeMetadata.contentRoles.includes('file')
	) {
		return null;
	}
	if (bridgeFileViewerCodeViewItemMatchesDescriptor({ descriptor, item })) {
		return item;
	}
	return props.openFileState.status === 'refreshing' || props.openFileState.status === 'stale'
		? item
		: null;
}

export function selectedBridgeFileViewerReadyCodeViewItemForSnapshot(props: {
	readonly openFileState: BridgeFileViewerOpenState;
	readonly renderSnapshot: BridgeMainRenderSnapshot;
}): BridgeFileViewerSelectedCodeViewItem | null {
	if (
		props.openFileState.status === 'idle' ||
		props.openFileState.status === 'failed' ||
		props.openFileState.status === 'unavailable'
	) {
		return null;
	}
	const descriptor = props.openFileState.descriptor;
	if (props.renderSnapshot.selectionSlice.selectedItemId !== descriptor.fileId) {
		return null;
	}
	const item = props.renderSnapshot.codeViewItemsById[descriptor.fileId];
	if (
		item === undefined ||
		item.type !== 'file' ||
		item.bridgeMetadata.itemId !== descriptor.fileId ||
		item.bridgeMetadata.displayPath !== descriptor.path ||
		!item.bridgeMetadata.contentRoles.includes('file') ||
		!bridgeFileViewerCodeViewItemMatchesDescriptor({ descriptor, item })
	) {
		return null;
	}
	return item;
}

export function bridgeFileViewerCodeViewItemMatchesDescriptor(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly item: BridgeFileViewerSelectedCodeViewItem;
}): boolean {
	const expectedCacheKeyPrefix =
		props.descriptor.contentHash === undefined
			? `${props.descriptor.contentHandle}:`
			: `${props.descriptor.contentHandle}:${props.descriptor.contentHash}`;
	return (
		props.item.bridgeMetadata.cacheKey === expectedCacheKeyPrefix ||
		props.item.bridgeMetadata.cacheKey.startsWith(
			props.descriptor.contentHash === undefined
				? expectedCacheKeyPrefix
				: `${expectedCacheKeyPrefix}:`,
		)
	);
}
