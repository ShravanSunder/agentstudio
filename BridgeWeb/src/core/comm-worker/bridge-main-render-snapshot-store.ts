import {
	BridgeMainFileDisplayPatchApplier,
	type BridgeMainFileDisplayPatchApplierProps,
	type BridgeMainFileDisplayState,
	type BridgeMainFileTreePatchStream,
} from './bridge-main-file-display-patch-applier.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerPanelChromePatchPayload,
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatch,
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerRowPaintPatchPayload,
	BridgeWorkerSlicePatch,
} from './bridge-worker-contracts.js';
export type {
	BridgeMainFileItemDisplayPayload,
	BridgeMainFileQueryDisplayPayload,
	BridgeMainFileStatusDisplayPayload,
	BridgeMainFileTreeDisplaySlice,
} from './bridge-main-file-display-patch-applier.js';
export type { BridgeMainFileTreeDisplayRow } from './bridge-main-file-tree-display-index.js';
import type {
	BridgeWorkerCodeViewDiffItem,
	BridgeWorkerCodeViewFileItem,
} from './bridge-worker-pierre-render-job.js';

export type BridgeMainCodeViewItem = BridgeWorkerCodeViewFileItem | BridgeWorkerCodeViewDiffItem;
export type BridgeMainReviewTreeDisplayRow = NonNullable<
	BridgeMainReviewDisplayState['reviewTreeRowsByIndex'][number]
>;

export interface BridgeMainSelectionSlice {
	readonly selectedItemId: string | null;
	readonly source: 'user' | 'keyboard' | 'programmatic' | null;
}

export interface BridgeMainViewportSlice {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
}

export interface BridgeMainReviewDisplayFreshness {
	readonly epoch: number;
	readonly projectionRevision: number;
	readonly sequence: number;
}

export interface BridgeMainReviewCatalogSnapshot {
	readonly changeCursor: number;
	readonly epoch: number | null;
	readonly itemOrderLength: number;
	readonly revision: number;
	readonly treeRowOrderLength: number;
}

export type BridgeMainReviewCatalogOrderMutation =
	| {
			readonly kind: 'replace';
			readonly length: number;
	  }
	| {
			readonly kind: 'setRange';
			readonly length: number;
			readonly startIndex: number;
	  }
	| {
			readonly deleteCount: number;
			readonly insertCount: number;
			readonly kind: 'splice';
			readonly startIndex: number;
	  };

export interface BridgeMainReviewCatalogChange {
	readonly cursor: number;
	readonly itemIds: readonly string[];
	readonly itemOrderMutations: readonly BridgeMainReviewCatalogOrderMutation[];
	readonly reset: boolean;
	readonly treeRowIds: readonly string[];
	readonly treeRowOrderMutations: readonly BridgeMainReviewCatalogOrderMutation[];
}

export interface BridgeMainReviewCatalogChangeRead {
	readonly changes: readonly BridgeMainReviewCatalogChange[];
	readonly resetRequired: boolean;
}

export type BridgeMainReviewSourceDisplaySlice =
	| Extract<
			BridgeWorkerReviewDisplayPatch,
			{ readonly operation: 'upsert'; readonly slice: 'reviewSource' }
	  >['payload']
	| Extract<
			BridgeWorkerReviewDisplayPatch,
			{ readonly operation: 'failed'; readonly slice: 'reviewSource' }
	  >['payload'];

export interface BridgeMainReviewDisplayState {
	readonly reviewDisplayFreshness: BridgeMainReviewDisplayFreshness | null;
	readonly reviewItemById: Readonly<Record<string, BridgeWorkerReviewDisplayItem>>;
	readonly reviewItemIdsByIndex: readonly (string | null)[];
	readonly reviewSourceSlice: BridgeMainReviewSourceDisplaySlice | null;
	readonly reviewTreeRowsByIndex: readonly (
		| Extract<
				BridgeWorkerReviewDisplayPatch,
				{ readonly operation: 'batch'; readonly slice: 'reviewTree' }
		  >['payload']['windows'][number]['rows'][number]
		| null
	)[];
}

export type BridgeMainCodeViewItemPatch =
	| {
			readonly operation: 'delete';
			readonly itemId: string;
	  }
	| {
			readonly operation: 'reset';
	  }
	| {
			readonly operation: 'upsert';
			readonly itemId: string;
			readonly item: BridgeMainCodeViewItem;
	  };

export interface BridgeMainRenderSnapshotUpdate {
	readonly codeViewItemPatches?: readonly BridgeMainCodeViewItemPatch[];
	readonly localSelection?: SetBridgeMainLocalSelectionProps;
	readonly localViewport?: SetBridgeMainLocalViewportProps;
	readonly workerPatches?: readonly BridgeWorkerSlicePatch[];
}

export interface BridgeMainRenderSnapshot
	extends BridgeMainFileDisplayState, BridgeMainReviewDisplayState {
	readonly selectionSlice: BridgeMainSelectionSlice;
	readonly viewportSlice: BridgeMainViewportSlice;
	readonly rowPaintById: Readonly<Record<string, BridgeWorkerRowPaintPatchPayload>>;
	readonly contentAvailabilityById: Readonly<
		Record<string, BridgeWorkerContentAvailabilityPatchPayload>
	>;
	readonly codeViewItemsById: Readonly<Record<string, BridgeMainCodeViewItem>>;
	readonly panelChromeSlice: BridgeWorkerPanelChromePatchPayload;
}

interface MutableBridgeMainReviewDisplayState {
	reviewDisplayFreshness: BridgeMainReviewDisplayFreshness | null;
	reviewItemById: Record<string, BridgeWorkerReviewDisplayItem>;
	reviewItemIdsByIndex: Array<string | null>;
	reviewSourceSlice: BridgeMainReviewSourceDisplaySlice | null;
	reviewTreeRowsByIndex: Array<BridgeMainReviewTreeDisplayRow | null>;
}

type MutableBridgeMainRenderSnapshot = Omit<
	BridgeMainRenderSnapshot,
	keyof BridgeMainReviewDisplayState
> &
	MutableBridgeMainReviewDisplayState;

