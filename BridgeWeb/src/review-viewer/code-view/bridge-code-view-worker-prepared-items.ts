import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import { bridgePierreOptionalHighlightLanguage } from '../workers/pierre/bridge-pierre-language-normalization.js';
import { bridgeCodeViewDescriptorPlaceholderSignature } from './bridge-code-view-descriptor-signature.js';
import {
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewDiffItem,
	type BridgeCodeViewFileItem,
	type BridgeCodeViewFilePresentationVersion,
	type BridgeCodeViewItem,
	type BridgeCodeViewItemPresentation,
} from './bridge-code-view-materialization.js';

type BridgeWorkerPreparedFilePayload = Extract<
	BridgeMainCodeViewItem,
	{ readonly type: 'file' }
>['file'];
type BridgeWorkerPreparedDiffPayload = Extract<
	BridgeMainCodeViewItem,
	{ readonly type: 'diff' }
>['fileDiff'];
type BridgeNormalizedLanguage = ReturnType<typeof bridgePierreOptionalHighlightLanguage>;

export function createBridgeCodeViewMetadataDeltaItemsForPanel(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly selectedContentLoadingItemId?: string | null | undefined;
	readonly selectedItemId: string | null;
	readonly selectedItemPresentation: BridgeCodeViewItemPresentation | null | undefined;
	readonly visibleCodeViewItems?: readonly BridgeMainCodeViewItem[] | undefined;
}): readonly BridgeCodeViewItem[] {
	const deltaItemsById = new Map<string, BridgeCodeViewItem>();
	for (const visibleCodeViewItem of props.visibleCodeViewItems ?? []) {
		const codeViewItem = bridgeCodeViewItemFromWorkerPreparedItem(visibleCodeViewItem);
		if (codeViewItem !== null && codeViewItem.bridgeMetadata.itemId === codeViewItem.id) {
			deltaItemsById.set(codeViewItem.id, codeViewItem);
		}
	}
	const selectedCodeViewItem = bridgeCodeViewItemFromWorkerPreparedItem(props.selectedCodeViewItem);
	if (props.selectedItemId === null) {
		return [...deltaItemsById.values()];
	}
	const selectedDescriptor = props.reviewPackage.itemsById[props.selectedItemId];
	const selectedVisibleCodeViewItem = deltaItemsById.get(props.selectedItemId) ?? null;
	const matchingSelectedCodeViewItem = [selectedCodeViewItem, selectedVisibleCodeViewItem].find(
		(item): item is BridgeCodeViewItem =>
			item !== null &&
			item.bridgeMetadata.itemId === props.selectedItemId &&
			selectedCodeViewItemMatchesPresentation({
				item,
				presentation: props.selectedItemPresentation,
				selectedDescriptor,
			}),
	);
	if (matchingSelectedCodeViewItem !== undefined) {
		deltaItemsById.set(props.selectedItemId, matchingSelectedCodeViewItem);
		return [...deltaItemsById.values()];
	}
	if (
		selectedDescriptor !== undefined &&
		((props.selectedItemPresentation !== null && props.selectedItemPresentation !== undefined) ||
			props.selectedContentLoadingItemId === props.selectedItemId)
	) {
		deltaItemsById.set(
			props.selectedItemId,
			materializeBridgeCodeViewLoadingItem(
				selectedDescriptor,
				props.selectedItemPresentation ?? null,
			),
		);
	}
	return [...deltaItemsById.values()];
}

export type BridgeCodeViewMetadataDeltaItemsForPanelSelector = (props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly selectedContentLoadingItemId?: string | null | undefined;
	readonly selectedItemId: string | null;
	readonly selectedItemPresentation: BridgeCodeViewItemPresentation | null | undefined;
	readonly sourceKey: string;
	readonly visibleCodeViewItems?: readonly BridgeMainCodeViewItem[] | undefined;
}) => readonly BridgeCodeViewItem[];

interface BridgeCodeViewMetadataDeltaItemsCacheEntry {
	readonly result: readonly BridgeCodeViewItem[];
	readonly selectedDescriptorSignature: string | null;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly selectedContentLoadingItemId: string | null | undefined;
	readonly selectedItemId: string | null;
	readonly selectedItemPresentationKey: string;
	readonly sourceKey: string;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[] | undefined;
}

