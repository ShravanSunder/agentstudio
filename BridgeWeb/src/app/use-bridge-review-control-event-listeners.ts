import type { MutableRefObject } from 'react';
import { useLayoutEffect } from 'react';

import type {
	BridgeFileChangeKind,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import {
	invalidBridgeAppControlProbeCommand,
	nextBridgeAppControlProbeSequence,
	publishBridgeAppControlProbe,
	type BridgeAppControlProbeState,
} from './bridge-app-control-probe.js';
import {
	bridgeAppControlCommandRejectionReason,
	bridgeAppControlCommandSchema,
	type BridgeAppControlCommand,
	type BridgeFileTreeFilterCandidate,
} from './bridge-app-control.js';
import type {
	BridgeViewerSearchAction,
	BridgeViewerSearchRejectionReason,
	BridgeViewerSearchState,
} from './bridge-viewer-search-state.js';

type BridgeReviewFilterCandidate = Extract<
	BridgeFileTreeFilterCandidate,
	{ readonly surface: 'review' }
>;

interface UseBridgeReviewControlEventListenersProps {
	readonly codeViewControlHandleRef: MutableRefObject<BridgeCodeViewControlHandle | null>;
	readonly controlProbeSequenceRef: MutableRefObject<number>;
	readonly categoryFilter: BridgeReviewFilterCandidate['categoryFilter'];
	readonly gitStatusFilter: BridgeFileChangeKind | 'all';
	readonly isActive: boolean;
	readonly onSearchRejected: (reason: BridgeViewerSearchRejectionReason) => void;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectReviewItem: (itemId: string) => boolean;
	readonly setReviewFilter: (filter: BridgeReviewFilterCandidate) => void;
	readonly applyTreeSearchActions: (
		actions: readonly BridgeViewerSearchAction[],
	) => BridgeViewerSearchRejectionReason | null;
	readonly target: EventTarget;
	readonly treeSearchStateRef: MutableRefObject<BridgeViewerSearchState>;
	readonly treeSearchState: BridgeViewerSearchState;
	readonly showBinary: boolean;
	readonly showLarge: boolean;
}

export function useBridgeReviewControlEventListeners(
	props: UseBridgeReviewControlEventListenersProps,
): void {
	useLayoutEffect((): (() => void) => {
		if (!props.isActive) return (): void => {};
		const handleSelectReviewItem = (event: Event): void => {
			const detail = eventDetail(event);
			if (
				typeof detail !== 'object' ||
				detail === null ||
				!('itemId' in detail) ||
				typeof detail.itemId !== 'string'
			) {
				return;
			}
			props.selectReviewItem(detail.itemId);
		};
		return installBridgeControlListener({
			eventName: '__bridge_select_review_item',
			handler: handleSelectReviewItem,
			target: props.target,
		});
	}, [props]);

	useLayoutEffect((): (() => void) => {
		if (!props.isActive) return (): void => {};
		const handleControl = (event: Event): void => {
			const detail = eventDetail(event);
			const parsedCommand = bridgeAppControlCommandSchema.safeParse(detail);
			const command = parsedCommand.success
				? parsedCommand.data
				: invalidBridgeAppControlProbeCommand;
			const result = parsedCommand.success
				? applyBridgeReviewControlCommand({ command, props })
				: {
						reason: bridgeAppControlCommandRejectionReason(detail),
						status: 'rejected' as const,
					};
			if (result.reason === 'search_query_too_long') {
				props.onSearchRejected(result.reason);
			}
			const liveTreeSearchState = props.treeSearchStateRef.current;
			const probeState: BridgeAppControlProbeState = {
				categoryFilter: props.categoryFilter,
				filterSurface: 'review',
				gitStatusFilter: props.gitStatusFilter,
				renderMode: { kind: 'codeView' },
				selectedItemId: props.selectedItemId,
				showBinary: props.showBinary,
				showLarge: props.showLarge,
				treeSearchMode: { kind: liveTreeSearchState.enteredCriteria.mode },
				treeSearchText: liveTreeSearchState.enteredCriteria.query,
				...result.probeStatePatch,
			};
			publishBridgeAppControlProbe({
				command,
				reason: result.reason,
				sequence: nextBridgeAppControlProbeSequence(props.controlProbeSequenceRef),
				state: probeState,
				status: result.status,
			});
		};
		return installBridgeControlListener({
			eventName: '__bridge_review_control',
			handler: handleControl,
			target: props.target,
		});
	}, [props]);
}

function applyBridgeReviewControlCommand(props: {
	readonly command: BridgeAppControlCommand;
	readonly props: UseBridgeReviewControlEventListenersProps;
}): {
	readonly probeStatePatch?: Partial<BridgeAppControlProbeState>;
	readonly reason: string | null;
	readonly status: 'accepted' | 'pending' | 'rejected';
} {
	const command = props.command;
	const controlProps = props.props;
	switch (command.method) {
		case 'bridge.diff.scrollToFile':
			return selectProjectedReviewItem(controlProps, command.itemId);
		case 'bridge.diff.expandFile':
		case 'bridge.diff.collapseFile': {
			if (!reviewProjectionContainsItem(controlProps, command.itemId)) {
				return { reason: 'item_not_found', status: 'rejected' };
			}
			const handle = controlProps.codeViewControlHandleRef.current;
			if (handle === null) return { reason: 'code_view_unavailable', status: 'rejected' };
			return handle.setItemCollapsed(command.itemId, command.method === 'bridge.diff.collapseFile')
				? { reason: null, status: 'accepted' }
				: { reason: 'item_not_rendered', status: 'rejected' };
		}
		case 'bridge.fileTree.search':
			const rejectionReason = controlProps.applyTreeSearchActions([
				{
					type: 'apply_semantic_criteria',
					criteria: { mode: command.searchMode.kind, query: command.searchText },
				},
			]);
			if (rejectionReason !== null) {
				return { reason: rejectionReason, status: 'rejected' };
			}
			return {
				probeStatePatch: {
					treeSearchMode: command.searchMode,
					treeSearchText: command.searchText,
				},
				reason: null,
				status: 'accepted',
			};
		case 'bridge.fileTree.setFilter':
			if (command.filter.surface !== 'review') {
				return { reason: 'unsupported_surface', status: 'rejected' };
			}
			controlProps.setReviewFilter(command.filter);
			return {
				probeStatePatch: {
					categoryFilter: command.filter.categoryFilter,
					gitStatusFilter: command.filter.gitStatusFilter,
					showBinary: command.filter.showBinary,
					showLarge: command.filter.showLarge,
				},
				reason: null,
				status: 'accepted',
			};
		case 'bridge.fileTree.revealPath': {
			const itemId = reviewItemIdForPath(controlProps.reviewPackage, command.path);
			return itemId === null
				? { reason: 'path_not_found', status: 'rejected' }
				: selectProjectedReviewItem(controlProps, itemId);
		}
		case 'bridge.fileView.showMarkdownPreview':
			return { reason: 'unsupported_surface', status: 'rejected' };
	}
	return assertUnhandledBridgeReviewControlCommand(command);
}

function assertUnhandledBridgeReviewControlCommand(command: never): never {
	throw new Error(`Unhandled Review control command: ${String(command)}`);
}

function selectProjectedReviewItem(
	props: UseBridgeReviewControlEventListenersProps,
	itemId: string,
): {
	readonly probeStatePatch?: Partial<BridgeAppControlProbeState>;
	readonly reason: string | null;
	readonly status: 'accepted' | 'rejected';
} {
	if (!reviewProjectionContainsItem(props, itemId)) {
		return { reason: 'item_not_found', status: 'rejected' };
	}
	return props.selectReviewItem(itemId)
		? { probeStatePatch: { selectedItemId: itemId }, reason: null, status: 'accepted' }
		: { reason: 'item_not_found', status: 'rejected' };
}

function reviewProjectionContainsItem(
	props: Pick<UseBridgeReviewControlEventListenersProps, 'projection' | 'reviewPackage'>,
	itemId: string,
): boolean {
	return (
		props.reviewPackage?.itemsById[itemId] !== undefined &&
		(props.projection?.orderedItemIds.includes(itemId) ?? false)
	);
}

function reviewItemIdForPath(
	reviewPackage: BridgeReviewPackage | null,
	path: string,
): string | null {
	if (reviewPackage === null) return null;
	for (const itemId of reviewPackage.orderedItemIds) {
		const item = reviewPackage.itemsById[itemId];
		if (item?.headPath === path || item?.basePath === path) return itemId;
	}
	return null;
}

function installBridgeControlListener(props: {
	readonly eventName: string;
	readonly handler: EventListener;
	readonly target: EventTarget;
}): () => void {
	const windowTarget = typeof window === 'undefined' ? null : window;
	props.target.addEventListener(props.eventName, props.handler);
	if (windowTarget !== null && windowTarget !== props.target) {
		windowTarget.addEventListener(props.eventName, props.handler);
	}
	return (): void => {
		props.target.removeEventListener(props.eventName, props.handler);
		if (windowTarget !== null && windowTarget !== props.target) {
			windowTarget.removeEventListener(props.eventName, props.handler);
		}
	};
}

function eventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}
