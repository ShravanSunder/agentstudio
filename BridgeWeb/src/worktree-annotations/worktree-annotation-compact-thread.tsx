import { Check, CircleMinus, CirclePlus, Expand, Pencil, Reply, RotateCcw } from 'lucide-react';
import { useState, type ReactElement, type ReactNode } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { Separator } from '@/components/ui/separator.js';

import { WorktreeAnnotationConversationFrame } from './worktree-annotation-conversation-frame.js';
import {
	WorktreeAnnotationCommandButton,
	WorktreeAnnotationInlineSurface,
} from './worktree-annotation-inline-surface.js';
import type { WorktreeAnnotationRange } from './worktree-annotation-interaction.js';
import { WorktreeAnnotationMessageBody } from './worktree-annotation-message-body.js';
import { WorktreeAnnotationOutputControls } from './worktree-annotation-output-controls.js';
import { toggleWorktreeAnnotationOutputMessage } from './worktree-annotation-output-selection.js';
import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';
import {
	annotationMessageStateLabel,
	annotationRelativeTime,
} from './worktree-annotation-thread-message.js';

export interface WorktreeAnnotationThreadProps {
	readonly rangeIdentity?:
		| { readonly itemId: string; readonly range: WorktreeAnnotationRange }
		| undefined;
	readonly thread: WorktreeAnnotationThreadProjection;
}