export interface SetBridgeMainLocalSelectionProps {
	readonly selectedItemId: string;
	readonly source: 'user' | 'keyboard' | 'programmatic';
}

export interface SetBridgeMainLocalViewportProps {
	readonly firstVisibleIndex: number;
	readonly lastVisibleIndex: number;
	readonly visibleItemIds: readonly string[];
}

export interface BridgeMainRenderSnapshotStore {
	readonly dispose: () => void;
	readonly getSnapshot: () => BridgeMainRenderSnapshot;
	readonly getServerSnapshot: () => BridgeMainRenderSnapshot;
	readonly getReviewAvailabilitySnapshot: (
		itemId: string,
	) => BridgeWorkerContentAvailabilityPatchPayload | undefined;
	readonly getReviewCatalogSnapshot: () => BridgeMainReviewCatalogSnapshot;
	readonly getReviewCodeViewItemSnapshot: (itemId: string) => BridgeMainCodeViewItem | undefined;
	readonly getReviewItemIdAtIndex: (itemIndex: number) => string | null | undefined;
	readonly getReviewItemSnapshot: (itemId: string) => BridgeWorkerReviewDisplayItem | undefined;
	readonly readReviewCatalogChangesAfter: (cursor: number) => BridgeMainReviewCatalogChangeRead;
	readonly reviewCatalogContainsItem: (itemId: string) => boolean;
	readonly getReviewSelectionSnapshot: () => BridgeMainSelectionSlice;
	readonly getReviewSourceSnapshot: () => BridgeMainReviewSourceDisplaySlice | null;
	readonly getReviewTreeRowSnapshot: (rowId: string) => BridgeMainReviewTreeDisplayRow | undefined;
	readonly getReviewTreeRowAtIndex: (
		treeRowIndex: number,
	) => BridgeMainReviewTreeDisplayRow | null | undefined;
	readonly subscribe: (listener: () => void) => () => void;
	readonly subscribeReviewAvailability: (itemId: string, listener: () => void) => () => void;
	readonly subscribeReviewCatalog: (listener: () => void) => () => void;
	readonly subscribeReviewCodeViewItem: (itemId: string, listener: () => void) => () => void;
	readonly subscribeReviewItem: (itemId: string, listener: () => void) => () => void;
	readonly subscribeReviewSelection: (listener: () => void) => () => void;
	readonly subscribeReviewSource: (listener: () => void) => () => void;
	readonly subscribeReviewTreeRow: (rowId: string, listener: () => void) => () => void;
	readonly setLocalSelection: (props: SetBridgeMainLocalSelectionProps) => void;
	readonly setLocalViewport: (props: SetBridgeMainLocalViewportProps) => void;
	readonly setWorkerCodeViewItem: (props: {
		readonly itemId: string;
		readonly item: BridgeMainCodeViewItem;
	}) => void;
	readonly applyWorkerPatch: (patch: BridgeWorkerSlicePatch) => void;
	readonly applySnapshotUpdate: (update: BridgeMainRenderSnapshotUpdate) => void;
	readonly applyFileDisplayPatchEvent: (event: BridgeWorkerFileDisplayPatchEvent) => void;
	readonly applyReviewDisplayPatchEvent: (event: BridgeWorkerReviewDisplayPatchEvent) => void;
	readonly completeFileQueryTransaction: (transactionId: string) => boolean;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
}

