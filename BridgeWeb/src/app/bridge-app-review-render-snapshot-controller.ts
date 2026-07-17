import type { MutableRefObject } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';

import {
	encodeBridgeWorkerMarkFileViewedCommand,
	encodeBridgeWorkerReviewIntakeReadyCommand,
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import { prepareBridgeMainPierreItemForPresentation } from '../core/comm-worker/bridge-main-pierre-item-adapter.js';
import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	type BridgeMainCodeViewItem,
	type BridgeMainRenderSnapshotStore,
	type BridgeMainReviewCatalogSnapshot,
	type BridgeMainReviewSourceDisplaySlice,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	createBridgeWorkerPierreCourier,
	type BridgeWorkerPierreCourier,
} from '../core/comm-worker/bridge-worker-pierre-courier.js';
import type { BridgeWorkerPierreRenderJob } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRpcLifecycleSnapshot } from '../core/comm-worker/bridge-worker-rpc-lifecycle-store.js';

const BRIDGE_REVIEW_INTAKE_READY_MAX_ATTEMPTS = 3;

type BridgeReviewIntakeReadyAttemptState = 'acked' | 'exhausted' | 'idle' | 'pending' | 'sending';

interface BridgeReviewIntakeReadyAttempt {
	attemptCount: number;
	readonly client: BridgePaneSurfaceClient;
	requestId: string | null;
	state: BridgeReviewIntakeReadyAttemptState;
}

export interface UseBridgeReviewRenderSnapshotControllerProps {
	readonly pierreCourier: BridgeWorkerPierreCourier;
	readonly reviewClient: BridgePaneSurfaceClient;
}

export interface BridgeReviewDirectDisplayStore extends Pick<
	BridgeMainRenderSnapshotStore,
	| 'getReviewItemIdAtIndex'
	| 'getReviewCodeViewItemSnapshot'
	| 'getReviewItemSnapshot'
	| 'getReviewTreeRowAtIndex'
	| 'getReviewTreeRowSnapshot'
	| 'readReviewCatalogChangesAfter'
	| 'reviewCatalogContainsItem'
	| 'subscribeReviewItem'
	| 'subscribeReviewCodeViewItem'
	| 'subscribeReviewTreeRow'
> {}

export interface BridgeReviewRenderSnapshotController {
	readonly catalogSnapshot: BridgeMainReviewCatalogSnapshot;
	readonly clearSelectedReviewItemId: () => void;
	readonly commitSelectedReviewItemId: (itemId: string) => void;
	readonly displayStore: BridgeReviewDirectDisplayStore;
	readonly emitSelectedReviewItemIntent: (
		itemId: string,
		selectedSource: 'keyboard' | 'programmatic' | 'user',
	) => void;
	readonly markFileViewed: (itemId: string, onDeliveryFailure?: () => void) => boolean;
	readonly panelChromeSlice: BridgeWorkerPanelChromePatchPayload;
	readonly reviewSourceSlice: BridgeMainReviewSourceDisplaySlice | null;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedItemId: string | null;
	readonly selectedReviewItem: BridgeWorkerReviewDisplayItem | null;
	readonly setReviewCodeViewVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly setReviewTreeVisibleItemIds: (itemIds: readonly string[]) => void;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[];
}

