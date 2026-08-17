import { HistoryIcon } from 'lucide-react';
import { useEffect, useMemo, useRef, useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import { Button } from '@/components/ui/button.js';
import { Checkbox } from '@/components/ui/checkbox.js';
import { Label } from '@/components/ui/label.js';
import {
	Popover,
	PopoverContent,
	PopoverDescription,
	PopoverHeader,
	PopoverTitle,
	PopoverTrigger,
} from '@/components/ui/popover.js';
import { Separator } from '@/components/ui/separator.js';

import {
	annotationOutputFeedback,
	annotationOutputHistoryStatus,
	commentCountLabel,
	type WorktreeAnnotationOutputFeedback,
} from './worktree-annotation-output-presentation.js';
import {
	clearWorktreeAnnotationOutputSelection,
	createWorktreeAnnotationOutputSelection,
	selectAllEligibleWorktreeAnnotationOutput,
	selectedWorktreeAnnotationMessageIds,
	toggleWorktreeAnnotationOutputMessage,
	worktreeAnnotationOutputWireSelection,
	type WorktreeAnnotationOutputSelection,
} from './worktree-annotation-output-selection.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationOutputHistorySummary,
	WorktreeAnnotationThreadProjection,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationOutputControlsProps {
	readonly activeSessionId: string;
	readonly compact?: boolean | undefined;
	readonly disabled?: boolean | undefined;
}

interface SelectableSavedMessage {
	readonly contextLabel: string;
	readonly messageRoleLabel: string;
	readonly threadLabel: string;
	readonly message: WorktreeAnnotationMessageEntry & {
		readonly draft: null;
		readonly savedBody: string;
		readonly savedRevision: number;
		readonly status: 'editable';
	};
}

export type WorktreeAnnotationOutputInspectionState =
	| { readonly kind: 'loading'; readonly attemptId: string }
	| {
			readonly attemptId: string;
			readonly byteLength: number;
			readonly content: string;
			readonly contentType: string;
			readonly kind: 'ready';
	  };

export function WorktreeAnnotationOutputControls(
	props: WorktreeAnnotationOutputControlsProps,
): ReactElement {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const [isOpen, setIsOpen] = useState(false);
	const [selection, setSelection] = useState<WorktreeAnnotationOutputSelection>(
		createWorktreeAnnotationOutputSelection,
	);
	const [feedback, setFeedback] = useState<WorktreeAnnotationOutputFeedback | null>(null);
	const [inspection, setInspection] = useState<WorktreeAnnotationOutputInspectionState | null>(
		null,
	);
	const [isOutputPending, setIsOutputPending] = useState(false);
	const compactTriggerRef = useRef<HTMLButtonElement | null>(null);
	const selectableMessages = useMemo(
		() => selectableSavedMessages(projection.threads, props.activeSessionId),
		[projection.threads, props.activeSessionId],
	);
	const eligibleMessageIds = selectableMessages.map(({ message }) => message.messageId);
	const selectedMessageIds = new Set(
		selectedWorktreeAnnotationMessageIds(selection, eligibleMessageIds),
	);
	const selectedMessages = selectableMessages.filter(({ message }): boolean =>
		selectedMessageIds.has(message.messageId),
	);
	const sessionHistory = projection.outputHistory.filter(
		(summary): boolean => summary.sessionId === props.activeSessionId,
	);
	const isInteractionDisabled = props.disabled === true;

	useEffect((): void => {
		setSelection(clearWorktreeAnnotationOutputSelection());
		setFeedback(null);
		setInspection(null);
	}, [props.activeSessionId]);

	const setOutputInteractionOpen = (nextIsOpen: boolean): void => {
		if (nextIsOpen && isInteractionDisabled) return;
		setIsOpen(nextIsOpen);
		if (!nextIsOpen) {
			setInspection(null);
			setFeedback(null);
		}
	};
	const refreshOutputHistory = (): void => {
		void annotationClient
			.execute({ kind: 'output.history', sessionId: props.activeSessionId })
			.catch((): void => {});
	};
	const prepareOutput = async (outputKind: 'clipboardMarkdown' | 'jsonFile'): Promise<void> => {
		if (isInteractionDisabled || selectedMessages.length === 0 || isOutputPending) return;
		setIsOutputPending(true);
		setFeedback(null);
		try {
			const commandOutcome = await annotationClient.execute({
				kind: 'output.prepare',
				outputKind,
				selection: worktreeAnnotationOutputWireSelection(selection),
				sessionId: props.activeSessionId,
			});
			handleCommandOutcome(commandOutcome);
			refreshOutputHistory();
		} catch (error: unknown) {
			setFeedback(outputInteractionFailure(error));
		} finally {
			setIsOutputPending(false);
		}
	};
	const repeatOutput = async (attemptId: string): Promise<void> => {
		if (isInteractionDisabled || isOutputPending) return;
		setIsOutputPending(true);
		setFeedback(null);
		try {
			const commandOutcome = await annotationClient.execute({
				attemptId,
				kind: 'output.repeat',
			});
			handleCommandOutcome(commandOutcome);
			refreshOutputHistory();
		} catch (error: unknown) {
			setFeedback(outputInteractionFailure(error));
		} finally {
			setIsOutputPending(false);
		}
	};
	const inspectOutput = async (attemptId: string): Promise<void> => {
		setInspection({ attemptId, kind: 'loading' });
		setFeedback(null);
		try {
			const output = await annotationClient.inspectOutput(attemptId);
			setInspection({
				attemptId,
				byteLength: output.descriptor.declaredByteLength,
				content: new TextDecoder('utf-8', { fatal: true }).decode(output.exactBytes),
				contentType: output.descriptor.contentType,
				kind: 'ready',
			});
		} catch (error: unknown) {
			setInspection(null);
			setFeedback(outputInteractionFailure(error));
		}
	};
	const handleCommandOutcome = (
		commandOutcome: Awaited<ReturnType<typeof annotationClient.execute>>,
	): void => {
		if (commandOutcome.status.kind === 'failed') {
			throw new Error(commandOutcome.status.code);
		}
		if (commandOutcome.status.kind !== 'output') {
			throw new Error('Annotation output command returned no output result.');
		}
		const nextFeedback = annotationOutputFeedback(commandOutcome.status.outcome);
		if (
			commandOutcome.status.outcome.kind === 'succeeded' ||
			commandOutcome.status.outcome.kind === 'unknown'
		) {
			setSelection(clearWorktreeAnnotationOutputSelection());
		}
		setFeedback(nextFeedback.message === null ? null : nextFeedback);
		if (nextFeedback.toast !== null) toast.success(nextFeedback.toast);
		if (nextFeedback.closeInteraction) setOutputInteractionOpen(false);
	};

	return (
		<Popover open={isOpen} onOpenChange={setOutputInteractionOpen}>
			{props.compact === true ? (
				<Button
					aria-label="Review output"
					disabled={
						isInteractionDisabled ||
						(selectableMessages.length === 0 && sessionHistory.length === 0)
					}
					onClick={() => setOutputInteractionOpen(true)}
					ref={compactTriggerRef}
					size="icon-xs"
					title="Review output"
					variant="ghost"
				>
					<HistoryIcon />
				</Button>
			) : (
				<PopoverTrigger
					render={
						<Button
							disabled={
								isInteractionDisabled ||
								(selectableMessages.length === 0 && sessionHistory.length === 0)
							}
							size="xs"
							variant="ghost"
						/>
					}
				>
					<HistoryIcon className="size-2.5" />
					Review output
				</PopoverTrigger>
			)}
			<PopoverContent
				align="end"
				anchor={props.compact === true ? compactTriggerRef : undefined}
				className="max-h-[min(36rem,var(--available-height))] w-96 gap-2 overflow-y-auto"
			>
				<PopoverHeader>
					<PopoverTitle>Review output</PopoverTitle>
					<PopoverDescription>
						Choose immutable saved versions. Copy and Export never resolve their threads.
					</PopoverDescription>
				</PopoverHeader>
				<SavedMessageSelection
					onSelectionChange={setSelection}
					selection={selection}
					selectableMessages={selectableMessages}
				/>
				<div className="flex items-center justify-end gap-1">
					<Button
						aria-label={`Copy ${commentCountLabel(selectedMessages.length)}`}
						disabled={selectedMessages.length === 0 || isOutputPending}
						size="xs"
						variant="secondary"
						onClick={() => void prepareOutput('clipboardMarkdown')}
					>
						Copy
					</Button>
					<Button
						aria-label={`Export ${commentCountLabel(selectedMessages.length)}`}
						disabled={selectedMessages.length === 0 || isOutputPending}
						size="xs"
						onClick={() => void prepareOutput('jsonFile')}
					>
						Export JSON
					</Button>
				</div>
				{feedback?.message === null || feedback === null ? null : (
					<p
						className={
							feedback.severity === 'error'
								? 'text-xs text-destructive'
								: feedback.severity === 'warning'
									? 'text-xs text-warning'
									: 'text-xs text-success'
						}
						role={feedback.severity === 'error' ? 'alert' : 'status'}
					>
						{feedback.message}
					</p>
				)}
				<Separator />
				<WorktreeAnnotationOutputHistory
					history={sessionHistory}
					inspection={inspection}
					isOutputPending={isOutputPending}
					onInspect={inspectOutput}
					onRepeat={repeatOutput}
				/>
			</PopoverContent>
		</Popover>
	);
}

function SavedMessageSelection(props: {
	readonly onSelectionChange: (selection: WorktreeAnnotationOutputSelection) => void;
	readonly selection: WorktreeAnnotationOutputSelection;
	readonly selectableMessages: readonly SelectableSavedMessage[];
}): ReactElement {
	const eligibleMessageIds = props.selectableMessages.map(({ message }) => message.messageId);
	const selectedMessageIds = new Set(
		selectedWorktreeAnnotationMessageIds(props.selection, eligibleMessageIds),
	);
	const selectedMessageCount = selectedMessageIds.size;
	const allAreSelected =
		props.selectableMessages.length > 0 && selectedMessageCount === props.selectableMessages.length;
	return (
		<div className="flex flex-col gap-1.5">
			<div className="flex items-center justify-between gap-2">
				<p className="text-xs font-medium text-comment-muted">Saved comments</p>
				<Button
					size="xs"
					variant="ghost"
					onClick={() =>
						props.onSelectionChange(
							allAreSelected
								? clearWorktreeAnnotationOutputSelection()
								: selectAllEligibleWorktreeAnnotationOutput(),
						)
					}
				>
					{allAreSelected ? 'Clear' : 'Select all'}
				</Button>
			</div>
			{props.selectableMessages.length === 0 ? (
				<p className="text-xs text-comment-muted">
					Save at least one comment before preparing output.
				</p>
			) : (
				<div className="flex max-h-44 flex-col gap-1 overflow-y-auto pr-1">
					{props.selectableMessages.map((entry) => {
						const revisionKey = savedMessageRevisionKey(entry.message);
						const checkboxId = `annotation-output-${entry.message.messageId}-${entry.message.savedRevision}`;
						const isSelected = selectedMessageIds.has(entry.message.messageId);
						return (
							<Label
								htmlFor={checkboxId}
								key={revisionKey}
								className="flex cursor-default items-start gap-2 rounded-md px-1.5 py-1 hover:bg-comment-hover"
							>
								<Checkbox
									aria-label={`Select ${entry.threadLabel}, ${entry.contextLabel}, ${entry.messageRoleLabel}, saved revision ${entry.message.savedRevision}`}
									checked={isSelected}
									id={checkboxId}
									onCheckedChange={(checked): void => {
										props.onSelectionChange(
											toggleWorktreeAnnotationOutputMessage(
												props.selection,
												entry.message.messageId,
												checked,
											),
										);
									}}
								/>
								<span className="min-w-0">
									<span className="block truncate text-xs text-comment-muted">
										{entry.contextLabel}
									</span>
									<span className="block truncate text-xs text-comment-muted">
										{entry.threadLabel} · {entry.messageRoleLabel} · Saved revision{' '}
										{entry.message.savedRevision}
									</span>
									<span className="block truncate text-xs text-comment-foreground">
										{savedMessagePreview(entry.message.savedBody)}
									</span>
								</span>
							</Label>
						);
					})}
				</div>
			)}
		</div>
	);
}

export function WorktreeAnnotationOutputHistory(props: {
	readonly history: readonly WorktreeAnnotationOutputHistorySummary[];
	readonly inspection: WorktreeAnnotationOutputInspectionState | null;
	readonly isOutputPending: boolean;
	readonly onInspect: (attemptId: string) => Promise<void>;
	readonly onRepeat: (attemptId: string) => Promise<void>;
}): ReactElement {
	return (
		<div className="flex flex-col gap-1.5" aria-label="Output history">
			<p className="text-xs font-medium text-comment-muted">Output history</p>
			{props.history.length === 0 ? (
				<p className="text-xs text-comment-muted">No output attempts yet.</p>
			) : (
				props.history.map((summary, attemptIndex) => (
					<div
						key={summary.attemptId}
						className="rounded-md border border-comment-border bg-comment-surface p-1.5"
					>
						<div className="flex items-start justify-between gap-2">
							<div className="min-w-0">
								<p className="text-xs font-medium text-comment-foreground">
									{summary.outputKind === 'clipboard_markdown' ? 'Clipboard Markdown' : 'JSON file'}{' '}
									· {commentCountLabel(summary.messageCount)}
								</p>
								<p className="text-xs text-comment-muted">
									{annotationOutputHistoryStatus(summary.state, summary.outputKind)}
								</p>
								<p className="text-xs text-comment-muted">
									Output attempt {attemptIndex + 1} · {annotationOutputTimestamp(summary.createdAt)}
									{summary.repeatedFromAttemptId === null ? '' : ' · repeated output'}
								</p>
							</div>
							<div className="flex shrink-0 items-center gap-1">
								<Button
									aria-label={`Inspect output attempt ${attemptIndex + 1}`}
									size="xs"
									variant="ghost"
									onClick={() => void props.onInspect(summary.attemptId)}
								>
									Inspect
								</Button>
								<Button
									aria-label={`Repeat output attempt ${attemptIndex + 1}`}
									disabled={props.isOutputPending || summary.state === 'prepared'}
									size="xs"
									variant="ghost"
									onClick={() => void props.onRepeat(summary.attemptId)}
								>
									Repeat
								</Button>
							</div>
						</div>
						{props.inspection?.attemptId === summary.attemptId ? (
							props.inspection.kind === 'loading' ? (
								<p className="mt-1 text-xs text-comment-muted">Loading exact bytes…</p>
							) : (
								<div className="mt-1" data-testid="annotation-output-inspection">
									<p className="text-xs text-comment-muted">
										Exact saved output · {props.inspection.byteLength} bytes ·{' '}
										{props.inspection.contentType}
									</p>
									<pre className="mt-1 max-h-36 overflow-auto whitespace-pre-wrap rounded bg-muted p-1.5 font-mono text-xs text-comment-foreground">
										{props.inspection.content}
									</pre>
								</div>
							)
						) : null}
					</div>
				))
			)}
		</div>
	);
}

function selectableSavedMessages(
	threads: readonly WorktreeAnnotationThreadProjection[],
	activeSessionId: string,
): readonly SelectableSavedMessage[] {
	return threads.flatMap((thread, threadIndex) =>
		thread.messages.flatMap((message, messageIndex): readonly SelectableSavedMessage[] => {
			if (message.sessionId !== activeSessionId || !hasSelectableSavedVersion(message)) {
				return [];
			}
			return [
				{
					contextLabel: outputContextLabel(thread),
					messageRoleLabel: messageIndex === 0 ? 'Root comment' : `Reply ${messageIndex}`,
					threadLabel: `Thread ${threadIndex + 1}`,
					message,
				},
			];
		}),
	);
}

function hasSelectableSavedVersion(
	message: WorktreeAnnotationMessageEntry,
): message is SelectableSavedMessage['message'] {
	return (
		message.savedBody !== null &&
		message.savedRevision !== null &&
		message.draft === null &&
		message.status === 'editable'
	);
}

function outputContextLabel(thread: WorktreeAnnotationThreadProjection): string {
	const path = thread.context.path;
	return thread.context.endLine === thread.context.startLine
		? `${path}:${thread.context.startLine}`
		: `${path}:${thread.context.startLine}-${thread.context.endLine}`;
}

function savedMessageRevisionKey(message: SelectableSavedMessage['message']): string {
	return `${message.messageId}:${message.savedRevision}`;
}

function savedMessagePreview(body: string): string {
	return body.trim().split(/\r?\n/, 1)[0] ?? '';
}

function annotationOutputTimestamp(timestamp: number | string): string {
	const date = typeof timestamp === 'number' ? new Date(timestamp) : new Date(timestamp);
	return new Intl.DateTimeFormat(undefined, {
		dateStyle: 'medium',
		timeStyle: 'short',
	}).format(date);
}

function outputInteractionFailure(error: unknown): WorktreeAnnotationOutputFeedback {
	return {
		closeInteraction: false,
		message: error instanceof Error ? error.message : 'Annotation output failed.',
		severity: 'error',
		toast: null,
	};
}