export function createBridgeMainRenderSnapshotStore(
	fileDisplayApplierProps: BridgeMainFileDisplayPatchApplierProps = {},
): BridgeMainRenderSnapshotStore {
	const fileDisplayPatchApplier = new BridgeMainFileDisplayPatchApplier(fileDisplayApplierProps);
	let snapshot = emptyBridgeMainRenderSnapshot(fileDisplayPatchApplier.state);
	const listeners = new Set<() => void>();
	const reviewAvailabilityListeners = new BridgeMainKeyedListenerRegistry<string>();
	const reviewCatalogListeners = new Set<() => void>();
	const reviewCodeViewItemListeners = new BridgeMainKeyedListenerRegistry<string>();
	const reviewItemIndexById = new Map<string, number>();
	const reviewItemListeners = new BridgeMainKeyedListenerRegistry<string>();
	const reviewSelectionListeners = new Set<() => void>();
	const reviewSourceListeners = new Set<() => void>();
	const reviewTreeRowById = new Map<string, BridgeMainReviewTreeDisplayRow>();
	const reviewTreeRowListeners = new BridgeMainKeyedListenerRegistry<string>();
	const fileTreePatchStreamUnsubscribers = new Set<() => void>();
	let isDisposed = false;
	let reviewCatalogChangeCursor = 0;
	const reviewCatalogChanges: BridgeMainReviewCatalogChange[] = [];
	let reviewCatalogSnapshot = emptyBridgeMainReviewCatalogSnapshot();
	const fileTreePatchStream: BridgeMainFileTreePatchStream = {
		getCursor: (): number =>
			isDisposed ? 0 : fileDisplayPatchApplier.fileTreePatchStream.getCursor(),
		getServerCursor: (): number =>
			isDisposed ? 0 : fileDisplayPatchApplier.fileTreePatchStream.getServerCursor(),
		readAfter: (
			cursor,
		): readonly ReturnType<BridgeMainFileTreePatchStream['readAfter']>[number][] =>
			isDisposed ? [] : fileDisplayPatchApplier.fileTreePatchStream.readAfter(cursor),
		subscribe: (listener): (() => void) => {
			if (isDisposed) return (): void => {};
			const unsubscribeFromStream = fileDisplayPatchApplier.fileTreePatchStream.subscribe(listener);
			let isSubscribed = true;
			const unsubscribe = (): void => {
				if (!isSubscribed) return;
				isSubscribed = false;
				fileTreePatchStreamUnsubscribers.delete(unsubscribe);
				unsubscribeFromStream();
			};
			fileTreePatchStreamUnsubscribers.add(unsubscribe);
			return unsubscribe;
		},
	};

	const publish = (nextSnapshot: MutableBridgeMainRenderSnapshot): void => {
		snapshot = nextSnapshot;
		for (const listener of listeners) {
			listener();
		}
	};

	return {
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			listeners.clear();
			reviewAvailabilityListeners.clear();
			reviewCatalogListeners.clear();
			reviewCodeViewItemListeners.clear();
			reviewItemListeners.clear();
			reviewSelectionListeners.clear();
			reviewSourceListeners.clear();
			reviewTreeRowListeners.clear();
			for (const unsubscribe of fileTreePatchStreamUnsubscribers) unsubscribe();
			reviewItemIndexById.clear();
			reviewTreeRowById.clear();
			reviewCatalogChanges.length = 0;
			reviewCatalogChangeCursor = 0;
			snapshot = emptyBridgeMainRenderSnapshot(new BridgeMainFileDisplayPatchApplier().state);
			reviewCatalogSnapshot = emptyBridgeMainReviewCatalogSnapshot();
		},
		getSnapshot: (): BridgeMainRenderSnapshot => snapshot,
		getServerSnapshot: (): BridgeMainRenderSnapshot => snapshot,
		getReviewAvailabilitySnapshot: (
			itemId,
		): BridgeWorkerContentAvailabilityPatchPayload | undefined =>
			snapshot.contentAvailabilityById[itemId],
		getReviewCatalogSnapshot: (): BridgeMainReviewCatalogSnapshot => reviewCatalogSnapshot,
		getReviewCodeViewItemSnapshot: (itemId): BridgeMainCodeViewItem | undefined =>
			snapshot.codeViewItemsById[itemId],
		getReviewItemIdAtIndex: (itemIndex): string | null | undefined =>
			snapshot.reviewItemIdsByIndex[itemIndex],
		getReviewItemSnapshot: (itemId): BridgeWorkerReviewDisplayItem | undefined =>
			snapshot.reviewItemById[itemId],
		readReviewCatalogChangesAfter: (cursor): BridgeMainReviewCatalogChangeRead =>
			readBridgeMainReviewCatalogChangesAfter({
				changes: reviewCatalogChanges,
				currentCursor: reviewCatalogChangeCursor,
				cursor,
			}),
		reviewCatalogContainsItem: (itemId): boolean => reviewItemIndexById.has(itemId),
		getReviewSelectionSnapshot: (): BridgeMainSelectionSlice => snapshot.selectionSlice,
		getReviewSourceSnapshot: (): BridgeMainReviewSourceDisplaySlice | null =>
			snapshot.reviewSourceSlice,
		getReviewTreeRowSnapshot: (rowId): BridgeMainReviewTreeDisplayRow | undefined =>
			reviewTreeRowById.get(rowId),
		getReviewTreeRowAtIndex: (treeRowIndex): BridgeMainReviewTreeDisplayRow | null | undefined =>
			snapshot.reviewTreeRowsByIndex[treeRowIndex],
		subscribe: (listener: () => void): (() => void) => {
			if (isDisposed) return (): void => {};
			listeners.add(listener);
			return (): void => {
				listeners.delete(listener);
			};
		},
		subscribeReviewAvailability: (itemId, listener): (() => void) =>
			isDisposed ? (): void => {} : reviewAvailabilityListeners.subscribe(itemId, listener),
		subscribeReviewCatalog: (listener): (() => void) =>
			isDisposed ? (): void => {} : subscribeBridgeMainListener(reviewCatalogListeners, listener),
		subscribeReviewCodeViewItem: (itemId, listener): (() => void) =>
			isDisposed ? (): void => {} : reviewCodeViewItemListeners.subscribe(itemId, listener),
		subscribeReviewItem: (itemId, listener): (() => void) =>
			isDisposed ? (): void => {} : reviewItemListeners.subscribe(itemId, listener),
		subscribeReviewSelection: (listener): (() => void) =>
			isDisposed ? (): void => {} : subscribeBridgeMainListener(reviewSelectionListeners, listener),
		subscribeReviewSource: (listener): (() => void) =>
			isDisposed ? (): void => {} : subscribeBridgeMainListener(reviewSourceListeners, listener),
		subscribeReviewTreeRow: (rowId, listener): (() => void) =>
			isDisposed ? (): void => {} : reviewTreeRowListeners.subscribe(rowId, listener),
		setLocalSelection: (props: SetBridgeMainLocalSelectionProps): void => {
			if (isDisposed) return;
			publish(
				buildSnapshotFromUpdate(snapshot, {
					localSelection: props,
				}),
			);
			publishBridgeMainListeners(reviewSelectionListeners);
		},
		setLocalViewport: (props: SetBridgeMainLocalViewportProps): void => {
			if (isDisposed) return;
			publish(
				buildSnapshotFromUpdate(snapshot, {
					localViewport: props,
				}),
			);
		},
		setWorkerCodeViewItem: (props): void => {
			if (isDisposed) return;
			publish(
				buildSnapshotFromUpdate(snapshot, {
					codeViewItemPatches: [
						{
							operation: 'upsert',
							itemId: props.itemId,
							item: props.item,
						},
					],
				}),
			);
			reviewCodeViewItemListeners.publish(props.itemId);
		},
		applyWorkerPatch: (patch: BridgeWorkerSlicePatch): void => {
			if (isDisposed) return;
			const availabilityItemIdsBeforeReset =
				patch.slice === 'contentAvailability' && patch.operation === 'reset'
					? Object.keys(snapshot.contentAvailabilityById)
					: [];
			const codeViewItemIdsBeforeReset =
				patch.slice === 'rowPaint' && patch.operation === 'reset'
					? Object.keys(snapshot.codeViewItemsById)
					: [];
			publish(
				buildSnapshotFromUpdate(snapshot, {
					workerPatches: [patch],
				}),
			);
			publishReviewWorkerPatchListeners({
				availabilityItemIdsBeforeReset,
				patch,
				reviewAvailabilityListeners,
				reviewSelectionListeners,
			});
			publishReviewCodeViewWorkerPatchListeners({
				codeViewItemIdsBeforeReset,
				patch,
				reviewCodeViewItemListeners,
			});
		},
		applySnapshotUpdate: (update: BridgeMainRenderSnapshotUpdate): void => {
			if (isDisposed) return;
			const availabilityItemIdsBeforeReset = update.workerPatches?.some(
				(patch): boolean => patch.slice === 'contentAvailability' && patch.operation === 'reset',
			)
				? Object.keys(snapshot.contentAvailabilityById)
				: [];
			const codeViewItemIdsBeforeUpdate =
				update.codeViewItemPatches?.some((patch): boolean => patch.operation === 'reset') ===
					true ||
				update.workerPatches?.some(
					(patch): boolean => patch.slice === 'rowPaint' && patch.operation === 'reset',
				) === true
					? Object.keys(snapshot.codeViewItemsById)
					: [];
			publish(buildSnapshotFromUpdate(snapshot, update));
			publishReviewCodeViewItemPatchListeners({
				codeViewItemIdsBeforeUpdate,
				patches: update.codeViewItemPatches ?? [],
				reviewCodeViewItemListeners,
			});
			for (const patch of update.workerPatches ?? []) {
				publishReviewWorkerPatchListeners({
					availabilityItemIdsBeforeReset,
					patch,
					reviewAvailabilityListeners,
					reviewSelectionListeners,
				});
				publishReviewCodeViewWorkerPatchListeners({
					codeViewItemIdsBeforeReset: codeViewItemIdsBeforeUpdate,
					patch,
					reviewCodeViewItemListeners,
				});
			}
			if (update.localSelection !== undefined) {
				publishBridgeMainListeners(reviewSelectionListeners);
			}
		},
		applyFileDisplayPatchEvent: (event: BridgeWorkerFileDisplayPatchEvent): void => {
			if (isDisposed) return;
			const fileDisplayState = fileDisplayPatchApplier.applyEvent(event);
			if (fileDisplayState !== null) publish({ ...snapshot, ...fileDisplayState });
		},
		applyReviewDisplayPatchEvent: (event: BridgeWorkerReviewDisplayPatchEvent): void => {
			if (isDisposed) return;
			const shouldPublishInitialRootSnapshot = snapshot.reviewDisplayFreshness === null;
			const itemIdsBeforeReset = reviewDisplayEventResetsPresentation(
				snapshot.reviewDisplayFreshness,
				event,
			)
				? [...reviewItemIndexById.keys()]
				: [];
			const effect = applyReviewDisplayPatchEventInPlace({
				event,
				reviewItemIndexById,
				reviewTreeRowById,
				snapshot,
			});
			if (effect === null) return;
			const removedItemIds = [...effect.itemIds].filter(
				(itemId): boolean => !reviewItemIndexById.has(itemId),
			);
			const renderCopyInvalidation = invalidateBridgeMainReviewRenderCopies({
				itemIds: [...new Set([...itemIdsBeforeReset, ...removedItemIds])],
				snapshot,
			});
			snapshot = renderCopyInvalidation.snapshot;
			reviewCatalogChangeCursor += 1;
			const catalogChange: BridgeMainReviewCatalogChange = {
				cursor: reviewCatalogChangeCursor,
				itemIds: [...effect.itemIds],
				itemOrderMutations: effect.itemOrderMutations,
				reset: effect.reset,
				treeRowIds: [...effect.treeRowIds],
				treeRowOrderMutations: effect.treeRowOrderMutations,
			};
			reviewCatalogChanges.push(catalogChange);
			if (reviewCatalogChanges.length > BRIDGE_MAIN_REVIEW_CATALOG_CHANGE_LIMIT) {
				reviewCatalogChanges.splice(
					0,
					reviewCatalogChanges.length - BRIDGE_MAIN_REVIEW_CATALOG_CHANGE_LIMIT,
				);
			}
			reviewCatalogSnapshot = {
				changeCursor: reviewCatalogChangeCursor,
				epoch: event.epoch,
				itemOrderLength: snapshot.reviewItemIdsByIndex.length,
				revision: event.projectionRevision,
				treeRowOrderLength: snapshot.reviewTreeRowsByIndex.length,
			};
			for (const itemId of effect.itemIds) reviewItemListeners.publish(itemId);
			for (const rowId of effect.treeRowIds) reviewTreeRowListeners.publish(rowId);
			if (effect.sourceChanged) publishBridgeMainListeners(reviewSourceListeners);
			if (renderCopyInvalidation.selectionChanged) {
				publishBridgeMainListeners(reviewSelectionListeners);
			}
			for (const itemId of renderCopyInvalidation.availabilityItemIds) {
				reviewAvailabilityListeners.publish(itemId);
			}
			for (const itemId of renderCopyInvalidation.codeViewItemIds) {
				reviewCodeViewItemListeners.publish(itemId);
			}
			publishBridgeMainListeners(reviewCatalogListeners);
			if (shouldPublishInitialRootSnapshot || renderCopyInvalidation.changed) {
				publish({ ...snapshot });
			}
		},
		completeFileQueryTransaction: (transactionId: string): boolean => {
			if (isDisposed) return false;
			const fileDisplayState = fileDisplayPatchApplier.completeQueryTransaction(transactionId);
			if (fileDisplayState === null) return false;
			publish({ ...snapshot, ...fileDisplayState });
			return true;
		},
		fileTreePatchStream,
	};
}

