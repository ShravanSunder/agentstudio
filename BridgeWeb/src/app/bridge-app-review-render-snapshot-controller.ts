import type { MutableRefObject } from 'react';
import { useCallback, useEffect, useMemo, useRef, useSyncExternalStore } from 'react';

import {
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerMetadataInterestUpdateCommand,
	encodeBridgeWorkerReviewIntakeReadyCommand,
	encodeBridgeWorkerReviewInvalidateCommand,
	encodeBridgeWorkerReviewSourceUpdateCommand,
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
	BridgeCommWorkerTelemetryBootstrapConfig,
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
import type { ReviewInvalidationFrame } from '../features/review/models/review-protocol-models.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryBootstrapConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
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
import type { ReviewMetadataInterestRequest } from './bridge-app-review-metadata-interest-controller.js';
import {
	resolveBridgeWorkerMarkFileViewedFailureCallbacks,
	resolveBridgeWorkerMetadataInterestRequestResolvers,
	resolveBridgeWorkerReviewIntakeReadyRequestResolvers,
} from './bridge-app-review-worker-health-resolvers.js';
import { bridgeReviewContentByteBoundsForHandle } from './bridge-review-content-byte-budget.js';

export interface UseBridgeReviewRenderSnapshotControllerProps {
	readonly panelChromeSlice: BridgeReviewPanelChromeSlice;
	readonly pierreCourier: BridgeWorkerPierreCourier;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
	readonly telemetryConfig: BridgeTelemetryBootstrapConfig | null;
	readonly transportFactory?: CreateBridgeReviewRuntimeProtocolDispatcherProps['transportFactory'];
}

export interface BridgeReviewRenderSnapshotController {
	readonly invalidateReviewContent: (frame: ReviewInvalidationFrame) => void;
	readonly markFileViewed: (itemId: string, onDeliveryFailure?: () => void) => boolean;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectionSlice: BridgeReviewSelectionSlice;
	readonly selectionSliceRef: MutableRefObject<BridgeReviewSelectionSlice>;
	readonly setReviewViewportItemIds: (itemIds: readonly string[]) => void;
	readonly sendMetadataInterestRequest: (
		request: ReviewMetadataInterestRequest,
	) => Promise<boolean>;
	readonly sendReviewIntakeReady: (props: {
		readonly reason: string | null;
		readonly streamId: string | null;
	}) => Promise<boolean>;
	readonly setSelectedReviewItemId: (itemId: string | null) => void;
	readonly synchronizeReviewSource: (source: BridgeReviewRuntimeSourceSnapshot) => void;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[];
	readonly viewportSliceRef: MutableRefObject<BridgeReviewViewportSlice>;
}

export interface BridgeReviewRuntimeSourceSnapshot {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly reviewTreeRows: readonly ReviewTreeRowMetadata[];
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
	const visibleCodeViewItems = visibleBridgeCodeViewItemsForReviewPackage({
		codeViewItemsById: renderSnapshot.codeViewItemsById,
		reviewPackage: props.reviewPackage,
		visibleItemIds: viewportSlice.visibleItemIds,
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
	const markFileViewedFailureCallbacksRef = useRef<Map<string, () => void>>(new Map());
	const reviewIntakeReadyRequestResolversRef = useRef<Map<string, (didSend: boolean) => void>>(
		new Map(),
	);
	const metadataInterestRequestResolversRef = useRef<Map<string, (didSend: boolean) => void>>(
		new Map(),
	);

	const publishWorkerMessages = useCallback(
		(messages: readonly BridgeWorkerServerToMainMessage[]): void => {
			resolveBridgeWorkerMarkFileViewedFailureCallbacks({
				failureCallbacksByRequestId: markFileViewedFailureCallbacksRef.current,
				messages,
			});
			resolveBridgeWorkerMetadataInterestRequestResolvers({
				messages,
				resolversByRequestId: metadataInterestRequestResolversRef.current,
			});
			resolveBridgeWorkerReviewIntakeReadyRequestResolvers({
				messages,
				resolversByRequestId: reviewIntakeReadyRequestResolversRef.current,
			});
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
				contentItems: [],
				contentRequestDescriptors: [],
				publishWorkerMessages,
				renderSemantics: [],
				rows: [],
				...(props.telemetryConfig === null ? {} : { telemetryConfig: props.telemetryConfig }),
				...(props.transportFactory === undefined
					? {}
					: { transportFactory: props.transportFactory }),
			}),
		[publishWorkerMessages, props.telemetryConfig, props.transportFactory],
	);
	const latestReviewSourceRef = useRef<BridgeReviewRuntimeSourceSnapshot>({
		reviewPackage: props.reviewPackage,
		reviewTreeRows: props.reviewTreeRows,
	});
	latestReviewSourceRef.current = {
		reviewPackage: props.reviewPackage,
		reviewTreeRows: props.reviewTreeRows,
	};
	const synchronizedReviewSourceRef = useRef<BridgeReviewRuntimeSourceSnapshot | null>(null);
	useEffect((): void => {
		synchronizedReviewSourceRef.current = null;
	}, [runtimeDispatcher]);
	useEffect(
		(): (() => void) => (): void => {
			runtimeDispatcher.dispose();
		},
		[runtimeDispatcher],
	);
	const synchronizeReviewSource = useCallback(
		(source: BridgeReviewRuntimeSourceSnapshot): void => {
			latestReviewSourceRef.current = source;
			const synchronizedSource = synchronizedReviewSourceRef.current;
			if (
				synchronizedSource?.reviewPackage === source.reviewPackage &&
				synchronizedSource.reviewTreeRows === source.reviewTreeRows
			) {
				return;
			}
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerReviewSourceUpdateCommand({
					requestId: nextBridgeReviewWorkerRequestId(requestSequenceRef),
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					contentItems: bridgeCommWorkerContentItemsFromReviewPackage(source.reviewPackage),
					contentRequestDescriptors: bridgeCommWorkerContentRequestDescriptorsFromReviewPackage(
						source.reviewPackage,
					),
					renderSemantics: bridgeCommWorkerRenderSemanticsFromReviewPackage(source.reviewPackage),
					rows: bridgeCommWorkerRowsFromReviewTreeRows(source.reviewTreeRows),
				}),
			);
			synchronizedReviewSourceRef.current = source;
		},
		[runtimeDispatcher],
	);
	const synchronizeLatestReviewSource = useCallback((): void => {
		synchronizeReviewSource(latestReviewSourceRef.current);
	}, [synchronizeReviewSource]);
	useEffect((): void => {
		synchronizeLatestReviewSource();
	}, [synchronizeLatestReviewSource, props.reviewPackage, props.reviewTreeRows]);
	const setSelectedReviewItemId = useCallback(
		(itemId: string | null): void => {
			if (itemId === null) {
				renderSnapshotStore.applyWorkerPatch({
					slice: 'selection',
					operation: 'delete',
				});
				return;
			}
			synchronizeLatestReviewSource();
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
		[renderSnapshotStore, runtimeDispatcher, synchronizeLatestReviewSource],
	);
	const markFileViewed = useCallback(
		(itemId: string, onDeliveryFailure?: () => void): boolean => {
			if (props.reviewPackage === null || !(itemId in props.reviewPackage.itemsById)) {
				return false;
			}
			const requestId = nextBridgeReviewWorkerRequestId(requestSequenceRef);
			if (onDeliveryFailure !== undefined) {
				markFileViewedFailureCallbacksRef.current.set(requestId, onDeliveryFailure);
			}
			synchronizeLatestReviewSource();
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerMarkFileViewedCommand({
					requestId,
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					fileId: itemId,
				}),
			);
			return true;
		},
		[props.reviewPackage, runtimeDispatcher, synchronizeLatestReviewSource],
	);
	const sendMetadataInterestRequest = useCallback(
		(request: ReviewMetadataInterestRequest): Promise<boolean> => {
			const requestId = nextBridgeReviewWorkerRequestId(requestSequenceRef);
			const completion = new Promise<boolean>((resolve): void => {
				metadataInterestRequestResolversRef.current.set(requestId, resolve);
			});
			synchronizeLatestReviewSource();
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerMetadataInterestUpdateCommand({
					requestId,
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					request,
				}),
			);
			return completion;
		},
		[runtimeDispatcher, synchronizeLatestReviewSource],
	);
	const sendReviewIntakeReady = useCallback(
		(request: {
			readonly reason: string | null;
			readonly streamId: string | null;
		}): Promise<boolean> => {
			const requestId = nextBridgeReviewWorkerRequestId(requestSequenceRef);
			const completion = new Promise<boolean>((resolve): void => {
				reviewIntakeReadyRequestResolversRef.current.set(requestId, resolve);
			});
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerReviewIntakeReadyCommand({
					requestId,
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					streamId: request.streamId,
					reason: request.reason,
				}),
			);
			return completion;
		},
		[runtimeDispatcher],
	);
	const setReviewViewportItemIds = useCallback(
		(itemIds: readonly string[]): void => {
			synchronizeLatestReviewSource();
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
		[renderSnapshotStore, runtimeDispatcher, synchronizeLatestReviewSource],
	);
	const invalidateReviewContent = useCallback(
		(frame: ReviewInvalidationFrame): void => {
			synchronizeLatestReviewSource();
			runtimeDispatcher.dispatch(
				encodeBridgeWorkerReviewInvalidateCommand({
					requestId: nextBridgeReviewWorkerRequestId(requestSequenceRef),
					epoch: nextBridgeReviewWorkerEpochForGeneration({
						workerEpochRef,
						generation: frame.generation,
					}),
					scope: frame.invalidation.scope,
					itemIds: frame.invalidation.itemIds ?? [],
					pathHints: frame.invalidation.pathHints ?? [],
					reason: frame.invalidation.reason,
				}),
			);
		},
		[runtimeDispatcher, synchronizeLatestReviewSource],
	);
	return {
		invalidateReviewContent,
		markFileViewed,
		rootSnapshot,
		selectedCodeViewItem,
		selectedContentAvailability,
		selectionSlice,
		selectionSliceRef,
		setReviewViewportItemIds,
		sendMetadataInterestRequest,
		sendReviewIntakeReady,
		setSelectedReviewItemId,
		synchronizeReviewSource,
		visibleCodeViewItems,
		viewportSliceRef,
	};
}

