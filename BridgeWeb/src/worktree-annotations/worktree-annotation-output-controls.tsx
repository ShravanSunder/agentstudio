import { HistoryIcon } from 'lucide-react';
import { useEffect, useMemo, useState, type ReactElement } from 'react';
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

type OutputInspectionState =
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
	const [deselectedRevisionKeys, setDeselectedRevisionKeys] = useState<ReadonlySet<string>>(
		() => new Set(),
	);
	const [feedback, setFeedback] = useState<WorktreeAnnotationOutputFeedback | null>(null);
	const [inspection, setInspection] = useState<OutputInspectionState | null>(null);
	const [isOutputPending, setIsOutputPending] = useState(false);
	const selectableMessages = useMemo(
		() => selectableSavedMessages(projection.threads, props.activeSessionId),
		[projection.threads, props.activeSessionId],
	);
	const selectedMessages = selectableMessages.filter(
		(entry): boolean => !deselectedRevisionKeys.has(savedMessageRevisionKey(entry.message)),
	);
	const sessionHistory = projection.outputHistory.filter(
		(summary): boolean => summary.sessionId === props.activeSessionId,
	);
	const isInteractionDisabled = props.disabled === true;

	useEffect((): void => {
		setDeselectedRevisionKeys(new Set());
		setFeedback(null);
		setInspection(null);
	}, [props.activeSessionId]);

	const setOutputInteractionOpen = (nextIsOpen: boolean): void => {
		if (nextIsOpen && isInteractionDisabled) return;
		setIsOpen(nextIsOpen);
		if (!nextIsOpen) {
			setInspection(null);
			setFeedback(null);
			return;
		}
		void annotationClient
			.execute({ kind: 'output.history', sessionId: props.activeSessionId })
			.catch((error: unknown): void => {
				setFeedback(outputInteractionFailure(error));
			});
	};
	const prepareOutput = async (outputKind: 'clipboardMarkdown' | 'jsonFile'): Promise<void> => {
		if (isInteractionDisabled || selectedMessages.length === 0 || isOutputPending) return;
		setIsOutputPending(true);
		setFeedback(null);
		try {
			const commandOutcome = await annotationClient.execute({
				kind: 'output.prepare',
				outputKind,
				selection: {
					kind: 'explicit',
					messageIds: selectedMessages.map(({ message }) => message.messageId),
				},
				sessionId: props.activeSessionId,
			});
			handleCommandOutcome(commandOutcome);
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
		setFeedback(nextFeedback.message === null ? null : nextFeedback);
		if (nextFeedback.toast !== null) toast.success(nextFeedback.toast);
		if (nextFeedback.closeInteraction) setOutputInteractionOpen(false);
	};

	return (
		<Popover open={isOpen} onOpenChange={setOutputInteractionOpen}>
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
			<PopoverContent
				align="end"
				className="max-h-[min(36rem,var(--available-height))] w-96 gap-2 overflow-y-auto"
			>
				<PopoverHeader>
					<PopoverTitle>Review output</PopoverTitle>
					<PopoverDescription>
						Choose immutable saved versions. Copy and Export never resolve their threads.
					</PopoverDescription>
				</PopoverHeader>
				<SavedMessageSelection
					deselectedRevisionKeys={deselectedRevisionKeys}
					onDeselectedRevisionKeysChange={setDeselectedRevisionKeys}
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
								? 'text-[10px] text-destructive'
								: feedback.severity === 'warning'
									? 'text-[10px] text-[var(--bridge-warning)]'
									: 'text-[10px] text-[var(--bridge-added)]'
						}
						role={feedback.severity === 'error' ? 'alert' : 'status'}
					>
						{feedback.message}
					</p>
				)}
				<Separator />
				<OutputHistory
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
	readonly deselectedRevisionKeys: ReadonlySet<string>;
	readonly onDeselectedRevisionKeysChange: (keys: ReadonlySet<string>) => void;
	readonly selectableMessages: readonly SelectableSavedMessage[];
}): ReactElement {
	const selectedMessageCount = props.selectableMessages.filter(
		({ message }): boolean => !props.deselectedRevisionKeys.has(savedMessageRevisionKey(message)),
	).length;
	const allAreSelected =
		props.selectableMessages.length > 0 && selectedMessageCount === props.selectableMessages.length;
	return (
		<div className="flex flex-col gap-1.5">
			<div className="flex items-center justify-between gap-2">
				<p className="text-[10px] font-medium text-[var(--bridge-text-secondary)]">
					Saved comments
				</p>
				<Button
					size="xs"
					variant="ghost"
					onClick={() =>
						props.onDeselectedRevisionKeysChange(
							allAreSelected
								? new Set(
										props.selectableMessages.map(({ message }) => savedMessageRevisionKey(message)),
									)
								: new Set(),
						)
					}
				>
					{allAreSelected ? 'Clear' : 'Select all'}
				</Button>
			</div>
			{props.selectableMessages.length === 0 ? (
				<p className="text-[10px] text-[var(--bridge-text-muted)]">
					Save at least one comment before preparing output.
				</p>
			) : (
				<div className="flex max-h-44 flex-col gap-1 overflow-y-auto pr-1">
					{props.selectableMessages.map((entry) => {
						const revisionKey = savedMessageRevisionKey(entry.message);
						const checkboxId = `annotation-output-${entry.message.messageId}-${entry.message.savedRevision}`;
						const isSelected = !props.deselectedRevisionKeys.has(revisionKey);
						return (
							<Label
								htmlFor={checkboxId}
								key={revisionKey}
								className="flex cursor-default items-start gap-2 rounded-md px-1.5 py-1 hover:bg-[var(--bridge-annotation-hover)]"
							>
								<Checkbox
									aria-label={`Select ${entry.threadLabel}, ${entry.contextLabel}, ${entry.messageRoleLabel}, saved revision ${entry.message.savedRevision}`}
									checked={isSelected}
									id={checkboxId}
									onCheckedChange={(checked): void => {
										const nextKeys = new Set(props.deselectedRevisionKeys);
										if (checked) nextKeys.delete(revisionKey);
										else nextKeys.add(revisionKey);
										props.onDeselectedRevisionKeysChange(nextKeys);
									}}
								/>
								<span className="min-w-0">
									<span className="block truncate text-[10px] text-[var(--bridge-text-secondary)]">
										{entry.contextLabel}
									</span>
									<span className="block truncate text-[10px] text-[var(--bridge-text-muted)]">
										{entry.threadLabel} · {entry.messageRoleLabel} · Saved revision{' '}
										{entry.message.savedRevision}
									</span>
									<span className="block truncate text-xs text-[var(--bridge-text-primary)]">
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

function OutputHistory(props: {
	readonly history: readonly WorktreeAnnotationOutputHistorySummary[];
	readonly inspection: OutputInspectionState | null;
	readonly isOutputPending: boolean;
	readonly onInspect: (attemptId: string) => Promise<void>;
	readonly onRepeat: (attemptId: string) => Promise<void>;
}): ReactElement {
	return (
		<div className="flex flex-col gap-1.5" aria-label="Output history">
			<p className="text-[10px] font-medium text-[var(--bridge-text-secondary)]">Output history</p>
			{props.history.length === 0 ? (
				<p className="text-[10px] text-[var(--bridge-text-muted)]">No output attempts yet.</p>
			) : (
				props.history.map((summary, attemptIndex) => (
					<div
						key={summary.attemptId}
						className="rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-surface-bg)] p-1.5"
					>
						<div className="flex items-start justify-between gap-2">
							<div className="min-w-0">
								<p className="text-[10px] font-medium text-[var(--bridge-text-primary)]">
									{summary.outputKind === 'clipboard_markdown' ? 'Clipboard Markdown' : 'JSON file'}{' '}
									· {commentCountLabel(summary.messageCount)}
								</p>
								<p className="text-[10px] text-[var(--bridge-text-muted)]">
									{annotationOutputHistoryStatus(summary.state, summary.outputKind)}
								</p>
								<p className="text-[10px] text-[var(--bridge-text-muted)]">
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
								<p className="mt-1 text-[10px] text-[var(--bridge-text-muted)]">
									Loading exact bytes…
								</p>
							) : (
								<div className="mt-1" data-testid="annotation-output-inspection">
									<p className="text-[10px] text-[var(--bridge-text-secondary)]">
										Exact saved output · {props.inspection.byteLength} bytes ·{' '}
										{props.inspection.contentType}
									</p>
									<pre className="mt-1 max-h-36 overflow-auto whitespace-pre-wrap rounded bg-[var(--bridge-canvas-bg)] p-1.5 font-mono text-[10px] text-[var(--bridge-text-primary)]">
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
