import type { MutableRefObject } from 'react';
import { useCallback, useMemo, useRef, useSyncExternalStore } from 'react';

import {
	createBridgeCommWorkerCommandHandler,
	type BridgeCommWorkerCommandHandler,
} from '../core/comm-worker/bridge-comm-worker-command-handler.js';
import {
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import type {
	BridgeReviewPanelChromeSlice,
	BridgeReviewSelectionSlice,
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewportSlice,
} from '../review-viewer/state/review-viewer-store.js';
import { bridgeReviewViewerRootSnapshotFromSlices } from '../review-viewer/state/review-viewer-store.js';

export interface UseBridgeReviewRenderSnapshotControllerProps {
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
}

export interface BridgeReviewRenderSnapshotController {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectionSlice: BridgeReviewSelectionSlice;
	readonly selectionSliceRef: MutableRefObject<BridgeReviewSelectionSlice>;
	readonly setReviewViewportItemIds: (itemIds: readonly string[]) => void;
	readonly setSelectedReviewItemId: (itemId: string | null) => void;
	readonly viewportSliceRef: MutableRefObject<BridgeReviewViewportSlice>;
}

export function useBridgeReviewRenderSnapshotController(
	props: UseBridgeReviewRenderSnapshotControllerProps,
): BridgeReviewRenderSnapshotController {
	const renderSnapshotStore = useMemo(() => createBridgeMainRenderSnapshotStore(), []);
	const renderSnapshot = useSyncExternalStore(
		renderSnapshotStore.subscribe,
		renderSnapshotStore.getSnapshot,
		renderSnapshotStore.getServerSnapshot,
	);
	const selectionSlice = useMemo(
		(): BridgeReviewSelectionSlice => ({
			selectedItemId: renderSnapshot.selectionSlice.selectedItemId,
		}),
		[renderSnapshot.selectionSlice.selectedItemId],
	);
	const viewportSlice = useMemo(
		(): BridgeReviewViewportSlice => ({
			visibleItemIds: renderSnapshot.viewportSlice.visibleItemIds,
		}),
		[renderSnapshot.viewportSlice.visibleItemIds],
	);
	const rootSnapshot = useMemo(
		(): BridgeReviewViewerRootSnapshot =>
			bridgeReviewViewerRootSnapshotFromSlices({
				panelChromeSlice: props.panelChromeSlice,
				selectionSlice,
			}),
		[props.panelChromeSlice, selectionSlice],
	);
	const commandHandler = useMemo(
		(): BridgeCommWorkerCommandHandler =>
			createBridgeCommWorkerCommandHandler({
				rows: bridgeCommWorkerRowsFromReviewTreeRows(props.reviewTreeRows),
			}),
		[props.reviewTreeRows],
	);
	const requestSequenceRef = useRef(0);
	const workerEpochRef = useRef(0);
	const selectionSliceRef = useRef(selectionSlice);
	selectionSliceRef.current = selectionSlice;
	const viewportSliceRef = useRef(viewportSlice);
	viewportSliceRef.current = viewportSlice;

	const publishWorkerMessages = useCallback(
		(messages: readonly BridgeWorkerServerToMainMessage[]): void => {
			applyBridgeWorkerMessagesToMainRenderSnapshotStore({
				messages,
				renderSnapshotStore,
			});
		},
		[renderSnapshotStore],
	);
	const setSelectedReviewItemId = useCallback(
		(itemId: string | null): void => {
			if (itemId === null) {
				renderSnapshotStore.applyWorkerPatch({
					slice: 'selection',
					operation: 'delete',
				});
				return;
			}
			renderSnapshotStore.setLocalSelection({
				selectedItemId: itemId,
				source: 'user',
			});
			publishWorkerMessages(
				commandHandler.handleMessage(
					encodeBridgeWorkerSelectCommand({
						requestId: nextBridgeReviewWorkerRequestId(requestSequenceRef),
						epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
						selectedItemId: itemId,
						selectedSource: 'user',
					}),
				),
			);
		},
		[commandHandler, publishWorkerMessages, renderSnapshotStore],
	);
	const setReviewViewportItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			const lastVisibleIndex = itemIds.length === 0 ? 0 : itemIds.length - 1;
			renderSnapshotStore.setLocalViewport({
				firstVisibleIndex: 0,
				lastVisibleIndex,
				visibleItemIds: itemIds,
			});
			publishWorkerMessages(
				commandHandler.handleMessage(
					encodeBridgeWorkerViewportCommand({
						requestId: nextBridgeReviewWorkerRequestId(requestSequenceRef),
						epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
						visibleItemIds: itemIds,
						firstVisibleIndex: 0,
						lastVisibleIndex,
						phase: 'settled',
					}),
				),
			);
		},
		[commandHandler, publishWorkerMessages, renderSnapshotStore],
	);

	return {
		rootSnapshot,
		selectionSlice,
		selectionSliceRef,
		setReviewViewportItemIds,
		setSelectedReviewItemId,
		viewportSliceRef,
	};
}

function bridgeCommWorkerRowsFromReviewTreeRows(
	rows: readonly ReviewTreeRowMetadata[],
): readonly { readonly id: string; readonly parentId: string | null; readonly index: number }[] {
	return rows.map((row, index) => ({
		id: row.itemId ?? row.rowId,
		parentId: null,
		index,
	}));
}

function applyBridgeWorkerMessagesToMainRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
}): void {
	for (const message of props.messages) {
		switch (message.kind) {
			case 'slicePatch':
				for (const patch of message.patches) {
					props.renderSnapshotStore.applyWorkerPatch(patch);
				}
				break;
			case 'health':
			case 'subscription':
			case 'pierreRenderJob':
				break;
			default:
				assertNeverBridgeWorkerServerMessage(message);
		}
	}
}

function nextBridgeReviewWorkerRequestId(requestSequenceRef: MutableRefObject<number>): string {
	requestSequenceRef.current += 1;
	return `review-worker-command-${requestSequenceRef.current}`;
}

function nextBridgeReviewWorkerEpoch(workerEpochRef: MutableRefObject<number>): number {
	workerEpochRef.current += 1;
	return workerEpochRef.current;
}

function assertNeverBridgeWorkerServerMessage(_message: never): never {
	throw new Error('Unhandled bridge worker server message.');
}