function emptyBridgeMainRenderSnapshot(
	fileDisplayState: BridgeMainFileDisplayState,
): MutableBridgeMainRenderSnapshot {
	return {
		...fileDisplayState,
		...emptyBridgeMainReviewDisplayState(),
		selectionSlice: {
			selectedItemId: null,
			source: null,
		},
		viewportSlice: {
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
			visibleItemIds: [],
		},
		rowPaintById: {},
		contentAvailabilityById: {},
		codeViewItemsById: {},
		panelChromeSlice: {},
	};
}

function emptyBridgeMainReviewCatalogSnapshot(): BridgeMainReviewCatalogSnapshot {
	return {
		changeCursor: 0,
		epoch: null,
		itemOrderLength: 0,
		revision: 0,
		treeRowOrderLength: 0,
	};
}

interface BridgeMainReviewDisplayPatchEffect {
	readonly itemIds: ReadonlySet<string>;
	readonly itemOrderMutations: readonly BridgeMainReviewCatalogOrderMutation[];
	readonly reset: boolean;
	readonly sourceChanged: boolean;
	readonly treeRowIds: ReadonlySet<string>;
	readonly treeRowOrderMutations: readonly BridgeMainReviewCatalogOrderMutation[];
}

function applyReviewDisplayPatchEventInPlace(props: {
	readonly event: BridgeWorkerReviewDisplayPatchEvent;
	readonly reviewItemIndexById: Map<string, number>;
	readonly reviewTreeRowById: Map<string, BridgeMainReviewTreeDisplayRow>;
	readonly snapshot: MutableBridgeMainRenderSnapshot;
}): BridgeMainReviewDisplayPatchEffect | null {
	if (!reviewDisplayEventIsFresh(props.snapshot.reviewDisplayFreshness, props.event)) return null;
	const mutableState = props.snapshot;
	const itemIds = new Set<string>();
	const itemOrderMutations: BridgeMainReviewCatalogOrderMutation[] = [];
	const treeRowIds = new Set<string>();
	const treeRowOrderMutations: BridgeMainReviewCatalogOrderMutation[] = [];
	let reset = false;
	let sourceChanged = false;
	if (
		mutableState.reviewDisplayFreshness !== null &&
		props.event.epoch > mutableState.reviewDisplayFreshness.epoch
	) {
		reset = true;
		for (const itemId of Object.keys(mutableState.reviewItemById)) itemIds.add(itemId);
		for (const rowId of props.reviewTreeRowById.keys()) treeRowIds.add(rowId);
		mutableState.reviewItemById = {};
		mutableState.reviewItemIdsByIndex = [];
		mutableState.reviewSourceSlice = null;
		mutableState.reviewTreeRowsByIndex = [];
		props.reviewTreeRowById.clear();
		props.reviewItemIndexById.clear();
		sourceChanged = true;
	}
	for (const patch of props.event.patches) {
		switch (patch.slice) {
			case 'reviewSource':
				mutableState.reviewSourceSlice = patch.payload;
				sourceChanged = true;
				break;
			case 'reviewItem':
				applyReviewItemDisplayPatchInPlace({
					itemIds,
					itemOrderMutations,
					mutableState,
					patch,
					resetPresentation: (): void => {
						reset = true;
					},
					reviewItemIndexById: props.reviewItemIndexById,
					reviewTreeRowById: props.reviewTreeRowById,
					treeRowIds,
					treeRowOrderMutations,
				});
				break;
			case 'reviewTree':
				applyReviewTreeDisplayPatchInPlace({
					mutableState,
					patch,
					resetPresentation: (): void => {
						reset = true;
					},
					reviewTreeRowById: props.reviewTreeRowById,
					treeRowIds,
					treeRowOrderMutations,
				});
				break;
			default:
				assertNeverReviewDisplayPatch(patch);
		}
	}
	mutableState.reviewDisplayFreshness = {
		epoch: props.event.epoch,
		projectionRevision: props.event.projectionRevision,
		sequence: props.event.sequence,
	};
	return {
		itemIds,
		itemOrderMutations,
		reset,
		sourceChanged,
		treeRowIds,
		treeRowOrderMutations,
	};
}

