import type {
	CodeViewItem,
	CodeViewOptions,
	DiffLineAnnotation,
	LineAnnotation,
	SelectedLineRange,
} from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';
import {
	useCallback,
	useMemo,
	useRef,
	useState,
	type MutableRefObject,
	type ReactNode,
} from 'react';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { createWorktreeAnnotationEditToken } from '../../worktree-annotations/worktree-annotation-edit-token.js';
import type { WorktreeAnnotationThreadProjection } from '../../worktree-annotations/worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSessionDemand,
} from '../../worktree-annotations/worktree-annotation-surface-provider.js';
import {
	WorktreeAnnotationNewMessageComposer,
	WorktreeAnnotationThread,
} from '../../worktree-annotations/worktree-annotation-thread.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	reviewAnnotationOriginForPierreSelection,
	reviewPierreAnnotationForExistingCodeViewComposer,
	reviewPierreAnnotationsForExistingCodeView,
	threadForPierreAnnotation,
	worktreeAnnotationMetadataForPierreAnnotation,
	worktreeAnnotationPierreRangesMatch,
	type WorktreeAnnotationLocatedOrigin,
} from './worktree-annotation-pierre-adapter.js';

export interface BridgeCodeViewWorktreeAnnotations {
	readonly activeThreads: readonly WorktreeAnnotationThreadProjection[];
	readonly annotateItem: (item: BridgeCodeViewItem) => BridgeCodeViewItem;
	readonly codeViewOptions: Readonly<CodeViewOptions<undefined>>;
	readonly projectionRevision: number | null;
	readonly renderAnnotation: (
		annotation: DiffLineAnnotation | LineAnnotation,
		item: CodeViewItem,
	) => ReactNode;
	readonly selectedItemIdRef: MutableRefObject<string | null>;
	readonly selectedRange: SelectedLineRange | null;
}

