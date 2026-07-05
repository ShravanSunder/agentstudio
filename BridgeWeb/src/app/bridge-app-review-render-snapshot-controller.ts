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
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	bridgeWorkerReviewContentRequestDescriptorSchema,
	bridgeWorkerReviewContentMetadataSchema,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	createBridgeWorkerPierreCourier,
	type BridgeWorkerPierreCourier,
} from '../core/comm-worker/bridge-worker-pierre-courier.js';
import type { BridgeWorkerPierreRenderJob } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { ReviewTreeRowMetadata } from '../features/review/models/review-protocol-models.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import type {
	BridgeReviewPanelChromeSlice,
	BridgeReviewSelectionSlice,
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewportSlice,
} from '../review-viewer/state/review-viewer-store.js';
import { bridgeReviewViewerRootSnapshotFromSlices } from '../review-viewer/state/review-viewer-store.js';

export interface UseBridgeReviewRenderSnapshotControllerProps {
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly pierreCourier?: BridgeWorkerPierreCourier;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
}

export interface BridgeReviewRenderSnapshotController {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
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
	const selectedContentAvailability =
		selectionSlice.selectedItemId === null
			? null
			: (renderSnapshot.contentAvailabilityById[selectionSlice.selectedItemId] ?? null);
	const commandHandler = useMemo(
		(): BridgeCommWorkerCommandHandler =>
			createBridgeCommWorkerCommandHandler({
				contentItems: bridgeCommWorkerContentItemsFromReviewPackage(props.reviewPackage),
				rows: bridgeCommWorkerRowsFromReviewTreeRows(props.reviewTreeRows),
			}),
		[props.reviewPackage, props.reviewTreeRows],
	);
	const pierreCourier = useMemo(
		(): BridgeWorkerPierreCourier =>
			props.pierreCourier ?? createUnsupportedBridgeReviewPierreCourier(),
		[props.pierreCourier],
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
				pierreCourier,
				renderSnapshotStore,
			});
		},
		[pierreCourier, renderSnapshotStore],
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
		selectedContentAvailability,
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

export function bridgeCommWorkerContentItemsFromReviewPackage(
	reviewPackage: BridgeReviewPackage | null,
): readonly BridgeWorkerReviewContentMetadata[] {
	if (reviewPackage === null) {
		return [];
	}
	return reviewPackage.orderedItemIds.flatMap(
		(itemId): readonly BridgeWorkerReviewContentMetadata[] => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				return [];
			}
			return [bridgeWorkerReviewContentMetadataFromReviewItem(item)];
		},
	);
}

export function bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(
	reviewPackage: BridgeReviewPackage | null,
): readonly BridgeWorkerReviewContentRequestDescriptor[] {
	if (reviewPackage === null) {
		return [];
	}
	return reviewPackage.orderedItemIds.flatMap(
		(itemId): readonly BridgeWorkerReviewContentRequestDescriptor[] => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				return [];
			}
			return contentRequestDescriptorsForReviewItem(item);
		},
	);
}

function bridgeWorkerReviewContentMetadataFromReviewItem(
	item: BridgeReviewItemDescriptor,
): BridgeWorkerReviewContentMetadata {
	return bridgeWorkerReviewContentMetadataSchema.parse({
		itemId: item.itemId,
		path: item.headPath ?? item.basePath ?? item.itemId,
		language: item.language ?? null,
		cacheKey: item.cacheKey,
		sizeBytes: item.sizeBytes,
		availableContentRoles: availableContentRolesForReviewItem(item),
		contentLineCountsByRole: item.contentLineCountsByRole ?? {},
	});
}

function availableContentRolesForReviewItem(
	item: BridgeReviewItemDescriptor,
): readonly BridgeContentRole[] {
	const roles: BridgeContentRole[] = [];
	for (const role of ['base', 'head', 'diff', 'file'] as const) {
		if (item.contentRoles[role] !== null && item.contentRoles[role] !== undefined) {
			roles.push(role);
		}
	}
	return roles;
}

function contentRequestDescriptorsForReviewItem(
	item: BridgeReviewItemDescriptor,
): readonly BridgeWorkerReviewContentRequestDescriptor[] {
	const descriptors: BridgeWorkerReviewContentRequestDescriptor[] = [];
	for (const role of ['base', 'head', 'diff', 'file'] as const) {
		const handle = item.contentRoles[role] ?? null;
		if (handle !== null) {
			descriptors.push(bridgeWorkerReviewContentRequestDescriptorFromHandle(handle));
		}
	}
	return descriptors;
}

function bridgeWorkerReviewContentRequestDescriptorFromHandle(
	handle: BridgeContentHandle,
): BridgeWorkerReviewContentRequestDescriptor {
	return bridgeWorkerReviewContentRequestDescriptorSchema.parse({
		itemId: handle.itemId,
		role: handle.role,
		handleId: handle.handleId,
		reviewGeneration: handle.reviewGeneration,
		resourceUrl: handle.resourceUrl,
		contentHash: handle.contentHash,
		contentHashAlgorithm: handle.contentHashAlgorithm,
		language: handle.language ?? null,
		sizeBytes: handle.sizeBytes,
		isBinary: handle.isBinary,
	});
}

export function applyBridgeWorkerMessagesToMainRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly pierreCourier: BridgeWorkerPierreCourier;
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
				break;
			case 'pierreRenderJob':
				props.pierreCourier.enqueue(message.job);
				break;
			default:
				assertNeverBridgeWorkerServerMessage(message);
		}
	}
}

export function createUnsupportedBridgeReviewPierreCourier(): BridgeWorkerPierreCourier {
	return createBridgeWorkerPierreCourier({
		enqueuePierreRenderJob: rejectUnsupportedBridgeWorkerPierreRenderJob,
	});
}

function rejectUnsupportedBridgeWorkerPierreRenderJob(job: BridgeWorkerPierreRenderJob): never {
	throw new Error(
		`Bridge Review received worker Pierre render job ${job.itemId} before a Pierre adapter was installed.`,
	);
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