export function createBridgeCodeViewMetadataDeltaItemsForPanelSelector(): BridgeCodeViewMetadataDeltaItemsForPanelSelector {
	let previousEntry: BridgeCodeViewMetadataDeltaItemsCacheEntry | null = null;
	return (props): readonly BridgeCodeViewItem[] => {
		const selectedDescriptor =
			props.selectedItemId === null
				? undefined
				: props.reviewPackage.itemsById[props.selectedItemId];
		const selectedDescriptorSignature = bridgeReviewSelectedDescriptorSignature(selectedDescriptor);
		const selectedItemPresentationKey = bridgeCodeViewItemPresentationKey(
			props.selectedItemPresentation,
		);
		if (
			previousEntry !== null &&
			previousEntry.sourceKey === props.sourceKey &&
			previousEntry.selectedItemId === props.selectedItemId &&
			previousEntry.selectedContentLoadingItemId === props.selectedContentLoadingItemId &&
			previousEntry.selectedCodeViewItem === props.selectedCodeViewItem &&
			previousEntry.selectedItemPresentationKey === selectedItemPresentationKey &&
			previousEntry.selectedDescriptorSignature === selectedDescriptorSignature &&
			optionalCodeViewItemArraysEqual(
				previousEntry.visibleCodeViewItems,
				props.visibleCodeViewItems,
			)
		) {
			return previousEntry.result;
		}
		const result = createBridgeCodeViewMetadataDeltaItemsForPanel(props);
		previousEntry = {
			result,
			selectedCodeViewItem: props.selectedCodeViewItem,
			selectedContentLoadingItemId: props.selectedContentLoadingItemId,
			selectedDescriptorSignature,
			selectedItemId: props.selectedItemId,
			selectedItemPresentationKey,
			sourceKey: props.sourceKey,
			visibleCodeViewItems: props.visibleCodeViewItems,
		};
		return result;
	};
}

function optionalCodeViewItemArraysEqual(
	first: readonly BridgeMainCodeViewItem[] | undefined,
	second: readonly BridgeMainCodeViewItem[] | undefined,
): boolean {
	if (first === undefined || second === undefined) {
		return first === second;
	}
	if (first.length !== second.length) {
		return false;
	}
	return first.every((item, index): boolean => item === second[index]);
}

export function bridgeMainCodeViewItemSignature(item: BridgeMainCodeViewItem): string {
	const metadata = item.bridgeMetadata;
	const baseFields = [
		item.id,
		item.type,
		String(item.version ?? ''),
		String(item.collapsed ?? ''),
		metadata.itemId,
		metadata.displayPath,
		metadata.contentState,
		metadata.contentRoles.join(','),
		metadata.cacheKey,
		String(metadata.lineCount ?? ''),
	];
	return item.type === 'file'
		? [...baseFields, bridgePreparedFilePayloadSignature(item.file)].join('\u001f')
		: [...baseFields, bridgePreparedDiffPayloadSignature(item.fileDiff)].join('\u001f');
}

function bridgePreparedFilePayloadSignature(file: BridgeWorkerPreparedFilePayload): string {
	return [
		file.name,
		normalizedWorkerPreparedLanguage(file.lang),
		file.header ?? '',
		file.cacheKey ?? 'unkeyed-file',
	].join('\u001e');
}

function bridgePreparedDiffPayloadSignature(fileDiff: BridgeWorkerPreparedDiffPayload): string {
	return [
		fileDiff.name,
		fileDiff.prevName ?? '',
		normalizedWorkerPreparedLanguage(fileDiff.lang),
		fileDiff.newObjectId ?? '',
		fileDiff.prevObjectId ?? '',
		fileDiff.mode ?? '',
		fileDiff.prevMode ?? '',
		fileDiff.type,
		String(fileDiff.splitLineCount),
		String(fileDiff.unifiedLineCount),
		String(fileDiff.isPartial),
		fileDiff.cacheKey ?? 'unkeyed-diff',
	].join('\u001e');
}

function normalizedWorkerPreparedLanguage(language: string | undefined): string {
	return bridgePierreOptionalHighlightLanguage(language) ?? '';
}