function applyReviewItemDisplayPatchInPlace(props: {
	readonly itemIds: Set<string>;
	readonly itemOrderMutations: BridgeMainReviewCatalogOrderMutation[];
	readonly mutableState: MutableBridgeMainReviewDisplayState;
	readonly patch: Extract<BridgeWorkerReviewDisplayPatch, { readonly slice: 'reviewItem' }>;
	readonly resetPresentation: () => void;
	readonly reviewItemIndexById: Map<string, number>;
	readonly reviewTreeRowById: Map<string, BridgeMainReviewTreeDisplayRow>;
	readonly treeRowIds: Set<string>;
	readonly treeRowOrderMutations: BridgeMainReviewCatalogOrderMutation[];
}): void {
	if (props.patch.operation === 'reset') {
		props.resetPresentation();
		for (const itemId of Object.keys(props.mutableState.reviewItemById)) props.itemIds.add(itemId);
		props.mutableState.reviewItemById = {};
		props.mutableState.reviewItemIdsByIndex = [];
		props.reviewItemIndexById.clear();
		return;
	}
	if (props.patch.payload.reset) {
		props.resetPresentation();
		for (const itemId of Object.keys(props.mutableState.reviewItemById)) props.itemIds.add(itemId);
		props.mutableState.reviewItemById = {};
		props.mutableState.reviewItemIdsByIndex = [];
		props.reviewItemIndexById.clear();
	}
	if (props.patch.payload.startIndex !== null) {
		props.itemOrderMutations.push({
			kind: 'setRange',
			length: props.patch.payload.items.length,
			startIndex: props.patch.payload.startIndex,
		});
	}
	for (const [offset, item] of props.patch.payload.items.entries()) {
		props.mutableState.reviewItemById[item.metadata.itemId] = item;
		props.itemIds.add(item.metadata.itemId);
		if (props.patch.payload.startIndex !== null) {
			const itemIndex = props.patch.payload.startIndex + offset;
			const previousItemId = props.mutableState.reviewItemIdsByIndex[itemIndex];
			if (previousItemId !== null && previousItemId !== undefined) {
				props.reviewItemIndexById.delete(previousItemId);
				if (previousItemId !== item.metadata.itemId) {
					delete props.mutableState.reviewItemById[previousItemId];
					props.itemIds.add(previousItemId);
				}
			}
			props.mutableState.reviewItemIdsByIndex[itemIndex] = item.metadata.itemId;
			props.reviewItemIndexById.set(item.metadata.itemId, itemIndex);
		}
	}
	applyReviewDisplayMutationOperationsInPlace({
		itemIds: props.itemIds,
		itemOrderMutations: props.itemOrderMutations,
		mutableState: props.mutableState,
		operations: props.patch.payload.operations ?? [],
		reviewItemIndexById: props.reviewItemIndexById,
		reviewTreeRowById: props.reviewTreeRowById,
		treeRowIds: props.treeRowIds,
		treeRowOrderMutations: props.treeRowOrderMutations,
	});
}

