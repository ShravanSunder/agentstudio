import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { resolveBridgeMarkdownPreviewDecisionFromCodeViewItem } from '../review-viewer/markdown/bridge-markdown-render-mode.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import type {
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import type { BridgeMarkdownRenderWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import type { BridgeAppControlCommand, BridgeAppControlProbe } from './bridge-app-control.js';
import {
	reviewFileTargetForReviewPackagePath,
	type BridgeReviewFileNavigationTarget,
	type SelectedMarkdownPreviewState,
} from './bridge-app-review-selection-state.js';

export interface ApplyBridgeAppControlCommandProps {
	readonly command: BridgeAppControlCommand;
	readonly codeViewControlHandle: BridgeCodeViewControlHandle | null;
	readonly markdownWorkerClient: BridgeMarkdownRenderWorkerClient | null;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectReviewItem: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
	readonly setTreeSearchOpen: (isOpen: boolean) => void;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}

interface ApplyBridgeAppControlCommandResult {
	readonly status: BridgeAppControlProbe['status'];
	readonly reason: string | null;
}

interface MakeBridgeAppControlProbeProps {
	readonly command: BridgeAppControlCommand;
	readonly status: BridgeAppControlProbe['status'];
	readonly reason: string | null;
	readonly sequence: number;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
}

export function applyBridgeAppControlCommand(
	props: ApplyBridgeAppControlCommandProps,
): ApplyBridgeAppControlCommandResult {
	const {
		command,
		codeViewControlHandle,
		markdownWorkerClient,
		projection,
		reviewPackage,
		selectReviewItem,
		selectedCodeViewItem,
		selectedMarkdownPreviewState,
		viewerActions,
	} = props;
	switch (command.method) {
		case 'bridge.diff.scrollToFile':
			if (reviewPackage === null || !(command.itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (!projectionContainsItemId(projection, command.itemId)) {
				return { status: 'rejected', reason: 'item_not_rendered' };
			}
			return selectReviewItem(command.itemId)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_found' };
		case 'bridge.diff.expandFile':
		case 'bridge.diff.collapseFile':
			if (reviewPackage === null || !(command.itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (!projectionContainsItemId(projection, command.itemId)) {
				return { status: 'rejected', reason: 'item_not_rendered' };
			}
			if (codeViewControlHandle === null) {
				return { status: 'rejected', reason: 'code_view_unavailable' };
			}
			return codeViewControlHandle.setItemCollapsed(
				command.itemId,
				command.method === 'bridge.diff.collapseFile',
			)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_rendered' };
		case 'bridge.fileTree.search':
			props.setTreeSearchOpen(true);
			viewerActions.setTreeSearchText(command.searchText);
			viewerActions.setTreeSearchMode(command.searchMode);
			return { status: 'accepted', reason: null };
		case 'bridge.fileTree.setFilter':
			viewerActions.setGitStatusFilter(command.gitStatusFilter);
			viewerActions.setFileClassFilter(command.fileClassFilter);
			return { status: 'accepted', reason: null };
		case 'bridge.fileTree.revealPath': {
			const presentationTarget = reviewFileTargetForReviewPackagePath({
				path: command.path,
				reviewPackage,
			});
			const itemId =
				projection?.primaryItemIdByTreePath[command.path] ??
				presentationTarget?.reviewItemId ??
				itemIdForReviewPackagePath({
					path: command.path,
					reviewPackage,
				});
			if (itemId === null) {
				return { status: 'rejected', reason: 'path_not_found' };
			}
			return selectReviewItem(
				itemId,
				presentationTarget?.reviewItemId === itemId ? presentationTarget : null,
			)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_found' };
		}
		case 'bridge.fileView.showMarkdownPreview': {
			const itemId = command.itemId ?? props.rootSnapshot.selectedItemId;
			if (itemId === null) {
				return { status: 'rejected', reason: 'item_not_selected' };
			}
			if (reviewPackage === null || !(itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (itemId !== props.rootSnapshot.selectedItemId) {
				if (!selectReviewItem(itemId)) {
					return { status: 'rejected', reason: 'item_not_found' };
				}
				viewerActions.setRenderMode({ kind: 'markdownPreview' });
				return { status: 'pending', reason: 'preview_selection_pending' };
			}
			const decision = resolveBridgeMarkdownPreviewDecisionFromCodeViewItem({
				reviewPackage,
				selectedCodeViewItem,
				selectedItemId: itemId,
			});
			if (decision.kind === 'codeView') {
				if (decision.reason === 'contentPending') {
					viewerActions.setRenderMode({ kind: 'markdownPreview' });
					return { status: 'pending', reason: 'preview_content_pending' };
				}
				return { status: 'rejected', reason: decision.reason };
			}
			if (markdownWorkerClient === null) {
				return { status: 'rejected', reason: 'worker_unavailable' };
			}
			if (props.rootSnapshot.renderMode.kind !== 'markdownPreview') {
				viewerActions.setRenderMode({ kind: 'markdownPreview' });
				return { status: 'pending', reason: 'preview_render_pending' };
			}
			return selectedMarkdownPreviewState !== null &&
				selectedMarkdownPreviewState.itemId === itemId &&
				selectedMarkdownPreviewState.status === 'ready'
				? { status: 'accepted', reason: null }
				: { status: 'pending', reason: 'preview_render_pending' };
		}
	}
	return { status: 'rejected', reason: 'unsupported_method' };
}

function projectionContainsItemId(
	projection: BridgeReviewProjectionResult | null,
	itemId: string,
): boolean {
	return projection?.orderedItemIds.includes(itemId) ?? false;
}

function itemIdForReviewPackagePath(props: {
	readonly path: string;
	readonly reviewPackage: BridgeReviewPackage | null;
}): string | null {
	if (props.reviewPackage === null) {
		return null;
	}
	for (const item of Object.values(props.reviewPackage.itemsById)) {
		if (item.headPath === props.path || item.basePath === props.path) {
			return item.itemId;
		}
	}
	return null;
}

export function makeBridgeAppControlProbe(
	props: MakeBridgeAppControlProbeProps,
): BridgeAppControlProbe {
	const path = props.command.method === 'bridge.fileTree.revealPath' ? props.command.path : null;
	const itemId =
		props.command.method === 'bridge.diff.scrollToFile' ||
		props.command.method === 'bridge.diff.expandFile' ||
		props.command.method === 'bridge.diff.collapseFile' ||
		props.command.method === 'bridge.fileView.showMarkdownPreview'
			? (props.command.itemId ?? props.rootSnapshot.selectedItemId)
			: props.rootSnapshot.selectedItemId;
	return {
		sequence: props.sequence,
		method: props.command.method,
		status: props.status,
		itemId,
		path,
		treeSearchText: props.rootSnapshot.treeSearchText,
		treeSearchMode: props.rootSnapshot.treeSearchMode,
		gitStatusFilter: props.rootSnapshot.gitStatusFilter,
		fileClassFilter: props.rootSnapshot.fileClassFilter,
		renderMode: props.rootSnapshot.renderMode,
		reason: props.reason,
	};
}

export function publishBridgeAppControlProbe(props: {
	readonly probe: BridgeAppControlProbe;
}): void {
	if (typeof window === 'undefined') {
		return;
	}
	window.bridgeReviewControlProbe = props.probe;
}

export function nextBridgeAppControlProbeSequence(ref: { current: number }): number {
	ref.current += 1;
	return ref.current;
}