export function useBridgeCodeViewWorktreeAnnotations(props: {
	readonly codeViewHandleRef: MutableRefObject<CodeViewHandle<undefined> | null>;
	readonly codeViewOptions: Readonly<CodeViewOptions<undefined>>;
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedItemId: string | null;
}): BridgeCodeViewWorktreeAnnotations {
	const projection = useWorktreeAnnotationProjection();
	const sessionSelection = useWorktreeAnnotationSessionSelection();
	const interaction = useWorktreeAnnotationInteraction();
	const activeSessionId = sessionSelection.activeSessionId;
	useWorktreeAnnotationSessionDemand(activeSessionId);
	const activeThreads = useMemo(
		() =>
			projection.threads.filter(
				(thread): boolean =>
					activeSessionId !== null &&
					thread.messages.some((message) => message.sessionId === activeSessionId),
			),
		[activeSessionId, projection.threads],
	);
	const [pendingComposer, setPendingComposer] = useState<{
		readonly editToken: string;
		readonly itemId: string;
		readonly origin: WorktreeAnnotationLocatedOrigin;
		readonly range: SelectedLineRange;
	} | null>(null);
	const [composerPresentationRevision, setComposerPresentationRevision] = useState(0);
	const [selectedRange, setSelectedRange] = useState<SelectedLineRange | null>(null);
	const selectedItemIdRef = useRef<string | null>(null);

	const annotateItem = useCallback(
		(item: BridgeCodeViewItem): BridgeCodeViewItem => {
			const descriptor = props.reviewPackage.itemsById[item.id];
			if (descriptor === undefined) return item;
			if (item.type === 'diff') {
				const annotations =
					projection.revision === null
						? []
						: reviewPierreAnnotationsForExistingCodeView({
								item: descriptor,
								itemType: 'diff',
								threads: activeThreads,
							});
				const composerAnnotation =
					pendingComposer?.itemId === item.id && selectedRange !== null
						? reviewPierreAnnotationForExistingCodeViewComposer({
								editToken: pendingComposer.editToken,
								itemType: 'diff',
								range: selectedRange,
							})
						: null;
				if (projection.revision === null && composerAnnotation === null) return item;
				return {
					...item,
					annotations:
						composerAnnotation === null ? annotations : [...annotations, composerAnnotation],
				};
			}
			const annotations =
				projection.revision === null
					? []
					: reviewPierreAnnotationsForExistingCodeView({
							item: descriptor,
							itemType: 'file',
							threads: activeThreads,
						});
			const composerAnnotation =
				pendingComposer?.itemId === item.id && selectedRange !== null
					? reviewPierreAnnotationForExistingCodeViewComposer({
							editToken: pendingComposer.editToken,
							itemType: 'file',
							range: selectedRange,
						})
					: null;
			if (projection.revision === null && composerAnnotation === null) return item;
			return {
				...item,
				annotations:
					composerAnnotation === null ? annotations : [...annotations, composerAnnotation],
			};
		},
		[
			activeThreads,
			pendingComposer,
			projection.revision,
			props.reviewPackage.itemsById,
			selectedRange,
		],
	);

	const admitSelectedRange = useCallback(
		(range: SelectedLineRange | null, item: CodeViewItem | null): void => {
			interaction.clearActiveThread();
			const descriptor = item === null ? undefined : props.reviewPackage.itemsById[item.id];
			if (range === null || descriptor === undefined || item === null) {
				selectedItemIdRef.current = null;
				setSelectedRange(null);
				setPendingComposer(null);
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			const fileSourceRole =
				item.type === 'file' && isAnnotationCodeViewItem(item)
					? item.bridgeMetadata.contentRoles.includes('head')
						? 'head'
						: item.bridgeMetadata.contentRoles.includes('base')
							? 'base'
							: undefined
					: undefined;
			const origin = reviewAnnotationOriginForPierreSelection({
				item: descriptor,
				itemType: item.type,
				range,
				...(fileSourceRole === undefined ? {} : { fileSourceRole }),
			});
			if (origin === null) {
				selectedItemIdRef.current = null;
				setSelectedRange(null);
				setPendingComposer(null);
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			selectedItemIdRef.current = item.id;
			setSelectedRange(range);
			setPendingComposer({
				editToken: createWorktreeAnnotationEditToken(),
				itemId: item.id,
				origin,
				range,
			});
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[interaction, props.reviewPackage.itemsById],
	);
	const retainSelectedRange = useCallback(
		(range: SelectedLineRange | null, item: CodeViewItem | null): void => {
			interaction.clearActiveThread();
			const descriptor = item === null ? undefined : props.reviewPackage.itemsById[item.id];
			if (range === null || descriptor === undefined || item === null) {
				selectedItemIdRef.current = null;
				setSelectedRange(null);
				setPendingComposer(null);
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			selectedItemIdRef.current = item.id;
			setSelectedRange(range);
			setPendingComposer((currentComposer) =>
				currentComposer?.itemId === item.id &&
				worktreeAnnotationPierreRangesMatch(currentComposer.range, range)
					? currentComposer
					: null,
			);
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[interaction, props.reviewPackage.itemsById],
	);
	const activateSavedAnnotationRange = useCallback(
		(range: SelectedLineRange, itemId: string): void => {
			selectedItemIdRef.current = itemId;
			setPendingComposer(null);
			setSelectedRange(range);
			props.codeViewHandleRef.current?.scrollTo({
				align: 'center',
				behavior: 'instant',
				id: itemId,
				range,
				type: 'range',
			});
		},
		[props.codeViewHandleRef],
	);

	const codeViewOptions = useMemo(
		() =>
			({
				...props.codeViewOptions,
				controlledSelection: true,
				enableGutterUtility: true,
				enableLineSelection: true,
				onGutterUtilityClick: (range, context): void => admitSelectedRange(range, context.item),
				onLineSelectionEnd: (range, context): void => retainSelectedRange(range, context.item),
			}) satisfies CodeViewOptions<undefined>,
		[admitSelectedRange, props.codeViewOptions, retainSelectedRange],
	);
	const renderAnnotation = useCallback(
		(annotation: DiffLineAnnotation | LineAnnotation, item: CodeViewItem): ReactNode => {
			const descriptor = props.reviewPackage.itemsById[item.id];
			if (descriptor === undefined) return null;
			const metadata = worktreeAnnotationMetadataForPierreAnnotation(annotation);
			if (
				metadata?.kind === 'composer' &&
				pendingComposer?.editToken === metadata.editToken &&
				pendingComposer.itemId === item.id
			) {
				return (
					<WorktreeAnnotationNewMessageComposer
						createOperation={(body, editToken) => ({
							admission: sessionSelection.rootAdmission,
							body,
							editToken,
							kind: 'root.create',
							origin: pendingComposer.origin,
						})}
						editToken={metadata.editToken}
						onCancel={() => admitSelectedRange(null, null)}
						onSaved={() => admitSelectedRange(null, null)}
						placeholder="Write an annotation in Markdown"
					/>
				);
			}
			if (metadata?.kind !== 'thread') return null;
			const thread = threadForPierreAnnotation({ annotation, threads: activeThreads });
			return thread === null ? null : (
				<WorktreeAnnotationThread
					onActivateRange={() => activateSavedAnnotationRange(metadata.range, item.id)}
					rangeActive={
						selectedItemIdRef.current === item.id &&
						selectedRange !== null &&
						worktreeAnnotationPierreRangesMatch(selectedRange, metadata.range)
					}
					thread={thread}
				/>
			);
		},
		[
			activeThreads,
			activateSavedAnnotationRange,
			admitSelectedRange,
			pendingComposer,
			props.reviewPackage.itemsById,
			selectedRange,
			sessionSelection.rootAdmission,
		],
	);

	return {
		activeThreads,
		annotateItem,
		codeViewOptions,
		projectionRevision:
			projection.revision === null && composerPresentationRevision === 0
				? null
				: (projection.presentationRevision ?? 0) * 1_000_000 + composerPresentationRevision,
		renderAnnotation,
		selectedItemIdRef,
		selectedRange,
	};
}

function isAnnotationCodeViewItem(item: CodeViewItem | undefined): item is BridgeCodeViewItem {
	return item !== undefined && 'bridgeMetadata' in item;
}