function applyReviewTreeDisplayPatchInPlace(props: {
	readonly mutableState: MutableBridgeMainReviewDisplayState;
	readonly patch: Extract<BridgeWorkerReviewDisplayPatch, { readonly slice: 'reviewTree' }>;
	readonly resetPresentation: () => void;
	readonly reviewTreeRowById: Map<string, BridgeMainReviewTreeDisplayRow>;
	readonly treeRowIds: Set<string>;
	readonly treeRowOrderMutations: BridgeMainReviewCatalogOrderMutation[];
}): void {
	if (props.patch.operation === 'reset') {
		props.resetPresentation();
		for (const rowId of props.reviewTreeRowById.keys()) props.treeRowIds.add(rowId);
		props.mutableState.reviewTreeRowsByIndex = [];
		props.reviewTreeRowById.clear();
		return;
	}
	if (props.patch.payload.reset) {
		props.resetPresentation();
		for (const rowId of props.reviewTreeRowById.keys()) props.treeRowIds.add(rowId);
		props.mutableState.reviewTreeRowsByIndex = [];
		props.reviewTreeRowById.clear();
	}
	for (const window of props.patch.payload.windows) {
		props.treeRowOrderMutations.push({
			kind: 'setRange',
			length: window.rows.length,
			startIndex: window.startIndex,
		});
		for (const [offset, row] of window.rows.entries()) {
			const rowIndex = window.startIndex + offset;
			const previousRow = props.mutableState.reviewTreeRowsByIndex[rowIndex];
			if (previousRow !== null && previousRow !== undefined) {
				props.reviewTreeRowById.delete(previousRow.rowId);
				props.treeRowIds.add(previousRow.rowId);
			}
			props.mutableState.reviewTreeRowsByIndex[rowIndex] = row;
			props.reviewTreeRowById.set(row.rowId, row);
			props.treeRowIds.add(row.rowId);
		}
	}
}

function applyReviewDisplayMutationOperationsInPlace(props: {
	readonly itemIds: Set<string>;
	readonly itemOrderMutations: BridgeMainReviewCatalogOrderMutation[];
	readonly mutableState: MutableBridgeMainReviewDisplayState;
	readonly operations: Extract<
		BridgeWorkerReviewDisplayPatch,
		{ readonly operation: 'batch'; readonly slice: 'reviewItem' }
	>['payload']['operations'];
	readonly reviewItemIndexById: Map<string, number>;
	readonly reviewTreeRowById: Map<string, BridgeMainReviewTreeDisplayRow>;
	readonly treeRowIds: Set<string>;
	readonly treeRowOrderMutations: BridgeMainReviewCatalogOrderMutation[];
}): void {
	for (const operation of props.operations) {
		switch (operation.operationKind) {
			case 'upsertItems':
				for (const item of operation.items) {
					props.mutableState.reviewItemById[item.metadata.itemId] = item;
					props.itemIds.add(item.metadata.itemId);
				}
				break;
			case 'removeItems':
				for (const itemId of operation.itemIds) {
					delete props.mutableState.reviewItemById[itemId];
					props.itemIds.add(itemId);
					const itemIndex = props.reviewItemIndexById.get(itemId);
					if (itemIndex !== undefined) {
						props.itemOrderMutations.push({
							kind: 'setRange',
							length: 1,
							startIndex: itemIndex,
						});
						props.mutableState.reviewItemIdsByIndex[itemIndex] = null;
						props.reviewItemIndexById.delete(itemId);
					}
				}
				break;
			case 'replaceItemOrder':
				for (const itemId of Object.keys(props.mutableState.reviewItemById)) {
					if (operation.itemIds.includes(itemId)) continue;
					delete props.mutableState.reviewItemById[itemId];
					props.itemIds.add(itemId);
				}
				props.mutableState.reviewItemIdsByIndex = [...operation.itemIds];
				props.itemOrderMutations.push({ kind: 'replace', length: operation.itemIds.length });
				props.reviewItemIndexById.clear();
				for (const [itemIndex, itemId] of operation.itemIds.entries()) {
					props.reviewItemIndexById.set(itemId, itemIndex);
				}
				break;
			case 'spliceTreeRows': {
				props.treeRowOrderMutations.push({
					deleteCount: operation.deleteCount,
					insertCount: operation.rows.length,
					kind: 'splice',
					startIndex: operation.startIndex,
				});
				const removedRows = props.mutableState.reviewTreeRowsByIndex.slice(
					operation.startIndex,
					operation.startIndex + operation.deleteCount,
				);
				props.mutableState.reviewTreeRowsByIndex.splice(
					operation.startIndex,
					operation.deleteCount,
					...operation.rows,
				);
				for (const row of removedRows) {
					if (row === null || row === undefined) continue;
					props.reviewTreeRowById.delete(row.rowId);
					props.treeRowIds.add(row.rowId);
				}
				for (const row of operation.rows) {
					props.reviewTreeRowById.set(row.rowId, row);
					props.treeRowIds.add(row.rowId);
				}
				break;
			}
			default:
				assertNeverReviewDisplayMutationOperation(operation);
		}
	}
}

function reviewDisplayEventIsFresh(
	current: BridgeMainReviewDisplayFreshness | null,
	event: BridgeWorkerReviewDisplayPatchEvent,
): boolean {
	if (current === null || event.epoch > current.epoch) return true;
	return (
		event.epoch === current.epoch &&
		event.sequence > current.sequence &&
		event.projectionRevision > current.projectionRevision
	);
}

const BRIDGE_MAIN_REVIEW_CATALOG_CHANGE_LIMIT = 256;

function reviewDisplayEventResetsPresentation(
	current: BridgeMainReviewDisplayFreshness | null,
	event: BridgeWorkerReviewDisplayPatchEvent,
): boolean {
	if (current !== null && event.epoch > current.epoch) return true;
	return event.patches.some((patch): boolean => {
		if (patch.slice === 'reviewSource') return false;
		return patch.operation === 'reset' || patch.payload.reset;
	});
}

interface BridgeMainReviewRenderCopyInvalidation {
	readonly availabilityItemIds: readonly string[];
	readonly changed: boolean;
	readonly codeViewItemIds: readonly string[];
	readonly selectionChanged: boolean;
	readonly snapshot: MutableBridgeMainRenderSnapshot;
}

