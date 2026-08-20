import type { LineAnnotation, SelectedLineRange } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import { makeBridgeReviewItem } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	fileAnnotationOriginForPierreSelection,
	filePierreAnnotationForComposer,
	filePierreAnnotationsForThreads,
	reviewAnnotationOriginForPierreSelection,
	reviewPierreAnnotationForComposer,
	reviewPierreAnnotationsForItem,
	threadForPierreAnnotation,
	worktreeAnnotationMetadataForPierreAnnotation,
	worktreeAnnotationPierreRangesMatch,
} from '../review-viewer/code-view/worktree-annotation-pierre-adapter.js';
import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';

describe('worktree annotation Pierre adapter', () => {
	test('maps exact and relocated File threads to end-line annotation slots', () => {
		const annotations = filePierreAnnotationsForThreads({
			path: 'Sources/App.swift',
			threads: [
				threadProjection({ endLine: 8, placement: 'exact', startLine: 4 }),
				threadProjection({ endLine: 20, placement: 'relocated', startLine: 19 }),
				threadProjection({ endLine: 30, placement: 'outdated', startLine: 30 }),
			],
		});

		expect(annotations.map(({ lineNumber }) => lineNumber)).toEqual([8, 20]);
	});

	test('maps Review sides to role-specific handles and rejects cross-side selection', () => {
		const item = makeBridgeReviewItem({ itemId: 'item-1', path: 'Sources/App.swift' });
		const additionsRange = { start: 4, end: 7, side: 'additions' } satisfies SelectedLineRange;

		expect(
			reviewAnnotationOriginForPierreSelection({
				item,
				itemType: 'diff',
				range: additionsRange,
				sourceDescriptorIdsByRole: {
					base: 'descriptor-item-1-base',
					head: 'descriptor-item-1-head',
				},
			}),
		).toEqual({
			diffSide: 'additions',
			endLine: 7,
			kind: 'located',
			path: 'Sources/App.swift',
			sourceIdentity: 'descriptor-item-1-head',
			sourceRole: 'reviewHead',
			startLine: 4,
		});
		expect(
			reviewAnnotationOriginForPierreSelection({
				item,
				itemType: 'diff',
				range: { start: 4, end: 7, side: 'deletions', endSide: 'additions' },
				sourceDescriptorIdsByRole: {
					base: 'descriptor-item-1-base',
					head: 'descriptor-item-1-head',
				},
			}),
		).toBeNull();
	});

	test('maps Review thread slots and File selection without replacing source authority', () => {
		const item = makeBridgeReviewItem({ itemId: 'item-1', path: 'Sources/App.swift' });
		const annotations = reviewPierreAnnotationsForItem({
			item,
			itemType: 'diff',
			threads: [
				threadProjection({ endLine: 9, sourceRole: 'review_head', startLine: 7 }),
				threadProjection({ endLine: 3, sourceRole: 'review_base', startLine: 2 }),
				threadProjection({
					endLine: 12,
					sourceRole: 'file',
					startLine: 11,
					threadId: '00000000-0000-7000-8000-000000000013',
				}),
			],
		});

		expect(annotations.map(({ lineNumber, side }) => [lineNumber, side])).toEqual([
			[9, 'additions'],
			[3, 'deletions'],
			[12, 'additions'],
		]);
		expect(
			fileAnnotationOriginForPierreSelection({
				path: 'Sources/App.swift',
				range: { start: 2, end: 5 },
				sourceDescriptorId: 'descriptor-file-1',
			}),
		).toEqual({
			diffSide: null,
			endLine: 5,
			kind: 'located',
			path: 'Sources/App.swift',
			sourceIdentity: 'descriptor-file-1',
			sourceRole: 'file',
			startLine: 2,
		});
	});

	test('keeps one typed Pierre annotation per thread when threads share a diff line and side', () => {
		const item = makeBridgeReviewItem({ itemId: 'item-1', path: 'Sources/App.swift' });
		const firstThreadId = '00000000-0000-7000-8000-000000000051';
		const secondThreadId = '00000000-0000-7000-8000-000000000052';

		const annotations = reviewPierreAnnotationsForItem({
			item,
			itemType: 'diff',
			threads: [
				threadProjection({
					endLine: 9,
					sourceRole: 'review_head',
					startLine: 7,
					threadId: firstThreadId,
				}),
				threadProjection({
					endLine: 9,
					sourceRole: 'review_head',
					startLine: 8,
					threadId: secondThreadId,
				}),
			],
		});

		expect(annotations).toEqual([
			{
				lineNumber: 9,
				metadata: {
					kind: 'thread',
					range: { end: 9, endSide: 'additions', side: 'additions', start: 7 },
					threadId: firstThreadId,
				},
				side: 'additions',
			},
			{
				lineNumber: 9,
				metadata: {
					kind: 'thread',
					range: { end: 9, endSide: 'additions', side: 'additions', start: 8 },
					threadId: secondThreadId,
				},
				side: 'additions',
			},
		]);
	});

	test('keeps composer edit identity and the complete selected range in Pierre metadata', () => {
		const fileRange = { end: 14, start: 11 } satisfies SelectedLineRange;
		const diffRange = {
			end: 9,
			endSide: 'additions',
			side: 'additions',
			start: 7,
		} satisfies SelectedLineRange;

		expect(filePierreAnnotationForComposer({ editToken: 'edit-file-1', range: fileRange })).toEqual(
			{
				lineNumber: 14,
				metadata: { editToken: 'edit-file-1', kind: 'composer', range: fileRange },
			},
		);
		expect(
			reviewPierreAnnotationForComposer({
				editToken: 'edit-review-1',
				itemType: 'diff',
				range: diffRange,
			}),
		).toEqual({
			lineNumber: 9,
			metadata: { editToken: 'edit-review-1', kind: 'composer', range: diffRange },
			side: 'additions',
		});
		expect(
			reviewPierreAnnotationForComposer({
				editToken: 'edit-review-cross-side',
				itemType: 'diff',
				range: { end: 9, endSide: 'deletions', side: 'additions', start: 7 },
			}),
		).toBeNull();
	});

	test('matches only the exact active Pierre range while normalizing an omitted end side', () => {
		const selectedRange = {
			end: 9,
			side: 'additions',
			start: 7,
		} satisfies SelectedLineRange;

		expect(
			worktreeAnnotationPierreRangesMatch(selectedRange, {
				...selectedRange,
				endSide: 'additions',
			}),
		).toBe(true);
		expect(worktreeAnnotationPierreRangesMatch(selectedRange, { ...selectedRange, start: 8 })).toBe(
			false,
		);
		expect(
			worktreeAnnotationPierreRangesMatch(selectedRange, {
				...selectedRange,
				endSide: 'deletions',
			}),
		).toBe(false);
	});

	test('validates erased Pierre metadata before resolving a thread or composer', () => {
		const thread = threadProjection({
			endLine: 9,
			startLine: 7,
			threadId: '00000000-0000-7000-8000-000000000053',
		});
		const threadMetadata = {
			kind: 'thread',
			range: { end: 9, start: 7 },
			threadId: thread.context.threadId,
		};
		const composerMetadata = {
			editToken: 'edit-file-2',
			kind: 'composer',
			range: { end: 12, start: 10 },
		};
		const threadAnnotation = erasedPierreLineAnnotation(9, threadMetadata);
		const composerAnnotation = erasedPierreLineAnnotation(12, composerMetadata);

		expect(worktreeAnnotationMetadataForPierreAnnotation(threadAnnotation)).toEqual(threadMetadata);
		expect(worktreeAnnotationMetadataForPierreAnnotation(composerAnnotation)).toEqual(
			composerMetadata,
		);
		expect(threadForPierreAnnotation({ annotation: threadAnnotation, threads: [thread] })).toBe(
			thread,
		);
		expect(
			worktreeAnnotationMetadataForPierreAnnotation(
				erasedPierreLineAnnotation(12, {
					editToken: 'edit-file-2',
					kind: 'composer',
					range: { end: '12', start: 10 },
				}),
			),
		).toBeNull();
		expect(
			worktreeAnnotationMetadataForPierreAnnotation(
				erasedPierreLineAnnotation(12, {
					kind: 'thread',
					range: { end: 12, start: 10 },
				}),
			),
		).toBeNull();
	});
});

