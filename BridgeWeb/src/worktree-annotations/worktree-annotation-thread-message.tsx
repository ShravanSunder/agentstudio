import { Pencil, RotateCcw, Save } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type ReactElement, type ReactNode } from 'react';

import { Textarea } from '@/components/ui/textarea.js';

import {
	browserWorktreeAnnotationDraftClock,
	WorktreeAnnotationDraftScheduler,
} from './worktree-annotation-draft-scheduler.js';
import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';
import {
	WorktreeAnnotationCommandButton,
	WorktreeAnnotationInlineSurface,
} from './worktree-annotation-inline-surface.js';
import { validateWorktreeAnnotationMarkdown } from './worktree-annotation-markdown-policy.js';
import { WorktreeAnnotationMessageBody } from './worktree-annotation-message-body.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationProjectionSnapshot,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationMessageEditorProps {
	readonly active: boolean;
	readonly canEdit: boolean;
	readonly commands: ReactNode;
	readonly isEditing: boolean;
	readonly message: WorktreeAnnotationMessageEntry;
	readonly onBeginEdit: () => void;
	readonly onFinishEdit: () => void;
	readonly ordinal: number;
	readonly path: string | null;
}

export interface WorktreeAnnotationThreadSummaryProps {
	readonly active: boolean;
	readonly commands: ReactNode;
	readonly hasDraft: boolean;
	readonly hasLockedMessage: boolean;
	readonly message: WorktreeAnnotationMessageEntry;
	readonly messageCount: number;
	readonly placement: 'exact' | 'outdated' | 'relocated' | 'unavailable';
	readonly resolution: 'open' | 'resolved';
}

export function WorktreeAnnotationThreadSummary(
	props: WorktreeAnnotationThreadSummaryProps,
): ReactElement {
	const latestBody = props.message.savedBody ?? props.message.draft?.body ?? '';
	return (
		<WorktreeAnnotationInlineSurface
			active={props.active}
			commands={props.commands}
			draft={props.message.draft !== null}
			metadata={
				<>
					<span className="font-medium text-comment-foreground">Latest · You</span>
					<span aria-hidden="true">·</span>
					<span>{annotationRelativeTime(props.message.createdAt)}</span>
					<span aria-hidden="true">·</span>
					<span>{props.resolution === 'open' ? 'Open' : 'Resolved'}</span>
					<span aria-hidden="true">·</span>
					<span>{props.messageCount} messages</span>
					{!props.hasDraft ? null : (
						<span className="inline-flex items-center gap-1 font-medium text-warning">
							<span aria-hidden="true" className="size-1.5 rounded-full bg-warning" />
							Draft
						</span>
					)}
					{props.hasLockedMessage ? <span>Contains locked output</span> : null}
					{props.placement === 'relocated' ? <span>Relocated</span> : null}
					{props.placement === 'outdated' ? <span>Outdated</span> : null}
					{props.placement === 'unavailable' ? <span>Source unavailable</span> : null}
				</>
			}
		>
			<p className="line-clamp-3 whitespace-pre-wrap text-xs/relaxed">
				{annotationPlainTextExcerpt(latestBody)}
			</p>
		</WorktreeAnnotationInlineSurface>
	);
}

