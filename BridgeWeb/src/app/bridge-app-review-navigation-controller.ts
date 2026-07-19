import { useEffect, useRef } from 'react';

import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerSelectCommand,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { recordBridgeReviewSelectionDiagnosticStage } from '../foundation/diagnostics/bridge-review-selection-diagnostic.js';
import type { BridgeViewerNavigationCommand } from './bridge-viewer-navigation-models.js';

export type BridgeReviewNavigationSelectionSource = BridgeWorkerSelectCommand['selectedSource'];

export interface BridgeReviewNavigationTarget {
	readonly commandId: string;
	readonly itemId: string | null;
	readonly path: string | null;
}

export type BridgeReviewNavigationTargetResolution =
	| { readonly status: 'none' }
	| {
			readonly itemId: string;
			readonly status: 'accepted';
			readonly target: BridgeReviewNavigationTarget;
	  }
	| {
			readonly status: 'outsideAcceptedProjection';
			readonly target: BridgeReviewNavigationTarget;
	  };

export interface UseBridgeReviewNavigationControllerProps {
	readonly catalogRevision: number;
	readonly clearReviewSelection: () => void;
	readonly getReviewItem: (itemId: string) => BridgeWorkerReviewDisplayItem | undefined;
	readonly isActive: boolean;
	readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
	readonly onTargetOutsideAcceptedProjection: (target: BridgeReviewNavigationTarget) => void;
	readonly orderedItemIds: readonly string[];
	readonly selectedItemId: string | null;
	readonly selectInitialReviewItem: (
		itemId: string,
		selectedSource: BridgeReviewNavigationSelectionSource,
	) => boolean | void;
	readonly selectReviewItem: (
		itemId: string,
		selectedSource: BridgeReviewNavigationSelectionSource,
	) => boolean | void;
}

export function useBridgeReviewNavigationController(
	props: UseBridgeReviewNavigationControllerProps,
): void {
	const {
		catalogRevision,
		clearReviewSelection,
		getReviewItem,
		isActive,
		navigationCommand,
		onTargetOutsideAcceptedProjection,
		orderedItemIds,
		selectedItemId,
		selectInitialReviewItem,
		selectReviewItem,
	} = props;
	const appliedNavigationCommandIdRef = useRef<string | null>(null);
	const pendingLocalSelectionItemIdRef = useRef<string | null>(null);

	useEffect((): void => {
		if (
			!isActive ||
			navigationCommand === undefined ||
			navigationCommand.context !== 'review' ||
			appliedNavigationCommandIdRef.current === navigationCommand.commandId
		) {
			return;
		}
		const resolution = resolveBridgeReviewNavigationTarget({
			getReviewItem,
			navigationCommand,
			orderedItemIds,
		});
		if (resolution.status === 'none') {
			return;
		}
		if (resolution.status === 'outsideAcceptedProjection') {
			onTargetOutsideAcceptedProjection(resolution.target);
			return;
		}
		if (selectReviewItem(resolution.itemId, 'programmatic') !== false) {
			appliedNavigationCommandIdRef.current = navigationCommand.commandId;
			pendingLocalSelectionItemIdRef.current = resolution.itemId;
		}
	}, [
		catalogRevision,
		getReviewItem,
		isActive,
		navigationCommand,
		onTargetOutsideAcceptedProjection,
		orderedItemIds,
		selectReviewItem,
	]);

	useEffect((): void => {
		if (!isActive) {
			return;
		}
		if (selectedItemId !== null && orderedItemIds.includes(selectedItemId)) {
			pendingLocalSelectionItemIdRef.current = null;
			return;
		}
		const pendingLocalSelectionItemId = pendingLocalSelectionItemIdRef.current;
		if (pendingLocalSelectionItemId !== null) {
			if (orderedItemIds.includes(pendingLocalSelectionItemId)) {
				return;
			}
			pendingLocalSelectionItemIdRef.current = null;
		}
		if (
			navigationCommand?.context === 'review' &&
			appliedNavigationCommandIdRef.current !== navigationCommand.commandId &&
			bridgeReviewNavigationTargetForCommand(navigationCommand) !== null
		) {
			return;
		}
		const firstProjectedItemId = orderedItemIds[0] ?? null;
		if (firstProjectedItemId === null) {
			pendingLocalSelectionItemIdRef.current = null;
			if (selectedItemId !== null) {
				clearReviewSelection();
			}
			return;
		}
		recordBridgeReviewSelectionDiagnosticStage('initial_selection_requested');
		if (selectInitialReviewItem(firstProjectedItemId, 'programmatic') !== false) {
			recordBridgeReviewSelectionDiagnosticStage('initial_selection_scheduling_accepted');
			pendingLocalSelectionItemIdRef.current = firstProjectedItemId;
		}
	}, [
		catalogRevision,
		clearReviewSelection,
		isActive,
		navigationCommand,
		orderedItemIds,
		selectedItemId,
		selectInitialReviewItem,
	]);
}

export function resolveBridgeReviewNavigationTarget(props: {
	readonly getReviewItem: (itemId: string) => BridgeWorkerReviewDisplayItem | undefined;
	readonly navigationCommand: BridgeViewerNavigationCommand;
	readonly orderedItemIds: readonly string[];
}): BridgeReviewNavigationTargetResolution {
	const target = bridgeReviewNavigationTargetForCommand(props.navigationCommand);
	if (target === null) {
		return { status: 'none' };
	}
	const targetItemId =
		target.itemId ??
		props.orderedItemIds.find((itemId): boolean => {
			const item = props.getReviewItem(itemId);
			const displayPath = item?.metadata.headPath ?? item?.metadata.basePath ?? null;
			return displayPath !== null && displayPath === target.path;
		}) ??
		null;
	if (targetItemId === null || !props.orderedItemIds.includes(targetItemId)) {
		return { status: 'outsideAcceptedProjection', target };
	}
	return { itemId: targetItemId, status: 'accepted', target };
}

export function bridgeReviewNavigationTargetForCommand(
	navigationCommand: BridgeViewerNavigationCommand,
): BridgeReviewNavigationTarget | null {
	if (navigationCommand.context !== 'review' || navigationCommand.target === undefined) {
		return null;
	}
	const target = navigationCommand.target;
	const path = target.targetKind === 'file' ? target.fileRef.path : (target.fileRef?.path ?? null);
	return {
		commandId: navigationCommand.commandId,
		itemId: target.reviewItemId ?? null,
		path,
	};
}
