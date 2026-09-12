import type { CodeViewLineSelection, CodeViewOptions, SelectedLineRange } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, useLayoutEffect, useMemo, useRef, useState, type ReactElement } from 'react';

import { Alert, AlertDescription } from '../components/ui/alert.js';
import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { codeViewSelectionScrollRetryFrameBudget } from '../review-viewer/code-view/bridge-code-view-panel-types.js';
import {
	bridgeCodeViewPresentationItemWithExactSource,
	observeBridgeCodeViewRenderFulfillment,
	reconcileBridgeCodeViewRenderFulfillment,
} from '../review-viewer/code-view/bridge-code-view-render-fulfillment.js';
import {
	fileAnnotationOriginForPierreSelection,
	filePierreAnnotationForExistingCodeViewComposer,
	filePierreAnnotationsForExistingCodeView,
	threadForPierreAnnotation,
	worktreeAnnotationMetadataForPierreAnnotation,
	worktreeAnnotationPierreRangesMatch,
	type WorktreeAnnotationLocatedOrigin,
} from '../review-viewer/code-view/worktree-annotation-pierre-adapter.js';
import { BridgePierreWorkerPoolProvider } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { useWorktreeAnnotationSelectionDismissal } from '../worktree-annotations/use-worktree-annotation-selection-dismissal.js';
import { mergeWorktreeAnnotationCommandConfirmedThreads } from '../worktree-annotations/worktree-annotation-command-confirmed-presentation.js';
import { createWorktreeAnnotationEditToken } from '../worktree-annotations/worktree-annotation-edit-token.js';
import { useWorktreeAnnotationNavigation } from '../worktree-annotations/worktree-annotation-navigation.js';
import { deriveWorktreeAnnotationShareProjection } from '../worktree-annotations/worktree-annotation-share-projection.js';
import {
	useWorktreeAnnotationActiveEditTokens,
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationEditSurfaceToken,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSessionDemand,
} from '../worktree-annotations/worktree-annotation-surface-provider.js';
import {
	WorktreeAnnotationNewMessageComposer,
	WorktreeAnnotationThread,
} from '../worktree-annotations/worktree-annotation-thread.js';
import {
	bridgeFileViewerCodeViewItemsForPanelState,
	type BridgeFileViewerCodePanelState,
	type BridgeFileViewerSelectedCodeViewItem,
} from './bridge-file-viewer-code-view-items.js';
import { bridgeFileViewerCodeViewOptions } from './bridge-file-viewer-code-view-options.js';

export type { BridgeFileViewerCodePanelState, BridgeFileViewerSelectedCodeViewItem };

export interface BridgeFileViewerCodePanelProps {
	readonly codeViewOptions?: Readonly<CodeViewOptions<undefined>>;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'observePostRender' | 'reconcilePublication'
	>;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly totalHeightPixels: number | null;
	readonly staleNotice?: ReactElement | null;
}

interface FileAnnotationAdmissionIdentity {
	readonly codeViewItemId: string;
	readonly fileId: string;
	readonly path: string;
	readonly range: SelectedLineRange;
	readonly sourceDescriptorId: string;
}

interface PendingFileAnnotationComposer extends FileAnnotationAdmissionIdentity {
	readonly committed: boolean;
	readonly editToken: string;
	readonly origin: WorktreeAnnotationLocatedOrigin;
}

