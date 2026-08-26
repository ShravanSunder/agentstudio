import type { CodeViewHandle } from '@pierre/diffs/react';

import { prepareBridgeMainPierreItemForPresentation } from '../../core/comm-worker/bridge-main-pierre-item-adapter.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { isBridgeCodeViewItem } from './bridge-code-view-panel-support.js';
import {
	bridgeCodeViewReanchorBoundFinalItem,
	bridgeCodeViewReanchorContentEquivalentPresentationItem,
	reconcileBridgeCodeViewRenderFulfillment,
	type BridgeCodeViewRenderFulfillmentCoordinator,
} from './bridge-code-view-render-fulfillment.js';

export function prepareBridgeCodeViewPublicationPresentationItem(props: {
	readonly currentItem: BridgeCodeViewItem | undefined;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly metadataItem: BridgeCodeViewItem;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderFulfillmentCoordinator;
}): BridgeCodeViewItem {
	if (props.renderFulfillmentCoordinator.isBoundFinalItem(props.metadataItem)) {
		return bridgeCodeViewReanchorBoundFinalItem(props.metadataItem);
	}
	const preparedItem = prepareBridgeMainPierreItemForPresentation({
		currentItem: props.currentItem,
		presentationItem: props.metadataItem,
	});
	props.renderFulfillmentCoordinator.bindPublicationItem({
		finalItem: preparedItem.item,
		publicationItem: props.metadataItem,
		residency: preparedItem.residency,
	});
	bridgeCodeViewReanchorBoundFinalItem(preparedItem.item);
	if (preparedItem.residency === 'reusedPainted') {
		const codeViewHandle = props.getCodeViewHandle();
		const currentHandlePresentationItem = codeViewHandle?.getItem(preparedItem.item.id);
		if (isBridgeCodeViewItem(currentHandlePresentationItem)) {
			bridgeCodeViewReanchorContentEquivalentPresentationItem({
				presentationItem: currentHandlePresentationItem,
				sourceItem: preparedItem.item,
			});
		}
		const renderedPresentationItem = codeViewHandle
			?.getInstance()
			?.getRenderedItems()
			.find((renderedItem): boolean => renderedItem.id === preparedItem.item.id)?.item;
		if (isBridgeCodeViewItem(renderedPresentationItem)) {
			bridgeCodeViewReanchorContentEquivalentPresentationItem({
				presentationItem: renderedPresentationItem,
				sourceItem: preparedItem.item,
			});
		}
		reconcileBridgeCodeViewRenderFulfillment({
			exactPresentationItem: preparedItem.item,
			getCodeViewHandle: props.getCodeViewHandle,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
		});
	}
	return preparedItem.item;
}
