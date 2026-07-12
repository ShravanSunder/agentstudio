import type { BridgeWorkerCodeViewFileItem } from '../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { BridgeCodeViewItem } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import { bridgePierreOptionalHighlightLanguage } from '../review-viewer/workers/pierre/bridge-pierre-language-normalization.js';
import type { BridgeFileViewerOpenState } from './bridge-file-viewer-display-model.js';

export type BridgeFileViewerCodePanelState = BridgeFileViewerOpenState;
export type BridgeFileViewerSelectedCodeViewItem = BridgeWorkerCodeViewFileItem;

export function bridgeFileViewerCodeViewItemsForPanelState(props: {
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
}): readonly BridgeCodeViewItem[] {
	if (props.selectedCodeViewItem !== null) {
		return [bridgeFileViewerPierreCodeViewItemFromSelectedItem(props.selectedCodeViewItem)];
	}
	return bridgeFileViewerPlaceholderItemsForOpenState(props.openFileState);
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

function bridgeFileViewerPlaceholderItemsForOpenState(
	openFileState: BridgeFileViewerCodePanelState,
): readonly BridgeCodeViewItem[] {
	if (
		openFileState.status === 'idle' ||
		openFileState.displayItem === null ||
		openFileState.displayItem.availability.kind !== 'available' ||
		openFileState.displayItem.payloadLineCount <= 0
	) {
		return [];
	}
	const lineCount = openFileState.displayItem.payloadLineCount;
	const cacheKey = [
		'file-placeholder',
		openFileState.fileId,
		String(openFileState.displayItem.payloadByteCount),
		String(openFileState.displayItem.payloadLineCount),
		String(lineCount),
	].join(':');
	return [
		{
			id: `file-placeholder:${openFileState.fileId}`,
			type: 'file',
			file: {
				cacheKey,
				contents: Array.from({ length: lineCount }, (): string => ' ').join('\n'),
				lang: 'text',
				name: openFileState.path,
			},
			version: lineCount,
			bridgeMetadata: {
				cacheKey,
				contentRoles: ['file'],
				contentState: 'placeholder',
				displayPath: openFileState.path,
				itemId: openFileState.fileId,
				lineCount,
			},
		},
	];
}
