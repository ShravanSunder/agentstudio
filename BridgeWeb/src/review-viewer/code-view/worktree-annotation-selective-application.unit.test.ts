import type { LineAnnotation } from '@pierre/diffs';
import { describe, expect, test, vi } from 'vitest';

import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { WorktreeAnnotationThreadContext } from '../../worktree-annotations/worktree-annotation-surface-client.js';
import type {
	BridgeCodeViewFileItem,
	BridgeCodeViewItem,
} from './bridge-code-view-materialization.js';
import { applyWorktreeAnnotationsToCandidateCodeViewItems } from './use-bridge-code-view-worktree-annotation-effects.js';
import { reviewAnnotationApplicationItemIds } from './use-bridge-code-view-worktree-annotations.js';

describe('Review worktree annotation selective application', () => {
	test('leaves unrelated and semantically equal items at the same reference and version', () => {
		const changed = codeViewItem('changed', 4, [threadAnnotation('thread-1', 'body-1')]);
		const unrelated = codeViewItem('unrelated', 9, []);
		const applyItemUpdate = vi.fn();

		const result = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem: (item) =>
				item.id === 'changed'
					? fileItemWithAnnotations(item, [threadAnnotation('thread-1', 'body-1')])
					: item,
			applyItemUpdate,
			candidateItemIds: ['changed'],
			currentItemForId: (itemId) => (itemId === 'changed' ? changed : unrelated),
			items: [changed, unrelated],
		});

		expect(result).toEqual([changed, unrelated]);
		expect(result[0]).toBe(changed);
		expect(result[1]).toBe(unrelated);
		expect(applyItemUpdate).not.toHaveBeenCalled();
	});

	test('updates only a candidate whose semantic annotation presentation changed', () => {
		const affected = codeViewItem('affected', 4, [threadAnnotation('thread-1', 'body-1')]);
		const unrelated = codeViewItem('unrelated', 9, []);
		const applyItemUpdate = vi.fn();

		const result = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem: (item) =>
				fileItemWithAnnotations(item, [threadAnnotation('thread-1', 'body-2')]),
			applyItemUpdate,
			candidateItemIds: ['affected'],
			currentItemForId: (itemId) => (itemId === 'affected' ? affected : unrelated),
			items: [affected, unrelated],
		});

		expect(result[0]?.version).toBe(5);
		expect(result[1]).toBe(unrelated);
		expect(applyItemUpdate).toHaveBeenCalledTimes(1);
		expect(applyItemUpdate).toHaveBeenCalledWith(result[0]);
	});

	test('uses full fallback candidates but still suppresses equal item updates', () => {
		const equal = codeViewItem('equal', 2, []);
		const changed = codeViewItem('changed', 6, []);
		const applyItemUpdate = vi.fn();

		const result = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem: (item) =>
				item.id === 'changed'
					? fileItemWithAnnotations(item, [threadAnnotation('thread-2', 'body-1')])
					: fileItemWithAnnotations(item, []),
			applyItemUpdate,
			candidateItemIds: null,
			currentItemForId: (itemId) => (itemId === 'equal' ? equal : changed),
			items: [equal, changed],
		});

		expect(result[0]).toBe(equal);
		expect(result[1]?.version).toBe(7);
		expect(applyItemUpdate).toHaveBeenCalledTimes(1);
	});

	test('preserves an equal active composer without advancing the item version', () => {
		const composer = composerAnnotation('edit-token-1');
		const item = codeViewItem('composer-owner', 7, [composer]);
		const applyItemUpdate = vi.fn();

		const [result] = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem: (candidate) =>
				fileItemWithAnnotations(candidate, [composerAnnotation('edit-token-1')]),
			applyItemUpdate,
			candidateItemIds: ['composer-owner'],
			currentItemForId: () => item,
			items: [item],
		});

		expect(result).toBe(item);
		expect(applyItemUpdate).not.toHaveBeenCalled();
	});

	test('removes unavailable placement and restores its returned Pierre annotation', () => {
		const exactItem = codeViewItem('affected', 4, [threadAnnotation('thread-1', 'exact-1')]);
		const removedUpdates: BridgeCodeViewItem[] = [];
		const [unavailableItem] = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem: (item) => fileItemWithAnnotations(item, []),
			applyItemUpdate: (item): void => {
				removedUpdates.push(item);
			},
			candidateItemIds: ['affected'],
			currentItemForId: () => exactItem,
			items: [exactItem],
		});
		if (unavailableItem === undefined) throw new Error('Expected unavailable presentation item.');

		const restoredUpdates: BridgeCodeViewItem[] = [];
		const [restoredItem] = applyWorktreeAnnotationsToCandidateCodeViewItems({
			annotateItem: (item) =>
				fileItemWithAnnotations(item, [threadAnnotation('thread-1', 'exact-2')]),
			applyItemUpdate: (item): void => {
				restoredUpdates.push(item);
			},
			candidateItemIds: ['affected'],
			currentItemForId: () => unavailableItem,
			items: [unavailableItem],
		});

		expect(removedUpdates).toHaveLength(1);
		expect(unavailableItem.annotations).toEqual([]);
		expect(restoredUpdates).toHaveLength(1);
		expect(restoredItem?.annotations).toHaveLength(1);
		expect(restoredItem?.version).toBe(6);
	});

	test('unions promoted, previous/current placement-owner, and active-editor items', () => {
		const basePackage = makeBridgeReviewPackage();
		const orderedItems = [
			makeBridgeReviewItem({ itemId: 'item-promoted', path: 'Sources/Promoted.swift' }),
			makeBridgeReviewItem({ itemId: 'item-old-owner', path: 'Sources/Old.swift' }),
			makeBridgeReviewItem({ itemId: 'item-new-owner', path: 'Sources/New.swift' }),
			makeBridgeReviewItem({ itemId: 'item-editor', path: 'Sources/Editor.swift' }),
		];
		const reviewPackage = {
			...basePackage,
			itemsById: Object.fromEntries(orderedItems.map((item) => [item.itemId, item])),
			orderedItemIds: orderedItems.map((item) => item.itemId),
		};

		expect(
			reviewAnnotationApplicationItemIds({
				activeEditorItemIds: ['item-editor'],
				application: {
					affectedItemIds: ['item-promoted'],
					applicationId: 1,
					changedThreadOwnerContexts: [
						threadOwnerContext('Sources/Old.swift'),
						threadOwnerContext('Sources/New.swift'),
					],
				},
				reviewPackage,
			}),
		).toEqual(['item-promoted', 'item-old-owner', 'item-new-owner', 'item-editor']);
		expect(
			reviewAnnotationApplicationItemIds({
				activeEditorItemIds: ['item-editor'],
				application: { affectedItemIds: [], applicationId: 2, changedThreadOwnerContexts: [] },
				reviewPackage,
			}),
		).toEqual(['item-editor']);
	});
});

