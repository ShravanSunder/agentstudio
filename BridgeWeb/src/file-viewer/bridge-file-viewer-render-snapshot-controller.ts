import { useCallback, useMemo, useSyncExternalStore } from 'react';

import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshot,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	bridgeFileViewerSelectedCodeViewItemForPanelState,
	type BridgeFileViewerCodePanelState,
	type BridgeFileViewerSelectedCodeViewItem,
} from './bridge-file-viewer-code-view-items.js';
import type { BridgeFileViewerOpenState } from './bridge-file-viewer-state.js';

export interface BridgeFileViewerRenderSnapshotController {
	readonly publishOpenFileContent: (props: PublishBridgeFileViewerOpenFileContentProps) => void;
	readonly publishOpenFileLoadingState: (descriptor: WorktreeFileDescriptor) => void;
	readonly publishOpenFileRefreshingState: (descriptor: WorktreeFileDescriptor) => void;
	readonly publishOpenFileTerminalState: (props: {
		readonly descriptor: WorktreeFileDescriptor;
		readonly state: 'failed' | 'stale' | 'unavailable';
	}) => void;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
}

export interface PublishBridgeFileViewerOpenFileContentProps {
	readonly body: string;
	readonly bodyVersion: number;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
	readonly state: Extract<
		BridgeFileViewerCodePanelState['status'],
		'loading' | 'ready' | 'refreshing'
	>;
}

export function useBridgeFileViewerRenderSnapshotController(props: {
	readonly openFileState: BridgeFileViewerOpenState;
}): BridgeFileViewerRenderSnapshotController {
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
	const publishOpenFileContent = useCallback(
		(content: PublishBridgeFileViewerOpenFileContentProps): void => {
			const item = bridgeFileViewerSelectedCodeViewItemForPanelState({
				openFileState: {
					status: content.state,
					path: content.path,
					descriptor: content.descriptor,
				},
				renderedFileContent: {
					body: content.body,
					bodyVersion: content.bodyVersion,
					descriptor: content.descriptor,
					path: content.path,
				},
			});
			if (item === null) {
				return;
			}
			publishBridgeFileViewerSelectedCodeViewItemToSnapshotStore({
				contentAvailabilityState: content.state === 'ready' ? 'ready' : 'loading',
				item,
				renderSnapshotStore,
				source: 'programmatic',
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
				workerPatches: [
					{
						slice: 'contentAvailability',
						operation: 'upsert',
						itemId: terminalState.descriptor.fileId,
						payload: { state: terminalState.state },
					},
				],
			});
		},
		[renderSnapshotStore],
	);

	return {
		publishOpenFileContent,
		publishOpenFileLoadingState,
		publishOpenFileRefreshingState,
		publishOpenFileTerminalState,
		selectedCodeViewItem,
	};
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
	readonly contentAvailabilityState?: 'loading' | 'ready';
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
		workerPatches: [
			{
				slice: 'contentAvailability',
				operation: 'upsert',
				itemId: props.item.bridgeMetadata.itemId,
				payload: { state: props.contentAvailabilityState ?? 'ready' },
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

function bridgeFileViewerCodeViewItemMatchesDescriptor(props: {
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
