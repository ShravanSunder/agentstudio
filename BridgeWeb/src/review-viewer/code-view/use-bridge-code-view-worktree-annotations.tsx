import type {
	CodeViewItem,
	CodeViewLineSelection,
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
import { useWorktreeAnnotationSelectionDismissal } from '../../worktree-annotations/use-worktree-annotation-selection-dismissal.js';
import { createWorktreeAnnotationEditToken } from '../../worktree-annotations/worktree-annotation-edit-token.js';
import { deriveWorktreeAnnotationShareProjection } from '../../worktree-annotations/worktree-annotation-share-projection.js';
import type { WorktreeAnnotationThreadProjection } from '../../worktree-annotations/worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveEditTokens,
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationEditSurfaceToken,
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
import { bridgeCodeViewPresentationItemWithExactSource } from './bridge-code-view-render-fulfillment.js';
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
	readonly onSelectedLinesChange: (selection: CodeViewLineSelection | null) => void;
	readonly renderAnnotation: (
		annotation: DiffLineAnnotation | LineAnnotation,
		item: CodeViewItem,
	) => ReactNode;
	readonly selectedItemIdRef: MutableRefObject<string | null>;
	readonly selectedLines: CodeViewLineSelection | null;
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
	const activeEditTokens = useWorktreeAnnotationActiveEditTokens();
	const activeNewMessageEditTokens = useWorktreeAnnotationActiveNewMessageEditTokens();
	const activeSessionId = sessionSelection.activeSessionId;
	useWorktreeAnnotationSessionDemand(activeSessionId);
	const activeThreads = useMemo(() => {
		const sessionThreads = projection.threads.filter(
			(thread): boolean =>
				activeSessionId !== null &&
				thread.messages.some((message) => message.sessionId === activeSessionId) &&
				!thread.messages.every(
					(message): boolean =>
						message.draft?.activeEditToken !== null &&
						message.draft?.activeEditToken !== undefined &&
						activeNewMessageEditTokens.has(message.draft.activeEditToken),
				),
		);
		return interaction.shareMode.kind === 'open'
			? deriveWorktreeAnnotationShareProjection({
					scope: interaction.shareMode.scope,
					threads: sessionThreads,
				}).inlineThreads
			: sessionThreads;
	}, [activeNewMessageEditTokens, activeSessionId, interaction.shareMode, projection.threads]);
	const [pendingComposer, setPendingComposer] = useState<{
		readonly editToken: string;
		readonly itemId: string;
		readonly origin: WorktreeAnnotationLocatedOrigin;
		readonly range: SelectedLineRange;
	} | null>(null);
	const pendingComposerRef = useRef(pendingComposer);
	pendingComposerRef.current = pendingComposer;
	useWorktreeAnnotationEditSurfaceToken(pendingComposer?.editToken ?? null);
	const [composerPresentationRevision, setComposerPresentationRevision] = useState(0);
	const selectedItemIdRef = useRef<string | null>(null);
	const rangePresentation = interaction.pierreRangePresentation;
	const selectedRange = rangePresentation.kind === 'none' ? null : rangePresentation.range;

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
				return bridgeCodeViewPresentationItemWithExactSource({
					presentationItem: {
						...item,
						annotations:
							composerAnnotation === null ? annotations : [...annotations, composerAnnotation],
					},
					sourceItem: item,
				});
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
			return bridgeCodeViewPresentationItemWithExactSource({
				presentationItem: {
					...item,
					annotations:
						composerAnnotation === null ? annotations : [...annotations, composerAnnotation],
				},
				sourceItem: item,
			});
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
			const descriptor = item === null ? undefined : props.reviewPackage.itemsById[item.id];
			if (range === null || descriptor === undefined || item === null) {
				selectedItemIdRef.current = null;
				interaction.clearRangePresentation();
				setPendingComposer(null);
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			const sourceDescriptorIdsByRole = isAnnotationCodeViewItem(item)
				? item.bridgeMetadata.sourceDescriptorIdsByRole
				: undefined;
			const fileSourceRole =
				item.type === 'file' && sourceDescriptorIdsByRole !== undefined
					? sourceDescriptorIdsByRole.head !== null
						? 'head'
						: sourceDescriptorIdsByRole.base !== null
							? 'base'
							: undefined
					: undefined;
			const origin =
				sourceDescriptorIdsByRole === undefined
					? null
					: reviewAnnotationOriginForPierreSelection({
							item: descriptor,
							itemType: item.type,
							range,
							sourceDescriptorIdsByRole,
							...(fileSourceRole === undefined ? {} : { fileSourceRole }),
						});
			if (origin === null) {
				selectedItemIdRef.current = null;
				interaction.clearRangePresentation();
				setPendingComposer(null);
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			selectedItemIdRef.current = item.id;
			interaction.setPendingRange(item.id, range);
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
		(range: SelectedLineRange | null, itemId: string | null): void => {
			const currentPresentation = interaction.pierreRangePresentation;
			if (
				currentPresentation.kind === 'savedThread' &&
				range !== null &&
				currentPresentation.itemId === itemId &&
				worktreeAnnotationPierreRangesMatch(currentPresentation.range, range)
			) {
				return;
			}
			if (range === null && pendingComposerRef.current !== null) return;
			const descriptor = itemId === null ? undefined : props.reviewPackage.itemsById[itemId];
			if (range === null || descriptor === undefined || itemId === null) {
				selectedItemIdRef.current = null;
				interaction.clearRangePresentation();
				setPendingComposer(null);
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			selectedItemIdRef.current = itemId;
			interaction.setPendingRange(itemId, range);
			setPendingComposer((currentComposer) =>
				currentComposer?.itemId === itemId &&
				worktreeAnnotationPierreRangesMatch(currentComposer.range, range)
					? currentComposer
					: null,
			);
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[interaction, props.reviewPackage.itemsById],
	);
	const selectedLines: CodeViewLineSelection | null =
		rangePresentation.kind === 'none'
			? null
			: { id: rangePresentation.itemId, range: rangePresentation.range };
	const onSelectedLinesChange = useCallback(
		(selection: CodeViewLineSelection | null): void => {
			retainSelectedRange(selection?.range ?? null, selection?.id ?? null);
		},
		[retainSelectedRange],
	);
	const clearSelection = useCallback(
		(): void => admitSelectedRange(null, null),
		[admitSelectedRange],
	);
	useWorktreeAnnotationSelectionDismissal({
		active: rangePresentation.kind === 'pending',
		clearSelection,
	});

	const codeViewOptions = useMemo(
		() =>
			({
				...props.codeViewOptions,
				enableGutterUtility: true,
				enableLineSelection: true,
				onGutterUtilityClick: (range, context): void => admitSelectedRange(range, context.item),
				onLineSelectionEnd: (range, context): void => {
					if (range === null) admitSelectedRange(null, null);
					else retainSelectedRange(range, context.item.id);
				},
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
						createOperation={(body, editToken, admission) => ({
							admission: admission ?? sessionSelection.rootAdmission,
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
					rangeIdentity={{ itemId: item.id, range: metadata.range }}
					thread={thread}
				/>
			);
		},
		[
			activeThreads,
			admitSelectedRange,
			pendingComposer,
			props.reviewPackage.itemsById,
			sessionSelection.rootAdmission,
		],
	);

	return {
		activeThreads,
		annotateItem,
		codeViewOptions,
		onSelectedLinesChange,
		projectionRevision:
			projection.revision === null && composerPresentationRevision === 0
				? null
				: (activeEditTokens.size === 0 ? projection.presentationRevision : 0) * 1_000_000 +
					composerPresentationRevision,
		renderAnnotation,
		selectedItemIdRef,
		selectedLines,
		selectedRange,
	};
}

function isAnnotationCodeViewItem(item: CodeViewItem | undefined): item is BridgeCodeViewItem {
	return item !== undefined && 'bridgeMetadata' in item;
}
