import { useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import { bridgeViewerActionToolbarSurfaceClassName } from '../app/bridge-viewer-action-toolbar.js';
import { WorktreeAnnotationMessageBody } from './worktree-annotation-message-body.js';
import { clearWorktreeAnnotationOutputHandled } from './worktree-annotation-output-handled-clear.js';
import { WorktreeAnnotationOutputHistoryControl } from './worktree-annotation-output-history-control.js';
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
	if (selection.activeSessionId === null && !membershipUnknown) return null;
	return (
		<WorktreeAnnotationShareTrigger
			disabled={
				interaction.shareMode.kind === 'open' ||
				(!membershipUnknown && !selection.capabilities.canOutput)
			}
			onOpen={interaction.openShareMode}
		/>
	);
}

export function WorktreeAnnotationShareSurface(): ReactElement | null {
	const client = useWorktreeAnnotationSurfaceClient();
	const interaction = useWorktreeAnnotationInteraction();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const viewedController = useWorktreeAnnotationViewedController();
	const [error, setError] = useState<string | null>(null);
	const [isPending, setIsPending] = useState(false);
	if (interaction.shareMode.kind === 'closed') return null;
	if (projection.revision === null) {
		return (
			<WorktreeAnnotationShareModeRow
				error={null}
				isOutputPending={false}
				isOutputReady={false}
				membership={{ kind: 'unknown' }}
				onCopy={ignoreUnknownOutput}
				onDone={interaction.closeShareMode}
				onExport={ignoreUnknownOutput}
				onScopeChange={interaction.setShareScope}
				scope={interaction.shareMode.scope}
			/>
		);
	}
	if (selection.activeSessionId === null) return null;
	const session = projection.sessions.find(
		({ sessionId }) => sessionId === selection.activeSessionId,
	);
	if (session === undefined) return null;
	const shared = deriveWorktreeAnnotationShareProjection({
		scope: interaction.shareMode.scope,
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
		if (isPending) return;
		setIsPending(true);
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
			if (feedback.closeInteraction) interaction.closeShareMode();
			else setError(feedback.message);
			void client
				.execute({ kind: 'output.history', sessionId: session.sessionId })
				.catch((): void => {});
		} catch (caught: unknown) {
			setError(caught instanceof Error ? caught.message : 'Output failed.');
		} finally {
			setIsPending(false);
		}
	};
	return (
		<>
			<WorktreeAnnotationShareModeRow
				error={error}
				isOutputPending={isPending}
				isOutputReady={isOutputReady}
				membership={{ allCount: shared.allCount, kind: 'ready', pendingCount: shared.pendingCount }}
				onCopy={(scope) => void executeOutput('clipboardMarkdown', scope)}
				onDone={interaction.closeShareMode}
				onExport={(scope) => void executeOutput('jsonFile', scope)}
				onScopeChange={interaction.setShareScope}
				scope={interaction.shareMode.scope}
			/>
			<WorktreeAnnotationOtherSavedComments threads={shared.otherThreads} />
			<WorktreeAnnotationOutputHistoryControl />
		</>
	);
}

function ignoreUnknownOutput(): undefined {
	return undefined;
}

function WorktreeAnnotationOtherSavedComments(props: {
	readonly threads: ReturnType<typeof deriveWorktreeAnnotationShareProjection>['otherThreads'];
}): ReactElement | null {
	if (props.threads.length === 0) return null;
	return (
		<section
			aria-label="Other saved comments"
			className={bridgeViewerActionToolbarSurfaceClassName}
		>
			<p className="text-[11px] font-medium text-[var(--bridge-text-primary)]">
				Other saved comments
			</p>
			{props.threads.map((thread) => (
				<div
					className="mt-1 text-[11px] text-[var(--bridge-text-secondary)]"
					key={thread.context.threadId}
				>
					{thread.context.path}:{thread.context.startLine} · {thread.context.placement}
					{thread.messages.map((message) => (
						<div className="text-[var(--bridge-text-primary)]" key={message.messageId}>
							<WorktreeAnnotationMessageBody
								body={message.savedBody ?? ''}
								messageId={message.messageId}
								messageRevision={message.messageRevision}
								path={thread.context.path}
								sessionId={message.sessionId}
								sessionRevision={message.sessionRevision}
							/>
						</div>
					))}
				</div>
			))}
		</section>
	);
}