export function useBridgeReviewRenderSnapshotController(
	props: UseBridgeReviewRenderSnapshotControllerProps,
): BridgeReviewRenderSnapshotController {
	if (props.reviewClient.surface !== 'review') {
		throw new Error('Bridge Review Viewer requires its pane-owned Review surface client.');
	}
	const displayStore = props.reviewClient.renderStore;
	const catalogSnapshot = useSyncExternalStore(
		displayStore.subscribeReviewCatalog,
		displayStore.getReviewCatalogSnapshot,
		displayStore.getReviewCatalogSnapshot,
	);
	const reviewSourceSlice = useSyncExternalStore(
		displayStore.subscribeReviewSource,
		displayStore.getReviewSourceSnapshot,
		displayStore.getReviewSourceSnapshot,
	);
	const selectionSlice = useSyncExternalStore(
		displayStore.subscribeReviewSelection,
		displayStore.getReviewSelectionSnapshot,
		displayStore.getReviewSelectionSnapshot,
	);
	const getPanelChromeSnapshot = useCallback(
		(): BridgeWorkerPanelChromePatchPayload => displayStore.getSnapshot().panelChromeSlice,
		[displayStore],
	);
	const panelChromeSlice = useSyncExternalStore(
		displayStore.subscribe,
		getPanelChromeSnapshot,
		getPanelChromeSnapshot,
	);
	const selectedItemId = selectionSlice.selectedItemId;
	const selectedReviewItem = useSelectedReviewStoreValue({
		getSnapshot: displayStore.getReviewItemSnapshot,
		itemId: selectedItemId,
		subscribe: displayStore.subscribeReviewItem,
	});
	const selectedCodeViewItem = useSelectedReviewStoreValue({
		getSnapshot: displayStore.getReviewCodeViewItemSnapshot,
		itemId: selectedItemId,
		subscribe: displayStore.subscribeReviewCodeViewItem,
	});
	const rawSelectedContentAvailability = useSelectedReviewStoreValue({
		getSnapshot: displayStore.getReviewAvailabilitySnapshot,
		itemId: selectedItemId,
		subscribe: displayStore.subscribeReviewAvailability,
	});
	const selectedContentAvailability =
		rawSelectedContentAvailability?.state === 'ready' && selectedCodeViewItem === null
			? ({ state: 'loading' } as const)
			: (rawSelectedContentAvailability ?? null);
	const [codeViewRenderedItemIds, setCodeViewRenderedItemIds] = useState<readonly string[]>([]);
	const visibleCodeViewItems = useVisibleReviewCodeViewItems({
		displayStore,
		itemIds: codeViewRenderedItemIds,
	});
	const workerViewportItemIds = useMemo(
		(): readonly string[] => reviewCodeViewBodyDemandItemIds(codeViewRenderedItemIds),
		[codeViewRenderedItemIds],
	);
	const workerEpochRef = useRef(0);
	const reviewIntakeReadyAttemptRef = useRef<BridgeReviewIntakeReadyAttempt | null>(null);
	const markFileViewedFailureCallbacksRef = useRef<Map<string, () => void>>(new Map());
	const settleWorkerRequests = useCallback((): void => {
		const lifecycleSnapshot = props.reviewClient.lifecycle.getSnapshot();
		settleBridgeReviewWorkerLifecycleRequests({
			failureCallbacksByRequestId: markFileViewedFailureCallbacksRef.current,
			lifecycleSnapshot,
		});
		settleBridgeReviewIntakeReadyAttempt({
			attemptRef: reviewIntakeReadyAttemptRef,
			client: props.reviewClient,
			lifecycleSnapshot,
			workerEpochRef,
		});
	}, [props.reviewClient]);
	const pierreCourier = props.pierreCourier;
	useEffect((): (() => void) => {
		const failureCallbacksByRequestId = markFileViewedFailureCallbacksRef.current;
		const unsubscribeMessages = props.reviewClient.subscribeMessages((message): void => {
			applyBridgeWorkerMessagesToMainRenderSnapshotStore({
				messages: [message],
				pierreCourier,
				renderFulfillmentCoordinator: props.reviewClient.renderFulfillmentCoordinator,
				renderSnapshotStore: displayStore,
			});
		});
		const unsubscribeLifecycle = props.reviewClient.lifecycle.subscribe(settleWorkerRequests);
		return (): void => {
			unsubscribeMessages();
			unsubscribeLifecycle();
			failureCallbacksByRequestId.clear();
		};
	}, [displayStore, pierreCourier, props.reviewClient, settleWorkerRequests]);
	useEffect((): void => {
		beginBridgeReviewIntakeReadyDelivery({
			attemptRef: reviewIntakeReadyAttemptRef,
			client: props.reviewClient,
			workerEpochRef,
		});
	}, [props.reviewClient]);
	const clearSelectedReviewItemId = useCallback((): void => {
		displayStore.applyWorkerPatch({ operation: 'delete', slice: 'selection' });
	}, [displayStore]);
	const commitSelectedReviewItemId = useCallback(
		(itemId: string): void => {
			displayStore.setLocalSelection({ selectedItemId: itemId, source: 'user' });
		},
		[displayStore],
	);
	const emitSelectedReviewItemIntent = useCallback(
		(itemId: string, selectedSource: 'keyboard' | 'programmatic' | 'user'): void => {
			props.reviewClient.send(
				encodeBridgeWorkerSelectCommand({
					epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
					requestId: 'review-client-owned',
					selectedItemId: itemId,
					selectedSource,
					surface: 'review',
				}),
			);
		},
		[props.reviewClient],
	);
	useEffect((): void => {
		const lastVisibleIndex = Math.max(0, workerViewportItemIds.length - 1);
		displayStore.setLocalViewport({
			firstVisibleIndex: 0,
			lastVisibleIndex,
			visibleItemIds: workerViewportItemIds,
		});
		props.reviewClient.send(
			encodeBridgeWorkerViewportCommand({
				epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
				firstVisibleIndex: 0,
				lastVisibleIndex,
				phase: 'settled',
				requestId: 'review-client-owned',
				surface: 'review',
				visibleItemIds: workerViewportItemIds,
			}),
		);
	}, [displayStore, props.reviewClient, workerViewportItemIds]);
	const setReviewCodeViewVisibleItemIds = useCallback((itemIds: readonly string[]): void => {
		const uniqueItemIds = reviewCodeViewBodyDemandItemIds(itemIds);
		setCodeViewRenderedItemIds((currentItemIds): readonly string[] =>
			stringArraysEqual(currentItemIds, uniqueItemIds) ? currentItemIds : uniqueItemIds,
		);
	}, []);
	const setReviewTreeVisibleItemIds = useCallback((_itemIds: readonly string[]): void => {
		// Review metadata already carries the complete tree manifest. Tree visibility is UI-local
		// and must not become CodeView body demand; body preparation follows CodeView visibility.
	}, []);
	const markFileViewed = useCallback(
		(itemId: string, onDeliveryFailure?: () => void): boolean => {
			if (displayStore.getReviewItemSnapshot(itemId) === undefined) return false;
			let requestId: string;
			try {
				requestId = props.reviewClient.send(
					encodeBridgeWorkerMarkFileViewedCommand({
						epoch: nextBridgeReviewWorkerEpoch(workerEpochRef),
						fileId: itemId,
						requestId: 'review-client-owned',
					}),
				);
			} catch {
				onDeliveryFailure?.();
				return false;
			}
			if (onDeliveryFailure !== undefined) {
				markFileViewedFailureCallbacksRef.current.set(requestId, onDeliveryFailure);
				settleWorkerRequests();
			}
			return true;
		},
		[displayStore, props.reviewClient, settleWorkerRequests],
	);
	return {
		catalogSnapshot,
		clearSelectedReviewItemId,
		commitSelectedReviewItemId,
		displayStore,
		emitSelectedReviewItemIntent,
		markFileViewed,
		panelChromeSlice,
		reviewSourceSlice,
		selectedCodeViewItem: selectedCodeViewItem ?? null,
		selectedContentAvailability,
		selectedItemId,
		selectedReviewItem: selectedReviewItem ?? null,
		setReviewCodeViewVisibleItemIds,
		setReviewTreeVisibleItemIds,
		visibleCodeViewItems,
	};
}

