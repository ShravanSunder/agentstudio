import type { CodeViewItem, PostRenderPhase } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';

import type {
	BridgeMainRenderedItemReadback,
	BridgeMainRenderFulfillmentCoordinator,
	BridgeMainRenderReadback,
} from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';

export type BridgeCodeViewRenderObservationCoordinator = Pick<
	BridgeMainRenderFulfillmentCoordinator,
	'observePostRender' | 'reconcilePublication'
>;

export type BridgeCodeViewRenderFulfillmentCoordinator =
	BridgeCodeViewRenderObservationCoordinator &
		Pick<BridgeMainRenderFulfillmentCoordinator, 'bindPublicationItem' | 'isBoundFinalItem'>;

export interface ObserveBridgeCodeViewRenderFulfillmentProps {
	readonly contextItem: CodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly itemId: string;
	readonly phase: PostRenderPhase;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderObservationCoordinator;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[] | undefined;
}

export function observeBridgeCodeViewRenderFulfillment(
	props: ObserveBridgeCodeViewRenderFulfillmentProps,
): void {
	const exactWorkerItem = exactWorkerItemForPostRender(props);
	if (exactWorkerItem === undefined) return;
	const readback = renderReadbackForExactWorkerItem({
		exactWorkerItem,
		getCodeViewHandle: props.getCodeViewHandle,
		itemId: props.itemId,
	});
	props.renderFulfillmentCoordinator.observePostRender({
		...readback,
		contextItem: exactWorkerItem,
		itemId: props.itemId,
		phase: props.phase,
	});
	if (props.phase === 'unmount') return;
	globalThis.queueMicrotask((): void => {
		props.renderFulfillmentCoordinator.reconcilePublication({
			...readback,
			itemId: props.itemId,
		});
	});
}

export function reconcileBridgeCodeViewRenderFulfillment(props: {
	readonly exactPresentationItem: BridgeMainCodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderObservationCoordinator;
}): void {
	props.renderFulfillmentCoordinator.reconcilePublication({
		...renderReadbackForExactWorkerItem({
			exactWorkerItem: props.exactPresentationItem,
			getCodeViewHandle: props.getCodeViewHandle,
			itemId: props.exactPresentationItem.id,
		}),
		itemId: props.exactPresentationItem.id,
	});
}

function exactWorkerItemForPostRender(
	props: ObserveBridgeCodeViewRenderFulfillmentProps,
): BridgeMainCodeViewItem | undefined {
	if (
		props.selectedCodeViewItem === props.contextItem &&
		props.selectedCodeViewItem.id === props.itemId
	) {
		return props.selectedCodeViewItem;
	}
	return props.visibleCodeViewItems?.find(
		(item): boolean => item === props.contextItem && item.id === props.itemId,
	);
}

function renderReadbackForExactWorkerItem(props: {
	readonly exactWorkerItem: BridgeMainCodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly itemId: string;
}): BridgeMainRenderReadback {
	return {
		readCurrentItem: (): BridgeMainCodeViewItem | undefined => {
			const currentItem = props.getCodeViewHandle()?.getItem(props.itemId);
			return currentItem === props.exactWorkerItem ? props.exactWorkerItem : undefined;
		},
		readRenderedItem: (): BridgeMainRenderedItemReadback | null => {
			const renderedItem = props
				.getCodeViewHandle()
				?.getInstance()
				?.getRenderedItems()
				.find((candidate): boolean => candidate.id === props.itemId);
			if (renderedItem?.item !== props.exactWorkerItem) return null;
			return {
				element: renderedItem.element,
				item: props.exactWorkerItem,
			};
		},
	};
}
