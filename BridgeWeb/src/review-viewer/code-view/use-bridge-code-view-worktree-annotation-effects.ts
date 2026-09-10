import type { CodeViewHandle } from '@pierre/diffs/react';
import { useLayoutEffect, useRef, type MutableRefObject } from 'react';

import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	controllerForHandle,
	isBridgeCodeViewItem,
	type BridgeCodeViewControllerEntry,
} from './bridge-code-view-panel-support.js';
import { bridgeCodeViewPresentationItemWithExactSource } from './bridge-code-view-render-fulfillment.js';
import type { BridgeCodeViewWorktreeAnnotations } from './use-bridge-code-view-worktree-annotations.js';
import { worktreeAnnotationPierrePresentationsMatch } from './worktree-annotation-pierre-adapter.js';

export function applyWorktreeAnnotationsToCandidateCodeViewItems(props: {
	readonly annotateItem: (item: BridgeCodeViewItem) => BridgeCodeViewItem;
	readonly applyItemUpdate: (item: BridgeCodeViewItem) => void;
	readonly candidateItemIds: readonly string[] | null;
	readonly currentItemForId: (itemId: string) => BridgeCodeViewItem | undefined;
	readonly items: readonly BridgeCodeViewItem[];
}): readonly BridgeCodeViewItem[] {
	const candidateItemIds = props.candidateItemIds === null ? null : new Set(props.candidateItemIds);
	return props.items.map((recordedItem): BridgeCodeViewItem => {
		if (candidateItemIds !== null && !candidateItemIds.has(recordedItem.id)) return recordedItem;
		const presentationItem = props.currentItemForId(recordedItem.id) ?? recordedItem;
		const annotatedItem = props.annotateItem(presentationItem);
		if (
			worktreeAnnotationPierrePresentationsMatch(
				presentationItem.annotations,
				annotatedItem.annotations,
			)
		) {
			return presentationItem;
		}
		const versionedItem = bridgeCodeViewPresentationItemWithExactSource({
			presentationItem: {
				...annotatedItem,
				version: (presentationItem.version ?? 0) + 1,
			},
			sourceItem: annotatedItem,
		});
		props.applyItemUpdate(versionedItem);
		return versionedItem;
	});
}

export function useBridgeCodeViewWorktreeAnnotationEffects(props: {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly codeViewMountVersion: number;
	readonly controllerEntryRef: MutableRefObject<BridgeCodeViewControllerEntry | null>;
	readonly currentCodeViewItemsRef: MutableRefObject<readonly BridgeCodeViewItem[]>;
	readonly presentation: BridgeCodeViewWorktreeAnnotations;
	readonly sourceKey: string;
}): void {
	const {
		acknowledgeReviewAnnotationApplication,
		annotateItem,
		annotationApplicationId,
		annotationApplicationItemIds,
		projectionRevision,
	} = props.presentation;
	const appliedProjectionKeyRef = useRef<string | null>(null);
	useLayoutEffect((): void => {
		const codeViewHandle = props.codeViewHandleRef.current;
		const annotationRevision = projectionRevision;
		if (codeViewHandle === null || annotationRevision === null) return;
		const projectionKey = `${props.sourceKey}:${props.codeViewMountVersion}:${annotationRevision}`;
		if (appliedProjectionKeyRef.current === projectionKey) return;
		const controller = controllerForHandle({
			controllerEntryRef: props.controllerEntryRef,
			handle: codeViewHandle,
		});
		const annotatedItems = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem,
			applyItemUpdate: (item): void => {
				controller.applyItemUpdate(item);
			},
			candidateItemIds: annotationApplicationItemIds,
			currentItemForId: (itemId): BridgeCodeViewItem | undefined => {
				const currentItem = codeViewHandle.getItem(itemId);
				return isBridgeCodeViewItem(currentItem) ? currentItem : undefined;
			},
			items: props.currentCodeViewItemsRef.current,
		});
		props.currentCodeViewItemsRef.current = annotatedItems;
		if (annotationApplicationId !== null) {
			acknowledgeReviewAnnotationApplication(annotationApplicationId);
		}
		appliedProjectionKeyRef.current = projectionKey;
	}, [
		props.codeViewHandleRef,
		props.codeViewMountVersion,
		props.controllerEntryRef,
		props.currentCodeViewItemsRef,
		acknowledgeReviewAnnotationApplication,
		annotateItem,
		annotationApplicationId,
		annotationApplicationItemIds,
		projectionRevision,
		props.sourceKey,
	]);
}
