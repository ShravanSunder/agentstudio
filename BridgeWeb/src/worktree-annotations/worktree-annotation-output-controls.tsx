import { useCallback, useRef, useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import { Popover } from '@/components/ui/popover.js';

import { BridgeViewerHeaderShelf } from '../app/bridge-viewer-header-shelf.js';
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
import { deriveWorktreeAnnotationShareProjection } from './worktree-annotation-share-projection.js';
import {
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
	useWorktreeAnnotationViewedController,
} from './worktree-annotation-surface-provider.js';

export function WorktreeAnnotationShareHeaderControl(): ReactElement | null {
	const interaction = useWorktreeAnnotationInteraction();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const membershipUnknown = projection.revision === null;
	const triggerRef = useRef<HTMLButtonElement | null>(null);
	const lastCloseReasonRef = useRef<string | null>(null);
	const outputPendingController = useWorktreeAnnotationOutputPendingController();
	const isOpen = interaction.shareMode.kind === 'open';
	const headerAnchor = useCallback(
		(): Element | null =>
			triggerRef.current?.closest('[data-bridge-viewer-content-topbar="true"]') ??
			triggerRef.current,
		[],
	);
	const closeShareMode = useCallback((): void => {
		lastCloseReasonRef.current = 'imperative-action';
		interaction.closeShareMode();
	}, [interaction]);
	if (selection.activeSessionId === null && !membershipUnknown) return null;
	return (
		<Popover
			modal={false}
			onOpenChange={(nextOpen, eventDetails): void => {
				if (nextOpen) {
					lastCloseReasonRef.current = null;
					interaction.openShareMode();
					return;
				}
				if (
					outputPendingController.isPending &&
					lastCloseReasonRef.current !== 'imperative-action'
				) {
					eventDetails.cancel();
					return;
				}
				lastCloseReasonRef.current = eventDetails.reason;
				interaction.closeShareMode();
			}}
			open={isOpen}
		>
			<WorktreeAnnotationShareTrigger
				buttonRef={triggerRef}
				disabled={!membershipUnknown && !selection.capabilities.canOutput}
				open={isOpen}
			/>
			<BridgeViewerHeaderShelf
				anchor={headerAnchor}
				ariaLabel="Share comments"
				finalFocus={(): false | HTMLElement | null =>
					lastCloseReasonRef.current === 'outside-press' ? false : triggerRef.current
				}
				testId="worktree-annotation-share-shelf"
			>
				<WorktreeAnnotationShareSurfaceContent
					outputPendingController={outputPendingController}
					onClose={closeShareMode}
				/>
			</BridgeViewerHeaderShelf>
		</Popover>
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
				onCopy={ignoreUnknownOutput}
				onDone={props.onClose}
				onExport={ignoreUnknownOutput}
				onScopeChange={interaction.setShareScope}
				scope={displayedScope}
			/>
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
		<>
			<WorktreeAnnotationShareModeRow
				error={error}
				isOutputPending={props.outputPendingController.isPending}
				isOutputReady={isOutputReady}
				membership={{ allCount: shared.allCount, kind: 'ready', pendingCount: shared.pendingCount }}
				onCopy={(scope) => void executeOutput('clipboardMarkdown', scope)}
				onDone={props.onClose}
				onExport={(scope) => void executeOutput('jsonFile', scope)}
				onScopeChange={interaction.setShareScope}
				scope={displayedScope}
			/>
			<WorktreeAnnotationOutputHistoryControl
				embedded
				outputPendingController={props.outputPendingController}
			/>
		</>
	);
}

function ignoreUnknownOutput(): undefined {
	return undefined;
}
