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
	useLayoutEffect,
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
import type {
	WorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationThreadProjection,
} from '../../worktree-annotations/worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveEditTokens,
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSessionDemand,
	useWorktreeAnnotationSurfaceClient,
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
} from './worktree-annotation-pierre-adapter.js';

export interface BridgeCodeViewWorktreeAnnotations {
	readonly activeThreads: readonly WorktreeAnnotationThreadProjection[];
	readonly activeEditorAttentionItemIds: readonly string[];
	readonly acknowledgeReviewAnnotationApplication: (applicationId: number) => boolean;
	readonly annotationApplicationItemIds: readonly string[] | null;
	readonly annotationApplicationId: number | null;
	readonly attentionItemIds: readonly string[];
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
	const annotationSurfaceClient = useWorktreeAnnotationSurfaceClient();
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
	const pendingComposer = interaction.pendingRootComposer;
	const pendingComposerRef = useRef(pendingComposer);
	pendingComposerRef.current = pendingComposer;
	const [composerPresentationRevision, setComposerPresentationRevision] = useState(0);
	const selectedItemIdRef = useRef<string | null>(null);
	const rangePresentation = interaction.pierreRangePresentation;
	const selectedRange = rangePresentation.kind === 'none' ? null : rangePresentation.range;
	const pendingComposerReattachment = useMemo((): {
		readonly itemId: string;
		readonly range: SelectedLineRange;
	} | null => {
		if (pendingComposer === null) return null;
		const durableThread = projection.threads.find((thread): boolean =>
			thread.messages.some(
				(message): boolean => message.draft?.activeEditToken === pendingComposer.editToken,
			),
		);
		if (
			durableThread === undefined ||
			(durableThread.context.placement !== 'exact' &&
				durableThread.context.placement !== 'relocated')
		)
			return null;
		const itemId = reviewItemIdForAnnotationThread({
			context: durableThread.context,
			reviewPackage: props.reviewPackage,
		});
		if (itemId === null) return null;
		const side =
			durableThread.context.sourceRole === 'review_base'
				? 'deletions'
				: durableThread.context.sourceRole === 'review_head'
					? 'additions'
					: null;
		if (side === null) return null;
		return {
			itemId,
			range: {
				end: durableThread.context.endLine,
				endSide: side,
				side,
				start: durableThread.context.startLine,
			},
		};
	}, [pendingComposer, projection.threads, props.reviewPackage]);
	useLayoutEffect((): void => {
		if (pendingComposerReattachment === null) return;
		const currentComposer = pendingComposerRef.current;
		if (
			currentComposer === null ||
			(currentComposer.itemId === pendingComposerReattachment.itemId &&
				worktreeAnnotationPierreRangesMatch(
					currentComposer.range,
					pendingComposerReattachment.range,
				))
		)
			return;
		selectedItemIdRef.current = pendingComposerReattachment.itemId;
		interaction.setPendingRange(
			pendingComposerReattachment.itemId,
			pendingComposerReattachment.range,
		);
		interaction.reattachPendingRootComposer({
			editToken: currentComposer.editToken,
			itemId: pendingComposerReattachment.itemId,
			range: pendingComposerReattachment.range,
		});
		setComposerPresentationRevision((revision): number => revision + 1);
	}, [interaction, pendingComposerReattachment]);
	const markPendingComposerDurable = useCallback(
		(editToken: string): void => {
			const currentComposer = pendingComposerRef.current;
			if (currentComposer?.editToken === editToken) {
				pendingComposerRef.current = {
					...currentComposer,
					hasDurableDraft: true,
				};
			}
			interaction.markPendingRootComposerDurable(editToken);
		},
		[interaction],
	);
	const activeEditorAttentionItemIds = useMemo((): readonly string[] => {
		const itemIds = new Set<string>();
		if (pendingComposer !== null) itemIds.add(pendingComposer.itemId);
		const threadExpansion = interaction.threadExpansion;
		if (threadExpansion.kind === 'open' && threadExpansion.editor !== null) {
			const thread = projection.threads.find(
				(candidate): boolean => candidate.context.threadId === threadExpansion.threadId,
			);
			const itemId =
				thread === undefined
					? null
					: reviewItemIdForAnnotationThread({
							context: thread.context,
							reviewPackage: props.reviewPackage,
						});
			if (itemId !== null) itemIds.add(itemId);
		}
		return props.reviewPackage.orderedItemIds.filter((itemId): boolean => itemIds.has(itemId));
	}, [interaction.threadExpansion, pendingComposer, projection.threads, props.reviewPackage]);
	const attentionItemIds = useMemo((): readonly string[] => {
		const itemIds = new Set(activeEditorAttentionItemIds);
		if (rangePresentation.kind !== 'none') itemIds.add(rangePresentation.itemId);
		return props.reviewPackage.orderedItemIds.filter((itemId): boolean => itemIds.has(itemId));
	}, [activeEditorAttentionItemIds, props.reviewPackage, rangePresentation]);
	const annotationApplicationItemIds = useMemo((): readonly string[] | null => {
		return reviewAnnotationApplicationItemIds({
			activeEditorItemIds: activeEditorAttentionItemIds,
			application: projection.reviewAnnotationApplication,
			reviewPackage: props.reviewPackage,
		});
	}, [activeEditorAttentionItemIds, projection.reviewAnnotationApplication, props.reviewPackage]);

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
				interaction.clearPendingRootComposer();
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
				interaction.clearPendingRootComposer();
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			selectedItemIdRef.current = item.id;
			interaction.setPendingRange(item.id, range);
			interaction.admitPendingRootComposer({
				committed: false,
				editToken: createWorktreeAnnotationEditToken(),
				hasDurableDraft: false,
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
			if (pendingComposerRef.current?.committed === true) return;
			if (range === null && pendingComposerRef.current !== null) return;
			const descriptor = itemId === null ? undefined : props.reviewPackage.itemsById[itemId];
			if (range === null || descriptor === undefined || itemId === null) {
				selectedItemIdRef.current = null;
				interaction.clearRangePresentation();
				interaction.clearPendingRootComposer();
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			selectedItemIdRef.current = itemId;
			interaction.setPendingRange(itemId, range);
			interaction.retainPendingRootComposer(itemId, range);
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
			if (pendingComposerRef.current?.hasDurableDraft === true) return;
			retainSelectedRange(selection?.range ?? null, selection?.id ?? null);
		},
		[retainSelectedRange],
	);
	const clearSelection = useCallback(
		(): void => admitSelectedRange(null, null),
		[admitSelectedRange],
	);
	useWorktreeAnnotationSelectionDismissal({
		active: rangePresentation.kind === 'pending' && pendingComposer?.committed !== true,
		clearSelection,
	});

	const codeViewOptions = useMemo(
		() =>
			({
				...props.codeViewOptions,
				enableGutterUtility: true,
				enableLineSelection: true,
				onGutterUtilityClick: (range, context): void => {
					if (pendingComposerRef.current?.committed === true) return;
					admitSelectedRange(range, context.item);
				},
				onLineSelectionEnd: (range, context): void => {
					if (pendingComposerRef.current?.committed === true) return;
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
						editSurfaceRegistrationOwner="parent"
						onCancel={() => admitSelectedRange(null, null)}
						onCommitted={() => interaction.markPendingRootComposerCommitted(metadata.editToken)}
						onDurableDraftCreated={() => markPendingComposerDurable(metadata.editToken)}
						onSaved={(savedMessage) => {
							const savedThreadIdentity = {
								itemId: item.id,
								range: metadata.range,
								threadId: savedMessage.threadId,
							};
							admitSelectedRange(null, null);
							interaction.activateSavedThread(savedThreadIdentity);
						}}
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
			interaction,
			markPendingComposerDurable,
			pendingComposer,
			props.reviewPackage.itemsById,
			sessionSelection.rootAdmission,
		],
	);

	return {
		activeThreads,
		activeEditorAttentionItemIds,
		acknowledgeReviewAnnotationApplication:
			annotationSurfaceClient.acknowledgeReviewAnnotationApplication,
		annotationApplicationItemIds,
		annotationApplicationId: projection.reviewAnnotationApplication?.applicationId ?? null,
		attentionItemIds,
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

export function reviewItemIdForAnnotationThread(props: {
	readonly context: WorktreeAnnotationThreadProjection['context'];
	readonly reviewPackage: BridgeReviewPackage;
}): string | null {
	for (const itemId of props.reviewPackage.orderedItemIds) {
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined) continue;
		const expectedPath = props.context.sourceRole === 'review_base' ? item.basePath : item.headPath;
		if (expectedPath === props.context.path) return itemId;
	}
	return null;
}

export function reviewAnnotationApplicationItemIds(props: {
	readonly activeEditorItemIds: readonly string[];
	readonly application: WorktreeAnnotationProjectionSnapshot['reviewAnnotationApplication'];
	readonly reviewPackage: BridgeReviewPackage;
}): readonly string[] | null {
	if (props.application === null) {
		const activeEditorItemIds = new Set(props.activeEditorItemIds);
		return props.reviewPackage.orderedItemIds.filter((itemId): boolean =>
			activeEditorItemIds.has(itemId),
		);
	}
	if (props.application.affectedItemIds === null) return null;
	const itemIds = new Set(props.application.affectedItemIds);
	for (const context of props.application.changedThreadOwnerContexts) {
		const itemId = reviewItemIdForAnnotationThread({
			context,
			reviewPackage: props.reviewPackage,
		});
		if (itemId !== null) itemIds.add(itemId);
	}
	for (const itemId of props.activeEditorItemIds) itemIds.add(itemId);
	return props.reviewPackage.orderedItemIds.filter((itemId): boolean => itemIds.has(itemId));
}

function isAnnotationCodeViewItem(item: CodeViewItem | undefined): item is BridgeCodeViewItem {
	return item !== undefined && 'bridgeMetadata' in item;
}
