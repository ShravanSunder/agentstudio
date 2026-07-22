import type {
	BridgeMainPierreItemResidency,
	BridgeMainRenderPublicationItem,
} from './bridge-main-render-fulfillment-coordinator.js';

export interface PrepareBridgeMainPierreItemForPresentationProps<
	TItem extends BridgeMainRenderPublicationItem,
> {
	readonly currentItem: TItem | undefined;
	readonly presentationItem: TItem;
}

export interface PreparedBridgeMainPierreItem<TItem extends BridgeMainRenderPublicationItem> {
	readonly item: TItem;
	readonly residency: BridgeMainPierreItemResidency;
}

export function prepareBridgeMainPierreItemForPresentation<
	TItem extends BridgeMainRenderPublicationItem,
>(
	props: PrepareBridgeMainPierreItemForPresentationProps<TItem>,
): PreparedBridgeMainPierreItem<TItem> {
	assertBridgeMainPierreItemIdentityIsStable(props);
	const presentationItem = bridgeMainPierreItemWithPreservedPresentation(props);
	if (
		props.currentItem !== undefined &&
		bridgeMainPierreItemFingerprint(props.currentItem) ===
			bridgeMainPierreItemFingerprint(presentationItem)
	) {
		return Object.freeze({ item: props.currentItem, residency: 'reusedPainted' });
	}

	const version = (props.currentItem?.version ?? 0) + 1;
	if (!Number.isSafeInteger(version)) {
		throw new Error('Bridge main Pierre item version exhausted its safe integer range.');
	}
	const item: TItem = { ...presentationItem, version };
	return Object.freeze({
		item,
		residency: 'replaced',
	});
}

function bridgeMainPierreItemWithPreservedPresentation<
	TItem extends BridgeMainRenderPublicationItem,
>(props: PrepareBridgeMainPierreItemForPresentationProps<TItem>): TItem {
	if (props.currentItem?.collapsed === undefined) {
		return props.presentationItem;
	}
	return {
		...props.presentationItem,
		collapsed: props.currentItem.collapsed,
	};
}

function bridgeMainPierreItemFingerprint(item: BridgeMainRenderPublicationItem): string {
	const fingerprintParts = [
		'bridge-main-pierre-item-v1',
		item.id,
		item.type,
		item.collapsed === true ? 'collapsed' : 'expanded',
		item.bridgeMetadata.itemId,
		item.bridgeMetadata.displayPath,
		item.bridgeMetadata.contentState,
		item.bridgeMetadata.cacheKey,
		item.bridgeMetadata.lineCount === null ? 'unknown-lines' : `${item.bridgeMetadata.lineCount}`,
		...item.bridgeMetadata.contentRoles,
	];
	if (item.type === 'file') {
		fingerprintParts.push(
			item.file.cacheKey ?? '',
			item.file.name,
			item.file.lang ?? '',
			item.file.header ?? '',
		);
	} else {
		fingerprintParts.push(
			item.fileDiff.cacheKey ?? '',
			item.fileDiff.name,
			item.fileDiff.prevName ?? '',
			item.fileDiff.lang ?? '',
			item.fileDiff.newObjectId ?? '',
			item.fileDiff.prevObjectId ?? '',
			item.fileDiff.mode ?? '',
			item.fileDiff.prevMode ?? '',
			item.fileDiff.type,
			item.fileDiff.isPartial ? 'partial' : 'complete',
			`${item.fileDiff.splitLineCount}`,
			`${item.fileDiff.unifiedLineCount}`,
		);
	}
	return fingerprintParts.map(bridgeMainPierreFingerprintToken).join('|');
}

function bridgeMainPierreFingerprintToken(value: string): string {
	return `${value.length}:${value}`;
}

function assertBridgeMainPierreItemIdentityIsStable(
	props: PrepareBridgeMainPierreItemForPresentationProps<BridgeMainRenderPublicationItem>,
): void {
	if (
		props.currentItem !== undefined &&
		(props.currentItem.id !== props.presentationItem.id ||
			props.currentItem.type !== props.presentationItem.type ||
			props.currentItem.bridgeMetadata.itemId !== props.presentationItem.bridgeMetadata.itemId)
	) {
		throw new Error('Bridge main Pierre item replacement changed stable item identity or kind.');
	}
}
