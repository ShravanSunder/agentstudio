import type { CodeViewHandle } from '@pierre/diffs/react';

import { prepareBridgeMainPierreItemForPresentation } from '../../core/comm-worker/bridge-main-pierre-item-adapter.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
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
		return props.metadataItem;
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
	if (preparedItem.residency === 'reusedPainted') {
		reconcileBridgeCodeViewRenderFulfillment({
			exactPresentationItem: preparedItem.item,
			getCodeViewHandle: props.getCodeViewHandle,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
		});
	}
	return preparedItem.item;
}
