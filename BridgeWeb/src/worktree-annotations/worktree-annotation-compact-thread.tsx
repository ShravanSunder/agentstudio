import { Check, ChevronDown, Reply, RotateCcw } from 'lucide-react';
import {
	useState,
	type CSSProperties,
	type MouseEvent as ReactMouseEvent,
	type ReactElement,
	type ReactNode,
} from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { Collapsible, CollapsibleContent } from '@/components/ui/collapsible.js';

import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-composer.js';
import { WorktreeAnnotationConversationFrame } from './worktree-annotation-conversation-frame.js';
import { WorktreeAnnotationCommandButton } from './worktree-annotation-inline-surface.js';
import type { WorktreeAnnotationRange } from './worktree-annotation-interaction.js';
import { isPendingWorktreeAnnotationMessage } from './worktree-annotation-share-projection.js';
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

const annotationHistoryMaskStyle: CSSProperties = {
	WebkitMaskImage:
		'linear-gradient(to bottom, black 0%, black 45.45%, transparent 50%, transparent 100%)',
	WebkitMaskRepeat: 'no-repeat',
	WebkitMaskSize: '100% 220%',
	maskImage:
		'linear-gradient(to bottom, black 0%, black 45.45%, transparent 50%, transparent 100%)',
	maskRepeat: 'no-repeat',
	maskSize: '100% 220%',
	transitionDuration: 'var(--motion-fast)',
	transitionProperty: 'mask-position, -webkit-mask-position',
	transitionTimingFunction: 'ease-out',
};

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
	const threadRevision = firstMessage?.threadRevision ?? 0;
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
	const handleThreadClick = (event: ReactMouseEvent<HTMLElement>): void => {
		activateRange();
		if (!hasMultipleMessages || isExpanded) return;
		if (
			event.target instanceof Element &&
			event.target.closest('a, button, input, select, textarea, [role="button"]') !== null
		)
			return;
		if (window.getSelection()?.isCollapsed === false) return;
		event.stopPropagation();
		interaction.expandThread(threadId, event.currentTarget);
	};
	const setResolution = async (): Promise<void> => {
		if (!canSetThreadResolution) return;
		setOperationError(null);
		const outcome = await annotationClient.execute({
			expectedThreadRevision: threadRevision,
			kind: 'thread.resolution.set',
			resolution: props.thread.context.resolution === 'open' ? 'resolved' : 'open',
			sessionId,
			threadId,
		});
		if (outcome.status.kind === 'failed') setOperationError(outcome.status.code);
	};
	const hasDraft = visibleMessages.some((message) => message.draft !== null);
	const hasLockedMessage = visibleMessages.some((message) => message.status === 'locked');
	const pendingMessageCount = visibleMessages.filter(isPendingWorktreeAnnotationMessage).length;

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
	const expansionControl: ReactNode = !hasMultipleMessages ? null : (
		<WorktreeAnnotationCommandButton
			appearance="timeline"
			expanded={isExpanded}
			label={`${isExpanded ? 'Collapse' : 'Expand'} ${visibleMessages.length} messages`}
			onClick={(event) => {
				activateRange();
				if (isExpanded) void interaction.collapseThread();
				else interaction.expandThread(threadId, event.currentTarget);
			}}
		>
			<ChevronDown
				className={`transition-transform duration-[var(--motion-fast)] ease-out motion-reduce:transition-none ${
					isExpanded ? 'rotate-180' : ''
				}`}
			/>
		</WorktreeAnnotationCommandButton>
	);
	const timelineActions: ReactNode = (
		<>
			{latestMessage.status !== 'editable' || !canEditMessages ? null : (
				<WorktreeAnnotationCommandButton
					appearance="toolbar"
					label="Edit annotation"
					onClick={(event) => {
						activateRange();
						interaction.startMessageEdit(threadId, latestMessage.messageId, event.currentTarget);
					}}
				>
					<span aria-hidden="true">•••</span>
				</WorktreeAnnotationCommandButton>
			)}
		</>
	);
	const earlierMessages = visibleMessages.slice(0, -1);
	const renderMessage = (
		message: WorktreeAnnotationMessageEntry,
		continueTimeline: boolean,
		compact: boolean,
	): ReactNode => {
		const messageEditor =
			threadExpansion?.editor?.kind === 'message' &&
			threadExpansion.editor.messageId === message.messageId
				? threadExpansion.editor
				: null;
		return (
			<WorktreeAnnotationMessageEditor
				key={message.messageId}
				active={rangeActive}
				canEdit={canEditMessages}
				compact={compact}
				commands={messageCommands(message)}
				continueTimeline={continueTimeline}
				editToken={messageEditor?.editToken ?? null}
				isEditing={messageEditor !== null}
				message={message}
				onBeginEdit={(invoker) =>
					interaction.shareMode.kind === 'open'
						? activateRange()
						: interaction.startMessageEdit(threadId, message.messageId, invoker)
				}
				onFinishEdit={interaction.finishThreadEditor}
				ordinal={message.ordinal + 1}
				path={props.thread.context.path}
				registerExitHandler={interaction.registerThreadEditorExit}
				timelineActions={!hasMultipleMessages ? timelineActions : undefined}
			/>
		);
	};

	return (
		<WorktreeAnnotationConversationFrame
			active={rangeActive}
			aria-label={`${annotationThreadLocationLabel(props.thread)} annotation thread`}
			data-annotation-thread-id={threadId}
			data-annotation-placement={props.thread.context.placement}
			data-annotation-resolution={props.thread.context.resolution}
			data-annotation-expanded={isExpanded ? 'true' : 'false'}
			data-testid="worktree-annotation-thread"
			onClickCapture={handleThreadClick}
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
			<Collapsible open={isExpanded}>
				{hasMultipleMessages ? (
					<WorktreeAnnotationTimelineSummary
						expansionControl={expansionControl}
						hasDraft={hasDraft}
						hasLockedMessage={hasLockedMessage}
						latestMessage={latestMessage}
						messageCount={visibleMessages.length}
						pendingMessageCount={pendingMessageCount}
						placement={props.thread.context.placement}
						readStatus={projection.readStatus.kind}
						resolution={props.thread.context.resolution}
						timelineActions={timelineActions}
					/>
				) : null}
				<div className="grid" data-testid="worktree-annotation-thread-chronology">
					{!hasMultipleMessages ? null : (
						<CollapsibleContent
							className="group/annotation-history duration-[var(--motion-fast)] data-ending-style:duration-[var(--motion-fast)]"
							data-testid="worktree-annotation-thread-history"
						>
							<div
								className="grid gap-1 pb-1 [-webkit-mask-position:0_0] [mask-position:0_0] group-data-ending-style/annotation-history:[-webkit-mask-position:0_100%] group-data-ending-style/annotation-history:[mask-position:0_100%] group-data-starting-style/annotation-history:[-webkit-mask-position:0_100%] group-data-starting-style/annotation-history:[mask-position:0_100%] motion-reduce:transition-none"
								data-testid="worktree-annotation-thread-history-group"
								style={annotationHistoryMaskStyle}
							>
								{earlierMessages.map((message) => renderMessage(message, true, false))}
							</div>
						</CollapsibleContent>
					)}
					{renderMessage(
						latestMessage,
						threadExpansion?.editor?.kind === 'reply',
						!isExpanded && hasMultipleMessages,
					)}
					{threadExpansion?.editor?.kind !== 'reply' ? null : (
						<div className="mt-1">
							<WorktreeAnnotationNewMessageComposer
								active
								continueTimeline={false}
								createOperation={(body, editToken) => ({
									body,
									editToken,
									expectedThreadRevision: threadRevision,
									kind: 'reply.create',
									sessionId,
									threadId,
								})}
								editToken={threadExpansion.editor.editToken}
								onCancel={interaction.finishThreadEditor}
								onSaved={interaction.finishThreadEditor}
								placement="timeline"
								placeholder="Reply with Markdown"
								registerExitHandler={interaction.registerThreadEditorExit}
							/>
						</div>
					)}
				</div>
			</Collapsible>
			{operationError === null ? null : (
				<Alert variant="destructive" className="mt-2 w-auto">
					<AlertDescription>{operationError}</AlertDescription>
				</Alert>
			)}
		</WorktreeAnnotationConversationFrame>
	);
}

