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
	type PropsWithChildren,
} from 'react';

import {
	encodeBridgeWorkerSelectCommand,
	encodeBridgeWorkerFileDisplayResyncCommand,
	encodeBridgeWorkerFileQueryUpdateCommand,
	encodeBridgeWorkerViewportCommand,
} from '../core/comm-worker/bridge-comm-worker-protocol.js';
import type { BridgeMainFileTreePatchStream } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import { prepareBridgeMainPierreItemForPresentation } from '../core/comm-worker/bridge-main-pierre-item-adapter.js';
import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	type BridgeMainRenderSnapshot,
	type BridgeMainRenderSnapshotStore,
} from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerContentAvailabilityPatchPayload,
	BridgeWorkerFileRenderPatch,
	BridgeWorkerHealthEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerFileQuery } from '../core/comm-worker/bridge-worker-file-query-contracts.js';
import { recordBridgeSelectionLifecycleSnapshot } from '../foundation/diagnostics/bridge-review-selection-diagnostic.js';
import type { BridgeFileViewerSelectedCodeViewItem } from './bridge-file-viewer-code-view-items.js';
import type { BridgeFileViewerSelection } from './bridge-file-viewer-display-model.js';

const bridgeFileViewerSurfaceClientContext = createContext<BridgePaneSurfaceClient | null>(null);

export function BridgeFileViewerSurfaceClientProvider(
	props: PropsWithChildren<{
		readonly surfaceClient: BridgePaneSurfaceClient;
	}>,
): ReactElement {
	return createElement(
		bridgeFileViewerSurfaceClientContext.Provider,
		{ value: props.surfaceClient },
		props.children,
	);
}

export interface BridgeFileViewerRenderSnapshotController {
	readonly clearSelectedFileViewContent: () => void;
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
	readonly panelChromeSlice: BridgeMainRenderSnapshot['panelChromeSlice'];
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'observePostRender' | 'reconcilePublication'
	>;
}

