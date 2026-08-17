import type { CodeViewOptions, SelectedLineRange } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, useLayoutEffect, useMemo, useRef, useState, type ReactElement } from 'react';

import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
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
import { createWorktreeAnnotationEditToken } from '../worktree-annotations/worktree-annotation-edit-token.js';
import {
	useWorktreeAnnotationActiveComposerEditTokens,
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
	readonly editToken: string;
	readonly origin: WorktreeAnnotationLocatedOrigin;
}

export function BridgeFileViewerCodePanel(props: BridgeFileViewerCodePanelProps): ReactElement {
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const annotationProjection = useWorktreeAnnotationProjection();
	const annotationSessionSelection = useWorktreeAnnotationSessionSelection();
	const annotationInteraction = useWorktreeAnnotationInteraction();
	const activeComposerEditTokens = useWorktreeAnnotationActiveComposerEditTokens();
	const activeAnnotationSessionId = annotationSessionSelection.activeSessionId;
	useWorktreeAnnotationSessionDemand(activeAnnotationSessionId);
	const activeAnnotationThreads = annotationProjection.threads.filter(
		(thread): boolean =>
			activeAnnotationSessionId !== null &&
			thread.messages.some((message) => message.sessionId === activeAnnotationSessionId) &&
			!thread.messages.every(
				(message): boolean =>
					message.draft?.activeEditToken !== null &&
					message.draft?.activeEditToken !== undefined &&
					activeComposerEditTokens.has(message.draft.activeEditToken),
			),
	);
	const [pendingAnnotationComposer, setPendingAnnotationComposer] =
		useState<PendingFileAnnotationComposer | null>(null);
	const [composerPresentationRevision, setComposerPresentationRevision] = useState(0);
	const [annotationSelection, setAnnotationSelection] =
		useState<FileAnnotationAdmissionIdentity | null>(null);
	const previousRenderedIdentityRef = useRef<{
		readonly fileId: string;
		readonly path: string;
	} | null>(null);
	const scrollEffectVersionRef = useRef(0);
	const codeViewItems = useMemo(() => {
		const items = bridgeFileViewerCodeViewItemsForPanelState({
			openFileState: props.openFileState,
			selectedCodeViewItem: props.selectedCodeViewItem,
		});
		return items.map((item) => {
			const annotations =
				annotationProjection.revision === null
					? []
					: filePierreAnnotationsForExistingCodeView({
							path: item.bridgeMetadata.displayPath,
							threads: activeAnnotationThreads,
						});
			const pendingComposerAnnotation =
				pendingAnnotationComposer === null ||
				!fileAnnotationIdentityMatchesItem(pendingAnnotationComposer, item)
					? null
					: filePierreAnnotationForExistingCodeViewComposer({
							editToken: pendingAnnotationComposer.editToken,
							range: pendingAnnotationComposer.range,
						});
			if (annotationProjection.revision === null && pendingComposerAnnotation === null) {
				return item;
			}
			return Object.assign({}, item, {
				annotations:
					pendingComposerAnnotation === null
						? annotations
						: [...annotations, pendingComposerAnnotation],
				version: annotationPresentationVersion(
					item.version,
					annotationProjection.presentationRevision,
					composerPresentationRevision,
				),
			});
		});
	}, [
		activeAnnotationThreads,
		annotationProjection.presentationRevision,
		annotationProjection.revision,
		composerPresentationRevision,
		pendingAnnotationComposer,
		props.openFileState,
		props.selectedCodeViewItem,
	]);
	const shouldRenderContentState = props.selectedCodeViewItem === null;
	useLayoutEffect((): void => {
		if (props.selectedCodeViewItem === null) return;
		reconcileBridgeCodeViewRenderFulfillment({
			exactPresentationItem: props.selectedCodeViewItem,
			getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
		});
	});
	const handleCodeViewPostRender = useCallback<
		NonNullable<CodeViewOptions<undefined>['onPostRender']>
	>(
		(node, _instance, phase, context): void => {
			observeBridgeCodeViewRenderFulfillment({
				contextItem: context.item,
				getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
				itemId: context.item.id,
				phase,
				renderedElement: node,
				renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				selectedCodeViewItem: props.selectedCodeViewItem,
				visibleCodeViewItems: undefined,
			});
		},
		[props.renderFulfillmentCoordinator, props.selectedCodeViewItem],
	);
	const admitSelectedRange = useCallback(
		(range: SelectedLineRange | null, itemId: string): void => {
			annotationInteraction.clearActiveThread();
			const selectedItem = props.selectedCodeViewItem;
			const sourceDescriptorId = selectedItem?.bridgeMetadata.sourceDescriptorId;
			if (
				range === null ||
				selectedItem === null ||
				sourceDescriptorId === undefined ||
				selectedItem.id !== itemId
			) {
				setPendingAnnotationComposer(null);
				setAnnotationSelection(null);
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
				editToken: createWorktreeAnnotationEditToken(),
				origin: fileAnnotationOriginForPierreSelection({
					path: selectedItem.bridgeMetadata.displayPath,
					range,
					sourceDescriptorId,
				}),
			});
			setAnnotationSelection(admissionIdentity);
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[annotationInteraction, props.selectedCodeViewItem],
	);
	const retainSelectedRange = useCallback(
		(range: SelectedLineRange | null, itemId: string): void => {
			annotationInteraction.clearActiveThread();
			const selectedItem = props.selectedCodeViewItem;
			const sourceDescriptorId = selectedItem?.bridgeMetadata.sourceDescriptorId;
			if (
				range === null ||
				selectedItem === null ||
				sourceDescriptorId === undefined ||
				selectedItem.id !== itemId
			) {
				setPendingAnnotationComposer(null);
				setAnnotationSelection(null);
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
			setAnnotationSelection(selectionIdentity);
			setComposerPresentationRevision((revision): number => revision + 1);
		},
		[annotationInteraction, props.selectedCodeViewItem],
	);
	const activateSavedAnnotationRange = useCallback(
		(range: SelectedLineRange, itemId: string): void => {
			const selectedItem = props.selectedCodeViewItem;
			const sourceDescriptorId = selectedItem?.bridgeMetadata.sourceDescriptorId;
			if (selectedItem === null || sourceDescriptorId === undefined || selectedItem.id !== itemId) {
				return;
			}
			setPendingAnnotationComposer(null);
			setAnnotationSelection(
				fileAnnotationAdmissionIdentity({ range, selectedItem, sourceDescriptorId }),
			);
			codeViewHandleRef.current?.scrollTo({
				align: 'center',
				behavior: 'instant',
				id: itemId,
				range,
				type: 'range',
			});
		},
		[props.selectedCodeViewItem],
	);
	const codeViewOptions = useMemo<CodeViewOptions<undefined>>(
		() => ({
			...(props.codeViewOptions ?? bridgeFileViewerCodeViewOptions),
			controlledSelection: true,
			enableGutterUtility: true,
			enableLineSelection: true,
			onGutterUtilityClick: (range, context): void => admitSelectedRange(range, context.item.id),
			onLineSelectionEnd: (range, context): void => retainSelectedRange(range, context.item.id),
			onPostRender: handleCodeViewPostRender,
		}),
		[admitSelectedRange, handleCodeViewPostRender, props.codeViewOptions, retainSelectedRange],
	);
	useLayoutEffect((): void => {
		const selectedItem = props.selectedCodeViewItem;
		codeViewHandleRef.current?.setSelectedLines(
			annotationSelection === null ||
				selectedItem === null ||
				!fileAnnotationIdentityMatchesItem(annotationSelection, selectedItem)
				? null
				: { id: selectedItem.id, range: annotationSelection.range },
		);
	}, [annotationSelection, props.selectedCodeViewItem]);
	useLayoutEffect((): void => {
		const selectedItem = props.selectedCodeViewItem;
		const composerMatchesDisplayedFile =
			pendingAnnotationComposer !== null &&
			selectedItem !== null &&
			fileAnnotationIdentityMatchesItem(pendingAnnotationComposer, selectedItem);
		const selectionMatchesDisplayedFile =
			annotationSelection !== null &&
			selectedItem !== null &&
			fileAnnotationIdentityMatchesItem(annotationSelection, selectedItem);
		if (pendingAnnotationComposer !== null && !composerMatchesDisplayedFile) {
			setPendingAnnotationComposer(null);
			setComposerPresentationRevision((revision): number => revision + 1);
		}
		if (annotationSelection !== null && !selectionMatchesDisplayedFile) {
			setAnnotationSelection(null);
		}
	}, [annotationSelection, pendingAnnotationComposer, props.selectedCodeViewItem]);
	useLayoutEffect((): void => {
		const selectedItem = props.selectedCodeViewItem;
		if (selectedItem === null) return;
		const currentIdentity = {
			fileId: selectedItem.bridgeMetadata.itemId,
			path: selectedItem.bridgeMetadata.displayPath,
		};
		const previousIdentity = previousRenderedIdentityRef.current;
		previousRenderedIdentityRef.current = currentIdentity;
		if (
			previousIdentity !== null &&
			previousIdentity.fileId === currentIdentity.fileId &&
			previousIdentity.path === currentIdentity.path
		) {
			return;
		}
		const effectVersion = scrollEffectVersionRef.current + 1;
		scrollEffectVersionRef.current = effectVersion;
		requestAnimationFrame((): void => {
			if (scrollEffectVersionRef.current !== effectVersion) return;
			codeViewHandleRef.current?.scrollTo({
				behavior: 'instant',
				position: 0,
				type: 'position',
			});
		});
	}, [props.selectedCodeViewItem]);
	return (
		<section
			aria-label="Selected file"
			className="relative h-full min-h-0 min-w-0 overflow-hidden bg-[var(--bridge-canvas-bg)]"
			data-bridge-code-view-overflow={codeViewOptions.overflow}
			data-pierre-code-view-owner="CodeView.file"
			data-shiki-rendering="pierre"
			data-testid="bridge-file-viewer-code-canvas"
			data-worktree-open-file-body-preview={props.selectedCodeViewItem?.file.contents.slice(0, 160)}
			data-worktree-rendered-file-path={props.selectedCodeViewItem?.bridgeMetadata.displayPath}
			data-worktree-rendered-content-roles={props.selectedCodeViewItem?.bridgeMetadata.contentRoles.join(
				',',
			)}
			data-worktree-rendered-content-state={props.selectedCodeViewItem?.bridgeMetadata.contentState}
			data-worktree-rendered-item-id={props.selectedCodeViewItem?.bridgeMetadata.itemId}
			data-worktree-rendered-line-count={props.selectedCodeViewItem?.bridgeMetadata.lineCount}
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
					className={`h-full min-h-0 min-w-0 ${props.openFileState.status === 'ready' ? '' : 'invisible'}`}
					data-testid="bridge-file-viewer-code-view"
				>
					<CodeView
						className="bridge-code-view-scroll-owner bridge-scrollbar cv-scrollbar relative h-full min-h-0 min-w-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain [overflow-anchor:none] [will-change:scroll-position] [&_diffs-container]:overflow-clip [&_diffs-container]:[contain:layout_paint_style]"
						items={codeViewItems}
						options={codeViewOptions}
						renderAnnotation={(annotation, item) => {
							if (item.type !== 'file') return null;
							const metadata = worktreeAnnotationMetadataForPierreAnnotation(annotation);
							if (
								metadata?.kind === 'composer' &&
								pendingAnnotationComposer?.editToken === metadata.editToken
							) {
								return (
									<WorktreeAnnotationNewMessageComposer
										createOperation={(body, editToken) => ({
											admission: annotationSessionSelection.rootAdmission,
											body,
											editToken,
											kind: 'root.create',
											origin: pendingAnnotationComposer.origin,
										})}
										editToken={metadata.editToken}
										onCancel={() => admitSelectedRange(null, '')}
										onSaved={() => admitSelectedRange(null, '')}
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
									onActivateRange={() => activateSavedAnnotationRange(metadata.range, item.id)}
									rangeActive={
										annotationSelection !== null &&
										props.selectedCodeViewItem !== null &&
										props.selectedCodeViewItem.id === item.id &&
										fileAnnotationIdentityMatchesItem(
											annotationSelection,
											props.selectedCodeViewItem,
										) &&
										worktreeAnnotationPierreRangesMatch(annotationSelection.range, metadata.range)
									}
									thread={thread}
								/>
							);
						}}
						ref={codeViewHandleRef}
						style={{ height: '100%' }}
					/>
				</div>
				{shouldRenderContentState ? (
					<div className="pointer-events-none absolute inset-0">
						<BridgeFileViewerContentState state={props.openFileState} />
					</div>
				) : null}
			</BridgePierreWorkerPoolProvider>
			{props.staleNotice ?? null}
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
			: props.state.status === 'loading'
				? 'Loading file'
				: 'Content unavailable';
	return (
		<div
			className="relative flex min-h-full items-start justify-center text-sm text-[var(--bridge-text-secondary)]"
			data-testid="bridge-file-viewer-content-state"
			role="status"
		>
			<div className="sticky top-0 flex min-h-screen items-center justify-center">{label}</div>
		</div>
	);
}