function codeViewItem(
	itemId: string,
	version: number,
	annotations: readonly LineAnnotation[],
): BridgeCodeViewFileItem {
	return {
		annotations: [...annotations],
		bridgeMetadata: {
			cacheKey: `cache-${itemId}`,
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath: `${itemId}.swift`,
			itemId,
			lineCount: 1,
			sourceDescriptorId: `source-${itemId}`,
		},
		file: { cacheKey: `cache-${itemId}`, contents: 'let value = 1', name: `${itemId}.swift` },
		id: itemId,
		type: 'file',
		version,
	};
}

function threadAnnotation(threadId: string, presentationIdentity: string): LineAnnotation {
	return erasedAnnotation({
		kind: 'thread',
		presentationIdentity,
		range: { end: 1, start: 1 },
		threadId,
	});
}

function threadOwnerContext(path: string): WorktreeAnnotationThreadContext {
	return {
		diffSide: 'additions' as const,
		endLine: 3,
		path,
		placement: 'exact' as const,
		resolution: 'open' as const,
		scope: 'located' as const,
		sourceIdentity: `source:${path}`,
		sourceRole: 'review_head' as const,
		startLine: 2,
		threadId: `thread:${path}`,
	};
}

function composerAnnotation(editToken: string): LineAnnotation {
	return erasedAnnotation({
		editToken,
		kind: 'composer',
		range: { end: 1, start: 1 },
	});
}

function erasedAnnotation(metadata: unknown): LineAnnotation {
	const annotation: LineAnnotation = { lineNumber: 1 };
	Object.defineProperty(annotation, 'metadata', { enumerable: true, value: metadata });
	return annotation;
}

function fileItemWithAnnotations(
	item: BridgeCodeViewItem,
	annotations: readonly LineAnnotation[],
): BridgeCodeViewFileItem {
	if (item.type !== 'file') throw new Error('Expected a file CodeView item.');
	return { ...item, annotations: [...annotations] };
}