export function WorktreeAnnotationMessageEditor(
	props: WorktreeAnnotationMessageEditorProps,
): ReactElement {
	const { canEdit, isEditing, onFinishEdit } = props;
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const initialBody = props.message.draft?.body ?? props.message.savedBody ?? '';
	const acknowledgedBody = props.message.draft?.body ?? props.message.savedBody;
	const [body, setBody] = useState(initialBody);
	const [operationError, setOperationError] = useState<string | null>(null);
	const editTokenRef = useRef(
		props.message.draft?.activeEditToken ?? createWorktreeAnnotationEditToken(),
	);
	const scheduler = useMemo(
		() =>
			new WorktreeAnnotationDraftScheduler({
				clock: browserWorktreeAnnotationDraftClock,
				initialAcknowledgedBody: acknowledgedBody,
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
		[acknowledgedBody, annotationClient, props.message.messageId],
	);
	useEffect((): (() => void) => (): void => scheduler.dispose(), [scheduler]);
	useEffect((): void => {
		if (!props.isEditing) setBody(props.message.draft?.body ?? props.message.savedBody ?? '');
	}, [props.isEditing, props.message.draft?.body, props.message.savedBody]);
	useEffect((): void => {
		if (!canEdit && isEditing) onFinishEdit();
	}, [canEdit, isEditing, onFinishEdit]);
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
			props.onFinishEdit();
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
			props.onFinishEdit();
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
			props.onFinishEdit();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	const messageCommands = props.isEditing ? (
		<>
			<WorktreeAnnotationCommandButton label="Revert draft" onClick={() => void revert()}>
				<RotateCcw />
			</WorktreeAnnotationCommandButton>
			<WorktreeAnnotationCommandButton
				disabled={!validation.ok}
				label="Save annotation"
				onClick={() => void save()}
				primary
			>
				<Save />
			</WorktreeAnnotationCommandButton>
		</>
	) : (
		<>
			{props.message.status === 'editable' ? (
				<WorktreeAnnotationCommandButton
					disabled={!props.canEdit}
					label={props.message.draft === null ? 'Edit annotation' : 'Resume draft'}
					onClick={props.onBeginEdit}
				>
					<Pencil />
				</WorktreeAnnotationCommandButton>
			) : null}
			{props.commands}
		</>
	);
	return (
		<WorktreeAnnotationInlineSurface
			active={props.active}
			commands={messageCommands}
			draft={props.message.draft !== null}
			metadata={
				<>
					<span className="font-medium text-comment-foreground">You</span>
					<span>{annotationMessageRoleLabel(props.ordinal)}</span>
					<span aria-hidden="true">·</span>
					<span>{annotationRelativeTime(props.message.createdAt)}</span>
					<span aria-hidden="true">·</span>
					{props.message.draft === null ? (
						<span>{annotationMessageStateLabel(props.message)}</span>
					) : (
						<span className="inline-flex items-center gap-1 font-medium text-warning">
							<span aria-hidden="true" className="size-1.5 rounded-full bg-warning" />
							{annotationMessageStateLabel(props.message)}
						</span>
					)}
				</>
			}
		>
			{props.isEditing && props.canEdit && props.message.status === 'editable' ? (
				<Textarea
					autoFocus
					aria-label="Annotation Markdown"
					className="min-h-16 rounded-none border-0 bg-comment-composer-bg p-0 shadow-none focus-visible:border-transparent focus-visible:ring-2 focus-visible:ring-ring/30"
					value={body}
					onBlur={(event) => {
						const surface = event.currentTarget.closest(
							'[data-testid="worktree-annotation-message"]',
						);
						if (
							event.relatedTarget instanceof Node &&
							surface?.contains(event.relatedTarget) === true
						) {
							return;
						}
						void scheduler
							.focusLost()
							.then(props.onFinishEdit)
							.catch((error: unknown) => setOperationError(annotationErrorMessage(error)));
					}}
					onChange={(event) => {
						const nextBody = event.currentTarget.value;
						setBody(nextBody);
						scheduler.edit(nextBody);
					}}
					onKeyDown={(event) => {
						if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
							event.preventDefault();
							void save();
						} else if (event.key === 'Escape') {
							event.preventDefault();
							void scheduler
								.focusLost()
								.then(props.onFinishEdit)
								.catch((error: unknown) => setOperationError(annotationErrorMessage(error)));
						}
					}}
				/>
			) : (
				<WorktreeAnnotationMessageBody
					body={props.message.draft?.body ?? props.message.savedBody ?? ''}
					messageId={props.message.messageId}
					messageRevision={props.message.messageRevision}
					path={props.path}
					sessionId={props.message.sessionId}
					sessionRevision={props.message.sessionRevision}
				/>
			)}
			{operationError === null ? null : (
				<p className="text-xs text-destructive" role="alert">
					{operationError}
				</p>
			)}
		</WorktreeAnnotationInlineSurface>
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

function annotationMessageRoleLabel(ordinal: number): string {
	return ordinal === 1 ? 'Root comment' : `Reply ${ordinal - 1}`;
}

function annotationPlainTextExcerpt(markdown: string): string {
	const plainText = markdown
		.replaceAll(/```[\s\S]*?```/g, ' code ')
		.replaceAll(/`([^`]*)`/g, '$1')
		.replaceAll(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
		.replaceAll(/\[([^\]]+)\]\([^)]*\)/g, '$1')
		.replaceAll(/^#{2,6}\s+/gm, '')
		.replaceAll(/[*_~>]/g, '')
		.replaceAll(/\s+/g, ' ')
		.trim();
	return plainText.length <= annotationSummaryCharacterLimit
		? plainText
		: `${plainText.slice(0, annotationSummaryCharacterLimit - 1).trimEnd()}…`;
}

function annotationRelativeTime(appleReferenceSeconds: number): string {
	const unixMilliseconds = (appleReferenceSeconds + appleReferenceDateUnixSeconds) * 1_000;
	const elapsedSeconds = Math.max(0, Math.floor((Date.now() - unixMilliseconds) / 1_000));
	if (elapsedSeconds < 60) return 'now';
	const elapsedMinutes = Math.floor(elapsedSeconds / 60);
	if (elapsedMinutes < 60) return `${elapsedMinutes}m`;
	const elapsedHours = Math.floor(elapsedMinutes / 60);
	if (elapsedHours < 24) return `${elapsedHours}h`;
	return `${Math.floor(elapsedHours / 24)}d`;
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

const annotationSummaryCharacterLimit = 180;
const appleReferenceDateUnixSeconds = 978_307_200;
