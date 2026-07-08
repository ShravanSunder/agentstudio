import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import { bridgePierreOptionalHighlightLanguage } from '../workers/pierre/bridge-pierre-language-normalization.js';
import {
	materializeBridgeCodeViewLoadingItem,
	type BridgeCodeViewFilePresentationVersion,
	type BridgeCodeViewItem,
	type BridgeCodeViewItemPresentation,
} from './bridge-code-view-materialization.js';

export function createBridgeCodeViewMetadataDeltaItemsForPanel(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
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
		props.selectedItemPresentation !== null &&
		props.selectedItemPresentation !== undefined
	) {
		deltaItemsById.set(
			props.selectedItemId,
			materializeBridgeCodeViewLoadingItem(selectedDescriptor, props.selectedItemPresentation),
		);
	}
	return [...deltaItemsById.values()];
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

export function bridgeCodeViewItemFromWorkerPreparedItem(
	item: BridgeMainCodeViewItem | null | undefined,
): BridgeCodeViewItem | null {
	if (item === null || item === undefined) {
		return null;
	}
	if (item.type === 'file') {
		const normalizedLanguage = bridgePierreOptionalHighlightLanguage(item.file.lang);
		return {
			id: item.id,
			type: item.type,
			file: {
				name: item.file.name,
				contents: item.file.contents,
				...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
				...(item.file.header === undefined ? {} : { header: item.file.header }),
				...(item.file.cacheKey === undefined ? {} : { cacheKey: item.file.cacheKey }),
			},
			...(item.version === undefined ? {} : { version: item.version }),
			...(item.collapsed === undefined ? {} : { collapsed: item.collapsed }),
			bridgeMetadata: item.bridgeMetadata,
		} satisfies BridgeCodeViewItem;
	}
	const normalizedLanguage = bridgePierreOptionalHighlightLanguage(item.fileDiff.lang);
	return {
		id: item.id,
		type: item.type,
		fileDiff: {
			name: item.fileDiff.name,
			...(item.fileDiff.prevName === undefined ? {} : { prevName: item.fileDiff.prevName }),
			...(normalizedLanguage === undefined ? {} : { lang: normalizedLanguage }),
			...(item.fileDiff.newObjectId === undefined
				? {}
				: { newObjectId: item.fileDiff.newObjectId }),
			...(item.fileDiff.prevObjectId === undefined
				? {}
				: { prevObjectId: item.fileDiff.prevObjectId }),
			...(item.fileDiff.mode === undefined ? {} : { mode: item.fileDiff.mode }),
			...(item.fileDiff.prevMode === undefined ? {} : { prevMode: item.fileDiff.prevMode }),
			type: item.fileDiff.type,
			hunks: item.fileDiff.hunks.map((hunk) => ({
				collapsedBefore: hunk.collapsedBefore,
				additionStart: hunk.additionStart,
				additionCount: hunk.additionCount,
				additionLines: hunk.additionLines,
				additionLineIndex: hunk.additionLineIndex,
				deletionStart: hunk.deletionStart,
				deletionCount: hunk.deletionCount,
				deletionLines: hunk.deletionLines,
				deletionLineIndex: hunk.deletionLineIndex,
				hunkContent: hunk.hunkContent.map((content) => ({ ...content })),
				...(hunk.hunkContext === undefined ? {} : { hunkContext: hunk.hunkContext }),
				...(hunk.hunkSpecs === undefined ? {} : { hunkSpecs: hunk.hunkSpecs }),
				splitLineStart: hunk.splitLineStart,
				splitLineCount: hunk.splitLineCount,
				unifiedLineStart: hunk.unifiedLineStart,
				unifiedLineCount: hunk.unifiedLineCount,
				noEOFCRDeletions: hunk.noEOFCRDeletions,
				noEOFCRAdditions: hunk.noEOFCRAdditions,
			})),
			splitLineCount: item.fileDiff.splitLineCount,
			unifiedLineCount: item.fileDiff.unifiedLineCount,
			isPartial: item.fileDiff.isPartial,
			deletionLines: [...item.fileDiff.deletionLines],
			additionLines: [...item.fileDiff.additionLines],
			...(item.fileDiff.cacheKey === undefined ? {} : { cacheKey: item.fileDiff.cacheKey }),
		},
		...(item.version === undefined ? {} : { version: item.version }),
		...(item.collapsed === undefined ? {} : { collapsed: item.collapsed }),
		bridgeMetadata: item.bridgeMetadata,
	} satisfies BridgeCodeViewItem;
}
