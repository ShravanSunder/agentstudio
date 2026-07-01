import { createHash } from 'node:crypto';

import { normalizeReviewTreeSearchQuery } from '../verify-bridge-viewer-worktree-review-proof.ts';

export function hashText(value: string): string {
	return createHash('sha256').update(value).digest('hex');
}

export function isNodeErrorWithCode(
	error: unknown,
	code: string,
): error is Error & { readonly code: string } {
	return error instanceof Error && 'code' in error && error.code === code;
}

export function countTextLines(text: string): number {
	const trimmedText = text.endsWith('\n') ? text.slice(0, -1) : text;
	return trimmedText.length === 0 ? 0 : trimmedText.split('\n').length;
}

export function escapeRegExp(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

export function reviewFileTargetUrlFromWorktreeDevServerUrl(props: {
	readonly itemId?: string;
	readonly path: string;
	readonly url: string;
	readonly version: 'base' | 'current' | 'head';
}): string {
	const parsedUrl = new URL(props.url);
	parsedUrl.searchParams.set('viewer', 'review');
	parsedUrl.searchParams.set('presentation', 'file');
	parsedUrl.searchParams.set('path', props.path);
	if (props.itemId !== undefined) {
		parsedUrl.searchParams.set('reviewItemId', props.itemId);
	}
	parsedUrl.searchParams.set('version', props.version);
	return parsedUrl.toString();
}

export function reviewTreeSearchInputMatchesTargetPath(props: {
	readonly actualSearchInputValue: string | null;
	readonly targetPath: string;
}): boolean {
	if (props.actualSearchInputValue === null) {
		return false;
	}
	const acceptedSearchInputs = new Set([
		normalizeReviewTreeSearchQuery(props.targetPath),
		reviewTreeModelSearchQueryForTargetPath(props.targetPath),
	]);
	return acceptedSearchInputs.has(props.actualSearchInputValue);
}

export function reviewTreeModelSearchQueryForTargetPath(path: string): string {
	const pathSegments = path.split('/').filter((pathSegment) => pathSegment.length > 0);
	const leafName = pathSegments.at(-1) ?? path;
	const extensionIndex = leafName.lastIndexOf('.');
	const modelQuery = extensionIndex <= 0 ? leafName : leafName.slice(0, extensionIndex);
	return normalizeReviewTreeSearchQuery(modelQuery);
}

export function cssStringLiteral(value: string): string {
	return `"${value.replace(/\\/gu, '\\\\').replace(/"/gu, '\\"')}"`;
}

export interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

export function makeDeferred<TValue>(): Deferred<TValue> {
	let resolve: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((promiseResolve) => {
		resolve = promiseResolve;
	});
	if (resolve === null) {
		throw new Error('Deferred promise did not initialize');
	}
	return { promise, resolve };
}