interface WorktreeAnnotationTimelineSummaryProps {
	readonly expansionControl: ReactNode;
	readonly hasDraft: boolean;
	readonly hasLockedMessage: boolean;
	readonly latestMessage: WorktreeAnnotationMessageEntry;
	readonly messageCount: number;
	readonly pendingMessageCount: number;
	readonly placement: 'exact' | 'outdated' | 'relocated' | 'unavailable';
	readonly readStatus: 'ready' | 'refreshing' | 'unavailable' | 'unknown';
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
			<div className="flex items-center justify-center">{props.expansionControl}</div>
			<div className="flex min-w-0 items-center gap-1.5 text-xs/relaxed text-comment-muted">
				<div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
					{props.pendingMessageCount === 0 ? null : (
						<span
							className="inline-flex items-center gap-1 font-medium text-warning"
							data-testid="worktree-annotation-pending-status"
						>
							<span aria-hidden="true" className="size-1.5 rounded-full bg-warning" />
							{props.pendingMessageCount} pending
						</span>
					)}
					{props.pendingMessageCount === 0 ? null : <span aria-hidden="true">·</span>}
					<span className="font-medium text-comment-foreground">{props.messageCount} messages</span>
					<span aria-hidden="true">·</span>
					<span>latest {annotationRelativeTime(props.latestMessage.createdAt)}</span>
					<span aria-hidden="true">·</span>
					<span>{props.resolution === 'open' ? 'Open' : 'Resolved'}</span>
					{!props.hasDraft ? null : <span className="font-medium text-warning">Draft</span>}
					{props.hasLockedMessage ? <span>Contains locked output</span> : null}
					{props.readStatus === 'unknown' ? <span>Membership unknown</span> : null}
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
