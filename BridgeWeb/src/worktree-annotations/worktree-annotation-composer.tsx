import { RotateCcw, Save } from 'lucide-react';
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
	useEffect((): void => {
		if (projection.transportStatus.kind === 'available') scheduler.retryFailedPersistence();
	}, [projection.transportStatus.kind, scheduler]);
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
		if (registerExitHandler === undefined) return undefined;
		return registerExitHandler(flushAndExit);
	}, [flushAndExit, registerExitHandler]);
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
							className="min-h-16 border-0 bg-comment-composer-bg p-0 shadow-none focus-visible:border-transparent focus-visible:ring-2 focus-visible:ring-ring/30"
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
