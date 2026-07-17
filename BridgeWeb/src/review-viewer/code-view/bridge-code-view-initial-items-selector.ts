import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import { bridgeCodeViewDescriptorPlaceholderSignature } from './bridge-code-view-descriptor-signature.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { createBridgeCodeViewInitialItemsForPanel } from './bridge-code-view-panel-support.js';

export type BridgeCodeViewInitialItemsForPanelSelector = (props: {
	readonly projection: BridgeReviewProjectionResult;
	readonly reviewPackage: BridgeReviewPackage;
	readonly seedItemIds?: readonly string[] | undefined;
	readonly sourceKey: string;
}) => readonly BridgeCodeViewItem[];

export function createBridgeCodeViewInitialItemsForPanelSelector(): BridgeCodeViewInitialItemsForPanelSelector {
	let previousSourceKey: string | null = null;
	let previousSeedItemIds: readonly string[] | undefined;
	let previousSeedSignature: string | null = null;
	let previousItems: readonly BridgeCodeViewItem[] | null = null;
	return (props): readonly BridgeCodeViewItem[] => {
		const seedSignature = bridgeCodeViewInitialSeedSignature(props);
		if (
			previousItems !== null &&
			previousSourceKey === props.sourceKey &&
			optionalStringArraysEqual(previousSeedItemIds, props.seedItemIds) &&
			previousSeedSignature === seedSignature
		) {
			return previousItems;
		}
		const nextItems = createBridgeCodeViewInitialItemsForPanel({
			projection: props.projection,
			reviewPackage: props.reviewPackage,
			...(props.seedItemIds === undefined ? {} : { seedItemIds: props.seedItemIds }),
		});
		previousSourceKey = props.sourceKey;
		previousSeedSignature = seedSignature;
		previousSeedItemIds = props.seedItemIds === undefined ? undefined : [...props.seedItemIds];
		previousItems = nextItems;
		return nextItems;
	};
}

function bridgeCodeViewInitialSeedSignature(props: {
	readonly projection: BridgeReviewProjectionResult;
	readonly reviewPackage: BridgeReviewPackage;
	readonly seedItemIds?: readonly string[] | undefined;
}): string {
	if (props.seedItemIds === undefined) {
		return props.projection.orderedItemIds
			.map((itemId): string =>
				[
					itemId,
					bridgeCodeViewDescriptorPlaceholderSignature(props.reviewPackage.itemsById[itemId]),
				].join('\u001e'),
			)
			.join('\u001d');
	}
	return props.seedItemIds
		.map((itemId): string => {
			const hasProjectionItem =
				props.projection.orderedItemRankByItemId === undefined
					? Object.hasOwn(props.projection.primaryDisplayPathByItemId, itemId)
					: props.projection.orderedItemRankByItemId[itemId] !== undefined;
			return [
				itemId,
				hasProjectionItem ? 'projected' : 'missing-projection',
				bridgeCodeViewDescriptorPlaceholderSignature(props.reviewPackage.itemsById[itemId]),
			].join('\u001e');
		})
		.join('\u001d');
}

function optionalStringArraysEqual(
	first: readonly string[] | undefined,
	second: readonly string[] | undefined,
): boolean {
	if (first === undefined || second === undefined) {
		return first === second;
	}
	if (first.length !== second.length) {
		return false;
	}
	return first.every((value, index): boolean => value === second[index]);
}
