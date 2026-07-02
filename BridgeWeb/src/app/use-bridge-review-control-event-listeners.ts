import type { MutableRefObject } from 'react';
import { useLayoutEffect } from 'react';

import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import type { BridgeCodeViewControlHandle } from '../review-viewer/code-view/bridge-code-view-panel.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import type {
	BridgeReviewViewerRootSnapshot,
	BridgeReviewViewerStore,
	BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import type { BridgeMarkdownRenderWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import {
	applyBridgeAppControlCommand,
	makeBridgeAppControlProbe,
	nextBridgeAppControlProbeSequence,
	publishBridgeAppControlProbe,
} from './bridge-app-control-commands.js';
import {
	bridgeAppControlCommandSchema,
	type BridgeAppControlCommand,
} from './bridge-app-control.js';
import type {
	BridgeReviewFileNavigationTarget,
	SelectedMarkdownPreviewState,
} from './bridge-app-review-selection-state.js';

interface UseBridgeReviewControlEventListenersProps {
	readonly codeViewControlHandleRef: MutableRefObject<BridgeCodeViewControlHandle | null>;
	readonly controlProbeSequenceRef: MutableRefObject<number>;
	readonly isActive: boolean;
	readonly markdownWorkerClient: BridgeMarkdownRenderWorkerClient | null;
	readonly projectionRef: MutableRefObject<BridgeReviewProjectionResult | null>;
	readonly reviewPackageRef: MutableRefObject<BridgeReviewPackage | null>;
	readonly rootSnapshotRef: MutableRefObject<BridgeReviewViewerRootSnapshot>;
	readonly selectedContentResources: BridgeCodeViewContentResources | null;
	readonly selectedMarkdownPreviewState: SelectedMarkdownPreviewState | null;
	readonly selectReviewItem: (
		itemId: string,
		presentationTarget?: BridgeReviewFileNavigationTarget | null,
	) => boolean;
	readonly setTreeSearchOpen: (isOpen: boolean) => void;
	readonly target: EventTarget;
	readonly viewerActions: BridgeReviewViewerStoreActions;
	readonly viewerStore: BridgeReviewViewerStore;
}

export function useBridgeReviewControlEventListeners(
	props: UseBridgeReviewControlEventListenersProps,
): void {
	const {
		codeViewControlHandleRef,
		controlProbeSequenceRef,
		isActive,
		markdownWorkerClient,
		projectionRef,
		reviewPackageRef,
		rootSnapshotRef,
		selectedContentResources,
		selectedMarkdownPreviewState,
		selectReviewItem,
		setTreeSearchOpen,
		target,
		viewerActions,
		viewerStore,
	} = props;

	useLayoutEffect((): (() => void) => {
		if (!isActive) {
			return (): void => {};
		}
		const handleSelectReviewItem = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			if (!isRecord(detail) || typeof detail['itemId'] !== 'string') {
				return;
			}
			selectReviewItem(detail['itemId']);
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		target.addEventListener('__bridge_select_review_item', handleSelectReviewItem);
		if (windowTarget !== null && windowTarget !== target) {
			windowTarget.addEventListener('__bridge_select_review_item', handleSelectReviewItem);
		}
		return (): void => {
			target.removeEventListener('__bridge_select_review_item', handleSelectReviewItem);
			if (windowTarget !== null && windowTarget !== target) {
				windowTarget.removeEventListener('__bridge_select_review_item', handleSelectReviewItem);
			}
		};
	}, [isActive, selectReviewItem, target]);

	useLayoutEffect((): (() => void) => {
		if (!isActive) {
			return (): void => {};
		}
		const handleBridgeAppControl = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const parsedCommand = bridgeAppControlCommandSchema.safeParse(detail);
			if (!parsedCommand.success) {
				publishBridgeAppControlProbe({
					probe: makeBridgeAppControlProbe({
						command: invalidControlProbeCommand,
						status: 'rejected',
						reason: 'invalid_control_command',
						sequence: nextBridgeAppControlProbeSequence(controlProbeSequenceRef),
						rootSnapshot: rootSnapshotRef.current,
					}),
				});
				return;
			}
			const result = applyBridgeAppControlCommand({
				command: parsedCommand.data,
				markdownWorkerClient,
				projection: projectionRef.current,
				rootSnapshot: rootSnapshotRef.current,
				reviewPackage: reviewPackageRef.current,
				selectReviewItem,
				selectedContentResources,
				selectedMarkdownPreviewState,
				setTreeSearchOpen,
				codeViewControlHandle: codeViewControlHandleRef.current,
				viewerActions,
			});
			publishBridgeAppControlProbe({
				probe: makeBridgeAppControlProbe({
					command: parsedCommand.data,
					status: result.status,
					reason: result.reason,
					sequence: nextBridgeAppControlProbeSequence(controlProbeSequenceRef),
					rootSnapshot: viewerStore.getState().rootSnapshot,
				}),
			});
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		target.addEventListener('__bridge_review_control', handleBridgeAppControl);
		if (windowTarget !== null && windowTarget !== target) {
			windowTarget.addEventListener('__bridge_review_control', handleBridgeAppControl);
		}
		return (): void => {
			target.removeEventListener('__bridge_review_control', handleBridgeAppControl);
			if (windowTarget !== null && windowTarget !== target) {
				windowTarget.removeEventListener('__bridge_review_control', handleBridgeAppControl);
			}
		};
	}, [
		codeViewControlHandleRef,
		controlProbeSequenceRef,
		isActive,
		markdownWorkerClient,
		projectionRef,
		reviewPackageRef,
		rootSnapshotRef,
		selectReviewItem,
		selectedContentResources,
		selectedMarkdownPreviewState,
		setTreeSearchOpen,
		target,
		viewerActions,
		viewerStore,
	]);
}

const invalidControlProbeCommand: BridgeAppControlCommand = {
	method: 'bridge.fileTree.search',
	searchText: '',
	searchMode: { kind: 'text' },
};

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