function invalidateBridgeMainReviewRenderCopies(props: {
	readonly itemIds: readonly string[];
	readonly snapshot: MutableBridgeMainRenderSnapshot;
}): BridgeMainReviewRenderCopyInvalidation {
	if (props.itemIds.length === 0) {
		return {
			availabilityItemIds: [],
			changed: false,
			codeViewItemIds: [],
			selectionChanged: false,
			snapshot: props.snapshot,
		};
	}
	const itemIds = new Set(props.itemIds);
	const availabilityItemIds = props.itemIds.filter(
		(itemId): boolean => props.snapshot.contentAvailabilityById[itemId] !== undefined,
	);
	const codeViewItemIds = props.itemIds.filter(
		(itemId): boolean => props.snapshot.codeViewItemsById[itemId] !== undefined,
	);
	const rowPaintItemIds = props.itemIds.filter(
		(itemId): boolean => props.snapshot.rowPaintById[itemId] !== undefined,
	);
	const selectedItemId = props.snapshot.selectionSlice.selectedItemId;
	const selectionChanged =
		selectedItemId !== null &&
		itemIds.has(selectedItemId) &&
		props.snapshot.reviewItemById[selectedItemId] === undefined;
	const changed =
		selectionChanged ||
		availabilityItemIds.length > 0 ||
		codeViewItemIds.length > 0 ||
		rowPaintItemIds.length > 0;
	if (!changed) {
		return {
			availabilityItemIds,
			changed,
			codeViewItemIds,
			selectionChanged,
			snapshot: props.snapshot,
		};
	}
	const contentAvailabilityById = { ...props.snapshot.contentAvailabilityById };
	const codeViewItemsById = { ...props.snapshot.codeViewItemsById };
	const rowPaintById = { ...props.snapshot.rowPaintById };
	for (const itemId of props.itemIds) {
		delete contentAvailabilityById[itemId];
		delete codeViewItemsById[itemId];
		delete rowPaintById[itemId];
	}
	return {
		availabilityItemIds,
		changed,
		codeViewItemIds,
		selectionChanged,
		snapshot: {
			...props.snapshot,
			codeViewItemsById,
			contentAvailabilityById,
			rowPaintById,
			selectionSlice: selectionChanged
				? { selectedItemId: null, source: null }
				: props.snapshot.selectionSlice,
		},
	};
}

function readBridgeMainReviewCatalogChangesAfter(props: {
	readonly changes: readonly BridgeMainReviewCatalogChange[];
	readonly currentCursor: number;
	readonly cursor: number;
}): BridgeMainReviewCatalogChangeRead {
	if (props.cursor === props.currentCursor) {
		return { changes: [], resetRequired: false };
	}
	const firstRetainedCursor = props.changes[0]?.cursor ?? props.currentCursor + 1;
	if (props.cursor < firstRetainedCursor - 1 || props.cursor > props.currentCursor) {
		return { changes: [], resetRequired: true };
	}
	return {
		changes: props.changes.filter((change): boolean => change.cursor > props.cursor),
		resetRequired: false,
	};
}

function emptyBridgeMainReviewDisplayState(): MutableBridgeMainReviewDisplayState {
	return {
		reviewDisplayFreshness: null,
		reviewItemById: {},
		reviewItemIdsByIndex: [],
		reviewSourceSlice: null,
		reviewTreeRowsByIndex: [],
	};
}

function assertNeverReviewDisplayPatch(patch: never): never {
	throw new Error(`Unhandled Review display patch: ${JSON.stringify(patch)}`);
}

function assertNeverReviewDisplayMutationOperation(operation: never): never {
	throw new Error(`Unhandled Review display mutation: ${JSON.stringify(operation)}`);
}

class BridgeMainKeyedListenerRegistry<TKey> {
	readonly #listenersByKey = new Map<TKey, Set<() => void>>();

	subscribe(key: TKey, listener: () => void): () => void {
		const listeners = this.#listenersByKey.get(key) ?? new Set<() => void>();
		listeners.add(listener);
		this.#listenersByKey.set(key, listeners);
		return (): void => {
			listeners.delete(listener);
			if (listeners.size === 0) this.#listenersByKey.delete(key);
		};
	}

