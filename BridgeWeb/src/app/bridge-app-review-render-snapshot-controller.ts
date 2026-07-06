import type { MutableRefObject } from 'react';
import { useCallback, useEffect, useMemo, useRef, useSyncExternalStore } from 'react';

import {
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type { BridgeCommWorkerRow } from '../core/comm-worker/bridge-comm-worker-store.js';
import {
	createBridgeMainRenderSnapshotStore,
	type BridgeMainCodeViewItem,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeCommWorkerBootstrapRequest,
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerMainToServerMessage,
	BridgeWorkerReviewContentRequestDescriptor,
	BridgeWorkerReviewContentMetadata,
	BridgeWorkerReviewRenderSemantics,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	bridgeCommWorkerBootstrapRequestSchema,
	bridgeWorkerReviewContentRequestDescriptorSchema,
	bridgeWorkerReviewContentMetadataSchema,
	bridgeWorkerReviewRenderSemanticsSchema,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	createBridgeWorkerPierreCourier,
	type BridgeWorkerPierreCourier,
} from '../core/comm-worker/bridge-worker-pierre-courier.js';
import type {
	BridgeWorkerDemandRank,
	BridgeWorkerPierreRenderBudget,
	BridgeWorkerPierreRenderJob,
} from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import { bridgeWorkerPierreRenderPolicy } from '../core/demand/bridge-content-demand-policy.js';
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
import {
	createBridgeReviewCommWorkerTransportDispatcher,
	type BridgeReviewCommWorkerTransportDispatcher,
} from '../review-viewer/workers/shared-rpc/bridge-comm-worker-transport.js';

export interface UseBridgeReviewRenderSnapshotControllerProps {
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly pierreCourier: BridgeWorkerPierreCourier;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
}

export interface BridgeReviewRenderSnapshotController {
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
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
	const selectedRawContentAvailability =
		selectionSlice.selectedItemId === null
			? null
			: (renderSnapshot.contentAvailabilityById[selectionSlice.selectedItemId] ?? null);
	const selectedCodeViewItem = selectedBridgeCodeViewItemForReviewPackage({
		codeViewItemsById: renderSnapshot.codeViewItemsById,
		reviewPackage: props.reviewPackage,
		selectedItemId: selectionSlice.selectedItemId,
	});
	const selectedContentAvailability = selectedContentAvailabilityForReviewPackage({
		rawAvailability: selectedRawContentAvailability,
		selectedCodeViewItem,
	});
	const pierreCourier = props.pierreCourier;
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
	const runtimeDispatcher = useMemo(
		(): BridgeReviewRuntimeProtocolDispatcher =>
			createBridgeReviewRuntimeProtocolDispatcher({
				contentItems: bridgeCommWorkerContentItemsFromReviewPackage(props.reviewPackage),
				contentRequestDescriptors: bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(
					props.reviewPackage,
				),
				publishWorkerMessages,
				renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(props.reviewPackage),
				rows: bridgeCommWorkerRowsFromReviewTreeRows(props.reviewTreeRows),
			}),
		[publishWorkerMessages, props.reviewPackage, props.reviewTreeRows],
	);
	useEffect(
		(): (() => void) => (): void => {
			runtimeDispatcher.dispose();
		},
		[runtimeDispatcher],
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
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerSelectCommand({
					requestId: nextBridgeReviewWorkerRequestId(requestSequenceRef),
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					selectedItemId: itemId,
					selectedSource: 'user',
				}),
			);
		},
		[renderSnapshotStore, runtimeDispatcher],
	);
	const setReviewViewportItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			const lastVisibleIndex = itemIds.length === 0 ? 0 : itemIds.length - 1;
			renderSnapshotStore.setLocalViewport({
				firstVisibleIndex: 0,
				lastVisibleIndex,
				visibleItemIds: itemIds,
			});
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerViewportCommand({
					requestId: nextBridgeReviewWorkerRequestId(requestSequenceRef),
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					visibleItemIds: itemIds,
					firstVisibleIndex: 0,
					lastVisibleIndex,
					phase: 'settled',
				}),
			);
		},
		[renderSnapshotStore, runtimeDispatcher],
	);
	return {
		rootSnapshot,
		selectedCodeViewItem,
		selectedContentAvailability,
		selectionSlice,
		selectionSliceRef,
		setReviewViewportItemIds,
		setSelectedReviewItemId,
		viewportSliceRef,
	};
}