function useVisibleReviewCodeViewItems(props: {
	readonly displayStore: BridgeReviewDirectDisplayStore;
	readonly itemIds: readonly string[];
}): readonly BridgeMainCodeViewItem[] {
	const selector = useMemo(() => createVisibleReviewCodeViewItemsSelector(), []);
	const subscribe = useCallback(
		(listener: () => void): (() => void) => {
			const unsubscribers = props.itemIds.map((itemId) =>
				props.displayStore.subscribeReviewCodeViewItem(itemId, listener),
			);
			return (): void => {
				for (const unsubscribe of unsubscribers) unsubscribe();
			};
		},
		[props.displayStore, props.itemIds],
	);
	const getSnapshot = useCallback(
		(): readonly BridgeMainCodeViewItem[] =>
			selector({
				getItem: props.displayStore.getReviewCodeViewItemSnapshot,
				itemIds: props.itemIds,
			}),
		[props.displayStore, props.itemIds, selector],
	);
	return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export function createVisibleReviewCodeViewItemsSelector(): (props: {
	readonly getItem: (itemId: string) => BridgeMainCodeViewItem | undefined;
	readonly itemIds: readonly string[];
}) => readonly BridgeMainCodeViewItem[] {
	let previousItems: readonly BridgeMainCodeViewItem[] = [];
	return (props): readonly BridgeMainCodeViewItem[] => {
		const nextItems = props.itemIds.flatMap((itemId): readonly BridgeMainCodeViewItem[] => {
			const item = props.getItem(itemId);
			return item === undefined || item.bridgeMetadata.itemId !== itemId ? [] : [item];
		});
		if (
			previousItems.length === nextItems.length &&
			previousItems.every((item, index): boolean => item === nextItems[index])
		) {
			return previousItems;
		}
		previousItems = nextItems;
		return nextItems;
	};
}

export function reviewCodeViewBodyDemandItemIds(
	codeViewVisibleItemIds: readonly string[],
): readonly string[] {
	return [...new Set(codeViewVisibleItemIds)];
}

function stringArraysEqual(first: readonly string[], second: readonly string[]): boolean {
	return (
		first.length === second.length &&
		first.every((itemId, itemIndex): boolean => itemId === second[itemIndex])
	);
}

function useSelectedReviewStoreValue<TValue>(props: {
	readonly getSnapshot: (itemId: string) => TValue | undefined;
	readonly itemId: string | null;
	readonly subscribe: (itemId: string, listener: () => void) => () => void;
}): TValue | undefined {
	const { getSnapshot: getItemSnapshot, itemId, subscribe: subscribeToItem } = props;
	const subscribe = useCallback(
		(listener: () => void): (() => void) =>
			itemId === null ? (): void => {} : subscribeToItem(itemId, listener),
		[itemId, subscribeToItem],
	);
	const getSnapshot = useCallback(
		(): TValue | undefined => (itemId === null ? undefined : getItemSnapshot(itemId)),
		[getItemSnapshot, itemId],
	);
	return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export function applyBridgeWorkerMessagesToMainRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly pierreCourier: BridgeWorkerPierreCourier;
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'acceptPublication' | 'bindPublicationItem' | 'markPublicationQueued' | 'rejectPublication'
	>;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
}): void {
	for (const message of props.messages) {
		switch (message.kind) {
			case 'fileDisplayPatch':
			case 'filePierreRenderJob':
			case 'fileRenderPatch':
				break;
			case 'reviewDisplayPatch':
				props.renderSnapshotStore.applyReviewDisplayPatchEvent(message);
				break;
			case 'reviewRenderPatch': {
				if (!bridgeReviewPublicationMatchesDisplayEpoch(props.renderSnapshotStore, message)) {
					break;
				}
				const currentMemberPatches = message.patches.filter(
					(patch): boolean =>
						patch.slice === 'panelChrome' ||
						patch.operation === 'reset' ||
						props.renderSnapshotStore.reviewCatalogContainsItem(patch.itemId),
				);
				if (currentMemberPatches.length > 0) {
					props.renderSnapshotStore.applySnapshotUpdate({ workerPatches: currentMemberPatches });
				}
				break;
			}
			case 'slicePatch':
				break;
			case 'health':
			case 'subscription':
				break;
			case 'reviewPierreRenderJob':
				if (
					!bridgeReviewPublicationMatchesDisplayEpoch(props.renderSnapshotStore, message) ||
					!props.renderSnapshotStore.reviewCatalogContainsItem(message.job.itemId)
				) {
					props.renderFulfillmentCoordinator.rejectPublication(message, 'stale_submission');
					break;
				}
				if (props.renderFulfillmentCoordinator.acceptPublication(message) === 'duplicate') {
					break;
				}
				const publicationItem = message.job.payload.item;
				const currentItem = props.renderSnapshotStore.getReviewCodeViewItemSnapshot(
					message.job.itemId,
				);
				if (currentItem === undefined) {
					const preparedItem = prepareBridgeMainPierreItemForPresentation({
						currentItem,
						presentationItem: publicationItem,
					});
					props.renderFulfillmentCoordinator.bindPublicationItem({
						finalItem: preparedItem.item,
						publicationItem,
						residency: preparedItem.residency,
					});
					props.renderSnapshotStore.setWorkerCodeViewItem({
						item: preparedItem.item,
						itemId: message.job.itemId,
					});
					props.pierreCourier.submit(message.job);
					props.renderFulfillmentCoordinator.markPublicationQueued(message);
					break;
				}
				props.renderSnapshotStore.setWorkerCodeViewItem({
					item: publicationItem,
					itemId: message.job.itemId,
				});
				props.pierreCourier.submit(message.job);
				props.renderFulfillmentCoordinator.markPublicationQueued(message);
				break;
			default:
				assertNeverBridgeWorkerServerMessage(message);
		}
	}
}

