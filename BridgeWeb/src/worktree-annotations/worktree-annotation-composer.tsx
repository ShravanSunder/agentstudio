import { Check, LoaderCircle, Undo2 } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type ReactElement } from 'react';

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
	WorktreeAnnotationInlineSurface,
} from './worktree-annotation-inline-surface.js';
import { validateWorktreeAnnotationMarkdown } from './worktree-annotation-markdown-policy.js';
import {
	messageCommandCursorFromOutcome,
	messageCommandCursorFromProjection,
	newestMessageCommandCursor,
	type WorktreeAnnotationMessageCommandCursor,
} from './worktree-annotation-message-command-cursor.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationProjectionSnapshot,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationDeferredEditRelease,
	useWorktreeAnnotationEditSurfaceToken,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionDemand,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationNewMessageComposerProps {
	readonly active?: boolean | undefined;
	readonly createOperation: (
		body: string,
		editToken: string,
		admission?: WorktreeAnnotationRootAdmission,
	) => BridgeProductWorktreeAnnotationOperation;
	readonly continueTimeline?: boolean | undefined;
	readonly editToken?: string | undefined;
	readonly onCancel: () => void;
	readonly onSaved: () => void;
	readonly placement?: 'embedded' | 'standalone' | undefined;
	readonly placeholder: string;
	readonly registerExitHandler?: ((handler: () => Promise<void>) => () => void) | undefined;
}

type WorktreeAnnotationRootAdmission = Extract<
	BridgeProductWorktreeAnnotationOperation,
	{ readonly kind: 'root.create' }
>['admission'];

type WorktreeAnnotationAdmissionDecision =
	| { readonly kind: 'cancel' }
	| { readonly kind: 'continue'; readonly sessionId: string }
	| { readonly kind: 'newSession' };