export function useBridgeFileViewerRenderSnapshotController(props: {
	readonly selection: BridgeFileViewerSelection | null;
}): BridgeFileViewerRenderSnapshotController {
	const fileViewClient = useContext(bridgeFileViewerSurfaceClientContext);
	if (fileViewClient === null || fileViewClient.surface !== 'fileView') {
		throw new Error('Bridge File Viewer requires its pane-owned File surface client.');
	}
	const requestSequenceRef = useRef(0);
	const latestFileSelectRequestIdRef = useRef<string | null>(null);
	const workerEpochRef = useRef(0);
	const selectionRef = useRef(props.selection);
	selectionRef.current = props.selection;
	const renderSnapshotStore = fileViewClient.renderStore;
	const renderSnapshot = useSyncExternalStore(
		renderSnapshotStore.subscribe,
		renderSnapshotStore.getSnapshot,
		renderSnapshotStore.getServerSnapshot,
	);
	const publishWorkerMessages = useCallback(
		(messages: readonly BridgeWorkerServerToMainMessage[]): void => {
			applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore({
				messages,
				renderFulfillmentCoordinator: fileViewClient.renderFulfillmentCoordinator,
				renderSnapshotStore,
				selection: selectionRef.current,
			});
		},
		[fileViewClient.renderFulfillmentCoordinator, renderSnapshotStore],
	);
	const recordLatestFileSelectLifecycleSnapshot = useCallback((): void => {
		recordBridgeSelectionLifecycleSnapshot({
			requestId: latestFileSelectRequestIdRef.current,
			snapshot: fileViewClient.lifecycle.getSnapshot(),
			surface: 'fileView',
		});
	}, [fileViewClient]);
	useEffect((): (() => void) => {
		const unsubscribe = fileViewClient.subscribeMessages((message): void => {
			publishWorkerMessages([message]);
			recordLatestFileSelectLifecycleSnapshot();
		});
		fileViewClient.send(
			encodeBridgeWorkerFileDisplayResyncCommand({
				epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
				reason: 'initialMount',
				requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
				transactionId: null,
			}),
		);
		recordLatestFileSelectLifecycleSnapshot();
		return unsubscribe;
	}, [fileViewClient, publishWorkerMessages, recordLatestFileSelectLifecycleSnapshot]);

	const dispatchSelectedFileViewContentRequest = useCallback(
		(dispatchProps: {
			readonly fileId: string;
			readonly selectedSource: 'keyboard' | 'programmatic' | 'user';
		}): void => {
			renderSnapshotStore.setLocalSelection({
				selectedItemId: dispatchProps.fileId,
				source: dispatchProps.selectedSource,
			});
			latestFileSelectRequestIdRef.current = fileViewClient.send(
				encodeBridgeWorkerSelectCommand({
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					surface: 'fileView',
					selectedItemId: dispatchProps.fileId,
					selectedSource: dispatchProps.selectedSource,
				}),
			);
			recordLatestFileSelectLifecycleSnapshot();
		},
		[fileViewClient, recordLatestFileSelectLifecycleSnapshot, renderSnapshotStore],
	);
	const clearSelectedFileViewContent = useCallback((): void => {
		renderSnapshotStore.applyWorkerPatch({ operation: 'delete', slice: 'selection' });
		latestFileSelectRequestIdRef.current = fileViewClient.send(
			encodeBridgeWorkerSelectCommand({
				epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
				requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
				selectedItemId: null,
				selectedSource: null,
				surface: 'fileView',
			}),
		);
		recordLatestFileSelectLifecycleSnapshot();
	}, [fileViewClient, recordLatestFileSelectLifecycleSnapshot, renderSnapshotStore]);
	const dispatchFileViewQueryFact = useCallback(
		(query: BridgeWorkerFileQuery): void => {
			fileViewClient.send(
				encodeBridgeWorkerFileQueryUpdateCommand({
					...query,
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
				}),
			);
		},
		[fileViewClient],
	);
	const dispatchVisibleFileViewViewportFact = useCallback(
		(dispatchProps: {
			readonly firstVisibleIndex: number;
			readonly lastVisibleIndex: number;
			readonly visibleItemIds: readonly string[];
		}): void => {
			fileViewClient.send(
				encodeBridgeWorkerViewportCommand({
					epoch: nextBridgeFileViewerWorkerEpoch(workerEpochRef),
					requestId: nextBridgeFileViewerWorkerRequestId(requestSequenceRef),
					surface: 'fileView',
					firstVisibleIndex: dispatchProps.firstVisibleIndex,
					lastVisibleIndex: dispatchProps.lastVisibleIndex,
					phase: 'settled',
					visibleItemIds: dispatchProps.visibleItemIds,
				}),
			);
		},
		[fileViewClient],
	);
	const selectedCodeViewItem = selectedBridgeFileViewerCodeViewItemForSnapshot({
		renderSnapshot,
		selection: props.selection,
	});
	const selectedContentAvailability =
		props.selection === null
			? null
			: (renderSnapshot.contentAvailabilityById[props.selection.fileId] ?? null);
	const fileStatusSlice = bridgeFileViewerStatusForSelectedRender({
		currentStatus: renderSnapshot.fileStatusSlice,
		selectedCodeViewItem,
		selectedContentAvailability,
	});

	return useMemo(
		(): BridgeFileViewerRenderSnapshotController => ({
			clearSelectedFileViewContent,
			completeFileQueryTransaction: renderSnapshotStore.completeFileQueryTransaction,
			dispatchFileViewQueryFact,
			dispatchSelectedFileViewContentRequest,
			dispatchVisibleFileViewViewportFact,
			fileDisplaySnapshot: {
				fileDisplayFreshness: renderSnapshot.fileDisplayFreshness,
				fileItemById: renderSnapshot.fileItemById,
				fileQuerySlice: renderSnapshot.fileQuerySlice,
				fileStatusSlice,
				fileTreeSlice: renderSnapshot.fileTreeSlice,
			},
			panelChromeSlice: renderSnapshot.panelChromeSlice,
			selectedContentAvailability,
			selectedCodeViewItem,
			fileTreePatchStream: renderSnapshotStore.fileTreePatchStream,
			renderFulfillmentCoordinator: fileViewClient.renderFulfillmentCoordinator,
		}),
		[
			clearSelectedFileViewContent,
			dispatchSelectedFileViewContentRequest,
			dispatchFileViewQueryFact,
			dispatchVisibleFileViewViewportFact,
			renderSnapshotStore.completeFileQueryTransaction,
			renderSnapshotStore.fileTreePatchStream,
			fileViewClient.renderFulfillmentCoordinator,
			renderSnapshot.fileDisplayFreshness,
			renderSnapshot.fileItemById,
			renderSnapshot.panelChromeSlice,
			renderSnapshot.fileQuerySlice,
			renderSnapshot.fileTreeSlice,
			fileStatusSlice,
			selectedCodeViewItem,
			selectedContentAvailability,
		],
	);
}

