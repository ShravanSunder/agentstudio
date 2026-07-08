import type { CodeViewDiffItem, FileContents } from '@pierre/diffs';

import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
} from '../../foundation/review-package/bridge-review-package.js';

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
	const lineCount = placeholderFileLineCount({
		item: props.item,
		version: props.version,
	});
	return {
		file: {
			name: props.path,
			contents: placeholderFileContents(lineCount),
			cacheKey: `${props.item.cacheKey}:placeholder`,
		},
		lineCount,
	};
}

export function createBridgeCodeViewPlaceholderDiffFiles(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly basePath: string;
	readonly headPath: string;
}): BridgeCodeViewPlaceholderDiffFilesResult {
	const lineCounts = placeholderDiffLineCounts(props.item);
	return {
		base: {
			name: props.basePath,
			contents: placeholderDiffContents({
				lineCount: lineCounts.base,
				role: 'base',
			}),
			cacheKey: `${props.item.cacheKey}:placeholder:base:${lineCounts.base}`,
		},
		baseLineCount: lineCounts.base,
		head: {
			name: props.headPath,
			contents: placeholderDiffContents({
				lineCount: lineCounts.head,
				role: 'head',
			}),
			cacheKey: `${props.item.cacheKey}:placeholder:head:${lineCounts.head}`,
		},
		headLineCount: lineCounts.head,
		lineCount: lineCounts.base + lineCounts.head,
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

function placeholderFileLineCount(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly version: BridgeCodeViewPlaceholderFileVersion;
}): number {
	const explicitLineCount = explicitFileLineCountForVersion(props);
	if (explicitLineCount !== null) {
		return positiveLineCount(explicitLineCount);
	}
	return positiveLineCount(props.item.additions + props.item.deletions);
}

function explicitFileLineCountForVersion(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly version: BridgeCodeViewPlaceholderFileVersion;
}): number | null {
	const lineCountsByRole = props.item.contentLineCountsByRole;
	switch (props.version) {
		case 'base':
			return lineCountsByRole?.base ?? lineCountsByRole?.diff ?? null;
		case 'current':
		case 'head':
			return lineCountsByRole?.head ?? lineCountsByRole?.file ?? null;
	}
	const exhaustiveVersion: never = props.version;
	void exhaustiveVersion;
	throw new Error('Unhandled Bridge CodeView placeholder file version');
}

function placeholderDiffLineCounts(item: BridgeReviewItemDescriptor): {
	readonly base: number;
	readonly head: number;
} {
	const base = placeholderDiffSideLineCount({
		item,
		role: 'base',
	});
	const head = placeholderDiffSideLineCount({
		item,
		role: 'head',
	});
	if (base + head > 0) {
		return { base, head };
	}
	switch (item.changeKind) {
		case 'added':
			return { base: 0, head: 1 };
		case 'deleted':
			return { base: 1, head: 0 };
		case 'modified':
		case 'renamed':
		case 'copied':
			return { base: 1, head: 1 };
	}
	const exhaustiveChangeKind: never = item.changeKind;
	void exhaustiveChangeKind;
	throw new Error('Unhandled Bridge review file change kind');
}

function placeholderDiffSideLineCount(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly role: Extract<BridgeContentRole, 'base' | 'head'>;
}): number {
	if (props.role === 'base') {
		if (props.item.changeKind === 'added') {
			return 0;
		}
		return nonnegativeLineCount(
			props.item.contentLineCountsByRole?.base ??
				props.item.contentLineCountsByRole?.diff ??
				props.item.deletions,
		);
	}
	if (props.item.changeKind === 'deleted') {
		return 0;
	}
	return nonnegativeLineCount(
		props.item.contentLineCountsByRole?.head ??
			props.item.contentLineCountsByRole?.file ??
			props.item.additions,
	);
}

function placeholderFileContents(lineCount: number): string {
	return '\n'.repeat(lineCount);
}

function placeholderDiffContents(props: {
	readonly lineCount: number;
	readonly role: Extract<BridgeContentRole, 'base' | 'head'>;
}): string {
	if (props.lineCount <= 0) {
		return '';
	}
	const prefix = props.role === 'base' ? '-' : '+';
	return `${prefix}\n`.repeat(props.lineCount);
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

function positiveLineCount(lineCount: number): number {
	return Math.max(1, nonnegativeLineCount(lineCount));
}

function nonnegativeLineCount(lineCount: number): number {
	return Math.max(0, Math.floor(lineCount));
}
