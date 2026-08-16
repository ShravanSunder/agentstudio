import type { DiffLineAnnotation, LineAnnotation, SelectedLineRange } from '@pierre/diffs';

import type { BridgeProductWorktreeAnnotationOperation } from '../../core/comm-worker/bridge-product-call-contracts.js';
import type { BridgeReviewItemDescriptor } from '../../foundation/review-package/bridge-review-package.js';
import type { WorktreeAnnotationThreadProjection } from '../../worktree-annotations/worktree-annotation-surface-client.js';

type WorktreeAnnotationRootCreateOperation = Extract<
	BridgeProductWorktreeAnnotationOperation,
	{ readonly kind: 'root.create' }
>;
export type WorktreeAnnotationOrigin = WorktreeAnnotationRootCreateOperation['origin'];
export type WorktreeAnnotationLocatedOrigin = Extract<
	WorktreeAnnotationOrigin,
	{ readonly kind: 'located' }
>;

export interface WorktreeAnnotationPierreThreadMetadata {
	readonly kind: 'thread';
	readonly range: SelectedLineRange;
	readonly threadId: string;
}

export interface WorktreeAnnotationPierreComposerMetadata {
	readonly editToken: string;
	readonly kind: 'composer';
	readonly range: SelectedLineRange;
}

export type WorktreeAnnotationPierreMetadata =
	| WorktreeAnnotationPierreComposerMetadata
	| WorktreeAnnotationPierreThreadMetadata;

export function filePierreAnnotationForComposer(props: {
	readonly editToken: string;
	readonly range: SelectedLineRange;
}): LineAnnotation<WorktreeAnnotationPierreMetadata> {
	return {
		lineNumber: Math.max(props.range.start, props.range.end),
		metadata: { editToken: props.editToken, kind: 'composer', range: props.range },
	};
}

export function reviewPierreAnnotationForComposer(props: {
	readonly editToken: string;
	readonly itemType: 'diff';
	readonly range: SelectedLineRange;
}): DiffLineAnnotation<WorktreeAnnotationPierreMetadata> | null;
export function reviewPierreAnnotationForComposer(props: {
	readonly editToken: string;
	readonly itemType: 'file';
	readonly range: SelectedLineRange;
}): LineAnnotation<WorktreeAnnotationPierreMetadata>;
export function reviewPierreAnnotationForComposer(props: {
	readonly editToken: string;
	readonly itemType: 'diff' | 'file';
	readonly range: SelectedLineRange;
}):
	| DiffLineAnnotation<WorktreeAnnotationPierreMetadata>
	| LineAnnotation<WorktreeAnnotationPierreMetadata>
	| null {
	const metadata = {
		editToken: props.editToken,
		kind: 'composer',
		range: props.range,
	} satisfies WorktreeAnnotationPierreComposerMetadata;
	if (props.itemType === 'file') {
		return { lineNumber: Math.max(props.range.start, props.range.end), metadata };
	}
	const side = props.range.side;
	if (side === undefined || (props.range.endSide ?? side) !== side) return null;
	return {
		lineNumber: Math.max(props.range.start, props.range.end),
		metadata,
		side,
	};
}

