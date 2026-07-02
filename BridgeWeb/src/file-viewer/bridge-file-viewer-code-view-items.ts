import type { CodeViewItem } from '@pierre/diffs';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';

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

export function bridgeFileViewerCodeViewItemsForPanelState(props: {
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly renderedFileContent: BridgeFileViewerCodePanelContent | null;
}): readonly CodeViewItem[] {
	if (props.renderedFileContent === null) {
		return codeViewPlaceholderItemsForOpenFileState(props.openFileState);
	}
	const content = props.renderedFileContent;
	const descriptor = content.descriptor;
	const reservedContent = contentBodyReservedForSelectedFileExtent({
		content,
		openFileState: props.openFileState,
	});
	return [
		{
			id: `file:${descriptor.fileId}`,
			type: 'file',
			file: {
				name: content.path,
				contents: reservedContent.body,
				cacheKey:
					reservedContent.cacheKeySegment === null
						? `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}`
						: `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}:${reservedContent.cacheKeySegment}`,
				...(reservedContent.cacheKeySegment === null ? {} : { lang: 'text' }),
			},
			version: content.bodyVersion + reservedContent.versionOffset,
		},
	];
}

function codeViewPlaceholderItemsForOpenFileState(
	openFileState: BridgeFileViewerCodePanelState,
): readonly CodeViewItem[] {
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
