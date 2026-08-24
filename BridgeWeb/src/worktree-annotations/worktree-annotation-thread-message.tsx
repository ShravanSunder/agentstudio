import { Check, Undo2 } from 'lucide-react';
import {
	useCallback,
	useEffect,
	useMemo,
	useRef,
	useState,
	type ReactElement,
	type MouseEvent as ReactMouseEvent,
	type ReactNode,
} from 'react';

import { Textarea } from '@/components/ui/textarea.js';

import {
	browserWorktreeAnnotationDraftClock,
	WorktreeAnnotationDraftScheduler,
} from './worktree-annotation-draft-scheduler.js';
import { WorktreeAnnotationEditOwnershipController } from './worktree-annotation-edit-ownership.js';
import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';
import {
	WorktreeAnnotationCommandButton,
	WorktreeAnnotationInlineSurface,
} from './worktree-annotation-inline-surface.js';
import { validateWorktreeAnnotationMarkdown } from './worktree-annotation-markdown-policy.js';
import { WorktreeAnnotationMessageBody } from './worktree-annotation-message-body.js';
import {
	messageCommandCursorFromOutcome,
	messageCommandCursorFromProjection,
	newestMessageCommandCursor,
} from './worktree-annotation-message-command-cursor.js';
import { isPendingWorktreeAnnotationMessage } from './worktree-annotation-share-projection.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationProjectionSnapshot,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationDeferredEditRelease,
	useWorktreeAnnotationEditSurfaceToken,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationMessageEditorProps {
	readonly active: boolean;
	readonly appearance?: 'card' | 'chronology' | undefined;
	readonly canEdit: boolean;
	readonly compact?: boolean | undefined;
	readonly commands: ReactNode;
	readonly continueTimeline?: boolean | undefined;
	readonly editToken: string | null;
	readonly isEditing: boolean;
	readonly message: WorktreeAnnotationMessageEntry;
	readonly onBeginEdit: (invoker: HTMLElement) => void;
	readonly onFinishEdit: () => void;
	readonly ordinal: number;
	readonly path: string | null;
	readonly registerExitHandler?: ((handler: () => Promise<void>) => () => void) | undefined;
	readonly timelineActions?: ReactNode | undefined;
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
	const commandCursorRef = useRef(messageCommandCursorFromProjection(props.message));
	commandCursorRef.current =
		newestMessageCommandCursor(
			commandCursorRef.current,
			messageCommandCursorFromProjection(props.message),
		) ?? commandCursorRef.current;
	const initialBody = props.message.draft?.body ?? props.message.savedBody ?? '';
	const acknowledgedBody = props.message.draft?.body ?? props.message.savedBody;
	const editingSeedRef = useRef({
		acknowledgedBody,
		persistFirstChangedEditImmediately: props.message.draft === null,
	});
	editingSeedRef.current = {
		acknowledgedBody,
		persistFirstChangedEditImmediately: props.message.draft === null,
	};
	const [body, setBody] = useState(initialBody);
	const [operationError, setOperationError] = useState<string | null>(null);
	const isPending = isPendingWorktreeAnnotationMessage(props.message);
	const inactiveEditTokenRef = useRef(createWorktreeAnnotationEditToken());
	const editToken = props.editToken ?? inactiveEditTokenRef.current;
	useWorktreeAnnotationEditSurfaceToken(props.isEditing ? editToken : null, 'message');
	const releaseWhenEditInactive = useWorktreeAnnotationDeferredEditRelease();
	const [editOwnershipReady, setEditOwnershipReady] = useState(props.message.draft === null);
	const editOwnershipController = useMemo(
		() =>
			new WorktreeAnnotationEditOwnershipController({
				annotationClient,
				editToken,
				messageId: props.message.messageId,
			}),
		[annotationClient, editToken, props.message.messageId],
	);
	const scheduler = useMemo(
		() =>
			new WorktreeAnnotationDraftScheduler({
				clock: browserWorktreeAnnotationDraftClock,
				persist: async (nextBody): Promise<void> => {
					const projectedMessage = currentMessageById(
						annotationClient.getSnapshot(),
						props.message.messageId,
					);
					const cursor = newestMessageCommandCursor(
						commandCursorRef.current,
						projectedMessage === null ? null : messageCommandCursorFromProjection(projectedMessage),
					);
					if (cursor === null) throw new Error('Annotation command cursor is unavailable.');
					const outcome = await annotationClient.execute({
						body: nextBody,
						editToken,
						expectedDraftRevision: cursor.draftRevision,
						expectedMessageRevision: cursor.messageRevision,
						kind: 'draft.flush',
						messageId: cursor.messageId,
						sessionId: cursor.sessionId,
					});
					assertCommittedAnnotationOutcome(outcome);
					commandCursorRef.current = messageCommandCursorFromOutcome(outcome);
				},
			}),
		[annotationClient, editToken, props.message.messageId],
	);
	useEffect((): (() => void) | undefined => {
		if (!props.isEditing) return undefined;
		let effectIsActive = true;
		scheduler.beginEditing(editingSeedRef.current);
		setEditOwnershipReady(false);
		void editOwnershipController
			.acquire()
			.then((): void => {
				if (effectIsActive) setEditOwnershipReady(true);
			})
			.catch((error: unknown): void => {
				if (effectIsActive) setOperationError(annotationErrorMessage(error));
			});
		return (): void => {
			effectIsActive = false;
			void scheduler
				.teardown(() => releaseWhenEditInactive(editToken, () => editOwnershipController.release()))
				.catch((): void => {});
		};
	}, [editOwnershipController, editToken, props.isEditing, releaseWhenEditInactive, scheduler]);
	useEffect((): void => {
		if (!props.isEditing) setBody(props.message.draft?.body ?? props.message.savedBody ?? '');
	}, [props.isEditing, props.message.draft?.body, props.message.savedBody]);
	useEffect((): void => {
		if (!canEdit && isEditing) onFinishEdit();
	}, [canEdit, isEditing, onFinishEdit]);
	const validation = validateWorktreeAnnotationMarkdown(body);
	const messageCanBeginEditing = props.canEdit && props.message.status === 'editable';
	const beginEditingFromBody = (event: ReactMouseEvent<HTMLDivElement>): void => {
		if (!messageCanBeginEditing || props.isEditing) return;
		if (
			event.target instanceof Element &&
			event.target.closest('a, button, input, select, textarea, [role="button"]') !== null
		)
			return;
		if (window.getSelection()?.isCollapsed === false) return;
		props.onBeginEdit(event.currentTarget);
	};
	const registerExitHandler = props.registerExitHandler;
	const flushAndFinish = useCallback(async (): Promise<void> => {
		try {
			await scheduler.focusLost();
			onFinishEdit();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
			throw error;
		}
	}, [onFinishEdit, scheduler]);
	useEffect((): (() => void) | undefined => {
		if (!isEditing || registerExitHandler === undefined) return undefined;
		return registerExitHandler(flushAndFinish);
	}, [flushAndFinish, isEditing, registerExitHandler]);
	const save = async (): Promise<void> => {
		if (!props.canEdit) return;
		setOperationError(null);
		try {
			if (!validation.ok) throw new Error(annotationMarkdownValidationMessage(validation.code));
			await scheduler.save(async (): Promise<void> => {
				const projectedMessage = currentMessageById(
					annotationClient.getSnapshot(),
					props.message.messageId,
				);
				const cursor = newestMessageCommandCursor(
					commandCursorRef.current,
					projectedMessage === null ? null : messageCommandCursorFromProjection(projectedMessage),
				);
				if (cursor === null) throw new Error('Annotation command cursor is unavailable.');
				if (cursor.draftRevision === null) {
					throw new Error('No durable draft is available to save.');
				}
				const outcome = await annotationClient.execute({
					editToken,
					expectedDraftRevision: cursor.draftRevision,
					expectedMessageRevision: cursor.messageRevision,
					kind: 'draft.save',
					messageId: cursor.messageId,
					sessionId: cursor.sessionId,
				});
				assertCommittedAnnotationOutcome(outcome);
				commandCursorRef.current = messageCommandCursorFromOutcome(outcome);
			});
			props.onFinishEdit();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	const revert = async (): Promise<void> => {
		if (!props.canEdit) return;
		setOperationError(null);
		const projectedMessage = currentMessageById(projection, props.message.messageId);
		const cursor = newestMessageCommandCursor(
			commandCursorRef.current,
			projectedMessage === null ? null : messageCommandCursorFromProjection(projectedMessage),
		);
		if (cursor === null) throw new Error('Annotation command cursor is unavailable.');
		if (cursor.draftRevision === null) {
			setBody(projectedMessage?.savedBody ?? props.message.savedBody ?? '');
			props.onFinishEdit();
			return;
		}
		try {
			const outcome = await annotationClient.execute({
				editToken,
				expectedDraftRevision: cursor.draftRevision,
				expectedMessageRevision: cursor.messageRevision,
				kind: 'draft.revert',
				messageId: cursor.messageId,
				sessionId: cursor.sessionId,
			});
			assertCommittedAnnotationOutcome(outcome);
			setBody(projectedMessage?.savedBody ?? props.message.savedBody ?? '');
			props.onFinishEdit();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	const messageCommands = props.isEditing ? (
		<>
			<WorktreeAnnotationCommandButton
				label="Revert draft"
				onClick={() => void revert()}
				preserveEditorFocus
			>
				<Undo2 />
			</WorktreeAnnotationCommandButton>
			<WorktreeAnnotationCommandButton
				disabled={!validation.ok || !editOwnershipReady}
				label="Save annotation"
				onClick={() => void save()}
				preserveEditorFocus
				appearance="primary"
			>
				<Check />
			</WorktreeAnnotationCommandButton>
		</>
	) : (
		props.commands
	);
	return (
		<WorktreeAnnotationInlineSurface
			active={props.active}
			appearance={props.appearance}
			commands={messageCommands}
			continueTimeline={props.continueTimeline}
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
					{!isPending ? null : (
						<>
							<span aria-hidden="true">·</span>
							<span
								className="inline-flex items-center gap-1 font-medium text-warning"
								data-testid="worktree-annotation-message-pending-status"
							>
								<span aria-hidden="true" className="size-1.5 rounded-full bg-warning" />
								Pending
							</span>
						</>
					)}
				</>
			}
			onKeyDownCapture={(event) => {
				if (
					!messageCanBeginEditing ||
					props.isEditing ||
					event.key !== 'Enter' ||
					event.target !== event.currentTarget ||
					event.altKey ||
					event.ctrlKey ||
					event.metaKey ||
					event.shiftKey
				)
					return;
				event.preventDefault();
				props.onBeginEdit(event.currentTarget);
			}}
			timelineActions={props.timelineActions}
		>
			{props.isEditing && props.canEdit && props.message.status === 'editable' ? (
				<Textarea
					appearance="embedded"
					autoFocus
					aria-label="Annotation Markdown"
					className="min-h-16"
					disabled={!editOwnershipReady}
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
				<div
					className={props.compact === true ? 'line-clamp-3' : undefined}
					onClick={beginEditingFromBody}
				>
					<WorktreeAnnotationMessageBody
						body={props.message.draft?.body ?? props.message.savedBody ?? ''}
						messageId={props.message.messageId}
						messageRevision={props.message.messageRevision}
						path={props.path}
						sessionId={props.message.sessionId}
						sessionRevision={props.message.sessionRevision}
					/>
				</div>
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
	if (outcome.status.kind !== 'committed') throw new Error('Annotation command did not commit.');
}

export function annotationMessageStateLabel(message: WorktreeAnnotationMessageEntry): string {
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

export function annotationRelativeTime(appleReferenceSeconds: number): string {
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