function bridgeCodeViewItemForReviewPackage(props: {
	readonly codeViewItemsById: Readonly<Record<string, BridgeMainCodeViewItem>>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly itemId: string | null;
}): BridgeMainCodeViewItem | null {
	if (props.reviewPackage === null || props.itemId === null) {
		return null;
	}
	const item = props.reviewPackage.itemsById[props.itemId];
	const codeViewItem = props.codeViewItemsById[props.itemId];
	if (
		item === undefined ||
		codeViewItem === undefined ||
		codeViewItem.bridgeMetadata.itemId !== props.itemId
	) {
		return null;
	}
	return codeViewItemCacheMatchesReviewItem(item, codeViewItem) ? codeViewItem : null;
}

export function selectedBridgeCodeViewItemForReviewPackage(props: {
	readonly codeViewItemsById: Readonly<Record<string, BridgeMainCodeViewItem>>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
}): BridgeMainCodeViewItem | null {
	return bridgeCodeViewItemForReviewPackage({
		codeViewItemsById: props.codeViewItemsById,
		itemId: props.selectedItemId,
		reviewPackage: props.reviewPackage,
	});
}

export function visibleBridgeCodeViewItemsForReviewPackage(props: {
	readonly codeViewItemsById: Readonly<Record<string, BridgeMainCodeViewItem>>;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly visibleItemIds: readonly string[];
}): readonly BridgeMainCodeViewItem[] {
	const visibleCodeViewItems: BridgeMainCodeViewItem[] = [];
	for (const itemId of props.visibleItemIds) {
		const codeViewItem = bridgeCodeViewItemForReviewPackage({
			codeViewItemsById: props.codeViewItemsById,
			itemId,
			reviewPackage: props.reviewPackage,
		});
		if (codeViewItem !== null) {
			visibleCodeViewItems.push(codeViewItem);
		}
	}
	return visibleCodeViewItems;
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
	readonly telemetryConfig?: BridgeTelemetryBootstrapConfig;
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
			...(props.telemetryConfig === undefined
				? {}
				: {
						telemetryConfig: bridgeCommWorkerTelemetryBootstrapConfigFromTelemetryConfig(
							props.telemetryConfig,
						),
					}),
		},
	});
}