	publish(key: TKey): void {
		for (const listener of this.#listenersByKey.get(key) ?? []) listener();
	}

	clear(): void {
		this.#listenersByKey.clear();
	}
}

function subscribeBridgeMainListener(listeners: Set<() => void>, listener: () => void): () => void {
	listeners.add(listener);
	return (): void => {
		listeners.delete(listener);
	};
}

function publishBridgeMainListeners(listeners: ReadonlySet<() => void>): void {
	for (const listener of listeners) listener();
}

function publishReviewWorkerPatchListeners(props: {
	readonly availabilityItemIdsBeforeReset: readonly string[];
	readonly patch: BridgeWorkerSlicePatch;
	readonly reviewAvailabilityListeners: BridgeMainKeyedListenerRegistry<string>;
	readonly reviewSelectionListeners: ReadonlySet<() => void>;
}): void {
	if (props.patch.slice === 'selection') {
		publishBridgeMainListeners(props.reviewSelectionListeners);
		return;
	}
	if (props.patch.slice !== 'contentAvailability') return;
	if (props.patch.operation === 'reset') {
		for (const itemId of props.availabilityItemIdsBeforeReset) {
			props.reviewAvailabilityListeners.publish(itemId);
		}
		return;
	}
	props.reviewAvailabilityListeners.publish(props.patch.itemId);
}

function publishReviewCodeViewItemPatchListeners(props: {
	readonly codeViewItemIdsBeforeUpdate: readonly string[];
	readonly patches: readonly BridgeMainCodeViewItemPatch[];
	readonly reviewCodeViewItemListeners: BridgeMainKeyedListenerRegistry<string>;
}): void {
	const affectedItemIds = new Set<string>();
	for (const patch of props.patches) {
		if (patch.operation === 'reset') {
			for (const itemId of props.codeViewItemIdsBeforeUpdate) affectedItemIds.add(itemId);
			continue;
		}
		affectedItemIds.add(patch.itemId);
	}
	for (const itemId of affectedItemIds) props.reviewCodeViewItemListeners.publish(itemId);
}

function publishReviewCodeViewWorkerPatchListeners(props: {
	readonly codeViewItemIdsBeforeReset: readonly string[];
	readonly patch: BridgeWorkerSlicePatch;
	readonly reviewCodeViewItemListeners: BridgeMainKeyedListenerRegistry<string>;
}): void {
	if (props.patch.slice !== 'rowPaint') return;
	if (props.patch.operation === 'reset') {
		for (const itemId of props.codeViewItemIdsBeforeReset) {
			props.reviewCodeViewItemListeners.publish(itemId);
		}
		return;
	}
	if (props.patch.operation === 'delete') {
		props.reviewCodeViewItemListeners.publish(props.patch.itemId);
	}
}

function buildSnapshotFromUpdate(
	snapshot: MutableBridgeMainRenderSnapshot,
	update: BridgeMainRenderSnapshotUpdate,
): MutableBridgeMainRenderSnapshot {
	let nextSnapshot = snapshot;
	if (update.localSelection !== undefined) {
		nextSnapshot = {
			...nextSnapshot,
			selectionSlice: update.localSelection,
		};
	}
	if (update.localViewport !== undefined) {
		nextSnapshot = {
			...nextSnapshot,
			viewportSlice: {
				firstVisibleIndex: update.localViewport.firstVisibleIndex,
				lastVisibleIndex: update.localViewport.lastVisibleIndex,
				visibleItemIds: [...update.localViewport.visibleItemIds],
			},
		};
	}
	for (const patch of update.codeViewItemPatches ?? []) {
		nextSnapshot = buildCodeViewItemPatchSnapshot(nextSnapshot, patch);
	}
	for (const patch of update.workerPatches ?? []) {
		nextSnapshot = buildWorkerPatchSnapshot(nextSnapshot, patch);
	}
	return nextSnapshot;
}

function buildCodeViewItemPatchSnapshot(
	snapshot: MutableBridgeMainRenderSnapshot,
	patch: BridgeMainCodeViewItemPatch,
): MutableBridgeMainRenderSnapshot {
	if (patch.operation === 'reset') {
		return {
			...snapshot,
			codeViewItemsById: {},
		};
	}
	const nextCodeViewItemsById = { ...snapshot.codeViewItemsById };
	if (patch.operation === 'delete') {
		delete nextCodeViewItemsById[patch.itemId];
	} else {
		nextCodeViewItemsById[patch.itemId] = patch.item;
	}
	return {
		...snapshot,
		codeViewItemsById: nextCodeViewItemsById,
	};
}

function buildWorkerPatchSnapshot(
	snapshot: MutableBridgeMainRenderSnapshot,
	patch: BridgeWorkerSlicePatch,
): MutableBridgeMainRenderSnapshot {
	switch (patch.slice) {
		case 'selection':
			return {
				...snapshot,
				selectionSlice: buildSelectionSliceFromPatch(patch),
			};
		case 'viewport':
			return {
				...snapshot,
				viewportSlice: buildViewportSliceFromPatch(patch),
			};
		case 'rowPaint':
			return buildRowPaintPatchSnapshot(snapshot, patch);
		case 'contentAvailability':
			return buildContentAvailabilityPatchSnapshot(snapshot, patch);
		case 'panelChrome':
			return {
				...snapshot,
				panelChromeSlice: patch.operation === 'upsert' ? patch.payload : {},
			};
	}
	return assertNeverBridgeWorkerSlicePatch(patch);
}

function assertNeverBridgeWorkerSlicePatch(patch: never): never {
	throw new Error(`Unhandled bridge worker slice patch: ${String(patch)}`);
}

function buildSelectionSliceFromPatch(
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'selection' }>,
): BridgeMainSelectionSlice {
	if (patch.operation === 'delete' || patch.operation === 'reset') {
		return {
			selectedItemId: null,
			source: null,
		};
	}
	return {
		selectedItemId: patch.payload.selectedItemId,
		source: patch.payload.source ?? null,
	};
}

function buildViewportSliceFromPatch(
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'viewport' }>,
): BridgeMainViewportSlice {
	if (patch.operation === 'delete' || patch.operation === 'reset') {
		return {
			firstVisibleIndex: 0,
			lastVisibleIndex: 0,
			visibleItemIds: [],
		};
	}
	return {
		firstVisibleIndex: patch.payload.firstVisibleIndex,
		lastVisibleIndex: patch.payload.lastVisibleIndex,
		visibleItemIds: [...patch.payload.visibleItemIds],
	};
}

function buildRowPaintPatchSnapshot(
	snapshot: MutableBridgeMainRenderSnapshot,
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'rowPaint' }>,
): MutableBridgeMainRenderSnapshot {
	if (patch.operation === 'reset') {
		return {
			...snapshot,
			rowPaintById: {},
			codeViewItemsById: {},
		};
	}
	const nextEntries = { ...snapshot.rowPaintById };
	if (patch.operation === 'delete') {
		const nextCodeViewItemsById = { ...snapshot.codeViewItemsById };
		delete nextEntries[patch.itemId];
		delete nextCodeViewItemsById[patch.itemId];
		return {
			...snapshot,
			rowPaintById: nextEntries,
			codeViewItemsById: nextCodeViewItemsById,
		};
	} else {
		nextEntries[patch.itemId] = patch.payload;
	}
	return {
		...snapshot,
		rowPaintById: nextEntries,
	};
}

function buildContentAvailabilityPatchSnapshot(
	snapshot: MutableBridgeMainRenderSnapshot,
	patch: Extract<BridgeWorkerSlicePatch, { slice: 'contentAvailability' }>,
): MutableBridgeMainRenderSnapshot {
	if (patch.operation === 'reset') {
		return {
			...snapshot,
			contentAvailabilityById: {},
		};
	}
	const nextEntries = { ...snapshot.contentAvailabilityById };
	if (patch.operation === 'delete') {
		delete nextEntries[patch.itemId];
	} else {
		nextEntries[patch.itemId] = patch.payload;
	}
	return {
		...snapshot,
		contentAvailabilityById: nextEntries,
	};
}
