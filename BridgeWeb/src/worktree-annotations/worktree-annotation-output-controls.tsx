import { useCallback, useRef, useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import { Drawer } from '@/components/ui/drawer.js';

import { BridgeViewerContextPanel } from '../app/bridge-viewer-context-panel.js';
import { clearWorktreeAnnotationOutputHandled } from './worktree-annotation-output-handled-clear.js';
import { WorktreeAnnotationOutputHistoryControl } from './worktree-annotation-output-history-control.js';
import {
	type WorktreeAnnotationOutputPendingController,
	useWorktreeAnnotationOutputPendingController,
} from './worktree-annotation-output-pending-controller.js';
import { annotationOutputFeedback } from './worktree-annotation-output-presentation.js';
import {
	WorktreeAnnotationShareModeRow,
	WorktreeAnnotationShareTrigger,
	type WorktreeAnnotationShareScope,
} from './worktree-annotation-share-mode.js';
import { WorktreeAnnotationSharePreview } from './worktree-annotation-share-preview.js';
import { deriveWorktreeAnnotationShareProjection } from './worktree-annotation-share-projection.js';
import {
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
	useWorktreeAnnotationViewedController,
} from './worktree-annotation-surface-provider.js';

export function WorktreeAnnotationShareHeaderControl(): ReactElement | null {
	const outputPendingController = useWorktreeAnnotationOutputPendingController();
	return (
		<WorktreeAnnotationSharePanelControl
			finalFocus={({ closeReason, trigger }): false | HTMLElement | null =>
				closeReason === 'outside-press' ? false : trigger
			}
			onOpenRequest={(): boolean => true}
			outputPendingController={outputPendingController}
		/>
	);
}

export interface WorktreeAnnotationSharePanelFinalFocusContext {
	readonly closeReason: string | null;
	readonly trigger: HTMLButtonElement | null;
}

export function WorktreeAnnotationSharePanelControl(props: {
	readonly finalFocus: (
		context: WorktreeAnnotationSharePanelFinalFocusContext,
	) => false | HTMLElement | null;
	readonly onOpenRequest: () => boolean;
	readonly outputPendingController: WorktreeAnnotationOutputPendingController;
}): ReactElement | null {
	const interaction = useWorktreeAnnotationInteraction();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const membershipUnknown = projection.revision === null;
	const triggerRef = useRef<HTMLButtonElement | null>(null);
	const lastCloseReasonRef = useRef<string | null>(null);
	const isOpen = interaction.shareMode.kind === 'open';
	const closeShareMode = useCallback((): void => {
		lastCloseReasonRef.current = 'imperative-action';
		interaction.closeShareMode();
	}, [interaction]);
	if (selection.activeSessionId === null && !membershipUnknown) return null;
	return (
		<Drawer
			modal={false}
			onOpenChange={(nextOpen, eventDetails): void => {
				if (nextOpen) {
					if (!props.onOpenRequest()) {
						eventDetails.cancel();
						return;
					}
					lastCloseReasonRef.current = null;
					interaction.openShareMode();
					return;
				}
				if (
					props.outputPendingController.isPending &&
					lastCloseReasonRef.current !== 'imperative-action'
				) {
					eventDetails.cancel();
					return;
				}
				lastCloseReasonRef.current = eventDetails.reason;
				interaction.closeShareMode();
			}}
			open={isOpen}
			swipeDirection="right"
		>
			<WorktreeAnnotationShareTrigger
				buttonRef={triggerRef}
				disabled={!membershipUnknown && !selection.capabilities.canOutput}
				open={isOpen}
			/>
			<BridgeViewerContextPanel
				ariaLabel="Share comments"
				finalFocus={(): false | HTMLElement | null =>
					props.finalFocus({
						closeReason: lastCloseReasonRef.current,
						trigger: triggerRef.current,
					})
				}
				height="full"
				inert={!isOpen}
				testId="worktree-annotation-share-shelf"
			>
				<WorktreeAnnotationShareSurfaceContent
					outputPendingController={props.outputPendingController}
					onClose={closeShareMode}
				/>
			</BridgeViewerContextPanel>
		</Drawer>
	);
}

function WorktreeAnnotationShareSurfaceContent(props: {
	readonly onClose: () => void;
	readonly outputPendingController: WorktreeAnnotationOutputPendingController;
}): ReactElement | null {
	const client = useWorktreeAnnotationSurfaceClient();
	const interaction = useWorktreeAnnotationInteraction();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const viewedController = useWorktreeAnnotationViewedController();
	const [error, setError] = useState<string | null>(null);
	const displayedScopeRef = useRef<WorktreeAnnotationShareScope>('pending');
	if (interaction.shareMode.kind === 'open') {
		displayedScopeRef.current = interaction.shareMode.scope;
	}
	const displayedScope = displayedScopeRef.current;
	if (projection.revision === null) {
		return (
			<WorktreeAnnotationShareModeRow
				error={null}
				isOutputPending={props.outputPendingController.isPending}
				isOutputReady={false}
				membership={{ kind: 'unknown' }}
				history={null}
				onCopy={ignoreUnknownOutput}
				onDone={props.onClose}
				onExport={ignoreUnknownOutput}
				onScopeChange={interaction.setShareScope}
				scope={displayedScope}
			>
				<WorktreeAnnotationSharePreview inlineThreads={[]} otherThreads={[]} readiness="unknown" />
			</WorktreeAnnotationShareModeRow>
		);
	}
	if (selection.activeSessionId === null) return null;
	const session = projection.sessions.find(
		({ sessionId }) => sessionId === selection.activeSessionId,
	);
	if (session === undefined) return null;
	const shared = deriveWorktreeAnnotationShareProjection({
		scope: displayedScope,
		threads: projection.threads.filter((thread) =>
			thread.messages.some(({ sessionId }) => sessionId === session.sessionId),
		),
	});
	const sessionMessages = projection.threads
		.flatMap((thread) => thread.messages)
		.filter((message) => message.sessionId === session.sessionId);
	const isOutputReady =
		projection.readStatus.kind === 'ready' &&
		!projection.unreconciledCommandReceiptSessionIds.includes(session.sessionId) &&
		viewedController.isOutputReady(session.sessionId, session.semanticRevision, sessionMessages);
	const clearHandled = async (attemptId: string, sessionId: string): Promise<void> => {
		try {
			const outcome = await clearWorktreeAnnotationOutputHandled({
				attemptId,
				client,
				sessionId,
			});
			if (outcome.status.kind === 'failed') toast.error(outcome.status.code);
			else toast.success('Comments marked as not handled.');
		} catch (caught: unknown) {
			toast.error(caught instanceof Error ? caught.message : 'Comments could not be updated.');
		}
	};
	const executeOutput = async (
		outputKind: 'clipboardMarkdown' | 'jsonFile',
		scope: WorktreeAnnotationShareScope,
	): Promise<void> => {
		const pendingLease = props.outputPendingController.tryAcquire();
		if (pendingLease === null) return;
		setError(null);
		try {
			const outcome = await client.execute({
				displayedProjectionRevision: projection.revision ?? 0,
				expectedSessionRevision: session.semanticRevision,
				kind: 'output.scope.commit',
				outputKind,
				scope,
				sessionId: session.sessionId,
				sourceGeneration: projection.sourceGeneration,
			});
			if (outcome.status.kind === 'failed') throw new Error(outcome.status.code);
			if (outcome.status.kind !== 'output') throw new Error('Output returned no result.');
			const feedback = annotationOutputFeedback(outcome.status.outcome);
			if (feedback.toast !== null) {
				const attemptId =
					outcome.status.outcome.kind === 'succeeded'
						? outcome.status.outcome.summary.attemptId
						: null;
				toast.success(
					feedback.toast,
					attemptId === null
						? undefined
						: {
								action: {
									label: 'Mark as not handled',
									onClick: () => void clearHandled(attemptId, session.sessionId),
								},
							},
				);
			}
			if (feedback.toast === null && feedback.closeInteraction && feedback.message !== null) {
				if (feedback.severity === 'warning') toast.warning(feedback.message);
				else if (feedback.severity === 'error') toast.error(feedback.message);
				else toast(feedback.message);
			}
			if (feedback.closeInteraction) props.onClose();
			else setError(feedback.message);
			void client
				.execute({ kind: 'output.history', sessionId: session.sessionId })
				.catch((): void => {});
		} catch (caught: unknown) {
			setError(caught instanceof Error ? caught.message : 'Output failed.');
		} finally {
			pendingLease.release();
		}
	};
	return (
		<WorktreeAnnotationShareModeRow
			error={error}
			isOutputPending={props.outputPendingController.isPending}
			isOutputReady={isOutputReady}
			membership={{
				allCount: shared.allCount,
				kind: 'ready',
				pendingCount: shared.pendingCount,
			}}
			history={
				<WorktreeAnnotationOutputHistoryControl
					embedded
					outputPendingController={props.outputPendingController}
				/>
			}
			onCopy={(scope) => void executeOutput('clipboardMarkdown', scope)}
			onDone={props.onClose}
			onExport={(scope) => void executeOutput('jsonFile', scope)}
			onScopeChange={interaction.setShareScope}
			scope={displayedScope}
		>
			<WorktreeAnnotationSharePreview
				inlineThreads={shared.inlineThreads}
				otherThreads={shared.otherThreads}
				readiness={isOutputReady ? 'current' : 'unconfirmed'}
			/>
		</WorktreeAnnotationShareModeRow>
	);
}

function ignoreUnknownOutput(): undefined {
	return undefined;
}
