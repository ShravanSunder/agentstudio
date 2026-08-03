import { useCallback, useState, type ReactElement } from 'react';

import {
	useBridgeReviewNavigationController,
	type BridgeReviewNavigationSelectionSource,
	type BridgeReviewNavigationTarget,
} from '../../app/bridge-app-review-navigation-controller.js';
import type { BridgeProductNavigationCommand } from '../../core/comm-worker/bridge-product-session-contracts.js';

type BridgeReviewTargetNavigationCommand = Extract<
	BridgeProductNavigationCommand,
	{ readonly commandKind: 'activateTarget'; readonly surface: 'review' }
>;

export function ReviewNavigationControllerProbe(props: {
	readonly events: string[];
}): ReactElement {
	const [catalogRevision, setCatalogRevision] = useState(1);
	const [navigationCommand, setNavigationCommand] = useState<BridgeReviewTargetNavigationCommand>(
		() => reviewNavigationCommand('command-two', 'item-two'),
	);
	const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
	const [orderedItemIds, setOrderedItemIds] = useState<readonly string[]>(['item-one', 'item-two']);
	const clearReviewSelection = useCallback((): void => {
		props.events.push('clear');
		setSelectedItemId(null);
	}, [props.events]);
	const onTargetOutsideAcceptedProjection = useCallback(
		(target: BridgeReviewNavigationTarget): void => {
			props.events.push(`outside:${target.itemId ?? target.path ?? 'unknown'}`);
		},
		[props.events],
	);
	const selectReviewItem = useCallback(
		(itemId: string, selectedSource: BridgeReviewNavigationSelectionSource): true => {
			props.events.push(`select:${itemId}:${selectedSource}`);
			setSelectedItemId(itemId);
			return true;
		},
		[props.events],
	);
	useBridgeReviewNavigationController({
		catalogRevision,
		clearReviewSelection,
		getReviewItem: (): undefined => undefined,
		isActive: true,
		navigationCommand,
		onTargetOutsideAcceptedProjection,
		orderedItemIds,
		selectedItemId,
		selectInitialReviewItem: selectReviewItem,
		selectReviewItem,
	});
	return (
		<>
			<button onClick={(): void => setCatalogRevision((revision) => revision + 1)} type="button">
				Advance Review catalog revision
			</button>
			<button onClick={(): void => setOrderedItemIds(['item-one'])} type="button">
				Filter selected Review item
			</button>
			<button
				onClick={(): void =>
					setNavigationCommand(reviewNavigationCommand('command-missing', 'item-missing'))
				}
				type="button"
			>
				Navigate outside Review projection
			</button>
			<output data-testid="review-navigation-selection">{selectedItemId ?? 'none'}</output>
		</>
	);
}

export function reviewNavigationCommand(
	commandId: string,
	reviewItemId: string,
): BridgeReviewTargetNavigationCommand {
	return {
		bindingRevision: 1,
		commandId,
		commandKind: 'activateTarget',
		source: {
			generation: 1,
			metadataSourceId: 'review-fixture',
			packageId: 'review-package',
			sourceKind: 'review',
		},
		surface: 'review',
		target: {
			reviewItemId,
			targetKind: 'review',
		},
	};
}