function erasedPierreLineAnnotation(lineNumber: number, metadata: unknown): LineAnnotation {
	const annotation: LineAnnotation = { lineNumber };
	Object.defineProperty(annotation, 'metadata', { enumerable: true, value: metadata });
	return annotation;
}

function threadProjection(
	overrides: Partial<WorktreeAnnotationThreadProjection['context']>,
): WorktreeAnnotationThreadProjection {
	const commonContext = {
		endLine: overrides.endLine ?? 6,
		path: overrides.path ?? 'Sources/App.swift',
		placement: overrides.placement ?? 'exact',
		resolution: overrides.resolution ?? 'open',
		scope: 'located',
		sourceIdentity: overrides.sourceIdentity ?? 'source-1',
		startLine: overrides.startLine ?? 5,
		threadId: overrides.threadId ?? '00000000-0000-7000-8000-000000000012',
	} as const;
	const context: WorktreeAnnotationThreadProjection['context'] =
		overrides.sourceRole === 'review_base'
			? { ...commonContext, diffSide: 'deletions', sourceRole: 'review_base' }
			: overrides.sourceRole === 'review_head'
				? { ...commonContext, diffSide: 'additions', sourceRole: 'review_head' }
				: { ...commonContext, diffSide: null, sourceRole: 'file' };
	return {
		context,
		messages: [],
	};
}
