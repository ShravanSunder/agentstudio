import { useEffect, useMemo, useRef, useState, type ReactElement } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { Button } from '@/components/ui/button.js';
import { Textarea } from '@/components/ui/textarea.js';

import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import { WorktreeAnnotationConversationFrame } from './worktree-annotation-conversation-frame.js';
import {
	browserWorktreeAnnotationDraftClock,
	WorktreeAnnotationDraftScheduler,
} from './worktree-annotation-draft-scheduler.js';
import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';
import { validateWorktreeAnnotationMarkdown } from './worktree-annotation-markdown-policy.js';
import { WorktreeAnnotationMessageBody } from './worktree-annotation-message-body.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveComposerEditTokens,
	useWorktreeAnnotationComposerEditToken,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationThreadProps {
	readonly onActivateRange?: (() => void) | undefined;
	readonly thread: WorktreeAnnotationThreadProjection;
}

export function WorktreeAnnotationThread(
	props: WorktreeAnnotationThreadProps,
): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const sessionSelection = useWorktreeAnnotationSessionSelection();
	const activeComposerEditTokens = useWorktreeAnnotationActiveComposerEditTokens();
	const [isReplying, setIsReplying] = useState(false);
	const [operationError, setOperationError] = useState<string | null>(null);
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
			!activeComposerEditTokens.has(message.draft.activeEditToken),
	);
	const setResolution = async (): Promise<void> => {
		if (sessionId === null || !canSetThreadResolution) return;
		setOperationError(null);
		const outcome = await annotationClient.execute({
			expectedSessionRevision: sessionRevision,
			kind: 'thread.resolution.set',
			resolution: props.thread.context.resolution === 'open' ? 'resolved' : 'open',
			sessionId,
			threadId: props.thread.context.threadId,
		});
		if (outcome.status.kind === 'failed') setOperationError(outcome.status.code);
	};
	if (visibleMessages.length === 0) return null;
	return (
		<WorktreeAnnotationConversationFrame
			aria-label={annotationThreadAccessibleLabel(props.thread)}
			data-annotation-placement={props.thread.context.placement}
			data-annotation-resolution={props.thread.context.resolution}
			data-testid="worktree-annotation-thread"
		>
			<header className="flex items-center justify-between gap-2 px-3 py-1.5 text-[10px] text-[var(--bridge-annotation-muted)]">
				{props.onActivateRange === undefined ? (
					<span className="truncate">{annotationThreadLocationLabel(props.thread)}</span>
				) : (
					<Button
						aria-label={`Show source range ${annotationThreadLocationLabel(props.thread)}`}
						className="min-w-0 justify-start px-0 font-normal text-[var(--bridge-annotation-muted)]"
						size="xs"
						variant="ghost"
						onClick={props.onActivateRange}
					>
						<span className="truncate">{annotationThreadLocationLabel(props.thread)}</span>
					</Button>
				)}
				<Button
					disabled={!canSetThreadResolution}
					size="xs"
					variant="ghost"
					onClick={() => void setResolution()}
				>
					{props.thread.context.resolution === 'open' ? 'Resolve' : 'Reopen'}
				</Button>
			</header>
			<div className="divide-y divide-[var(--bridge-annotation-divider)]">
				{visibleMessages.map((message) => {
					const messageOrdinal = props.thread.messages.findIndex(
						(candidate): boolean => candidate.messageId === message.messageId,
					);
					return (
						<WorktreeAnnotationMessageEditor
							canEdit={canEditMessages}
							key={message.messageId}
							message={message}
							ordinal={messageOrdinal + 1}
							path={props.thread.context.path}
						/>
					);
				})}
			</div>
			{operationError === null ? null : (
				<Alert variant="destructive" className="m-2 w-auto">
					<AlertDescription>{operationError}</AlertDescription>
				</Alert>
			)}
			{sessionId === null ? null : isReplying ? (
				<div className="border-t border-[var(--bridge-annotation-divider)]">
					<WorktreeAnnotationNewMessageComposer
						createOperation={(body, editToken) => ({
							body,
							editToken,
							expectedSessionRevision: sessionRevision,
							kind: 'reply.create',
							sessionId,
							threadId: props.thread.context.threadId,
						})}
						onCancel={() => setIsReplying(false)}
						onSaved={() => setIsReplying(false)}
						placement="embedded"
						placeholder="Reply with Markdown"
					/>
				</div>
			) : (
				<div className="flex justify-end border-t border-[var(--bridge-annotation-divider)] px-3 py-1">
					<Button
						disabled={!canReply}
						size="xs"
						variant="ghost"
						onClick={() => setIsReplying(true)}
					>
						Reply
					</Button>
				</div>
			)}
		</WorktreeAnnotationConversationFrame>
	);
}