function bridgeCodeViewItemPresentationKey(
	presentation: BridgeCodeViewItemPresentation | null | undefined,
): string {
	if (presentation === null || presentation === undefined) {
		return 'none';
	}
	if (presentation.kind === 'diff') {
		return 'diff';
	}
	return `file:${presentation.version}`;
}

function bridgeReviewSelectedDescriptorSignature(
	descriptor: BridgeReviewItemDescriptor | undefined,
): string | null {
	if (descriptor === undefined) {
		return null;
	}
	return bridgeCodeViewDescriptorPlaceholderSignature(descriptor);
}

function selectedCodeViewItemMatchesPresentation(props: {
	readonly item: BridgeCodeViewItem;
	readonly presentation: BridgeCodeViewItemPresentation | null | undefined;
	readonly selectedDescriptor: BridgeReviewItemDescriptor | undefined;
}): boolean {
	if (props.presentation === null || props.presentation === undefined) {
		return true;
	}
	if (props.presentation.kind === 'diff') {
		return props.item.type === 'diff';
	}
	if (props.selectedDescriptor === undefined) {
		return false;
	}
	const expectedRole = contentRoleForFilePresentation({
		item: props.selectedDescriptor,
		version: props.presentation.version,
	});
	if (expectedRole === null || !props.item.bridgeMetadata.contentRoles.includes(expectedRole)) {
		return false;
	}
	if (props.item.type === 'file') {
		return true;
	}
	return (
		props.item.type === 'diff' &&
		(props.selectedDescriptor.changeKind === 'added' ||
			props.selectedDescriptor.changeKind === 'deleted')
	);
}

function contentRoleForFilePresentation(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly version: BridgeCodeViewFilePresentationVersion;
}): BridgeContentRole | null {
	switch (props.version) {
		case 'base':
			return props.item.contentRoles.base === null || props.item.contentRoles.base === undefined
				? null
				: 'base';
		case 'head':
			if (props.item.contentRoles.head !== null && props.item.contentRoles.head !== undefined) {
				return 'head';
			}
			return props.item.contentRoles.file === null || props.item.contentRoles.file === undefined
				? null
				: 'file';
		case 'current':
			if (props.item.contentRoles.head !== null && props.item.contentRoles.head !== undefined) {
				return 'head';
			}
			if (props.item.contentRoles.file !== null && props.item.contentRoles.file !== undefined) {
				return 'file';
			}
			if (props.item.contentRoles.diff !== null && props.item.contentRoles.diff !== undefined) {
				return 'diff';
			}
			return props.item.contentRoles.base === null || props.item.contentRoles.base === undefined
				? null
				: 'base';
	}
	const exhaustiveVersion: never = props.version;
	void exhaustiveVersion;
	return null;
}

function bridgeWorkerPreparedFileWithNormalizedLanguage(
	file: BridgeWorkerPreparedFilePayload,
	normalizedLanguage: BridgeNormalizedLanguage,
): BridgeCodeViewFileItem['file'] {
	if (bridgeWorkerPreparedFileUsesNormalizedLanguage(file, normalizedLanguage)) {
		return file;
	}
	return {
		name: file.name,
		contents: file.contents,
		...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
		...(file.header === undefined ? {} : { header: file.header }),
		...(file.cacheKey === undefined ? {} : { cacheKey: file.cacheKey }),
	} satisfies BridgeCodeViewFileItem['file'];
}

function bridgeWorkerPreparedDiffWithNormalizedLanguage(
	fileDiff: BridgeWorkerPreparedDiffPayload,
	normalizedLanguage: BridgeNormalizedLanguage,
): BridgeCodeViewDiffItem['fileDiff'] {
	if (bridgeWorkerPreparedDiffUsesNormalizedLanguage(fileDiff, normalizedLanguage)) {
		return fileDiff;
	}
	if (!bridgeWorkerPreparedDiffUsesPierreArrayReferences(fileDiff)) {
		throw new Error('Expected worker-prepared diff arrays to be Pierre-compatible arrays.');
	}
	return {
		name: fileDiff.name,
		...(fileDiff.prevName === undefined ? {} : { prevName: fileDiff.prevName }),
		...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
		...(fileDiff.newObjectId === undefined ? {} : { newObjectId: fileDiff.newObjectId }),
		...(fileDiff.prevObjectId === undefined ? {} : { prevObjectId: fileDiff.prevObjectId }),
		...(fileDiff.mode === undefined ? {} : { mode: fileDiff.mode }),
		...(fileDiff.prevMode === undefined ? {} : { prevMode: fileDiff.prevMode }),
		type: fileDiff.type,
		hunks: fileDiff.hunks,
		splitLineCount: fileDiff.splitLineCount,
		unifiedLineCount: fileDiff.unifiedLineCount,
		isPartial: fileDiff.isPartial,
		deletionLines: fileDiff.deletionLines,
		additionLines: fileDiff.additionLines,
		...(fileDiff.cacheKey === undefined ? {} : { cacheKey: fileDiff.cacheKey }),
	} satisfies BridgeCodeViewDiffItem['fileDiff'];
}