export function WorktreeAnnotationThread(
	props: WorktreeAnnotationThreadProps,
): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const interaction = useWorktreeAnnotationInteraction();
	const sessionSelection = useWorktreeAnnotationSessionSelection();
	const activeNewMessageEditTokens = useWorktreeAnnotationActiveNewMessageEditTokens();
	const [operationError, setOperationError] = useState<string | null>(null);
	const threadId = props.thread.context.threadId;
	const firstMessage = props.thread.messages[0];
	const sessionRevision = firstMessage?.sessionRevision ?? 0;
	const sessionId = firstMessage?.sessionId ?? null;
	const ownsActiveSession = sessionId !== null && sessionId === sessionSelection.activeSessionId;
	const canEditMessages = ownsActiveSession && sessionSelection.capabilities.canEditMessages;
	const canReply = ownsActiveSession && sessionSelection.capabilities.canReply;
	const canSetThreadResolution =
		ownsActiveSession && sessionSelection.capabilities.canSetThreadResolution;
	const visibleMessages = props.thread.messages.filter(
		(message): boolean =>
			message.draft?.activeEditToken === null ||
			message.draft?.activeEditToken === undefined ||
			!activeNewMessageEditTokens.has(message.draft.activeEditToken),
	);
	const latestMessage = visibleMessages.at(-1);
	const rangeActive = interaction.activeThreadId === threadId;
	const activateRange = (): void => {
		if (props.rangeIdentity === undefined) return;
		interaction.activateSavedThread({ threadId, ...props.rangeIdentity });
	};
	const setResolution = async (): Promise<void> => {
		if (sessionId === null || !canSetThreadResolution) return;
		setOperationError(null);
		const outcome = await annotationClient.execute({
			expectedSessionRevision: sessionRevision,
			kind: 'thread.resolution.set',
			resolution: props.thread.context.resolution === 'open' ? 'resolved' : 'open',
			sessionId,
			threadId,
		});
		if (outcome.status.kind === 'failed') setOperationError(outcome.status.code);
	};
	if (visibleMessages.length === 0 || latestMessage === undefined) return null;
	const latestMessageIsIncluded =
		interaction.outputSelection.kind === 'explicit'
			? interaction.outputSelection.messageIds.has(latestMessage.messageId)
			: !interaction.outputSelection.excludedMessageIds.has(latestMessage.messageId);
	const canSelectLatestForOutput =
		sessionId !== null &&
		latestMessage.savedBody !== null &&
		latestMessage.draft === null &&
		latestMessage.status === 'editable' &&
		sessionSelection.capabilities.canOutput;
	const hasDraft = visibleMessages.some((message) => message.draft !== null);
	const hasLockedMessage = visibleMessages.some((message) => message.status === 'locked');
	const openOverlay = (invoker: HTMLElement): void => {
		activateRange();
		interaction.openThreadOverlay(threadId, invoker);
	};
	const threadCommands: ReactNode = (
		<>
			{latestMessage.status === 'editable' ? (
				<WorktreeAnnotationCommandButton
					disabled={!canEditMessages}
					label={latestMessage.draft === null ? 'Edit annotation' : 'Resume draft'}
					onClick={(event) => {
						activateRange();
						interaction.startMessageEdit(threadId, latestMessage.messageId, event.currentTarget);
					}}
				>
					<Pencil />
				</WorktreeAnnotationCommandButton>
			) : null}
			<WorktreeAnnotationCommandButton
				disabled={!canReply}
				label="Reply to thread"
				onClick={(event) => {
					activateRange();
					interaction.startReply(threadId, event.currentTarget);
				}}
			>
				<Reply />
			</WorktreeAnnotationCommandButton>
			<WorktreeAnnotationCommandButton
				disabled={!canSetThreadResolution}
				label={props.thread.context.resolution === 'open' ? 'Resolve thread' : 'Reopen thread'}
				onClick={() => void setResolution()}
			>
				{props.thread.context.resolution === 'open' ? <Check /> : <RotateCcw />}
			</WorktreeAnnotationCommandButton>
		</>
	);
	const timelineActions: ReactNode = (
		<>
			{canSelectLatestForOutput ? (
				<WorktreeAnnotationCommandButton
					label={latestMessageIsIncluded ? 'Exclude latest comment' : 'Include latest comment'}
					onClick={() =>
						interaction.setOutputSelection(
							toggleWorktreeAnnotationOutputMessage(
								interaction.outputSelection,
								latestMessage.messageId,
								!latestMessageIsIncluded,
							),
						)
					}
				>
					{latestMessageIsIncluded ? <CircleMinus /> : <CirclePlus />}
				</WorktreeAnnotationCommandButton>
			) : null}
			<WorktreeAnnotationCommandButton
				label={`Expand ${visibleMessages.length} ${visibleMessages.length === 1 ? 'message' : 'messages'}`}
				onClick={(event) => openOverlay(event.currentTarget)}
			>
				<Expand />
			</WorktreeAnnotationCommandButton>
			{sessionId === null ? null : (
				<WorktreeAnnotationOutputControls
					activeSessionId={sessionId}
					compact
					disabled={!ownsActiveSession}
					triggerLabel="More comment actions"
				/>
			)}
		</>
	);
	return (
		<WorktreeAnnotationConversationFrame
			aria-label={`${annotationThreadLocationLabel(props.thread)} annotation thread`}
			data-annotation-thread-id={threadId}
			data-annotation-placement={props.thread.context.placement}
			data-annotation-resolution={props.thread.context.resolution}
			data-testid="worktree-annotation-thread"
		>
			<WorktreeAnnotationInlineSurface
				active={rangeActive}
				commands={threadCommands}
				draft={latestMessage.draft !== null}
				metadata={
					<>
						<span className="font-medium text-comment-foreground">You</span>
						<span aria-hidden="true">·</span>
						<span>{annotationRelativeTime(latestMessage.createdAt)}</span>
						<span aria-hidden="true">·</span>
						<span>{annotationMessageStateLabel(latestMessage)}</span>
						<span aria-hidden="true">·</span>
						<span>{props.thread.context.resolution === 'open' ? 'Open' : 'Resolved'}</span>
						{!hasDraft || latestMessage.draft !== null ? null : <span>Draft</span>}
						{hasLockedMessage ? <span>Contains locked output</span> : null}
						{props.thread.context.placement === 'relocated' ? <span>Relocated</span> : null}
					</>
				}
				onBlurCapture={(event) => interaction.handleCommentBlur(event.relatedTarget)}
				onFocusCapture={activateRange}
				timelineActions={timelineActions}
			>
				{visibleMessages.length === 1 ? null : (
					<>
						<p
							className="text-xs text-comment-muted"
							data-testid="worktree-annotation-thread-summary"
						>
							{visibleMessages.length} messages · latest activity{' '}
							{annotationRelativeTime(latestMessage.createdAt)}
						</p>
						<Separator className="my-2 bg-comment-divider" />
					</>
				)}
				<div className={visibleMessages.length === 1 ? undefined : 'line-clamp-3'}>
					<WorktreeAnnotationMessageBody
						body={latestMessage.draft?.body ?? latestMessage.savedBody ?? ''}
						messageId={latestMessage.messageId}
						messageRevision={latestMessage.messageRevision}
						path={props.thread.context.path}
						sessionId={latestMessage.sessionId}
						sessionRevision={latestMessage.sessionRevision}
					/>
				</div>
			</WorktreeAnnotationInlineSurface>
			{operationError === null ? null : (
				<Alert variant="destructive" className="mt-2 w-auto">
					<AlertDescription>{operationError}</AlertDescription>
				</Alert>
			)}
		</WorktreeAnnotationConversationFrame>
	);
}

function annotationThreadLocationLabel(thread: WorktreeAnnotationThreadProjection): string {
	const location =
		thread.context.startLine === null
			? (thread.context.path ?? 'Session')
			: `${thread.context.path ?? 'Source'}:${thread.context.startLine}-${thread.context.endLine ?? thread.context.startLine}`;
	return thread.context.placement === 'relocated' ? `${location} · relocated` : location;
}
