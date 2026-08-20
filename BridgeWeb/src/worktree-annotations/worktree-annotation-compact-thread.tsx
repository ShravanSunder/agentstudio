import { Check, ChevronDown, ChevronUp, Reply, RotateCcw } from 'lucide-react';
import { useState, type FocusEvent, type ReactElement, type ReactNode } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';

import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-composer.js';
import { WorktreeAnnotationConversationFrame } from './worktree-annotation-conversation-frame.js';
import { WorktreeAnnotationCommandButton } from './worktree-annotation-inline-surface.js';
import type { WorktreeAnnotationRange } from './worktree-annotation-interaction.js';
import { WorktreeAnnotationOutputControls } from './worktree-annotation-output-controls.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionDemand,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';
import {
	annotationRelativeTime,
	WorktreeAnnotationMessageEditor,
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
	const projection = useWorktreeAnnotationProjection();
	const sessionSelection = useWorktreeAnnotationSessionSelection();
	const activeNewMessageEditTokens = useWorktreeAnnotationActiveNewMessageEditTokens();
	const [operationError, setOperationError] = useState<string | null>(null);
	const threadId = props.thread.context.threadId;
	const visibleMessages = props.thread.messages.filter(
		(message): boolean =>
			message.draft?.activeEditToken === null ||
			message.draft?.activeEditToken === undefined ||
			!activeNewMessageEditTokens.has(message.draft.activeEditToken),
	);
	const firstMessage = visibleMessages[0];
	const latestMessage = visibleMessages.at(-1);
	const sessionId = firstMessage?.sessionId ?? null;
	const sessionRevision = firstMessage?.sessionRevision ?? 0;
	useWorktreeAnnotationSessionDemand(sessionId);
	if (firstMessage === undefined || latestMessage === undefined || sessionId === null) return null;

	const ownsActiveSession = sessionId === sessionSelection.activeSessionId;
	const canEditMessages = ownsActiveSession && sessionSelection.capabilities.canEditMessages;
	const canReply = ownsActiveSession && sessionSelection.capabilities.canReply;
	const canSetThreadResolution =
		ownsActiveSession && sessionSelection.capabilities.canSetThreadResolution;
	const hasMultipleMessages = visibleMessages.length > 1;
	const threadExpansion =
		interaction.threadExpansion.kind === 'open' && interaction.threadExpansion.threadId === threadId
			? interaction.threadExpansion
			: null;
	const isExpanded = threadExpansion !== null;
	const rangeActive = interaction.activeThreadId === threadId;
	const activateRange = (): void => {
		if (props.rangeIdentity === undefined) return;
		interaction.activateSavedThread({ threadId, ...props.rangeIdentity });
	};
	const handleThreadBlur = (event: FocusEvent<HTMLElement>): void => {
		interaction.handleCommentBlur(event.relatedTarget);
	};
	const setResolution = async (): Promise<void> => {
		if (!canSetThreadResolution) return;
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
	const hasDraft = visibleMessages.some((message) => message.draft !== null);
	const hasLockedMessage = visibleMessages.some((message) => message.status === 'locked');

	const startReply = (invoker: HTMLElement): void => {
		activateRange();
		interaction.startReply(threadId, invoker);
	};
	const messageCommands = (message: WorktreeAnnotationMessageEntry): ReactNode => {
		const isLatest = message.messageId === latestMessage.messageId;
		return (
			<>
				<WorktreeAnnotationCommandButton
					disabled={!canReply}
					label="Reply to thread"
					onClick={(event) => startReply(event.currentTarget)}
				>
					<Reply />
				</WorktreeAnnotationCommandButton>
				{!isLatest ? null : (
					<WorktreeAnnotationCommandButton
						appearance="primary"
						disabled={!canSetThreadResolution}
						label={props.thread.context.resolution === 'open' ? 'Resolve thread' : 'Reopen thread'}
						onClick={() => void setResolution()}
					>
						{props.thread.context.resolution === 'open' ? <Check /> : <RotateCcw />}
					</WorktreeAnnotationCommandButton>
				)}
			</>
		);
	};
	const timelineActions: ReactNode = (
		<>
			{!hasMultipleMessages ? null : (
				<WorktreeAnnotationCommandButton
					appearance="toolbar"
					label={`${isExpanded ? 'Collapse' : 'Expand'} ${visibleMessages.length} messages`}
					onClick={(event) => {
						activateRange();
						if (isExpanded) void interaction.collapseThread();
						else interaction.expandThread(threadId, event.currentTarget);
					}}
				>
					{isExpanded ? <ChevronUp /> : <ChevronDown />}
				</WorktreeAnnotationCommandButton>
			)}
			<WorktreeAnnotationOutputControls
				activeSessionId={sessionId}
				compact
				compactButtonAppearance="toolbar"
				disabled={!ownsActiveSession}
				onEdit={
					latestMessage.status === 'editable' && canEditMessages
						? (invoker) => {
								activateRange();
								interaction.startMessageEdit(threadId, latestMessage.messageId, invoker);
							}
						: undefined
				}
				triggerLabel="More comment actions"
			/>
		</>
	);
	const renderedMessages = isExpanded ? visibleMessages : [latestMessage];

	return (
		<WorktreeAnnotationConversationFrame
			active={rangeActive}
			aria-label={`${annotationThreadLocationLabel(props.thread)} annotation thread`}
			data-annotation-thread-id={threadId}
			data-annotation-placement={props.thread.context.placement}
			data-annotation-resolution={props.thread.context.resolution}
			data-annotation-expanded={isExpanded ? 'true' : 'false'}
			data-testid="worktree-annotation-thread"
			onBlurCapture={handleThreadBlur}
			onClickCapture={activateRange}
			onFocusCapture={activateRange}
			onKeyDownCapture={(event) => {
				if (
					event.target instanceof Element &&
					event.target.closest('[data-worktree-annotation-preserve-expansion]') !== null
				)
					return;
				if (event.key !== 'Escape' || threadExpansion?.editor !== null) return;
				event.preventDefault();
				const focusTarget = interaction.resolveThreadFocus();
				void interaction.collapseThread().then((): void => focusTarget?.focus());
			}}
		>
			{hasMultipleMessages ? (
				<WorktreeAnnotationTimelineSummary
					expanded={isExpanded}
					hasDraft={hasDraft}
					hasLockedMessage={hasLockedMessage}
					latestMessage={latestMessage}
					messageCount={visibleMessages.length}
					placement={props.thread.context.placement}
					readStatus={projection.readStatus.kind}
					resolution={props.thread.context.resolution}
					timelineActions={timelineActions}
				/>
			) : null}
			<div className="grid gap-1" data-testid="worktree-annotation-thread-chronology">
				{renderedMessages.map((message) => {
					const messageEditor =
						threadExpansion?.editor?.kind === 'message' &&
						threadExpansion.editor.messageId === message.messageId
							? threadExpansion.editor
							: null;
					const isLastMessage = message.messageId === renderedMessages.at(-1)?.messageId;
					return (
						<WorktreeAnnotationMessageEditor
							key={message.messageId}
							active={rangeActive}
							canEdit={canEditMessages}
							compact={!isExpanded && hasMultipleMessages}
							commands={messageCommands(message)}
							continueTimeline={!isLastMessage || threadExpansion?.editor?.kind === 'reply'}
							editToken={messageEditor?.editToken ?? null}
							isEditing={messageEditor !== null}
							message={message}
							onBeginEdit={(invoker) =>
								interaction.startMessageEdit(threadId, message.messageId, invoker)
							}
							onFinishEdit={interaction.finishThreadEditor}
							ordinal={message.ordinal + 1}
							path={props.thread.context.path}
							registerExitHandler={interaction.registerThreadEditorExit}
							timelineActions={!hasMultipleMessages ? timelineActions : undefined}
						/>
					);
				})}
				{threadExpansion?.editor?.kind !== 'reply' ? null : (
					<WorktreeAnnotationNewMessageComposer
						active
						continueTimeline={false}
						createOperation={(body, editToken) => ({
							body,
							editToken,
							expectedSessionRevision: sessionRevision,
							kind: 'reply.create',
							sessionId,
							threadId,
						})}
						editToken={threadExpansion.editor.editToken}
						onCancel={interaction.finishThreadEditor}
						onSaved={interaction.finishThreadEditor}
						placeholder="Reply with Markdown"
						registerExitHandler={interaction.registerThreadEditorExit}
					/>
				)}
			</div>
			{operationError === null ? null : (
				<Alert variant="destructive" className="mt-2 w-auto">
					<AlertDescription>{operationError}</AlertDescription>
				</Alert>
			)}
		</WorktreeAnnotationConversationFrame>
	);
}

interface WorktreeAnnotationTimelineSummaryProps {
	readonly expanded: boolean;
	readonly hasDraft: boolean;
	readonly hasLockedMessage: boolean;
	readonly latestMessage: WorktreeAnnotationMessageEntry;
	readonly messageCount: number;
	readonly placement: 'exact' | 'outdated' | 'relocated' | 'unavailable';
	readonly readStatus: 'ready' | 'refreshing' | 'unavailable';
	readonly resolution: 'open' | 'resolved';
	readonly timelineActions: ReactNode;
}

function WorktreeAnnotationTimelineSummary(
	props: WorktreeAnnotationTimelineSummaryProps,
): ReactElement {
	return (
		<div
			className="grid min-w-0 grid-cols-[1.5rem_minmax(0,1fr)] gap-x-2"
			data-testid="worktree-annotation-thread-summary"
		>
			<div className="flex items-center justify-center" aria-hidden="true">
				{props.expanded ? null : (
					<span
						className="size-2 rounded-full bg-comment-active"
						data-testid="worktree-annotation-summary-node"
					/>
				)}
			</div>
			<div className="flex min-w-0 items-center gap-1.5 text-xs/relaxed text-comment-muted">
				<div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
					<span className="font-medium text-comment-foreground">{props.messageCount} messages</span>
					<span aria-hidden="true">·</span>
					<span>latest {annotationRelativeTime(props.latestMessage.createdAt)}</span>
					<span aria-hidden="true">·</span>
					<span>{props.resolution === 'open' ? 'Open' : 'Resolved'}</span>
					{!props.hasDraft ? null : <span className="font-medium text-warning">Draft</span>}
					{props.hasLockedMessage ? <span>Contains locked output</span> : null}
					{props.readStatus === 'refreshing' ? <span>Refreshing</span> : null}
					{props.readStatus === 'unavailable' ? <span>Updates unavailable</span> : null}
					{props.placement === 'relocated' ? <span>Relocated</span> : null}
					{props.placement === 'outdated' ? <span>Outdated</span> : null}
					{props.placement === 'unavailable' ? <span>Source unavailable</span> : null}
				</div>
				<div aria-label="Comment timeline actions" className="flex shrink-0 items-center gap-1">
					{props.timelineActions}
				</div>
			</div>
			<div className="flex justify-center" aria-hidden="true">
				<span className="h-full w-px bg-comment-border" />
			</div>
			<div />
		</div>
	);
}

function annotationThreadLocationLabel(thread: WorktreeAnnotationThreadProjection): string {
	const location =
		thread.context.startLine === null
			? (thread.context.path ?? 'Session')
			: `${thread.context.path ?? 'Source'}:${thread.context.startLine}-${thread.context.endLine ?? thread.context.startLine}`;
	return thread.context.placement === 'relocated' ? `${location} · relocated` : location;
}
