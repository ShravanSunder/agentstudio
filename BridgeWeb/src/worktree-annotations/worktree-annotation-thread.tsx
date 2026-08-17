import { Check, ChevronDown, ChevronUp, MapPin, Reply, RotateCcw, Save } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type ReactElement, type ReactNode } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { Collapsible, CollapsibleContent } from '@/components/ui/collapsible.js';
import { Textarea } from '@/components/ui/textarea.js';

import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import {
	WorktreeAnnotationAdmissionPopover,
	type WorktreeAnnotationAdmissionRequirement,
} from './worktree-annotation-admission-popover.js';
import {
	annotationErrorMessage,
	annotationMarkdownValidationMessage,
	assertCommittedAnnotationOutcome,
} from './worktree-annotation-command-result.js';
import { WorktreeAnnotationConversationFrame } from './worktree-annotation-conversation-frame.js';
import {
	browserWorktreeAnnotationDraftClock,
	WorktreeAnnotationDraftScheduler,
} from './worktree-annotation-draft-scheduler.js';
import { WorktreeAnnotationEditOwnershipController } from './worktree-annotation-edit-ownership.js';
import { createWorktreeAnnotationEditToken } from './worktree-annotation-edit-token.js';
import {
	WorktreeAnnotationCommandButton,
	WorktreeAnnotationDisclosureButton,
	WorktreeAnnotationInlineSurface,
} from './worktree-annotation-inline-surface.js';
import { validateWorktreeAnnotationMarkdown } from './worktree-annotation-markdown-policy.js';
import { WorktreeAnnotationOutputControls } from './worktree-annotation-output-controls.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationProjectionSnapshot,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveNewMessageEditTokens,
	useWorktreeAnnotationDeferredEditRelease,
	useWorktreeAnnotationEditSurfaceToken,
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';
import {
	WorktreeAnnotationMessageEditor,
	WorktreeAnnotationThreadSummary,
} from './worktree-annotation-thread-message.js';