function bridgeFileViewerStatusForSelectedRender(props: {
	readonly currentStatus: BridgeMainRenderSnapshot['fileStatusSlice'];
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly selectedContentAvailability: BridgeWorkerContentAvailabilityPatchPayload | null;
}): BridgeMainRenderSnapshot['fileStatusSlice'] {
	if (
		props.currentStatus !== null ||
		props.selectedContentAvailability?.state !== 'ready' ||
		props.selectedCodeViewItem === null
	) {
		return props.currentStatus;
	}
	return {
		ahead: null,
		behind: null,
		branchName: null,
		staged: null,
		state: 'ready',
		unstaged: null,
		untracked: null,
	};
}

export function applyBridgeWorkerMessagesToFileViewerRenderSnapshotStore(props: {
	readonly messages: readonly BridgeWorkerServerToMainMessage[];
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'acceptPublication' | 'bindPublicationItem' | 'markPublicationQueued' | 'rejectPublication'
	>;
	readonly renderSnapshotStore: BridgeMainRenderSnapshotStore;
	readonly selection?: BridgeFileViewerSelection | null;
}): void {
	for (const message of props.messages) {
		switch (message.kind) {
			case 'fileDisplayPatch': {
				const currentSnapshot = props.renderSnapshotStore.getSnapshot();
				const currentFreshness = currentSnapshot.fileDisplayFreshness;
				const selection = props.selection ?? null;
				if (
					bridgeFileDisplayEventIsAccepted(currentFreshness, message) &&
					(message.patches.some(
						(patch): boolean =>
							patch.slice === 'fileTree' &&
							(patch.operation === 'reset' || patch.operation === 'replacementCommit'),
					) ||
						fileDisplayPatchInvalidatesSelection(message, selection))
				) {
					const retainedSelectedItem = fileDisplayPatchRetainsSelection(message, selection)
						? selectedBridgeFileViewerCodeViewItemForSnapshot({
								renderSnapshot: currentSnapshot,
								selection,
							})
						: null;
					props.renderSnapshotStore.applySnapshotUpdate({
						codeViewItemPatches: [
							{ operation: 'reset' },
							...(retainedSelectedItem === null
								? []
								: [
										{
											item: retainedSelectedItem,
											itemId: retainedSelectedItem.bridgeMetadata.itemId,
											operation: 'upsert' as const,
										},
									]),
						],
						workerPatches: [
							{ operation: 'reset', slice: 'contentAvailability' },
							{ operation: 'reset', slice: 'rowPaint' },
						],
					});
				}
				props.renderSnapshotStore.applyFileDisplayPatchEvent(message);
				break;
			}
			case 'reviewDisplayPatch':
			case 'reviewPierreRenderJob':
			case 'reviewRenderPatch':
				break;
			case 'slicePatch': {
				break;
			}
			case 'fileRenderPatch':
				if (bridgeFilePublicationMatchesDisplayEpoch(props.renderSnapshotStore, message)) {
					props.renderSnapshotStore.applySnapshotUpdate({
						workerPatches: normalizeSelectedFileSourceReconciliationRenderPatches({
							patches: message.patches,
							renderSnapshot: props.renderSnapshotStore.getSnapshot(),
							selection: props.selection ?? null,
						}),
					});
				}
				break;
			case 'filePierreRenderJob': {
				const publicationItem = message.job.payload.item;
				if (
					!bridgeFilePublicationMatchesDisplayEpoch(props.renderSnapshotStore, message) ||
					publicationItem.type !== 'file' ||
					!bridgeFileViewerItemIdBelongsToSnapshot(props.renderSnapshotStore, message.job.itemId)
				) {
					props.renderFulfillmentCoordinator.rejectPublication(message, 'stale_submission');
					break;
				}
				if (props.renderFulfillmentCoordinator.acceptPublication(message) === 'duplicate') {
					break;
				}
				const currentItem =
					props.renderSnapshotStore.getSnapshot().codeViewItemsById[message.job.itemId];
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
				props.renderFulfillmentCoordinator.markPublicationQueued(message);
				break;
			}
			case 'health':
				publishBridgeProductMetadataStreamDiagnostic(message.diagnostic);
				break;
			case 'nativeSurfaceSelectionRequest':
			case 'subscription':
			case 'reviewComparisonTargetsQuery':
				break;
			default:
				assertNeverBridgeFileViewerWorkerServerMessage(message);
		}
	}
}