export function filePierreAnnotationsForThreads(props: {
	readonly path: string;
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): LineAnnotation<WorktreeAnnotationPierreMetadata>[] {
	return props.threads.flatMap(
		(thread): readonly LineAnnotation<WorktreeAnnotationPierreMetadata>[] => {
			const context = thread.context;
			if (
				!threadCanUsePierreSlot(thread) ||
				context.sourceRole !== 'file' ||
				context.path !== props.path ||
				context.startLine === null ||
				context.endLine === null
			) {
				return [];
			}
			return [
				{
					lineNumber: context.endLine,
					metadata: {
						kind: 'thread',
						range: { end: context.endLine, start: context.startLine },
						threadId: context.threadId,
					},
				},
			];
		},
	);
}

export function reviewPierreAnnotationsForItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'diff';
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): DiffLineAnnotation<WorktreeAnnotationPierreMetadata>[];
export function reviewPierreAnnotationsForItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'file';
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): LineAnnotation<WorktreeAnnotationPierreMetadata>[];
export function reviewPierreAnnotationsForItem(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'diff' | 'file';
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): (
	| DiffLineAnnotation<WorktreeAnnotationPierreMetadata>
	| LineAnnotation<WorktreeAnnotationPierreMetadata>
)[] {
	return props.threads.flatMap(
		(
			thread,
		): readonly (
			| DiffLineAnnotation<WorktreeAnnotationPierreMetadata>
			| LineAnnotation<WorktreeAnnotationPierreMetadata>
		)[] => {
			const context = thread.context;
			if (
				!threadCanUsePierreSlot(thread) ||
				context.startLine === null ||
				context.endLine === null
			) {
				return [];
			}
			const expectedPath =
				context.sourceRole === 'review_base' ? props.item.basePath : props.item.headPath;
			if (expectedPath === null || expectedPath === undefined || context.path !== expectedPath) {
				return [];
			}
			if (props.itemType === 'file') {
				return [
					{
						lineNumber: context.endLine,
						metadata: {
							kind: 'thread',
							range: { end: context.endLine, start: context.startLine },
							threadId: context.threadId,
						},
					},
				];
			}
			const side = reviewDiffSideForSourceRole(context.sourceRole);
			if (side === null) return [];
			return [
				{
					lineNumber: context.endLine,
					metadata: {
						kind: 'thread',
						range: {
							end: context.endLine,
							endSide: side,
							side,
							start: context.startLine,
						},
						threadId: context.threadId,
					},
					side,
				},
			];
		},
	);
}