export function selectedBridgeCodeViewItemForReviewPackage(props: {
	readonly codeViewItemsById: Readonly<Record<string, BridgeMainCodeViewItem>>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
}): BridgeMainCodeViewItem | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	const item = props.reviewPackage.itemsById[props.selectedItemId];
	const codeViewItem = props.codeViewItemsById[props.selectedItemId];
	if (
		item === undefined ||
		codeViewItem === undefined ||
		codeViewItem.bridgeMetadata.itemId !== props.selectedItemId
	) {
		return null;
	}
	return codeViewItemCacheMatchesReviewItem(item, codeViewItem) ? codeViewItem : null;
}

export function selectedContentAvailabilityForReviewPackage(props: {
	readonly rawAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
}): BridgeWorkerContentAvailabilityPatchPayload | null {
	if (props.rawAvailability?.state !== 'ready') {
		return props.rawAvailability;
	}
	return props.selectedCodeViewItem === null ? { state: 'loading' } : props.rawAvailability;
}

function codeViewItemCacheMatchesReviewItem(
	item: BridgeReviewItemDescriptor,
	codeViewItem: BridgeMainCodeViewItem,
): boolean {
	if (codeViewItem.type === 'file') {
		const role = codeViewItem.bridgeMetadata.contentRoles[0];
		if (role === undefined) {
			return false;
		}
		const expectedCacheKey = pierreContentCacheKeyForReviewRole(item, role);
		return expectedCacheKey !== null && codeViewItem.bridgeMetadata.cacheKey === expectedCacheKey;
	}
	const roles = codeViewItem.bridgeMetadata.contentRoles;
	const hasBase = roles.includes('base');
	const hasHead = roles.includes('head');
	if (!hasBase && !hasHead) {
		return false;
	}
	const baseCacheKey = hasBase
		? pierreContentCacheKeyForReviewRole(item, 'base')
		: 'pierre-content:empty';
	const headCacheKey = hasHead
		? pierreContentCacheKeyForReviewRole(item, 'head')
		: 'pierre-content:empty';
	if (baseCacheKey === null || headCacheKey === null) {
		return false;
	}
	return codeViewItem.bridgeMetadata.cacheKey === `${baseCacheKey}|${headCacheKey}`;
}

function pierreContentCacheKeyForReviewRole(
	item: BridgeReviewItemDescriptor,
	role: BridgeContentRole,
): string | null {
	const handle = reviewContentHandleForRole(item, role);
	return handle === null
		? null
		: `pierre-content:${handle.contentHashAlgorithm}:${handle.contentHash}`;
}

function reviewContentHandleForRole(
	item: BridgeReviewItemDescriptor,
	role: BridgeContentRole,
): BridgeContentHandle | null {
	const directHandle = item.contentRoles[role];
	if (directHandle !== null && directHandle !== undefined) {
		return directHandle;
	}
	return (
		Object.values(item.contentRoles).find(
			(handle): handle is BridgeContentHandle =>
				handle !== null && handle !== undefined && handle.role === role,
		) ?? null
	);
}