function bridgeReviewPublicationMatchesDisplayEpoch(
	store: BridgeMainRenderSnapshotStore,
	publication: Extract<
		BridgeWorkerServerToMainMessage,
		{ readonly kind: 'reviewPierreRenderJob' | 'reviewRenderPatch' }
	>,
): boolean {
	return store.getSnapshot().reviewDisplayFreshness?.epoch === publication.workerDerivationEpoch;
}

export function createBridgeReviewWorkerPierreCourier(): BridgeWorkerPierreCourier {
	return createBridgeWorkerPierreCourier({
		submitPierreRenderJob: (_job: BridgeWorkerPierreRenderJob): void => {},
	});
}

function settleBridgeReviewWorkerLifecycleRequests(props: {
	readonly failureCallbacksByRequestId: Map<string, () => void>;
	readonly lifecycleSnapshot: BridgeWorkerRpcLifecycleSnapshot;
}): void {
	for (const request of Object.values(props.lifecycleSnapshot.requestsById)) {
		if (request.state === 'pending') continue;
		const failureCallback = props.failureCallbacksByRequestId.get(request.requestId);
		if (failureCallback === undefined) continue;
		props.failureCallbacksByRequestId.delete(request.requestId);
		if (request.state !== 'acked') failureCallback();
	}
}