export interface WorktreeAnnotationThreadProps {
	readonly onActivateRange?: (() => void) | undefined;
	readonly rangeActive?: boolean | undefined;
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
	const disclosureButtonRef = useRef<HTMLButtonElement | null>(null);
	const threadId = props.thread.context.threadId;
	const editor = interaction.editorForThread(threadId);
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
	const isExpanded =
		visibleMessages.length <= 1 || interaction.isThreadExpanded(threadId) || editor !== null;
	const activateRange = (): void => {
		interaction.activateThread(threadId);
		props.onActivateRange?.();
	};
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
	const latestMessage = visibleMessages.at(-1);
	if (latestMessage === undefined) return null;
	const threadCommands = (disclosure: 'collapse' | 'expand' | null): ReactNode => (
		<>
			{props.onActivateRange === undefined ? null : (
				<WorktreeAnnotationCommandButton
					label={`Show source range ${annotationThreadLocationLabel(props.thread)}`}
					onClick={activateRange}
				>
					<MapPin />
				</WorktreeAnnotationCommandButton>
			)}
			{disclosure === 'expand' || sessionId === null ? null : (
				<WorktreeAnnotationOutputControls
					activeSessionId={sessionId}
					compact
					disabled={!ownsActiveSession}
				/>
			)}
			<WorktreeAnnotationCommandButton
				disabled={!canReply}
				label="Reply to thread"
				onClick={() => interaction.startReply(threadId)}
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
			{disclosure === null ? null : (
				<WorktreeAnnotationDisclosureButton
					buttonRef={disclosureButtonRef}
					disabled={editor !== null}
					label={`${disclosure === 'expand' ? 'Expand' : 'Collapse'} ${visibleMessages.length} messages`}
				>
					{disclosure === 'expand' ? <ChevronDown /> : <ChevronUp />}
				</WorktreeAnnotationDisclosureButton>
			)}
		</>
	);
	return (
		<WorktreeAnnotationConversationFrame
			aria-label={`${annotationThreadLocationLabel(props.thread)} annotation thread`}
			data-annotation-placement={props.thread.context.placement}
			data-annotation-resolution={props.thread.context.resolution}
			data-testid="worktree-annotation-thread"
		>
			<Collapsible
				open={isExpanded}
				onOpenChange={(open) => {
					const disclosureHadFocus = document.activeElement === disclosureButtonRef.current;
					interaction.setThreadExpanded(threadId, open);
					if (disclosureHadFocus) {
						requestAnimationFrame((): void => disclosureButtonRef.current?.focus());
					}
				}}
			>
				{isExpanded ? (
					<CollapsibleContent className="space-y-2">
						{visibleMessages.map((message, visibleIndex) => {
							const messageOrdinal = props.thread.messages.findIndex(
								(candidate): boolean => candidate.messageId === message.messageId,
							);
							const isLatest = visibleIndex === visibleMessages.length - 1;
							return (
								<WorktreeAnnotationMessageEditor
									active={props.rangeActive === true && interaction.activeThreadId === threadId}
									canEdit={canEditMessages}
									commands={
										isLatest ? threadCommands(visibleMessages.length > 1 ? 'collapse' : null) : null
									}
									editToken={
										editor?.kind === 'message' && editor.messageId === message.messageId
											? editor.editToken
											: null
									}
									isEditing={editor?.kind === 'message' && editor.messageId === message.messageId}
									key={message.messageId}
									message={message}
									onBeginEdit={() => interaction.startMessageEdit(threadId, message.messageId)}
									onFinishEdit={() => interaction.clearEditor(threadId)}
									ordinal={messageOrdinal + 1}
									path={props.thread.context.path}
								/>
							);
						})}
					</CollapsibleContent>
				) : (
					<WorktreeAnnotationThreadSummary
						active={props.rangeActive === true && interaction.activeThreadId === threadId}
						commands={threadCommands('expand')}
						hasDraft={visibleMessages.some((message) => message.draft !== null)}
						hasLockedMessage={visibleMessages.some((message) => message.status === 'locked')}
						message={latestMessage}
						messageCount={visibleMessages.length}
						placement={props.thread.context.placement}
						resolution={props.thread.context.resolution}
					/>
				)}
			</Collapsible>
			{operationError === null ? null : (
				<Alert variant="destructive" className="mt-2 w-auto">
					<AlertDescription>{operationError}</AlertDescription>
				</Alert>
			)}
			{sessionId === null || editor?.kind !== 'reply' ? null : (
				<div className="mt-2">
					<WorktreeAnnotationNewMessageComposer
						active
						createOperation={(body, editToken) => ({
							body,
							editToken,
							expectedSessionRevision: sessionRevision,
							kind: 'reply.create',
							sessionId,
							threadId: props.thread.context.threadId,
						})}
						editToken={editor.editToken}
						onCancel={() => interaction.clearEditor(threadId)}
						onSaved={() => interaction.clearEditor(threadId)}
						placement="embedded"
						placeholder="Reply with Markdown"
					/>
				</div>
			)}
		</WorktreeAnnotationConversationFrame>
	);
}

export interface WorktreeAnnotationNewMessageComposerProps {
	readonly active?: boolean | undefined;
	readonly createOperation: (
		body: string,
		editToken: string,
		admission?: WorktreeAnnotationRootAdmission,
	) => BridgeProductWorktreeAnnotationOperation;
	readonly editToken?: string | undefined;
	readonly onCancel: () => void;
	readonly onSaved: () => void;
	readonly placement?: 'embedded' | 'standalone' | undefined;
	readonly placeholder: string;
}

type WorktreeAnnotationRootAdmission = Extract<
	BridgeProductWorktreeAnnotationOperation,
	{ readonly kind: 'root.create' }
>['admission'];

type WorktreeAnnotationAdmissionDecision =
	| { readonly kind: 'cancel' }
	| { readonly kind: 'continue'; readonly sessionId: string }
	| { readonly kind: 'newSession' };