function bridgeCommWorkerRowsFromReviewTreeRows(
	rows: readonly ReviewTreeRowMetadata[],
): readonly BridgeCommWorkerRow[] {
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

export function bridgeCommWorkerRenderSemanticsFromReviewPackage(
	reviewPackage: BridgeReviewPackage | null,
): readonly BridgeWorkerReviewRenderSemantics[] {
	if (reviewPackage === null) {
		return [];
	}
	return reviewPackage.orderedItemIds.flatMap(
		(itemId): readonly BridgeWorkerReviewRenderSemantics[] => {
			const item = reviewPackage.itemsById[itemId];
			if (item === undefined) {
				return [];
			}
			return [bridgeWorkerReviewRenderSemanticsFromReviewItem(item)];
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

export interface BridgeReviewRuntimeProtocolDispatcher {
	readonly dispatch: (message: BridgeWorkerMainToServerMessage) => void;
	readonly dispose: () => void;
}

export interface CreateBridgeReviewRuntimeProtocolDispatcherProps {
	readonly bootstrapRequestId?: string;
	readonly bridgeDemandRank?: BridgeWorkerDemandRank;
	readonly budget?: BridgeWorkerPierreRenderBudget;
	readonly contentItems: readonly BridgeWorkerReviewContentMetadata[];
	readonly contentRequestDescriptors: readonly BridgeWorkerReviewContentRequestDescriptor[];
	readonly maxPreparationSliceMs?: number;
	readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	readonly renderSemantics: readonly BridgeWorkerReviewRenderSemantics[];
	readonly rows: readonly BridgeCommWorkerRow[];
	readonly transportFactory?: (props: {
		readonly bootstrapRequest: BridgeCommWorkerBootstrapRequest;
		readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	}) => BridgeReviewCommWorkerTransportDispatcher;
}

export function createBridgeReviewRuntimeProtocolDispatcher(
	props: CreateBridgeReviewRuntimeProtocolDispatcherProps,
): BridgeReviewRuntimeProtocolDispatcher {
	const bootstrapRequest = bridgeCommWorkerBootstrapRequestFromReviewRuntimeProps({
		...props,
		requestId: props.bootstrapRequestId ?? 'review-worker-bootstrap',
	});
	return (props.transportFactory ?? createBridgeReviewCommWorkerTransportDispatcher)({
		bootstrapRequest,
		publishWorkerMessages: props.publishWorkerMessages,
	});
}

export function bridgeCommWorkerBootstrapRequestFromReviewRuntimeProps(
	props: CreateBridgeReviewRuntimeProtocolDispatcherProps & {
		readonly requestId: string;
	},
): BridgeCommWorkerBootstrapRequest {
	return bridgeCommWorkerBootstrapRequestSchema.parse({
		schemaVersion: 1,
		method: 'bridgeCommWorker.bootstrap',
		requestId: props.requestId,
		runtime: {
			bridgeDemandRank: props.bridgeDemandRank ?? bridgeReviewRuntimeInteractiveDemandRank,
			budget: props.budget ?? bridgeReviewRuntimeInteractiveBudget,
			contentItems: props.contentItems,
			contentRequestDescriptors: props.contentRequestDescriptors,
			renderSemantics: props.renderSemantics,
			rows: props.rows,
			...(props.maxPreparationSliceMs === undefined
				? {}
				: { maxPreparationSliceMs: props.maxPreparationSliceMs }),
		},
	});
}

const bridgeReviewRuntimeInteractiveDemandRank: BridgeWorkerDemandRank = {
	lane: 'selected',
	priority: 0,
};

const bridgeReviewRuntimeInteractiveBudget: BridgeWorkerPierreRenderBudget = {
	...bridgeWorkerPierreRenderPolicy.interactiveRenderBudget,
};

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

function bridgeWorkerReviewRenderSemanticsFromReviewItem(
	item: BridgeReviewItemDescriptor,
): BridgeWorkerReviewRenderSemantics {
	return bridgeWorkerReviewRenderSemanticsSchema.parse({
		itemId: item.itemId,
		itemKind: item.itemKind,
		changeKind: item.changeKind,
		displayPath: displayPathForReviewItem(item),
		basePath: item.basePath ?? null,
		headPath: item.headPath ?? null,
		language: item.language ?? null,
		contentLineCountsByRole: item.contentLineCountsByRole ?? {},
	});
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

function displayPathForReviewItem(item: BridgeReviewItemDescriptor): string {
	return item.headPath ?? item.basePath ?? item.itemId;
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
				props.renderSnapshotStore.setWorkerCodeViewItem({
					itemId: message.job.itemId,
					item: message.job.payload.item,
				});
				break;
			default:
				assertNeverBridgeWorkerServerMessage(message);
		}
	}
}

export function createBridgeReviewWorkerPierreCourier(): BridgeWorkerPierreCourier {
	return createBridgeWorkerPierreCourier({
		enqueuePierreRenderJob: (job: BridgeWorkerPierreRenderJob) => ({
			status: 'enqueued',
			itemId: job.itemId,
			payloadByteLength: job.payloadByteLength,
			budgetClass: job.budgetClass,
		}),
	});
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
