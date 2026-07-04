import type { FileContents } from '@pierre/diffs';

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
	readonly head: FileContents;
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
		head: {
			name: props.headPath,
			contents: placeholderDiffContents({
				lineCount: lineCounts.head,
				role: 'head',
			}),
			cacheKey: `${props.item.cacheKey}:placeholder:head:${lineCounts.head}`,
		},
		lineCount: lineCounts.base + lineCounts.head,
	};
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

function positiveLineCount(lineCount: number): number {
	return Math.max(1, nonnegativeLineCount(lineCount));
}

function nonnegativeLineCount(lineCount: number): number {
	return Math.max(0, Math.floor(lineCount));
}
