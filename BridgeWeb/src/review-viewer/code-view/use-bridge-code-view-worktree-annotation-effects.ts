import type { CodeViewHandle } from '@pierre/diffs/react';
import { useLayoutEffect, useRef, type MutableRefObject } from 'react';

import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	controllerForHandle,
	isBridgeCodeViewItem,
	type BridgeCodeViewControllerEntry,
} from './bridge-code-view-panel-support.js';
import type { BridgeCodeViewWorktreeAnnotations } from './use-bridge-code-view-worktree-annotations.js';

export function useBridgeCodeViewWorktreeAnnotationEffects(props: {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly codeViewMountVersion: number;
	readonly controllerEntryRef: MutableRefObject<BridgeCodeViewControllerEntry | null>;
	readonly currentCodeViewItemsRef: MutableRefObject<readonly BridgeCodeViewItem[]>;
	readonly presentation: BridgeCodeViewWorktreeAnnotations;
	readonly sourceKey: string;
}): void {
	const { annotateItem, projectionRevision, selectedItemIdRef, selectedRange } = props.presentation;
	const appliedProjectionKeyRef = useRef<string | null>(null);
	useLayoutEffect((): void => {
		const codeViewHandle = props.codeViewHandleRef.current;
		const annotationRevision = projectionRevision;
		if (codeViewHandle === null || annotationRevision === null) return;
		const projectionKey = `${props.sourceKey}:${props.codeViewMountVersion}:${annotationRevision}`;
		if (appliedProjectionKeyRef.current === projectionKey) return;
		const annotatedItems = props.currentCodeViewItemsRef.current.map((recordedItem) => {
			const currentItem = codeViewHandle.getItem(recordedItem.id);
			const presentationItem = isBridgeCodeViewItem(currentItem) ? currentItem : recordedItem;
			return {
				...annotateItem(presentationItem),
				version: (presentationItem.version ?? 0) + 1,
			};
		});
		const controller = controllerForHandle({
			controllerEntryRef: props.controllerEntryRef,
			handle: codeViewHandle,
		});
		for (const item of annotatedItems) controller.applyItemUpdate(item);
		props.currentCodeViewItemsRef.current = annotatedItems;
		appliedProjectionKeyRef.current = projectionKey;
	}, [
		props.codeViewHandleRef,
		props.codeViewMountVersion,
		props.controllerEntryRef,
		props.currentCodeViewItemsRef,
		annotateItem,
		projectionRevision,
		props.sourceKey,
	]);
	useLayoutEffect((): void => {
		const codeViewHandle = props.codeViewHandleRef.current;
		if (codeViewHandle === null) return;
		const selectedItemId = selectedItemIdRef.current;
		codeViewHandle.setSelectedLines(
			selectedItemId === null || selectedRange === null
				? null
				: { id: selectedItemId, range: selectedRange },
		);
	}, [props.codeViewHandleRef, props.codeViewMountVersion, selectedItemIdRef, selectedRange]);
}
