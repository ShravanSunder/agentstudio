import type { BridgeWorkerCodeViewFileItem } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeCodeViewItem } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import { bridgePierreOptionalHighlightLanguage } from '../review-viewer/workers/pierre/bridge-pierre-language-normalization.js';

export type BridgeFileViewerCodePanelState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
	  };

export interface BridgeFileViewerCodePanelContent {
	readonly body: string;
	readonly bodyVersion: number;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
}

export type BridgeFileViewerSelectedCodeViewItem = BridgeWorkerCodeViewFileItem;

export function bridgeFileViewerCodeViewItemsForPanelState(props: {
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
}): readonly BridgeCodeViewItem[] {
	if (props.selectedCodeViewItem === null) {
		return codeViewPlaceholderItemsForOpenFileState(props.openFileState);
	}
	return [bridgeFileViewerPierreCodeViewItemFromSelectedItem(props.selectedCodeViewItem)];
}

export function bridgeFileViewerSelectedCodeViewItemForPanelState(props: {
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly renderedFileContent: BridgeFileViewerCodePanelContent | null;
}): BridgeFileViewerSelectedCodeViewItem | null {
	if (props.renderedFileContent === null) {
		return null;
	}
	const content = props.renderedFileContent;
	const descriptor = content.descriptor;
	const reservedContent = contentBodyReservedForSelectedFileExtent({
		content,
		openFileState: props.openFileState,
	});
	const cacheKey =
		reservedContent.cacheKeySegment === null
			? `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}`
			: `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}:${reservedContent.cacheKeySegment}`;

	return {
		id: `file:${descriptor.fileId}`,
		type: 'file',
		file: {
			name: content.path,
			contents: reservedContent.body,
			cacheKey,
			...(reservedContent.cacheKeySegment === null ? {} : { lang: 'text' }),
		},
		version: content.bodyVersion + reservedContent.versionOffset,
		bridgeMetadata: {
			cacheKey,
			contentRoles: ['file'],
			contentState: reservedContent.cacheKeySegment === null ? 'hydrated' : 'windowed',
			displayPath: content.path,
			itemId: descriptor.fileId,
			lineCount: descriptor.lineCount ?? null,
		},
	};
}

function bridgeFileViewerPierreCodeViewItemFromSelectedItem(
	item: BridgeFileViewerSelectedCodeViewItem,
): BridgeCodeViewItem {
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

function codeViewPlaceholderItemsForOpenFileState(
	openFileState: BridgeFileViewerCodePanelState,
): readonly BridgeCodeViewItem[] {
	if (
		openFileState.status === 'idle' ||
		openFileState.descriptor.isBinary ||
		openFileState.descriptor.virtualizedExtentKind !== 'exactLineCount' ||
		openFileState.descriptor.lineCount === undefined ||
		openFileState.descriptor.lineCount <= 0
	) {
		return [];
	}
	return [
		{
			id: `file-placeholder:${openFileState.descriptor.fileId}`,
			type: 'file',
			file: {
				name: openFileState.path,
				contents: Array.from(
					{ length: openFileState.descriptor.lineCount },
					(): string => ' ',
				).join('\n'),
				cacheKey: `${openFileState.descriptor.contentHandle}:placeholder:${openFileState.descriptor.lineCount}`,
				lang: 'text',
			},
			version: openFileState.descriptor.lineCount,
			bridgeMetadata: {
				cacheKey: `${openFileState.descriptor.contentHandle}:placeholder:${openFileState.descriptor.lineCount}`,
				contentRoles: ['file'],
				contentState: 'placeholder',
				displayPath: openFileState.path,
				itemId: openFileState.descriptor.fileId,
				lineCount: openFileState.descriptor.lineCount,
			},
		},
	];
}

function contentBodyReservedForSelectedFileExtent(props: {
	readonly content: BridgeFileViewerCodePanelContent;
	readonly openFileState: BridgeFileViewerCodePanelState;
}): {
	readonly body: string;
	readonly cacheKeySegment: string | null;
	readonly versionOffset: number;
} {
	if (
		props.openFileState.status === 'idle' ||
		props.openFileState.path === props.content.path ||
		props.openFileState.descriptor.isBinary ||
		props.openFileState.descriptor.virtualizedExtentKind !== 'exactLineCount' ||
		props.openFileState.descriptor.lineCount === undefined
	) {
		return {
			body: props.content.body,
			cacheKeySegment: null,
			versionOffset: 0,
		};
	}
	const minimumLineCount = props.openFileState.descriptor.lineCount;
	const body = textPaddedToMinimumRenderedLineCount({
		minimumLineCount,
		text: props.content.body,
	});
	return {
		body,
		cacheKeySegment: `reserved:${props.openFileState.path}:${minimumLineCount}`,
		versionOffset: minimumLineCount,
	};
}

function textPaddedToMinimumRenderedLineCount(props: {
	readonly minimumLineCount: number;
	readonly text: string;
}): string {
	if (props.minimumLineCount <= 0) {
		return props.text;
	}
	const currentLineCount = renderedLineCountForPierreFileContent(props.text);
	const missingLineCount = Math.max(props.minimumLineCount - currentLineCount, 0);
	if (missingLineCount === 0) {
		return props.text;
	}
	return `${props.text}${'\n'.repeat(missingLineCount)} `;
}

function renderedLineCountForPierreFileContent(text: string): number {
	if (text.length === 0) {
		return 0;
	}
	return (text.match(/\n/gu)?.length ?? 0) + 1;
}