function normalizeSelectedFileSourceReconciliationRenderPatches(props: {
	readonly patches: readonly BridgeWorkerFileRenderPatch[];
	readonly renderSnapshot: BridgeMainRenderSnapshot;
	readonly selection: BridgeFileViewerSelection | null;
}): readonly BridgeWorkerFileRenderPatch[] {
	const retainedSelectedItem = selectedBridgeFileViewerCodeViewItemForSnapshot({
		renderSnapshot: props.renderSnapshot,
		selection: props.selection,
	});
	return props.patches.flatMap((patch): readonly BridgeWorkerFileRenderPatch[] => {
		if (
			retainedSelectedItem !== null &&
			patch.slice === 'rowPaint' &&
			patch.operation === 'delete' &&
			patch.itemId === retainedSelectedItem.bridgeMetadata.itemId
		) {
			return [];
		}
		if (
			props.selection !== null &&
			patch.slice === 'contentAvailability' &&
			patch.operation === 'upsert' &&
			patch.itemId === props.selection.fileId &&
			patch.payload.state === 'stale'
		) {
			return [
				{
					itemId: patch.itemId,
					operation: 'delete',
					slice: 'contentAvailability',
				},
			];
		}
		return [patch];
	});
}

function fileDisplayPatchRetainsSelection(
	message: Extract<BridgeWorkerServerToMainMessage, { readonly kind: 'fileDisplayPatch' }>,
	selection: BridgeFileViewerSelection | null,
): boolean {
	if (selection === null) return false;
	const deletesSelectedItem = message.patches.some(
		(patch): boolean =>
			patch.slice === 'fileItem' &&
			patch.operation === 'delete' &&
			patch.itemId === selection.fileId,
	);
	if (deletesSelectedItem) return false;
	const selectedItemUpsert = message.patches.find(
		(patch) =>
			patch.slice === 'fileItem' &&
			patch.operation === 'upsert' &&
			patch.itemId === selection.fileId,
	);
	if (selectedItemUpsert?.slice === 'fileItem' && selectedItemUpsert.operation === 'upsert')
		return selectedItemUpsert.payload.displayPath === selection.path;
	const beginsSourceReplacement = message.patches.some(
		(patch): boolean => patch.slice === 'fileTree' && patch.operation === 'reset',
	);
	const commitsSourceReplacement = message.patches.some(
		(patch): boolean => patch.slice === 'fileTree' && patch.operation === 'replacementCommit',
	);
	return beginsSourceReplacement || commitsSourceReplacement;
}

function fileDisplayPatchInvalidatesSelection(
	message: Extract<BridgeWorkerServerToMainMessage, { readonly kind: 'fileDisplayPatch' }>,
	selection: BridgeFileViewerSelection | null,
): boolean {
	if (selection === null) return false;
	return message.patches.some(
		(patch): boolean =>
			patch.slice === 'fileItem' &&
			(patch.operation === 'reset' ||
				(patch.operation === 'delete' && patch.itemId === selection.fileId) ||
				(patch.operation === 'upsert' &&
					patch.itemId === selection.fileId &&
					patch.payload.displayPath !== selection.path)),
	);
}

type BridgeProductMetadataStreamHealthDiagnostic = NonNullable<
	BridgeWorkerHealthEvent['diagnostic']
>;

function publishBridgeProductMetadataStreamDiagnostic(
	diagnostic: BridgeWorkerHealthEvent['diagnostic'],
): void {
	if (diagnostic?.kind !== 'productMetadataStream') return;
	const diagnosticGlobal = globalThis as typeof globalThis & {
		__bridgeProductMetadataStreamDiagnostic?: BridgeProductMetadataStreamHealthDiagnostic;
	};
	diagnosticGlobal.__bridgeProductMetadataStreamDiagnostic = Object.freeze({ ...diagnostic });
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
	if (
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