export function WorktreeAnnotationNewMessageComposer(
	props: WorktreeAnnotationNewMessageComposerProps,
): ReactElement {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const editTokenRef = useRef(props.editToken ?? createWorktreeAnnotationEditToken());
	const initialDurableMessageRef = useRef(
		messageByEditToken(annotationClient.getSnapshot(), editTokenRef.current),
	);
	const initialDurableMessage = initialDurableMessageRef.current;
	const initialDurableBody = initialDurableMessage?.draft?.body ?? null;
	const [body, setBody] = useState(initialDurableBody ?? '');
	const [isDurable, setIsDurable] = useState(initialDurableMessage !== null);
	const [operationError, setOperationError] = useState<string | null>(null);
	const [pendingAdmission, setPendingAdmission] = useState<{
		readonly requirement: WorktreeAnnotationAdmissionRequirement;
		readonly resolve: (decision: WorktreeAnnotationAdmissionDecision) => void;
	} | null>(null);
	const admissionAnchorRef = useRef<HTMLDivElement | null>(null);
	const hasLocalEditSinceMountRef = useRef(false);
	const targetMessageIdRef = useRef<string | null>(initialDurableMessage?.messageId ?? null);
	useWorktreeAnnotationEditSurfaceToken(editTokenRef.current);
	const releaseWhenEditInactive = useWorktreeAnnotationDeferredEditRelease();
	const createOperationRef = useRef(props.createOperation);
	createOperationRef.current = props.createOperation;
	const scheduler = useMemo(
		() =>
			new WorktreeAnnotationDraftScheduler({
				clock: browserWorktreeAnnotationDraftClock,
				initialAcknowledgedBody: initialDurableBody,
				persist: async (nextBody): Promise<void> => {
					if (targetMessageIdRef.current === null) {
						let outcome = await annotationClient.execute(
							createOperationRef.current(nextBody, editTokenRef.current),
						);
						if (outcome.status.kind === 'admission_required') {
							const admissionRequirement = outcome.status;
							const decision = await new Promise<WorktreeAnnotationAdmissionDecision>(
								(resolve): void => {
									setPendingAdmission({ requirement: admissionRequirement, resolve });
								},
							);
							setPendingAdmission(null);
							if (decision.kind === 'cancel') return;
							if (
								decision.kind === 'continue' &&
								admissionRequirement.reason === 'uncertain_continuity_choice'
							) {
								const session = annotationClient
									.getSnapshot()
									.sessions.find((candidate) => candidate.sessionId === decision.sessionId);
								if (session === undefined) {
									throw new Error('The selected annotation session is unavailable.');
								}
								const continuityOutcome = await annotationClient.execute({
									decision: 'acceptCurrentSource',
									expectedSessionRevision: session.semanticRevision,
									kind: 'continuity.choose',
									sessionId: session.sessionId,
								});
								assertCommittedAnnotationOutcome(continuityOutcome);
							}
							const admission: WorktreeAnnotationRootAdmission =
								decision.kind === 'continue'
									? { kind: 'selected', sessionId: decision.sessionId }
									: { kind: 'newSession' };
							outcome = await annotationClient.execute(
								createOperationRef.current(nextBody, editTokenRef.current, admission),
							);
						}
						assertCommittedAnnotationOutcome(outcome);
						const createdMessage = await annotationClient.waitForSnapshot((snapshot) =>
							messageByEditToken(snapshot, editTokenRef.current),
						);
						targetMessageIdRef.current = createdMessage.messageId;
						setIsDurable(true);
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
						if (currentMessage.savedBody === null && nextBody.trim().length === 0) {
							return projectedMessage === null ? currentMessage : null;
						}
						return projectedMessage?.draft?.body === nextBody ? projectedMessage : null;
					});
				},
			}),
		[annotationClient, initialDurableBody],
	);
	useEffect(
		(): (() => void) => (): void => {
			void scheduler
				.teardown(async (): Promise<void> => {
					await releaseWhenEditInactive(editTokenRef.current, async (): Promise<void> => {
						const messageId = targetMessageIdRef.current;
						if (messageId === null) return;
						const editOwnership = new WorktreeAnnotationEditOwnershipController({
							annotationClient,
							editToken: editTokenRef.current,
							messageId,
						});
						await editOwnership.release();
					});
				})
				.catch((): void => {});
		},
		[annotationClient, releaseWhenEditInactive, scheduler],
	);
	const projectedDurableMessage = messageByEditToken(projection, editTokenRef.current);
	useEffect((): void => {
		const projectedDraft = projectedDurableMessage?.draft ?? null;
		if (projectedDurableMessage === null || projectedDraft === null) return;
		if (targetMessageIdRef.current === projectedDurableMessage.messageId && isDurable) return;
		targetMessageIdRef.current = projectedDurableMessage.messageId;
		scheduler.adoptAcknowledgedBody({
			body: projectedDraft.body,
			preserveCurrentBody: hasLocalEditSinceMountRef.current,
		});
		if (!hasLocalEditSinceMountRef.current) setBody(projectedDraft.body);
		setIsDurable(true);
	}, [isDurable, projectedDurableMessage, scheduler]);
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
	const revert = async (): Promise<void> => {
		setOperationError(null);
		const messageId = targetMessageIdRef.current;
		if (messageId === null) {
			props.onCancel();
			return;
		}
		const currentMessage = currentMessageById(annotationClient.getSnapshot(), messageId);
		if (currentMessage?.draft === null || currentMessage === null) {
			props.onCancel();
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
			props.onCancel();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
		}
	};
	return (
		<div ref={admissionAnchorRef}>
			<WorktreeAnnotationConversationFrame
				aria-label={`${props.placeholder} composer`}
				placement={props.placement}
			>
				<WorktreeAnnotationInlineSurface
					active={props.active}
					commands={
						<>
							<WorktreeAnnotationCommandButton
								label="Revert draft"
								onClick={() => void revert()}
								preserveEditorFocus
							>
								<RotateCcw />
							</WorktreeAnnotationCommandButton>
							<WorktreeAnnotationCommandButton
								disabled={!validation.ok}
								label="Save annotation"
								onClick={() => void save()}
								preserveEditorFocus
								primary
							>
								<Save />
							</WorktreeAnnotationCommandButton>
						</>
					}
					draft={isDurable}
					metadata={
						<>
							<span className="font-medium text-comment-foreground">You</span>
							<span aria-hidden="true">·</span>
							{isDurable ? (
								<>
									<span className="inline-flex items-center gap-1 font-medium text-warning">
										<span aria-hidden="true" className="size-1.5 rounded-full bg-warning" />
										Draft
									</span>
									<span aria-hidden="true">·</span>
									<span>saved locally</span>
								</>
							) : (
								<span>New comment</span>
							)}
						</>
					}
				>
					<div data-testid="worktree-annotation-new-message-composer">
						<Textarea
							autoFocus
							aria-label={props.placeholder}
							className="min-h-16 rounded-none border-0 bg-comment-composer-bg p-0 shadow-none focus-visible:border-transparent focus-visible:ring-2 focus-visible:ring-ring/30"
							placeholder={props.placeholder}
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
								if (body.trim().length === 0 && targetMessageIdRef.current === null) {
									props.onCancel();
									return;
								}
								void scheduler
									.focusLost()
									.then((): void => {
										if (body.trim().length === 0) props.onCancel();
									})
									.catch((error: unknown) => setOperationError(annotationErrorMessage(error)));
							}}
							onChange={(event) => {
								const nextBody = event.currentTarget.value;
								hasLocalEditSinceMountRef.current = true;
								setBody(nextBody);
								scheduler.edit(nextBody);
							}}
							onKeyDown={(event) => {
								if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
									event.preventDefault();
									void save();
								} else if (event.key === 'Escape') {
									event.preventDefault();
									if (body.trim().length === 0) props.onCancel();
									else {
										void scheduler
											.focusLost()
											.then(props.onCancel)
											.catch((error: unknown) => setOperationError(annotationErrorMessage(error)));
									}
								}
							}}
						/>
						{operationError === null ? null : (
							<p className="text-xs text-destructive" role="alert">
								{operationError}
							</p>
						)}
					</div>
				</WorktreeAnnotationInlineSurface>
			</WorktreeAnnotationConversationFrame>
			{pendingAdmission === null ? null : (
				<WorktreeAnnotationAdmissionPopover
					anchor={admissionAnchorRef}
					onContinue={(sessionId): void =>
						pendingAdmission.resolve({ kind: 'continue', sessionId })
					}
					onDismiss={(): void => {
						pendingAdmission.resolve({ kind: 'cancel' });
						props.onCancel();
					}}
					onLeavePaused={(): void => {
						pendingAdmission.resolve({ kind: 'cancel' });
						props.onCancel();
					}}
					onStartAnother={(): void => pendingAdmission.resolve({ kind: 'newSession' })}
					requirement={pendingAdmission.requirement}
					sessions={projection.sessions}
				/>
			)}
		</div>
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

function annotationThreadLocationLabel(thread: WorktreeAnnotationThreadProjection): string {
	const location =
		thread.context.startLine === null
			? (thread.context.path ?? 'Session')
			: `${thread.context.path ?? 'Source'}:${thread.context.startLine}-${thread.context.endLine ?? thread.context.startLine}`;
	return thread.context.placement === 'relocated' ? `${location} · relocated` : location;
}