function beginBridgeReviewIntakeReadyDelivery(props: {
	readonly attemptRef: MutableRefObject<BridgeReviewIntakeReadyAttempt | null>;
	readonly client: BridgePaneSurfaceClient;
	readonly workerEpochRef: MutableRefObject<number>;
}): void {
	let attempt = props.attemptRef.current;
	if (attempt?.client !== props.client) {
		attempt = {
			attemptCount: 0,
			client: props.client,
			requestId: null,
			state: 'idle',
		};
		props.attemptRef.current = attempt;
	}
	if (attempt.state !== 'idle') return;
	startBridgeReviewIntakeReadyAttempt(props);
}

function startBridgeReviewIntakeReadyAttempt(props: {
	readonly attemptRef: MutableRefObject<BridgeReviewIntakeReadyAttempt | null>;
	readonly client: BridgePaneSurfaceClient;
	readonly workerEpochRef: MutableRefObject<number>;
}): void {
	const attempt = props.attemptRef.current;
	if (attempt?.client !== props.client || attempt.state !== 'idle') return;
	if (attempt.attemptCount >= BRIDGE_REVIEW_INTAKE_READY_MAX_ATTEMPTS) {
		attempt.state = 'exhausted';
		return;
	}
	attempt.attemptCount += 1;
	attempt.requestId = null;
	attempt.state = 'sending';
	let requestId: string;
	try {
		requestId = props.client.send(
			encodeBridgeWorkerReviewIntakeReadyCommand({
				epoch: nextBridgeReviewWorkerEpoch(props.workerEpochRef),
				requestId: 'review-client-owned',
				streamId: null,
			}),
		);
	} catch (error: unknown) {
		if (props.attemptRef.current === attempt) attempt.state = 'exhausted';
		throw error;
	}
	if (props.attemptRef.current !== attempt) return;
	attempt.requestId = requestId;
	attempt.state = 'pending';
	settleBridgeReviewIntakeReadyAttempt({
		...props,
		lifecycleSnapshot: props.client.lifecycle.getSnapshot(),
	});
}

function settleBridgeReviewIntakeReadyAttempt(props: {
	readonly attemptRef: MutableRefObject<BridgeReviewIntakeReadyAttempt | null>;
	readonly client: BridgePaneSurfaceClient;
	readonly lifecycleSnapshot: BridgeWorkerRpcLifecycleSnapshot;
	readonly workerEpochRef: MutableRefObject<number>;
}): void {
	const attempt = props.attemptRef.current;
	if (
		attempt?.client !== props.client ||
		attempt.state !== 'pending' ||
		attempt.requestId === null
	) {
		return;
	}
	const request = props.lifecycleSnapshot.requestsById[attempt.requestId];
	if (request === undefined || request.state === 'pending') return;
	if (request.state === 'acked') {
		attempt.state = 'acked';
		return;
	}
	if (request.state !== 'failed' && request.state !== 'timed_out') return;
	attempt.requestId = null;
	attempt.state =
		attempt.attemptCount >= BRIDGE_REVIEW_INTAKE_READY_MAX_ATTEMPTS ? 'exhausted' : 'idle';
	if (attempt.state === 'idle') startBridgeReviewIntakeReadyAttempt(props);
}

function nextBridgeReviewWorkerEpoch(workerEpochRef: MutableRefObject<number>): number {
	workerEpochRef.current += 1;
	return workerEpochRef.current;
}

function assertNeverBridgeWorkerServerMessage(_message: never): never {
	throw new Error('Unhandled bridge worker server message.');
}