function bridgeWorkerPreparedFileUsesNormalizedLanguage(
	file: BridgeWorkerPreparedFilePayload,
	normalizedLanguage: BridgeNormalizedLanguage,
): file is BridgeCodeViewFileItem['file'] {
	return file.lang === normalizedLanguage;
}

function bridgeWorkerPreparedDiffUsesNormalizedLanguage(
	fileDiff: BridgeWorkerPreparedDiffPayload,
	normalizedLanguage: BridgeNormalizedLanguage,
): fileDiff is BridgeCodeViewDiffItem['fileDiff'] {
	return fileDiff.lang === normalizedLanguage;
}

function bridgeWorkerPreparedDiffUsesPierreArrayReferences(
	fileDiff: BridgeWorkerPreparedDiffPayload,
): fileDiff is BridgeWorkerPreparedDiffPayload &
	Pick<BridgeCodeViewDiffItem['fileDiff'], 'additionLines' | 'deletionLines' | 'hunks'> {
	return (
		Array.isArray(fileDiff.hunks) &&
		Array.isArray(fileDiff.additionLines) &&
		Array.isArray(fileDiff.deletionLines)
	);
}

function bridgeWorkerPreparedFileItemUsesNormalizedLanguage(
	item: Extract<BridgeMainCodeViewItem, { readonly type: 'file' }>,
	normalizedLanguage: BridgeNormalizedLanguage,
): item is BridgeCodeViewFileItem {
	return bridgeWorkerPreparedFileUsesNormalizedLanguage(item.file, normalizedLanguage);
}

function bridgeWorkerPreparedDiffItemUsesNormalizedLanguage(
	item: Extract<BridgeMainCodeViewItem, { readonly type: 'diff' }>,
	normalizedLanguage: BridgeNormalizedLanguage,
): item is BridgeCodeViewDiffItem {
	return bridgeWorkerPreparedDiffUsesNormalizedLanguage(item.fileDiff, normalizedLanguage);
}

export function bridgeCodeViewItemFromWorkerPreparedItem(
	item: BridgeMainCodeViewItem | null | undefined,
): BridgeCodeViewItem | null {
	if (item === null || item === undefined) {
		return null;
	}
	if (item.type === 'file') {
		const normalizedLanguage = bridgePierreOptionalHighlightLanguage(item.file.lang);
		if (bridgeWorkerPreparedFileItemUsesNormalizedLanguage(item, normalizedLanguage)) {
			return item;
		}
		const file = bridgeWorkerPreparedFileWithNormalizedLanguage(item.file, normalizedLanguage);
		return {
			id: item.id,
			type: item.type,
			file,
			...(item.version === undefined ? {} : { version: item.version }),
			...(item.collapsed === undefined ? {} : { collapsed: item.collapsed }),
			bridgeMetadata: item.bridgeMetadata,
		} satisfies BridgeCodeViewItem;
	}
	const normalizedLanguage = bridgePierreOptionalHighlightLanguage(item.fileDiff.lang);
	if (bridgeWorkerPreparedDiffItemUsesNormalizedLanguage(item, normalizedLanguage)) {
		return item;
	}
	const fileDiff = bridgeWorkerPreparedDiffWithNormalizedLanguage(
		item.fileDiff,
		normalizedLanguage,
	);
	return {
		id: item.id,
		type: item.type,
		fileDiff,
		...(item.version === undefined ? {} : { version: item.version }),
		...(item.collapsed === undefined ? {} : { collapsed: item.collapsed }),
		bridgeMetadata: item.bridgeMetadata,
	} satisfies BridgeCodeViewItem;
}
