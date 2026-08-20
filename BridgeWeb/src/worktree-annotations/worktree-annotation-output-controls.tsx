import { Ellipsis, HistoryIcon } from 'lucide-react';
import { useEffect, useRef, useState, type ReactElement } from 'react';
import { toast } from 'sonner';
import { uuidv7 } from 'uuidv7';

import { Button } from '@/components/ui/button.js';
import {
	Popover,
	PopoverContent,
	PopoverDescription,
	PopoverHeader,
	PopoverTitle,
	PopoverTrigger,
} from '@/components/ui/popover.js';
import { Separator } from '@/components/ui/separator.js';

import type { BridgeProductCallResult } from '../core/comm-worker/bridge-product-call-contracts.js';
import { WorktreeAnnotationCommandButton } from './worktree-annotation-inline-surface.js';
import {
	WorktreeAnnotationOutputCandidateSelection,
	type WorktreeAnnotationOutputCandidate,
} from './worktree-annotation-output-candidate-selection.js';
import {
	annotationOutputFeedback,
	annotationOutputHistoryStatus,
	commentCountLabel,
	type WorktreeAnnotationOutputFeedback,
} from './worktree-annotation-output-presentation.js';
import {
	clearWorktreeAnnotationOutputSelection,
	worktreeAnnotationOutputTransferOperations,
} from './worktree-annotation-output-selection.js';
import type { WorktreeAnnotationOutputHistorySummary } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationInteraction,
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationOutputControlsProps {
	readonly activeSessionId: string;
	readonly compact?: boolean | undefined;
	readonly compactButtonAppearance?: 'message' | 'toolbar' | undefined;
	readonly disabled?: boolean | undefined;
	readonly triggerLabel?: string | undefined;
}

type WorktreeAnnotationOutputCandidateCursor = NonNullable<
	BridgeProductCallResult<'file.annotations.output.candidates.query'>['nextCursor']
