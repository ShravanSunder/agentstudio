import { Check, Reply, RotateCcw } from 'lucide-react';
import { useEffect, useState, type ReactElement } from 'react';

import {
	Popover,
	PopoverContent,
	PopoverDescription,
	PopoverHeader,
	PopoverTitle,
} from '@/components/ui/popover.js';
import { ScrollArea } from '@/components/ui/scroll-area.js';
import { Separator } from '@/components/ui/separator.js';

import { annotationErrorMessage } from './worktree-annotation-command-result.js';
import { WorktreeAnnotationCommandButton } from './worktree-annotation-inline-surface.js';
import {
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationMessageEditor } from './worktree-annotation-thread-message.js';
import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-thread.js';

export function WorktreeAnnotationThreadOverlayHost(): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const interaction = useWorktreeAnnotationInteraction();
	const projection = useWorktreeAnnotationProjection();
	const sessionSelection = useWorktreeAnnotationSessionSelection();
	const activeNewMessageEditTokens = useWorktreeAnnotationActiveNewMessageEditTokens();
	const [operationError, setOperationError] = useState<string | null>(null);
	const overlay = interaction.threadOverlay;
	const thread =
		overlay.kind === 'open'
			? (projection.threads.find(
					(candidate): boolean => candidate.context.threadId === overlay.threadId,
				) ?? null)
			: null;

	useEffect((): void => {
		if (overlay.kind === 'open' && thread === null) void interaction.closeOverlay();
	}, [interaction, overlay.kind, thread]);
	if (overlay.kind === 'closed' || thread === null) return null;

	const visibleMessages = thread.messages.filter(
		(message): boolean =>
			message.draft?.activeEditToken === null ||
			message.draft?.activeEditToken === undefined ||
			!activeNewMessageEditTokens.has(message.draft.activeEditToken),
	);
	const firstMessage = visibleMessages[0];
	if (firstMessage === undefined) return null;
	const sessionId = firstMessage.sessionId;
	const ownsActiveSession = sessionId === sessionSelection.activeSessionId;
	const canEdit = ownsActiveSession && sessionSelection.capabilities.canEditMessages;
	const canReply = ownsActiveSession && sessionSelection.capabilities.canReply;
	const canSetResolution =
		ownsActiveSession && sessionSelection.capabilities.canSetThreadResolution;
	const setResolution = async (): Promise<void> => {
		if (!canSetResolution) return;
		setOperationError(null);
		try {
			const outcome = await annotationClient.execute({
				expectedSessionRevision: firstMessage.sessionRevision,
				kind: 'thread.resolution.set',
				resolution: thread.context.resolution === 'open' ? 'resolved' : 'open',
				sessionId,
				threadId: thread.context.threadId,
			});
			if (outcome.status.kind === 'failed') throw new Error(outcome.status.code);
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	return (
		<Popover
			modal={false}
			onOpenChange={(isOpen, eventDetails): void => {
				if (isOpen) return;
				if (overlay.editor !== null && eventDetails.reason === 'escape-key') {
					void interaction.exitOverlayEditor();
					return;
				}
				void interaction.closeOverlay();
			}}
			open
		>
			<PopoverContent
				align="end"
				anchor={overlay.invoker}
				className="w-96 max-w-full gap-2"
				data-testid="worktree-annotation-thread-overlay"
				finalFocus={interaction.resolveOverlayFinalFocus}
				onBlurCapture={(event) => interaction.handleCommentBlur(event.relatedTarget)}
				side="bottom"
			>
				<PopoverHeader className="flex-row items-start justify-between gap-2">
					<div className="min-w-0">
						<PopoverTitle>Comment thread</PopoverTitle>
						<PopoverDescription>
							{visibleMessages.length} {visibleMessages.length === 1 ? 'message' : 'messages'} ·{' '}
							{thread.context.resolution === 'open' ? 'Open' : 'Resolved'}
						</PopoverDescription>
					</div>
					<WorktreeAnnotationCommandButton
						disabled={!canSetResolution}
						label={thread.context.resolution === 'open' ? 'Resolve thread' : 'Reopen thread'}
						onClick={() => void setResolution()}
					>
						{thread.context.resolution === 'open' ? <Check /> : <RotateCcw />}
					</WorktreeAnnotationCommandButton>
				</PopoverHeader>
				<Separator className="bg-comment-divider" />
				<ScrollArea className="max-h-80" data-testid="worktree-annotation-thread-chronology">
					<div className="space-y-2 pr-1">
						{visibleMessages.map((message, messageIndex) => {
							const messageEditor =
								overlay.editor?.kind === 'message' && overlay.editor.messageId === message.messageId
									? overlay.editor
									: null;
							return (
								<WorktreeAnnotationMessageEditor
									active
									canEdit={canEdit}
									commands={
										<WorktreeAnnotationCommandButton
											disabled={!canReply}
											label="Reply to thread"
											onClick={(event) =>
												interaction.startReply(thread.context.threadId, event.currentTarget)
											}
										>
											<Reply />
										</WorktreeAnnotationCommandButton>
									}
									editToken={messageEditor?.editToken ?? null}
									isEditing={messageEditor !== null}
									key={message.messageId}
									message={message}
									onBeginEdit={(invoker) =>
										interaction.startMessageEdit(
											thread.context.threadId,
											message.messageId,
											invoker,
										)
									}
									onFinishEdit={interaction.finishOverlayEditor}
									ordinal={messageIndex + 1}
									path={thread.context.path}
									registerExitHandler={interaction.registerOverlayEditorExit}
								/>
							);
						})}
					</div>
				</ScrollArea>
				{overlay.editor?.kind !== 'reply' ? null : (
					<WorktreeAnnotationNewMessageComposer
						active
						createOperation={(body, editToken) => ({
							body,
							editToken,
							expectedSessionRevision: firstMessage.sessionRevision,
							kind: 'reply.create',
							sessionId,
							threadId: thread.context.threadId,
						})}
						editToken={overlay.editor.editToken}
						onCancel={interaction.finishOverlayEditor}
						onSaved={interaction.finishOverlayEditor}
						placement="embedded"
						placeholder="Reply with Markdown"
						registerExitHandler={interaction.registerOverlayEditorExit}
					/>
				)}
				{operationError === null ? null : (
					<p className="text-xs text-destructive" role="alert">
						{operationError}
					</p>
				)}
			</PopoverContent>
		</Popover>
	);
}