interface WorktreeAnnotationMessageEditorProps {
	readonly canEdit: boolean;
	readonly message: WorktreeAnnotationMessageEntry;
	readonly ordinal: number;
	readonly path: string | null;
}

function WorktreeAnnotationMessageEditor(
	props: WorktreeAnnotationMessageEditorProps,
): ReactElement {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const messageRef = useRef(props.message);
	messageRef.current = props.message;
	const initialBody = props.message.draft?.body ?? props.message.savedBody ?? '';
	const [body, setBody] = useState(initialBody);
	const [isEditing, setIsEditing] = useState(props.canEdit && props.message.savedBody === null);
	const [operationError, setOperationError] = useState<string | null>(null);
	const editTokenRef = useRef(
		props.message.draft?.activeEditToken ?? createWorktreeAnnotationEditToken(),
	);
	const scheduler = useMemo(
		() =>
			new WorktreeAnnotationDraftScheduler({
				clock: browserWorktreeAnnotationDraftClock,
				persist: async (nextBody): Promise<void> => {
					const currentMessage = currentMessageById(
						annotationClient.getSnapshot(),
						props.message.messageId,
					);
					if (currentMessage === null) throw new Error('Annotation message is unavailable.');
					const outcome = await annotationClient.execute({
						body: nextBody,
						editToken: editTokenRef.current,
						expectedDraftRevision: currentMessage.draft?.revision ?? null,
						expectedSessionRevision: currentMessage.sessionRevision,
						kind: 'draft.flush',
						messageId: currentMessage.messageId,
						sessionId: currentMessage.sessionId,
					});
					assertCommittedAnnotationOutcome(outcome);
					await annotationClient.waitForSnapshot((snapshot) => {
						const projectedMessage = currentMessageById(snapshot, currentMessage.messageId);
						return projectedMessage?.draft?.body === nextBody ? projectedMessage : null;
					});
				},
			}),
		[annotationClient, props.message.messageId],
	);
	useEffect((): (() => void) => (): void => scheduler.dispose(), [scheduler]);
	useEffect((): void => {
		if (!isEditing) setBody(props.message.draft?.body ?? props.message.savedBody ?? '');
	}, [isEditing, props.message.draft?.body, props.message.savedBody]);
	useEffect((): void => {
		if (!props.canEdit) setIsEditing(false);
	}, [props.canEdit]);
	const validation = validateWorktreeAnnotationMarkdown(body);
	const save = async (): Promise<void> => {
		if (!props.canEdit) return;
		setOperationError(null);
		try {
			if (!validation.ok) throw new Error(annotationMarkdownValidationMessage(validation.code));
			await scheduler.save(async (): Promise<void> => {
				const currentMessage = currentMessageById(
					annotationClient.getSnapshot(),
					props.message.messageId,
				);
				if (currentMessage?.draft === null || currentMessage === null) {
					throw new Error('No durable draft is available to save.');
				}
				const outcome = await annotationClient.execute({
					editToken: editTokenRef.current,
					expectedDraftRevision: currentMessage.draft.revision,
					expectedSessionRevision: currentMessage.sessionRevision,
					kind: 'draft.save',
					messageId: currentMessage.messageId,
					sessionId: currentMessage.sessionId,
				});
				assertCommittedAnnotationOutcome(outcome);
				await annotationClient.waitForSnapshot((snapshot) => {
					const savedMessage = currentMessageById(snapshot, currentMessage.messageId);
					return savedMessage?.draft === null && savedMessage.savedBody === body
						? savedMessage
						: null;
				});
			});
			setIsEditing(false);
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	const revert = async (): Promise<void> => {
		if (!props.canEdit) return;
		setOperationError(null);
		const currentMessage = currentMessageById(projection, props.message.messageId);
		if (currentMessage?.draft === null || currentMessage === null) {
			setBody(currentMessage?.savedBody ?? '');
			setIsEditing(false);
			return;
		}
		try {
			const outcome = await annotationClient.execute({
				editToken: editTokenRef.current,
				expectedDraftRevision: currentMessage.draft.revision,
				expectedSessionRevision: currentMessage.sessionRevision,
				kind: 'draft.revert',
				messageId: currentMessage.messageId,
				sessionId: currentMessage.sessionId,
			});
			assertCommittedAnnotationOutcome(outcome);
			setBody(currentMessage.savedBody ?? '');
			setIsEditing(false);
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	return (
		<article
			className="space-y-1.5 px-3 py-2"
			data-annotation-draft={props.message.draft === null ? 'absent' : 'present'}
		>
			<div className="flex items-center justify-between gap-2 text-[10px] text-[var(--bridge-annotation-muted)]">
				<span className="flex min-w-0 items-center gap-1.5">
					<span className="font-medium text-[var(--bridge-annotation-foreground)]">You</span>
					<span>{annotationMessageRoleLabel(props.ordinal)}</span>
					<span aria-hidden="true">·</span>
					<span>{annotationMessageStateLabel(props.message)}</span>
				</span>
				{!isEditing && props.message.status === 'editable' ? (
					<Button
						disabled={!props.canEdit}
						size="xs"
						variant="ghost"
						onClick={() => setIsEditing(true)}
					>
						Edit
					</Button>
				) : null}
			</div>
			{isEditing && props.canEdit && props.message.status === 'editable' ? (
				<>
					<Textarea
						aria-label="Annotation Markdown"
						value={body}
						onBlur={() =>
							void scheduler.focusLost().catch((error: unknown) => {
								setOperationError(annotationErrorMessage(error));
							})
						}
						onChange={(event) => {
							const nextBody = event.currentTarget.value;
							setBody(nextBody);
							scheduler.edit(nextBody);
						}}
					/>
					<div className="flex justify-end gap-1">
						<Button size="xs" variant="ghost" onClick={() => void revert()}>
							Revert
						</Button>
						<Button size="xs" disabled={!validation.ok} onClick={() => void save()}>
							Save
						</Button>
					</div>
				</>
			) : (
				<WorktreeAnnotationMessageBody
					body={props.message.savedBody ?? props.message.draft?.body ?? ''}
					messageId={props.message.messageId}
					messageRevision={props.message.messageRevision}
					path={props.path}
					sessionId={props.message.sessionId}
					sessionRevision={props.message.sessionRevision}
				/>
			)}
			{operationError === null ? null : (
				<p className="text-[10px] text-destructive" role="alert">
					{operationError}
				</p>
			)}
		</article>
	);
}

export interface WorktreeAnnotationNewMessageComposerProps {
	readonly createOperation: (
		body: string,
		editToken: string,
	) => BridgeProductWorktreeAnnotationOperation;
	readonly editToken?: string | undefined;
	readonly onCancel: () => void;
	readonly onSaved: () => void;
	readonly placement?: 'embedded' | 'standalone' | undefined;
	readonly placeholder: string;
}

export function WorktreeAnnotationNewMessageComposer(
	props: WorktreeAnnotationNewMessageComposerProps,
): ReactElement {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const [body, setBody] = useState('');
	const [operationError, setOperationError] = useState<string | null>(null);
	const targetMessageIdRef = useRef<string | null>(null);
	const editTokenRef = useRef(props.editToken ?? createWorktreeAnnotationEditToken());
	useWorktreeAnnotationComposerEditToken(editTokenRef.current);
	const createOperationRef = useRef(props.createOperation);
	createOperationRef.current = props.createOperation;
	const scheduler = useMemo(
		() =>
			new WorktreeAnnotationDraftScheduler({
				clock: browserWorktreeAnnotationDraftClock,
				persist: async (nextBody): Promise<void> => {
					if (targetMessageIdRef.current === null) {
						const outcome = await annotationClient.execute(
							createOperationRef.current(nextBody, editTokenRef.current),
						);
						assertCommittedAnnotationOutcome(outcome);
						const createdMessage = await annotationClient.waitForSnapshot((snapshot) =>
							messageByEditToken(snapshot, editTokenRef.current),
						);
						targetMessageIdRef.current = createdMessage.messageId;
						return;
					}
					const currentMessage = currentMessageById(
						annotationClient.getSnapshot(),
						targetMessageIdRef.current,
					);
					if (currentMessage === null) throw new Error('Created annotation is unavailable.');
					const outcome = await annotationClient.execute({
						body: nextBody,
						editToken: editTokenRef.current,
						expectedDraftRevision: currentMessage.draft?.revision ?? null,
						expectedSessionRevision: currentMessage.sessionRevision,
						kind: 'draft.flush',
						messageId: currentMessage.messageId,
						sessionId: currentMessage.sessionId,
					});
					assertCommittedAnnotationOutcome(outcome);
					await annotationClient.waitForSnapshot((snapshot) => {
						const projectedMessage = currentMessageById(snapshot, currentMessage.messageId);
						return projectedMessage?.draft?.body === nextBody ? projectedMessage : null;
					});
				},
			}),
		[annotationClient],
	);
	useEffect((): (() => void) => (): void => scheduler.dispose(), [scheduler]);
	const validation = validateWorktreeAnnotationMarkdown(body);
	const save = async (): Promise<void> => {
		setOperationError(null);
		try {
			if (!validation.ok) throw new Error(annotationMarkdownValidationMessage(validation.code));
			await scheduler.save(async (): Promise<void> => {
				const messageId = targetMessageIdRef.current;
				const currentMessage =
					messageId === null ? null : currentMessageById(annotationClient.getSnapshot(), messageId);
				if (currentMessage?.draft === null || currentMessage === null) {
					throw new Error('No durable draft is available to save.');
				}
				const outcome = await annotationClient.execute({
					editToken: editTokenRef.current,
					expectedDraftRevision: currentMessage.draft.revision,
					expectedSessionRevision: currentMessage.sessionRevision,
					kind: 'draft.save',
					messageId: currentMessage.messageId,
					sessionId: currentMessage.sessionId,
				});
				assertCommittedAnnotationOutcome(outcome);
			});
			props.onSaved();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	return (
		<WorktreeAnnotationConversationFrame
			aria-label={`${props.placeholder} composer`}
			placement={props.placement}
		>
			<div className="space-y-2 p-3" data-testid="worktree-annotation-new-message-composer">
				<Textarea
					autoFocus
					aria-label={props.placeholder}
					className="min-h-20"
					placeholder={props.placeholder}
					value={body}
					onBlur={() =>
						void scheduler.focusLost().catch((error: unknown) => {
							setOperationError(annotationErrorMessage(error));
						})
					}
					onChange={(event) => {
						const nextBody = event.currentTarget.value;
						setBody(nextBody);
						scheduler.edit(nextBody);
					}}
				/>
				{operationError === null ? null : (
					<p className="text-[10px] text-destructive" role="alert">
						{operationError}
					</p>
				)}
				<div className="flex justify-end gap-1.5">
					<Button size="xs" variant="ghost" onClick={props.onCancel}>
						Cancel
					</Button>
					<Button size="xs" disabled={!validation.ok} onClick={() => void save()}>
						Save
					</Button>
				</div>
			</div>
		</WorktreeAnnotationConversationFrame>
	);
}

function currentMessageById(
	snapshot: WorktreeAnnotationProjectionSnapshot,
	messageId: string,
): WorktreeAnnotationMessageEntry | null {
	for (const thread of snapshot.threads) {
		const message = thread.messages.find((candidate) => candidate.messageId === messageId);
		if (message !== undefined) return message;
	}
	return null;
}

function messageByEditToken(
	snapshot: WorktreeAnnotationProjectionSnapshot,
	editToken: string,
): WorktreeAnnotationMessageEntry | null {
	for (const thread of snapshot.threads) {
		const message = thread.messages.find(
			(candidate) => candidate.draft?.activeEditToken === editToken,
		);
		if (message !== undefined) return message;
	}
	return null;
}

function assertCommittedAnnotationOutcome(
	outcome: Awaited<ReturnType<ReturnType<typeof useWorktreeAnnotationSurfaceClient>['execute']>>,
): void {
	if (outcome.status.kind === 'failed') throw new Error(outcome.status.code);
}

function annotationMessageStateLabel(message: WorktreeAnnotationMessageEntry): string {
	if (message.status === 'locked') return 'Output locked';
	if (message.savedBody === null) return 'Draft';
	if (message.draft !== null) return 'Saved · draft changes';
	return 'Saved';
}

function annotationThreadLocationLabel(thread: WorktreeAnnotationThreadProjection): string {
	const location =
		thread.context.startLine === null
			? (thread.context.path ?? 'Session')
			: `${thread.context.path ?? 'Source'}:${thread.context.startLine}-${thread.context.endLine ?? thread.context.startLine}`;
	return thread.context.placement === 'relocated' ? `${location} · relocated` : location;
}

function annotationThreadAccessibleLabel(thread: WorktreeAnnotationThreadProjection): string {
	return `${annotationThreadLocationLabel(thread)} annotation thread`;
}

function annotationMessageRoleLabel(ordinal: number): string {
	return ordinal === 1 ? 'Root comment' : `Reply ${ordinal - 1}`;
}

function annotationErrorMessage(error: unknown): string {
	return error instanceof Error ? error.message : 'Annotation operation failed.';
}

function annotationMarkdownValidationMessage(
	code: 'bodyTooLarge' | 'emptyBody' | 'levelOneHeading' | 'rawHtml' | 'unsafeLinkDestination',
): string {
	const messages = {
		bodyTooLarge: 'Annotation Markdown must be 16 KiB or smaller.',
		emptyBody: 'Annotation Markdown cannot be empty.',
		levelOneHeading: 'Use H2-H6 headings; H1 is reserved for copied output.',
		rawHtml: 'Raw HTML is not allowed in annotation Markdown.',
		unsafeLinkDestination: 'Markdown links must use absolute HTTP(S) destinations.',
	} satisfies Readonly<Record<typeof code, string>>;
	return messages[code];
}
