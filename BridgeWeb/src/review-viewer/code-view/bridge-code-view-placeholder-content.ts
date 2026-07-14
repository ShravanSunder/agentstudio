import type { CodeViewDiffItem, FileContents } from '@pierre/diffs';

import type { BridgeReviewItemDescriptor } from '../../foundation/review-package/bridge-review-package.js';

export type BridgeCodeViewPlaceholderFileVersion = 'base' | 'current' | 'head';

export interface BridgeCodeViewPlaceholderFileContentsResult {
	readonly file: FileContents;
	readonly lineCount: number;
}

export interface BridgeCodeViewPlaceholderDiffFilesResult {
	readonly base: FileContents;
	readonly baseLineCount: number;
	readonly head: FileContents;
	readonly headLineCount: number;
	readonly lineCount: number;
}

export function createBridgeCodeViewPlaceholderFileContents(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly path: string;
	readonly version: BridgeCodeViewPlaceholderFileVersion;
}): BridgeCodeViewPlaceholderFileContentsResult {
	return {
		file: {
			name: props.path,
			contents: '',
			cacheKey: `${props.item.cacheKey}:placeholder:${props.version}:header-only`,
		},
		lineCount: 0,
	};
}

export function createBridgeCodeViewPlaceholderDiffFiles(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly basePath: string;
	readonly headPath: string;
}): BridgeCodeViewPlaceholderDiffFilesResult {
	return {
		base: {
			name: props.basePath,
			contents: '',
			cacheKey: `${props.item.cacheKey}:placeholder:base:header-only`,
		},
		baseLineCount: 0,
		head: {
			name: props.headPath,
			contents: '',
			cacheKey: `${props.item.cacheKey}:placeholder:head:header-only`,
		},
		headLineCount: 0,
		lineCount: 0,
	};
}

export function createBridgeCodeViewPlaceholderFileDiff(
	props: BridgeCodeViewPlaceholderDiffFilesResult,
): CodeViewDiffItem['fileDiff'] {
	const deletionLines = placeholderDiffLines({
		line: '-\n',
		lineCount: props.baseLineCount,
	});
	const additionLines = placeholderDiffLines({
		line: '+\n',
		lineCount: props.headLineCount,
	});
	return {
		name: props.head.name,
		...(props.base.name === props.head.name ? {} : { prevName: props.base.name }),
		type: placeholderFileDiffType({
			baseName: props.base.name,
			deletionLineCount: deletionLines.length,
			headName: props.head.name,
			additionLineCount: additionLines.length,
		}),
		hunks: placeholderDiffHunks({
			additionLineCount: additionLines.length,
			deletionLineCount: deletionLines.length,
		}),
		splitLineCount: Math.max(deletionLines.length, additionLines.length),
		unifiedLineCount: deletionLines.length + additionLines.length,
		isPartial: false,
		additionLines,
		deletionLines,
		...(props.base.cacheKey === undefined || props.head.cacheKey === undefined
			? {}
			: { cacheKey: `${props.base.cacheKey}:${props.head.cacheKey}` }),
	} satisfies CodeViewDiffItem['fileDiff'];
}

function placeholderFileDiffType(props: {
	readonly additionLineCount: number;
	readonly baseName: string;
	readonly deletionLineCount: number;
	readonly headName: string;
}): CodeViewDiffItem['fileDiff']['type'] {
	if (props.deletionLineCount === 0 && props.additionLineCount > 0) {
		return 'new';
	}
	if (props.deletionLineCount > 0 && props.additionLineCount === 0) {
		return 'deleted';
	}
	return props.baseName === props.headName ? 'change' : 'rename-changed';
}

function placeholderDiffHunks(props: {
	readonly additionLineCount: number;
	readonly deletionLineCount: number;
}): CodeViewDiffItem['fileDiff']['hunks'] {
	if (props.additionLineCount === 0 && props.deletionLineCount === 0) {
		return [];
	}
	const additionLineIndex = props.additionLineCount === 0 ? -1 : 0;
	const deletionLineIndex = props.deletionLineCount === 0 ? -1 : 0;
	const additionStart = props.additionLineCount === 0 ? 0 : 1;
	const deletionStart = props.deletionLineCount === 0 ? 0 : 1;
	return [
		{
			collapsedBefore: 0,
			additionStart,
			additionCount: props.additionLineCount,
			additionLines: props.additionLineCount,
			additionLineIndex,
			deletionStart,
			deletionCount: props.deletionLineCount,
			deletionLines: props.deletionLineCount,
			deletionLineIndex,
			hunkContent: [
				{
					type: 'change',
					additions: props.additionLineCount,
					deletions: props.deletionLineCount,
					additionLineIndex,
					deletionLineIndex,
				},
			],
			hunkSpecs: `@@ -${deletionStart},${props.deletionLineCount} +${additionStart},${props.additionLineCount} @@\n`,
			splitLineStart: 0,
			splitLineCount: Math.max(props.deletionLineCount, props.additionLineCount),
			unifiedLineStart: 0,
			unifiedLineCount: props.deletionLineCount + props.additionLineCount,
			noEOFCRDeletions: false,
			noEOFCRAdditions: false,
		},
	];
}

function placeholderDiffLines(props: {
	readonly line: string;
	readonly lineCount: number;
}): string[] {
	return Array.from({ length: props.lineCount }, (): string => props.line);
}