type WorktreeAnnotationSavePhase = 'idle' | 'saving';

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
	const [savePhase, setSavePhase] = useState<WorktreeAnnotationSavePhase>('idle');
	const [committedCursor, setCommittedCursor] =
		useState<WorktreeAnnotationMessageCommandCursor | null>(null);
	const [demandedSessionId, setDemandedSessionId] = useState<string | null>(
		initialDurableMessage?.sessionId ?? null,
	);
	const [pendingAdmission, setPendingAdmission] = useState<{
		readonly requirement: WorktreeAnnotationAdmissionRequirement;
		readonly resolve: (decision: WorktreeAnnotationAdmissionDecision) => void;
	} | null>(null);
	const admissionAnchorRef = useRef<HTMLDivElement | null>(null);
	const hasLocalEditSinceMountRef = useRef(false);
	const targetMessageIdRef = useRef<string | null>(initialDurableMessage?.messageId ?? null);
	const targetMessageCursorRef = useRef<WorktreeAnnotationMessageCommandCursor | null>(
		initialDurableMessage === null
			? null
			: messageCommandCursorFromProjection(initialDurableMessage),
	);
	useWorktreeAnnotationEditSurfaceToken(committedCursor === null ? editTokenRef.current : null);
	useWorktreeAnnotationSessionDemand(demandedSessionId);
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
						if (outcome.sessionId === null) {
							throw new Error('Committed annotation draft did not identify its session.');
						}
						const cursor = messageCommandCursorFromOutcome(outcome);
						if (cursor.draftRevision === null) {
							throw new Error('Committed annotation draft did not identify its draft revision.');
						}
						setDemandedSessionId(outcome.sessionId);
						targetMessageIdRef.current = cursor.messageId;
						targetMessageCursorRef.current = cursor;
						setIsDurable(true);
						return;
					}
					const projectedMessage = currentMessageById(
						annotationClient.getSnapshot(),
						targetMessageIdRef.current,
					);
					const cursor = newestMessageCommandCursor(
						targetMessageCursorRef.current,
						projectedMessage === null ? null : messageCommandCursorFromProjection(projectedMessage),
					);
					if (cursor === null) throw new Error('Created annotation command cursor is unavailable.');
					const outcome = await annotationClient.execute({
						body: nextBody,
						editToken: editTokenRef.current,
						expectedDraftRevision: cursor.draftRevision,
						expectedMessageRevision: cursor.messageRevision,
						kind: 'draft.flush',
						messageId: cursor.messageId,
						sessionId: cursor.sessionId,
					});
					assertCommittedAnnotationOutcome(outcome);
					if (nextBody.trim().length === 0 && cursor.savedRevision === null) {
						targetMessageCursorRef.current = null;
						targetMessageIdRef.current = null;
						return;
					}
					targetMessageCursorRef.current = messageCommandCursorFromOutcome(outcome);
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
		targetMessageCursorRef.current = newestMessageCommandCursor(
			targetMessageCursorRef.current,
			messageCommandCursorFromProjection(projectedDurableMessage),
		);
		if (targetMessageIdRef.current === projectedDurableMessage.messageId && isDurable) return;
		targetMessageIdRef.current = projectedDurableMessage.messageId;
		setDemandedSessionId(projectedDurableMessage.sessionId);
		scheduler.adoptAcknowledgedBody({
			body: projectedDraft.body,
			preserveCurrentBody: hasLocalEditSinceMountRef.current,
		});
		if (!hasLocalEditSinceMountRef.current) setBody(projectedDraft.body);
		setIsDurable(true);
	}, [isDurable, projectedDurableMessage, scheduler]);
	const projectedCommittedMessage =
		committedCursor === null ? null : currentMessageById(projection, committedCursor.messageId);
	useEffect((): void => {
		if (
			committedCursor === null ||
			projectedCommittedMessage === null ||
			projectedCommittedMessage.savedRevision === null ||
			projectedCommittedMessage.savedRevision < (committedCursor.savedRevision ?? 0)
		) {
			return;
		}
		props.onSaved();
	}, [committedCursor, projectedCommittedMessage, props]);
	const validation = validateWorktreeAnnotationMarkdown(body);
	const onCancel = props.onCancel;
	const registerExitHandler = props.registerExitHandler;
	const flushAndExit = useCallback(async (): Promise<void> => {
		if (body.trim().length === 0 && targetMessageIdRef.current === null) {
			onCancel();
			return;
		}
		try {
			await scheduler.focusLost();
			onCancel();
		} catch (error: unknown) {
			setOperationError(annotationErrorMessage(error));
			throw error;
		}
	}, [body, onCancel, scheduler]);
	useEffect((): (() => void) | undefined => {
		if (committedCursor !== null || registerExitHandler === undefined) return undefined;
		return registerExitHandler(flushAndExit);
	}, [committedCursor, flushAndExit, registerExitHandler]);
	const save = async (): Promise<void> => {
		if (savePhase !== 'idle') return;
		setOperationError(null);
		setSavePhase('saving');
		try {
			if (!validation.ok) throw new Error(annotationMarkdownValidationMessage(validation.code));
			await scheduler.save(async (): Promise<void> => {
				const messageId = targetMessageIdRef.current;
				const projectedMessage =
					messageId === null ? null : currentMessageById(annotationClient.getSnapshot(), messageId);
				const cursor = newestMessageCommandCursor(
					targetMessageCursorRef.current,
					projectedMessage === null ? null : messageCommandCursorFromProjection(projectedMessage),
				);
				if (cursor === null || cursor.draftRevision === null) {
					throw new Error('No durable draft is available to save.');
				}
				const outcome = await annotationClient.execute({
					editToken: editTokenRef.current,
					expectedDraftRevision: cursor.draftRevision,
					expectedMessageRevision: cursor.messageRevision,
					kind: 'draft.save',
					messageId: cursor.messageId,
					sessionId: cursor.sessionId,
				});
				assertCommittedAnnotationOutcome(outcome);
				const savedCursor = messageCommandCursorFromOutcome(outcome);
				if (savedCursor.draftRevision !== null || savedCursor.savedRevision === null) {
					throw new Error('Committed annotation Save did not return its saved message receipt.');
				}
				targetMessageCursorRef.current = savedCursor;
				setCommittedCursor(savedCursor);
			});
			setSavePhase('idle');
		} catch (error: unknown) {
			setSavePhase('idle');
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
		const projectedMessage = currentMessageById(annotationClient.getSnapshot(), messageId);
		const cursor = newestMessageCommandCursor(
			targetMessageCursorRef.current,
			projectedMessage === null ? null : messageCommandCursorFromProjection(projectedMessage),
		);
		if (cursor === null || cursor.draftRevision === null) {
			props.onCancel();
			return;
		}
		try {
			const outcome = await annotationClient.execute({
				editToken: editTokenRef.current,
				expectedDraftRevision: cursor.draftRevision,
				expectedMessageRevision: cursor.messageRevision,
				kind: 'draft.revert',
				messageId: cursor.messageId,
				sessionId: cursor.sessionId,
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
						committedCursor === null ? (
							<>
								<WorktreeAnnotationCommandButton
									disabled={savePhase !== 'idle'}
									label="Revert draft"
									onClick={() => void revert()}
									preserveEditorFocus
								>
									<Undo2 />
								</WorktreeAnnotationCommandButton>
								<WorktreeAnnotationCommandButton
									disabled={!validation.ok || savePhase !== 'idle'}
									label={savePhase === 'saving' ? 'Saving annotation' : 'Save annotation'}
									onClick={() => void save()}
									preserveEditorFocus
									appearance="primary"
								>
									{savePhase === 'idle' ? <Check /> : <LoaderCircle className="animate-spin" />}
								</WorktreeAnnotationCommandButton>
							</>
						) : undefined
					}
					continueTimeline={props.continueTimeline}
					draft={isDurable && committedCursor === null}
					embedded={props.placement === 'embedded'}
					metadata={
						<>
							<span className="font-medium text-comment-foreground">You</span>
							<span aria-hidden="true">·</span>
							{committedCursor !== null ? (
								<span className="font-medium text-comment-foreground">Saved</span>
							) : savePhase === 'saving' ? (
								<span>Saving draft…</span>
							) : isDurable ? (
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
							{projection.readStatus.kind === 'refreshing' ? <span>Refreshing</span> : null}
							{projection.readStatus.kind === 'unavailable' ? (
								<span>Updates unavailable</span>
							) : null}
						</>
					}
				>
					{committedCursor === null ? (
						<div
							aria-busy={savePhase === 'idle' ? undefined : true}
							data-testid="worktree-annotation-new-message-composer"
						>
							<Textarea
								appearance="embedded"
								autoFocus
								aria-label={props.placeholder}
								className="min-h-16"
								placeholder={props.placeholder}
								readOnly={savePhase !== 'idle'}
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
									if (
										event.key === 'Enter' &&
										(event.metaKey || event.ctrlKey) &&
										savePhase === 'idle'
									) {
										event.preventDefault();
										void save();
									} else if (event.key === 'Escape') {
										event.preventDefault();
										if (body.trim().length === 0) props.onCancel();
										else {
											void scheduler
												.focusLost()
												.then(props.onCancel)
												.catch((error: unknown) =>
													setOperationError(annotationErrorMessage(error)),
												);
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
					) : (
						<div data-testid="worktree-annotation-committed-pending-projection">
							<p className="whitespace-pre-wrap text-xs/relaxed">{body}</p>
						</div>
					)}
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