function bridgeCommWorkerTelemetryBootstrapConfigFromTelemetryConfig(
	config: BridgeTelemetryBootstrapConfig,
): BridgeCommWorkerTelemetryBootstrapConfig {
	return {
		enabledScopes: [...config.enabledScopes],
		endpointUrl: config.endpointUrl,
		maxEncodedBatchBytes: config.maxEncodedBatchBytes,
		maxSamplesPerBatch: config.maxSamplesPerBatch,
		minimumFlushIntervalMilliseconds: config.minimumFlushIntervalMilliseconds,
		scenario: config.scenario,
	};
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
	const byteBounds = bridgeReviewContentByteBoundsForHandle(handle);
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
		...(byteBounds.expectedBytes === undefined ? {} : { expectedBytes: byteBounds.expectedBytes }),
		maxBytes: byteBounds.maxBytes,
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
			case 'worktreeFileOpenSourceStreamResult':
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

function nextBridgeReviewWorkerEpochForGeneration(props: {
	readonly workerEpochRef: MutableRefObject<number>;
	readonly generation: number;
}): number {
	props.workerEpochRef.current = Math.max(props.workerEpochRef.current + 1, props.generation);
	return props.workerEpochRef.current;
}

function assertNeverBridgeWorkerServerMessage(_message: never): never {
	throw new Error('Unhandled bridge worker server message.');
}