export function BridgeFileViewerCodePanel(props: BridgeFileViewerCodePanelProps): ReactElement {
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const annotationProjection = useWorktreeAnnotationProjection();
	const annotationSessionSelection = useWorktreeAnnotationSessionSelection();
	const annotationInteraction = useWorktreeAnnotationInteraction();
	const navigation = useWorktreeAnnotationNavigation();
	const navigationRequest =
		navigation?.activeSurface === 'file' &&
		navigation.request?.destination === 'file' &&
		navigation.request.phase === 'ready'
			? navigation.request
			: null;
	const navigationThread =
		navigationRequest === null
			? undefined
			: annotationProjection.threads.find(
					(thread): boolean => thread.context.threadId === navigationRequest.threadId,
				);
	const navigationTarget = useMemo(
		() =>
			navigationRequest !== null && navigationThread !== undefined
				? { request: navigationRequest, thread: navigationThread }
				: null,
		[navigationRequest, navigationThread],
	);
	const [navigationPaintRevision, setNavigationPaintRevision] = useState(0);
	const activeEditTokens = useWorktreeAnnotationActiveEditTokens();
	const activeNewMessageEditTokens = useWorktreeAnnotationActiveNewMessageEditTokens();
	const activeAnnotationSessionId = annotationSessionSelection.activeSessionId;
	useWorktreeAnnotationSessionDemand(activeAnnotationSessionId);
	const serverAnnotationThreads = annotationProjection.threads.filter(
		(thread): boolean =>
			activeAnnotationSessionId !== null &&
			thread.messages.some((message) => message.sessionId === activeAnnotationSessionId) &&
			!thread.messages.every(
				(message): boolean =>
					message.draft?.activeEditToken !== null &&
					message.draft?.activeEditToken !== undefined &&
					activeNewMessageEditTokens.has(message.draft.activeEditToken),
			),
	);
	const commandConfirmedAnnotationThreads = annotationProjection.commandConfirmedThreads.filter(
		(thread): boolean =>
			(activeAnnotationSessionId === null
				? annotationProjection.sessions.length === 0
				: thread.messages.some((message) => message.sessionId === activeAnnotationSessionId)) &&
			!thread.messages.every(
				(message): boolean =>
					message.draft?.activeEditToken !== null &&
					message.draft?.activeEditToken !== undefined &&
					activeNewMessageEditTokens.has(message.draft.activeEditToken),
			),
	);
	const activeAnnotationThreads =
		annotationInteraction.shareMode.kind === 'open'
			? deriveWorktreeAnnotationShareProjection({
					scope: annotationInteraction.shareMode.scope,
					threads: serverAnnotationThreads,
				}).inlineThreads
			: mergeWorktreeAnnotationCommandConfirmedThreads({
					commandConfirmedThreads: commandConfirmedAnnotationThreads,
					serverThreads: serverAnnotationThreads,
				});
	const [pendingAnnotationComposer, setPendingAnnotationComposer] =
		useState<PendingFileAnnotationComposer | null>(null);
	const pendingAnnotationComposerRef = useRef(pendingAnnotationComposer);
	pendingAnnotationComposerRef.current = pendingAnnotationComposer;
	const [composerPresentationRevision, setComposerPresentationRevision] = useState(0);
	const previousRenderedIdentityRef = useRef<{
		readonly fileId: string;
		readonly path: string;
	} | null>(null);
	useWorktreeAnnotationEditSurfaceToken(pendingAnnotationComposer?.editToken ?? null);
	const scrollEffectVersionRef = useRef(0);
	const lastDisplayedItemRef = useRef(props.selectedCodeViewItem);
	const previousItem = lastDisplayedItemRef.current;
	const candidateItem = props.selectedCodeViewItem;
	const previousSourceId = previousItem?.bridgeMetadata.sourceDescriptorId;
	const retainsAnnotationSource =
		previousItem !== null &&
		candidateItem !== null &&
		previousItem.bridgeMetadata.itemId === candidateItem.bridgeMetadata.itemId &&
		previousItem.bridgeMetadata.displayPath === candidateItem.bridgeMetadata.displayPath &&
		previousSourceId !== undefined &&
		previousSourceId !== candidateItem.bridgeMetadata.sourceDescriptorId &&
		commandConfirmedAnnotationThreads.some(
			(thread): boolean =>
				thread.context.path === previousItem.bridgeMetadata.displayPath &&
				thread.context.sourceIdentity === previousSourceId,
		);
	const displayedCodeViewItem = retainsAnnotationSource ? previousItem : candidateItem;
	useLayoutEffect((): void => {
		// Retain the committed presentation reference, never a second copy of source bytes.
		lastDisplayedItemRef.current = displayedCodeViewItem;
	});
	const codeViewItems = useMemo(() => {
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: props.openFileState,
			selectedCodeViewItem: displayedCodeViewItem,
		});
		return items.map((item) => {
			const annotations =
				annotationProjection.revision === null &&
				annotationProjection.commandConfirmedThreads.length === 0
					? []
					: filePierreAnnotationsForExistingCodeView({
							path: item.bridgeMetadata.displayPath,
							sourceDescriptorId: item.bridgeMetadata.sourceDescriptorIdsByRole?.file ?? null,
							threads: activeAnnotationThreads,
						});
			const pendingComposerAnnotation =
				pendingAnnotationComposer === null ||
				!fileAnnotationComposerMatchesItem(pendingAnnotationComposer, item)
					? null
					: filePierreAnnotationForExistingCodeViewComposer({
							editToken: pendingAnnotationComposer.editToken,
							range: pendingAnnotationComposer.range,
						});
			if (
				annotationProjection.revision === null &&
				annotationProjection.commandConfirmedThreads.length === 0 &&
				pendingComposerAnnotation === null
			) {
				return item;
			}
			return bridgeCodeViewPresentationItemWithExactSource({
				presentationItem: Object.assign({}, item, {
					annotations:
						pendingComposerAnnotation === null
							? annotations
							: [...annotations, pendingComposerAnnotation],
					version: annotationPresentationVersion(
						item.version,
						activeEditTokens.size === 0 ? annotationProjection.presentationRevision : null,
						composerPresentationRevision,
					),
				}),
				sourceItem: item,
			});
		});
	}, [
		activeEditTokens.size,
		activeAnnotationThreads,
		annotationProjection.commandConfirmedThreads.length,
		annotationProjection.presentationRevision,
		annotationProjection.revision,
		composerPresentationRevision,
		pendingAnnotationComposer,
		props.openFileState,
		displayedCodeViewItem,
	]);
	const shouldRenderContentState = props.openFileState.status !== 'ready';
	useLayoutEffect((): void => {
		if (displayedCodeViewItem === null) return;
		reconcileBridgeCodeViewRenderFulfillment({
			exactPresentationItem: displayedCodeViewItem,
			getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
		});
	});
	const handleCodeViewPostRender = useCallback<
		NonNullable<CodeViewOptions<undefined>['onPostRender']>
	>(
		(node, _instance, phase, context): void => {
			if (navigationRequest !== null)
				setNavigationPaintRevision((revision): number => revision + 1);
			observeBridgeCodeViewRenderFulfillment({
				contextItem: context.item,
				getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
				itemId: context.item.id,
				phase,
				renderedElement: node,
				renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				selectedCodeViewItem: displayedCodeViewItem,
				visibleCodeViewItems: undefined,
			});
		},
		[props.renderFulfillmentCoordinator, displayedCodeViewItem, navigationRequest],
	);
	const admitSelectedRange = useCallback(
		(range: SelectedLineRange | null, itemId: string): void => {
			const selectedItem = displayedCodeViewItem;
			const sourceDescriptorId = selectedItem?.bridgeMetadata.sourceDescriptorId;
			if (
				range === null ||
				selectedItem === null ||
				sourceDescriptorId === undefined ||
				selectedItem.id !== itemId
			) {
				setPendingAnnotationComposer(null);
				annotationInteraction.clearRangePresentation();
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			const admissionIdentity = fileAnnotationAdmissionIdentity({
				range,
				selectedItem,
				sourceDescriptorId,
			});
			setPendingAnnotationComposer({
				...admissionIdentity,
				committed: false,
				editToken: createWorktreeAnnotationEditToken(),
				origin: fileAnnotationOriginForPierreSelection({
					path: selectedItem.bridgeMetadata.displayPath,
					range,
					sourceDescriptorId,
				}),
			});
			annotationInteraction.setPendingRange(itemId, range);
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[annotationInteraction, displayedCodeViewItem],
	);
	const retainSelectedRange = useCallback(
		(range: SelectedLineRange | null, itemId: string): void => {
			const currentPresentation = annotationInteraction.pierreRangePresentation;
			if (
				currentPresentation.kind === 'savedThread' &&
				range !== null &&
				currentPresentation.itemId === itemId &&
				worktreeAnnotationPierreRangesMatch(currentPresentation.range, range)
			) {
				return;
			}
			if (pendingAnnotationComposerRef.current?.committed === true) return;
			if (range === null && pendingAnnotationComposerRef.current !== null) return;
			const selectedItem = displayedCodeViewItem;
			const sourceDescriptorId = selectedItem?.bridgeMetadata.sourceDescriptorId;
			if (
				range === null ||
				selectedItem === null ||
				sourceDescriptorId === undefined ||
				selectedItem.id !== itemId
			) {
				setPendingAnnotationComposer(null);
				annotationInteraction.clearRangePresentation();
				setComposerPresentationRevision((revision): number => revision + 1);
				return;
			}
			const selectionIdentity = fileAnnotationAdmissionIdentity({
				range,
				selectedItem,
				sourceDescriptorId,
			});
			setPendingAnnotationComposer((currentComposer) =>
				currentComposer !== null &&
				fileAnnotationIdentityMatchesItem(currentComposer, selectedItem) &&
				worktreeAnnotationPierreRangesMatch(currentComposer.range, range)
					? currentComposer
					: null,
			);
			annotationInteraction.setPendingRange(selectionIdentity.codeViewItemId, range);
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[annotationInteraction, displayedCodeViewItem],
	);
	const annotationRangePresentation = annotationInteraction.pierreRangePresentation;
	const selectedAnnotationLines: CodeViewLineSelection | null =
		annotationRangePresentation.kind === 'none'
			? null
			: {
					id: annotationRangePresentation.itemId,
					range: annotationRangePresentation.range,
				};
	const handleSelectedAnnotationLinesChange = useCallback(
		(selection: CodeViewLineSelection | null): void => {
			retainSelectedRange(selection?.range ?? null, selection?.id ?? '');
		},
		[retainSelectedRange],
	);
	const clearAnnotationSelection = useCallback(
		(): void => admitSelectedRange(null, ''),
		[admitSelectedRange],
	);
	useWorktreeAnnotationSelectionDismissal({
		active:
			annotationRangePresentation.kind === 'pending' &&
			pendingAnnotationComposer?.committed !== true,
		clearSelection: clearAnnotationSelection,
	});
	const codeViewOptions = useMemo<CodeViewOptions<undefined>>(
		() => ({
			...(props.codeViewOptions ?? bridgeFileViewerCodeViewOptions),
			enableGutterUtility: true,
			enableLineSelection: true,
			onGutterUtilityClick: (range, context): void => {
				if (pendingAnnotationComposerRef.current?.committed === true) return;
				admitSelectedRange(range, context.item.id);
			},
			onLineSelectionEnd: (range, context): void => {
				if (pendingAnnotationComposerRef.current?.committed === true) return;
				if (range === null) admitSelectedRange(null, '');
				else retainSelectedRange(range, context.item.id);
			},
			onPostRender: handleCodeViewPostRender,
		}),
		[admitSelectedRange, handleCodeViewPostRender, props.codeViewOptions, retainSelectedRange],
	);
	useLayoutEffect((): void => {
		const selectedItem = displayedCodeViewItem;
		const composerMatchesDisplayedFile =
			pendingAnnotationComposer !== null &&
			selectedItem !== null &&
			fileAnnotationComposerMatchesItem(pendingAnnotationComposer, selectedItem);
		const selectionMatchesDisplayedFile =
			annotationRangePresentation.kind === 'none' ||
			(selectedItem !== null && annotationRangePresentation.itemId === selectedItem.id);
		if (pendingAnnotationComposer !== null && !composerMatchesDisplayedFile) {
			setPendingAnnotationComposer(null);
			setComposerPresentationRevision((revision): number => revision + 1);
		}
		if (!selectionMatchesDisplayedFile) {
			annotationInteraction.clearRangePresentation();
		}
	}, [
		annotationInteraction,
		annotationRangePresentation,
		pendingAnnotationComposer,
		displayedCodeViewItem,
	]);
	useLayoutEffect((): (() => void) | void => {
		const selectedItem = displayedCodeViewItem;
		if (selectedItem === null) return;
		const currentIdentity = {
			fileId: selectedItem.bridgeMetadata.itemId,
			path: selectedItem.bridgeMetadata.displayPath,
		};
		const previousIdentity = previousRenderedIdentityRef.current;
		previousRenderedIdentityRef.current = currentIdentity;
		const requestedThread = navigationTarget?.thread;
		const revealRequest =
			requestedThread?.context.path === currentIdentity.path ? navigationTarget : null;
		if (
			revealRequest === null &&
			previousIdentity !== null &&
			previousIdentity.fileId === currentIdentity.fileId &&
			previousIdentity.path === currentIdentity.path
		) {
			return;
		}
		const effectVersion = scrollEffectVersionRef.current + 1;
		scrollEffectVersionRef.current = effectVersion;
		let scheduledFrame = 0;
		const reveal = (remainingFrames: number): void => {
			scheduledFrame = requestAnimationFrame((): void => {
				if (scrollEffectVersionRef.current !== effectVersion) return;
				const handle = codeViewHandleRef.current;
				const instance = handle?.getInstance();
				if (revealRequest !== null && revealRequest !== undefined) {
					const owner = instance?.getContainerElement();
					const frame = owner?.querySelector<HTMLElement>(
						`[data-annotation-thread-id="${CSS.escape(revealRequest.request.threadId)}"]`,
					);
					if (
						frame !== null &&
						frame !== undefined &&
						owner !== null &&
						owner !== undefined &&
						instance !== undefined
					) {
						handle?.scrollTo({
							type: 'position',
							position:
								instance.getScrollTop() +
								frame.getBoundingClientRect().top -
								owner.getBoundingClientRect().top -
								8,
							behavior: 'instant',
						});
						navigation?.finish(revealRequest.request.requestId);
						return;
					}
					const endLine = revealRequest.thread.context.endLine;
					if (endLine !== null)
						handle?.scrollTo({
							type: 'line',
							id: selectedItem.id,
							lineNumber: endLine,
							align: 'start',
							behavior: 'instant',
						});
					if (remainingFrames > 0) reveal(remainingFrames - 1);
					return;
				}
				handle?.scrollTo({
					behavior: 'instant',
					position: 0,
					type: 'position',
				});
			});
		};
		reveal(codeViewSelectionScrollRetryFrameBudget);
		const scrollOwner = codeViewHandleRef.current?.getInstance()?.getContainerElement();
		const cancelByUser = (): void => {
			scrollEffectVersionRef.current += 1;
			cancelAnimationFrame(scheduledFrame);
			if (revealRequest != null) navigation?.finish(revealRequest.request.requestId);
		};
		if (revealRequest != null) {
			scrollOwner?.addEventListener('wheel', cancelByUser, { passive: true });
			scrollOwner?.addEventListener('pointerdown', cancelByUser);
		}
		return (): void => {
			cancelAnimationFrame(scheduledFrame);
			scrollOwner?.removeEventListener('wheel', cancelByUser);
			scrollOwner?.removeEventListener('pointerdown', cancelByUser);
		};
	}, [displayedCodeViewItem, navigation, navigationTarget, navigationPaintRevision]);
	return (
		<section
			aria-label="Selected file"
			className="relative h-full min-h-0 min-w-0 overflow-hidden bg-background"
			data-bridge-code-view-overflow={codeViewOptions.overflow}
			data-pierre-code-view-owner="CodeView.file"
			data-shiki-rendering="pierre"
			data-testid="bridge-file-viewer-code-canvas"
			data-worktree-open-file-body-preview={displayedCodeViewItem?.file.contents.slice(0, 160)}
			data-worktree-rendered-file-path={displayedCodeViewItem?.bridgeMetadata.displayPath}
			data-worktree-rendered-content-roles={displayedCodeViewItem?.bridgeMetadata.contentRoles.join(
				',',
			)}
			data-worktree-rendered-content-state={displayedCodeViewItem?.bridgeMetadata.contentState}
			data-worktree-rendered-item-id={displayedCodeViewItem?.bridgeMetadata.itemId}
			data-worktree-rendered-line-count={displayedCodeViewItem?.bridgeMetadata.lineCount}
			data-worker-backed-highlighting={
				props.codeViewWorkerPoolEnabled === true ? 'requested' : 'disabled'
			}
			{...(props.openFileState.status === 'idle'
				? {}
				: {
						'data-worktree-open-file-path': props.openFileState.path,
						'data-worktree-open-file-state': props.openFileState.status,
					})}
			{...(props.totalHeightPixels === null
				? {}
				: { 'data-worktree-open-file-total-size': String(props.totalHeightPixels) })}
		>
			<BridgePierreWorkerPoolProvider
				{...(props.codeViewWorkerPoolEnabled === undefined
					? {}
					: { enabled: props.codeViewWorkerPoolEnabled })}
				{...(props.codeViewWorkerFactory === undefined
					? {}
					: { workerFactory: props.codeViewWorkerFactory })}
			>
				<div
					className={`h-full min-h-0 min-w-0 ${codeViewItems.length > 0 ? '' : 'invisible'}`}
					data-testid="bridge-file-viewer-code-view"
				>
					<CodeView
						className="bridge-code-view-scroll-owner bridge-scrollbar cv-scrollbar relative h-full min-h-0 min-w-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain [overflow-anchor:none] [will-change:scroll-position] [&_diffs-container]:overflow-clip [&_diffs-container]:[contain:layout_paint_style]"
						items={codeViewItems}
						options={codeViewOptions}
						onSelectedLinesChange={handleSelectedAnnotationLinesChange}
						renderAnnotation={(annotation, item) => {
							if (item.type !== 'file') return null;
							const metadata = worktreeAnnotationMetadataForPierreAnnotation(annotation);
							if (
								metadata?.kind === 'composer' &&
								pendingAnnotationComposer?.editToken === metadata.editToken
							) {
								return (
									<WorktreeAnnotationNewMessageComposer
										createOperation={(body, editToken, admission) => ({
											admission: admission ?? annotationSessionSelection.rootAdmission,
											body,
											editToken,
											kind: 'root.create',
											origin: pendingAnnotationComposer.origin,
										})}
										editToken={metadata.editToken}
										editSurfaceRegistrationOwner="parent"
										onCancel={() => admitSelectedRange(null, '')}
										onCommitted={() =>
											setPendingAnnotationComposer((currentComposer) =>
												currentComposer?.editToken === metadata.editToken
													? { ...currentComposer, committed: true }
													: currentComposer,
											)
										}
										onSaved={(savedMessage) => {
											const savedThreadIdentity = {
												itemId: item.id,
												range: metadata.range,
												threadId: savedMessage.threadId,
											};
											admitSelectedRange(null, '');
											annotationInteraction.activateSavedThread(savedThreadIdentity);
										}}
										placeholder="Write an annotation in Markdown"
									/>
								);
							}
							if (metadata?.kind !== 'thread') return null;
							const thread = threadForPierreAnnotation({
								annotation,
								threads: activeAnnotationThreads,
							});
							return thread === null ? null : (
								<WorktreeAnnotationThread
									rangeIdentity={{ itemId: item.id, range: metadata.range }}
									thread={thread}
								/>
							);
						}}
						ref={codeViewHandleRef}
						selectedLines={selectedAnnotationLines}
						style={{ height: '100%' }}
					/>
				</div>
				{shouldRenderContentState ? (
					<div className="pointer-events-none absolute inset-0">
						<BridgeFileViewerContentState state={props.openFileState} />
					</div>
				) : null}
			</BridgePierreWorkerPoolProvider>
			{props.staleNotice ??
				(retainsAnnotationSource ? (
					<div className="pointer-events-none absolute right-2 bottom-2">
						<Alert role="status">
							<AlertDescription>
								{annotationProjection.readStatus.kind === 'unavailable'
									? 'Annotation refresh unavailable. Showing the previous file and comments.'
									: 'File updated. Keeping your saved comment visible while annotations refresh.'}
							</AlertDescription>
						</Alert>
					</div>
				) : null)}
		</section>
	);
}

function fileAnnotationAdmissionIdentity(props: {
	readonly range: SelectedLineRange;
	readonly selectedItem: BridgeFileViewerSelectedCodeViewItem;
	readonly sourceDescriptorId: string;
}): FileAnnotationAdmissionIdentity {
	return {
		codeViewItemId: props.selectedItem.id,
		fileId: props.selectedItem.bridgeMetadata.itemId,
		path: props.selectedItem.bridgeMetadata.displayPath,
		range: props.range,
		sourceDescriptorId: props.sourceDescriptorId,
	};
}

function fileAnnotationIdentityMatchesItem(
	identity: FileAnnotationAdmissionIdentity,
	item: BridgeFileViewerSelectedCodeViewItem,
): boolean {
	return (
		identity.codeViewItemId === item.id &&
		identity.fileId === item.bridgeMetadata.itemId &&
		identity.path === item.bridgeMetadata.displayPath &&
		identity.sourceDescriptorId === item.bridgeMetadata.sourceDescriptorId
	);
}

function fileAnnotationComposerMatchesItem(
	composer: PendingFileAnnotationComposer,
	item: BridgeFileViewerSelectedCodeViewItem,
): boolean {
	return (
		composer.codeViewItemId === item.id &&
		composer.fileId === item.bridgeMetadata.itemId &&
		composer.path === item.bridgeMetadata.displayPath &&
		(composer.committed || composer.sourceDescriptorId === item.bridgeMetadata.sourceDescriptorId)
	);
}

function annotationPresentationVersion(
	contentVersion: number | undefined,
	projectionRevision: number | null,
	composerRevision: number,
): number {
	const baseContentVersion =
		contentVersion !== undefined && contentVersion >= 1_000_000
			? Math.floor(contentVersion / 1_000_000)
			: (contentVersion ?? 0);
	return baseContentVersion * 1_000_000 + (projectionRevision ?? 0) + composerRevision;
}

function BridgeFileViewerContentState(props: {
	readonly state: BridgeFileViewerCodePanelState;
}): ReactElement {
	const label =
		props.state.status === 'idle'
			? 'Select a file'
			: props.state.status === 'loading' || props.state.status === 'stale'
				? 'Loading file'
				: 'Content unavailable';
	return (
		<div
			className="relative flex min-h-full items-start justify-center text-sm text-muted-foreground"
			data-testid="bridge-file-viewer-content-state"
			role="status"
		>
			<div className="sticky top-0 flex min-h-screen items-center justify-center">{label}</div>
		</div>
	);
}