>;
type WorktreeAnnotationOutputCandidateQueryCursor =
	| { readonly kind: 'start' }
	| WorktreeAnnotationOutputCandidateCursor;

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
	const interaction = useWorktreeAnnotationInteraction();
	const selection = interaction.outputSelection;
	const setOutputSelection = interaction.setOutputSelection;
	const [feedback, setFeedback] = useState<WorktreeAnnotationOutputFeedback | null>(null);
	const [inspection, setInspection] = useState<WorktreeAnnotationOutputInspectionState | null>(
		null,
	);
	const [isOutputPending, setIsOutputPending] = useState(false);
	const [candidates, setCandidates] = useState<readonly WorktreeAnnotationOutputCandidate[]>([]);
	const [candidateError, setCandidateError] = useState<string | null>(null);
	const [candidateRetryCursor, setCandidateRetryCursor] =
		useState<WorktreeAnnotationOutputCandidateQueryCursor | null>(null);
	const [isCandidateQueryPending, setIsCandidateQueryPending] = useState(false);
	const [eligibleMessageCount, setEligibleMessageCount] = useState(0);
	const [nextCandidateCursor, setNextCandidateCursor] =
		useState<BridgeProductCallResult<'file.annotations.output.candidates.query'>['nextCursor']>(
			null,
		);
	const compactTriggerRef = useRef<HTMLButtonElement | null>(null);
	const activeSession = projection.sessions.find(
		(session): boolean => session.sessionId === props.activeSessionId,
	);
	const selectedMessageCount =
		selection.kind === 'explicit'
			? selection.messageIds.size
			: Math.max(0, eligibleMessageCount - selection.excludedMessageIds.size);
	const sessionHistory = projection.outputHistory.filter(
		(summary): boolean => summary.sessionId === props.activeSessionId,
	);
	const isInteractionDisabled = props.disabled === true;
	const triggerLabel = props.triggerLabel ?? 'Review output';

	useEffect((): void => {
		setOutputSelection(clearWorktreeAnnotationOutputSelection());
		setFeedback(null);
		setInspection(null);
		setCandidates([]);
		setCandidateError(null);
		setCandidateRetryCursor(null);
		setEligibleMessageCount(0);
		setNextCandidateCursor(null);
	}, [activeSession?.semanticRevision, props.activeSessionId, setOutputSelection]);

	const queryCandidates = async (
		cursor: WorktreeAnnotationOutputCandidateQueryCursor,
	): Promise<void> => {
		if (activeSession === undefined || isCandidateQueryPending) return;
		setIsCandidateQueryPending(true);
		setCandidateError(null);
		setCandidateRetryCursor(null);
		try {
			const page = await annotationClient.queryOutputCandidates({
				cursor,
				expectedSessionRevision: activeSession.semanticRevision,
				limit: 16,
				sessionId: props.activeSessionId,
			});
			setCandidates((current) => {
				const byMessageId = new Map(current.map((candidate) => [candidate.messageId, candidate]));
				for (const candidate of page.candidates) byMessageId.set(candidate.messageId, candidate);
				return [...byMessageId.values()].toSorted(
					(left, right) => left.flatOrdinal - right.flatOrdinal,
				);
			});
			setEligibleMessageCount(page.eligibleMessageCount);
			setNextCandidateCursor(page.nextCursor);
		} catch (error: unknown) {
			setCandidateRetryCursor(cursor);
			setCandidateError(
				error instanceof Error ? error.message : 'Saved comments could not be loaded.',
			);
		} finally {
			setIsCandidateQueryPending(false);
		}
	};

	const setOutputInteractionOpen = (nextIsOpen: boolean): void => {
		if (nextIsOpen && isInteractionDisabled) return;
		setIsOpen(nextIsOpen);
		if (nextIsOpen && candidates.length === 0) void queryCandidates({ kind: 'start' });
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
		if (isInteractionDisabled || selectedMessageCount === 0 || isOutputPending) return;
		setIsOutputPending(true);
		setFeedback(null);
		const transferId = `annotation-output-${uuidv7()}`;
		try {
			const operations = worktreeAnnotationOutputTransferOperations({
				outputKind,
				selection,
				sessionId: props.activeSessionId,
				transferId,
			});
			let commandOutcome: Awaited<ReturnType<typeof annotationClient.execute>> | null = null;
			for (const operation of operations) {
				// eslint-disable-next-line no-await-in-loop -- Output selection chunks are an ordered transaction protocol.
				commandOutcome = await annotationClient.execute(operation);
			}
			if (commandOutcome === null) throw new Error('Annotation output transfer was empty.');
			handleCommandOutcome(commandOutcome);
			refreshOutputHistory();
		} catch (error: unknown) {
			void annotationClient
				.execute({
					kind: 'output.selection.cancel',
					selectionMode: selection.kind,
					sessionId: props.activeSessionId,
					transferId,
				})
				.catch((): void => {});
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
		if (commandOutcome.status.outcome.kind === 'succeeded') {
			setOutputSelection(clearWorktreeAnnotationOutputSelection());
		}
		setFeedback(nextFeedback.message === null ? null : nextFeedback);
		if (nextFeedback.toast !== null) toast.success(nextFeedback.toast);
		if (nextFeedback.closeInteraction) setOutputInteractionOpen(false);
	};

	return (
		<Popover open={isOpen} onOpenChange={setOutputInteractionOpen}>
			{props.compact === true ? (
				<WorktreeAnnotationCommandButton
					appearance={props.compactButtonAppearance ?? 'toolbar'}
					buttonRef={compactTriggerRef}
					disabled={
						isInteractionDisabled ||
						((activeSession?.eligibleMessageCount ?? 0) === 0 && sessionHistory.length === 0)
					}
					label={triggerLabel}
					onClick={() => setOutputInteractionOpen(true)}
				>
					<Ellipsis />
				</WorktreeAnnotationCommandButton>
			) : (
				<PopoverTrigger
					render={
						<Button
							disabled={
								isInteractionDisabled ||
								((activeSession?.eligibleMessageCount ?? 0) === 0 && sessionHistory.length === 0)
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
				data-worktree-annotation-preserve-expansion
			>
				<PopoverHeader>
					<PopoverTitle>Review output</PopoverTitle>
					<PopoverDescription>
						Choose immutable saved versions. Copy and Export never resolve their threads.
					</PopoverDescription>
				</PopoverHeader>
				<WorktreeAnnotationOutputCandidateSelection
					candidates={candidates}
					eligibleMessageCount={eligibleMessageCount}
					error={candidateError}
					isLoading={isCandidateQueryPending}
					nextCursor={nextCandidateCursor}
					onLoadMore={() => {
						if (nextCandidateCursor !== null) void queryCandidates(nextCandidateCursor);
					}}
					onRetry={() => void queryCandidates(candidateRetryCursor ?? { kind: 'start' })}
					onSelectionChange={setOutputSelection}
					selection={selection}
				/>
				<div className="flex items-center justify-end gap-1">
					<Button
						aria-label={`Copy ${commentCountLabel(selectedMessageCount)}`}
						disabled={selectedMessageCount === 0 || isOutputPending}
						size="xs"
						variant="secondary"
						onClick={() => void prepareOutput('clipboardMarkdown')}
					>
						Copy
					</Button>
					<Button
						aria-label={`Export ${commentCountLabel(selectedMessageCount)}`}
						disabled={selectedMessageCount === 0 || isOutputPending}
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