// The existing File/Review CodeView owners predate annotations and instantiate Pierre with
// `undefined` metadata. Keep that broad generic untouched while PR1 attaches and validates its
// own metadata at the annotation renderer boundary.
export function filePierreAnnotationsForExistingCodeView(props: {
	readonly path: string;
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): LineAnnotation[] {
	return filePierreAnnotationsForThreads(props) as unknown as LineAnnotation[];
}

export function filePierreAnnotationForExistingCodeViewComposer(props: {
	readonly editToken: string;
	readonly range: SelectedLineRange;
}): LineAnnotation {
	return filePierreAnnotationForComposer(props) as unknown as LineAnnotation;
}

export function reviewPierreAnnotationsForExistingCodeView(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'diff';
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): DiffLineAnnotation[];
export function reviewPierreAnnotationsForExistingCodeView(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'file';
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): LineAnnotation[];
export function reviewPierreAnnotationsForExistingCodeView(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'diff' | 'file';
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): (DiffLineAnnotation | LineAnnotation)[] {
	return props.itemType === 'diff'
		? (reviewPierreAnnotationsForItem({
				...props,
				itemType: 'diff',
			}) as unknown as DiffLineAnnotation[])
		: (reviewPierreAnnotationsForItem({
				...props,
				itemType: 'file',
			}) as unknown as LineAnnotation[]);
}

export function reviewPierreAnnotationForExistingCodeViewComposer(props: {
	readonly editToken: string;
	readonly itemType: 'diff';
	readonly range: SelectedLineRange;
}): DiffLineAnnotation | null;
export function reviewPierreAnnotationForExistingCodeViewComposer(props: {
	readonly editToken: string;
	readonly itemType: 'file';
	readonly range: SelectedLineRange;
}): LineAnnotation;
export function reviewPierreAnnotationForExistingCodeViewComposer(props: {
	readonly editToken: string;
	readonly itemType: 'diff' | 'file';
	readonly range: SelectedLineRange;
}): DiffLineAnnotation | LineAnnotation | null {
	return props.itemType === 'diff'
		? (reviewPierreAnnotationForComposer({
				...props,
				itemType: 'diff',
			}) as unknown as DiffLineAnnotation | null)
		: (reviewPierreAnnotationForComposer({
				...props,
				itemType: 'file',
			}) as unknown as LineAnnotation);
}

export function threadForPierreAnnotation(props: {
	readonly annotation: DiffLineAnnotation | LineAnnotation;
	readonly threads: readonly WorktreeAnnotationThreadProjection[];
}): WorktreeAnnotationThreadProjection | null {
	const metadata = worktreeAnnotationMetadataForPierreAnnotation(props.annotation);
	if (metadata === null || metadata.kind !== 'thread') return null;
	return (
		props.threads.find((thread): boolean => thread.context.threadId === metadata.threadId) ?? null
	);
}

export function worktreeAnnotationMetadataForPierreAnnotation(
	annotation: DiffLineAnnotation | LineAnnotation,
): WorktreeAnnotationPierreMetadata | null {
	const metadata = Object.getOwnPropertyDescriptor(annotation, 'metadata')?.value as unknown;
	if (
		typeof metadata !== 'object' ||
		metadata === null ||
		!('kind' in metadata) ||
		(metadata.kind !== 'thread' && metadata.kind !== 'composer') ||
		!('range' in metadata) ||
		typeof metadata.range !== 'object' ||
		metadata.range === null
	) {
		return null;
	}
	const range = metadata.range;
	if (
		!('start' in range) ||
		typeof range.start !== 'number' ||
		!('end' in range) ||
		typeof range.end !== 'number' ||
		('side' in range &&
			range.side !== undefined &&
			range.side !== 'additions' &&
			range.side !== 'deletions') ||
		('endSide' in range &&
			range.endSide !== undefined &&
			range.endSide !== 'additions' &&
			range.endSide !== 'deletions')
	) {
		return null;
	}
	const side =
		'side' in range && (range.side === 'additions' || range.side === 'deletions')
			? range.side
			: undefined;
	const endSide =
		'endSide' in range && (range.endSide === 'additions' || range.endSide === 'deletions')
			? range.endSide
			: undefined;
	const selectedRange = {
		end: range.end,
		...(endSide === undefined ? {} : { endSide }),
		...(side === undefined ? {} : { side }),
		start: range.start,
	} satisfies SelectedLineRange;
	if (metadata.kind === 'thread') {
		if (!('threadId' in metadata) || typeof metadata.threadId !== 'string') return null;
		return { kind: 'thread', range: selectedRange, threadId: metadata.threadId };
	}
	if (!('editToken' in metadata) || typeof metadata.editToken !== 'string') return null;
	return { editToken: metadata.editToken, kind: 'composer', range: selectedRange };
}

export function fileAnnotationOriginForPierreSelection(props: {
	readonly path: string;
	readonly range: SelectedLineRange;
	readonly sourceDescriptorId: string;
}): WorktreeAnnotationLocatedOrigin {
	return {
		diffSide: null,
		endLine: Math.max(props.range.start, props.range.end),
		kind: 'located',
		path: props.path,
		sourceIdentity: props.sourceDescriptorId,
		sourceRole: 'file',
		startLine: Math.min(props.range.start, props.range.end),
	};
}

export function reviewAnnotationOriginForPierreSelection(props: {
	readonly item: BridgeReviewItemDescriptor;
	readonly itemType: 'diff' | 'file';
	readonly range: SelectedLineRange;
	readonly fileSourceRole?: 'base' | 'head';
}): WorktreeAnnotationLocatedOrigin | null {
	const role = reviewSelectionRole(props);
	if (role === null) return null;
	const handle = props.item.contentRoles[role];
	const path = role === 'base' ? props.item.basePath : props.item.headPath;
	if (handle === null || handle === undefined || path === null || path === undefined) return null;
	return {
		diffSide: props.itemType === 'diff' ? (role === 'base' ? 'deletions' : 'additions') : null,
		endLine: Math.max(props.range.start, props.range.end),
		kind: 'located',
		path,
		sourceIdentity: handle.handleId,
		sourceRole: role === 'base' ? 'reviewBase' : 'reviewHead',
		startLine: Math.min(props.range.start, props.range.end),
	};
}

function threadCanUsePierreSlot(thread: WorktreeAnnotationThreadProjection): boolean {
	return (
		thread.context.scope === 'located' &&
		(thread.context.placement === 'exact' || thread.context.placement === 'relocated')
	);
}

function reviewDiffSideForSourceRole(
	sourceRole: WorktreeAnnotationThreadProjection['context']['sourceRole'],
): 'additions' | 'deletions' | null {
	if (sourceRole === 'review_base') return 'deletions';
	if (sourceRole === 'review_head') return 'additions';
	return null;
}

function reviewSelectionRole(props: {
	readonly itemType: 'diff' | 'file';
	readonly range: SelectedLineRange;
	readonly fileSourceRole?: 'base' | 'head';
}): 'base' | 'head' | null {
	if (props.itemType === 'file') return props.fileSourceRole ?? null;
	const startSide = props.range.side;
	const endSide = props.range.endSide ?? startSide;
	if (startSide === undefined || endSide !== startSide) return null;
	return startSide === 'deletions' ? 'base' : 'head';
}
