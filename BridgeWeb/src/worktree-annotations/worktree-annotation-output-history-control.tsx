import { Check, Clock3, LoaderCircle, RotateCcw, Search, TriangleAlert, Undo2 } from 'lucide-react';
import { useEffect, useRef, useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import { Alert } from '@/components/ui/alert.js';
import {
	Card,
	CardContent,
	CardDescription,
	CardFooter,
	CardHeader,
	CardTitle,
} from '@/components/ui/card.js';
import {
	Collapsible,
	CollapsibleContent,
	CollapsibleHeading,
} from '@/components/ui/collapsible.js';
import { ItemDescription, ItemMetadata, ItemMetadataIcon } from '@/components/ui/item-content.js';

import { bridgeViewerActionToolbarSurfaceClassName } from '../app/bridge-viewer-action-toolbar.js';
import { BridgeViewerButton } from '../app/bridge-viewer-button.js';
import { cn } from '../app/class-name.js';
import { clearWorktreeAnnotationOutputHandled } from './worktree-annotation-output-handled-clear.js';
import {
	type WorktreeAnnotationOutputPendingController,
	useWorktreeAnnotationOutputPendingController,
} from './worktree-annotation-output-pending-controller.js';
import {
	annotationOutputFeedback,
	annotationOutputHistoryStatus,
	annotationCountLabel,
} from './worktree-annotation-output-presentation.js';
import type { WorktreeAnnotationOutputHistorySummary } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSessionSelection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

type WorktreeAnnotationOutputInspectionState =
	| { readonly attemptId: string; readonly kind: 'loading' }
	| { readonly attemptId: string; readonly kind: 'failed'; readonly message: string }
	| {
			readonly attemptId: string;
			readonly byteLength: number;
			readonly content: string;
			readonly contentType: string;
			readonly kind: 'ready';
	  };

interface HistoryActionFeedback {
	readonly attemptId: string;
	readonly message: string;
	readonly failed: boolean;
}

export function WorktreeAnnotationOutputHistoryControl(props: {
	readonly embedded?: boolean | undefined;
	readonly outputPendingController?: WorktreeAnnotationOutputPendingController | undefined;
}): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const [inspection, setInspection] = useState<WorktreeAnnotationOutputInspectionState | null>(
		null,
	);
	const inspectionSequence = useRef(0);
	const [markingAttemptId, setMarkingAttemptId] = useState<string | null>(null);
	const [actionFeedback, setActionFeedback] = useState<HistoryActionFeedback | null>(null);
	useEffect((): (() => void) => {
		inspectionSequence.current += 1;
		setInspection(null);
		setActionFeedback(null);
		return (): void => {
			inspectionSequence.current += 1;
		};
	}, [selection.activeSessionId]);
	const localOutputPendingController = useWorktreeAnnotationOutputPendingController();
	const outputPendingController = props.outputPendingController ?? localOutputPendingController;
	const history = projection.outputHistory.filter(
		(summary) => summary.sessionId === selection.activeSessionId,
	);
	if (history.length === 0) return null;

	const inspectOutput = async (attemptId: string): Promise<void> => {
		const requestSequence = ++inspectionSequence.current;
		setInspection({ attemptId, kind: 'loading' });
		try {
			const output = await annotationClient.inspectOutput(attemptId);
			if (requestSequence !== inspectionSequence.current) return;
			setInspection({
				attemptId,
				byteLength: output.descriptor.declaredByteLength,
				content: new TextDecoder('utf-8', { fatal: true }).decode(output.exactBytes),
				contentType: output.descriptor.contentType,
				kind: 'ready',
			});
		} catch (error: unknown) {
			if (requestSequence !== inspectionSequence.current) return;
			setInspection({
				attemptId,
				kind: 'failed',
				message: error instanceof Error ? error.message : 'Output inspection failed.',
			});
		}
	};
	const markNotHandled = async (summary: (typeof history)[number]): Promise<void> => {
		const pendingLease = outputPendingController.tryAcquire();
		if (pendingLease === null) return;
		setMarkingAttemptId(summary.attemptId);
		setActionFeedback(null);
		try {
			const outcome = await clearWorktreeAnnotationOutputHandled({
				attemptId: summary.attemptId,
				client: annotationClient,
				sessionId: summary.sessionId,
			});
			if (outcome.status.kind === 'failed') throw new Error(outcome.status.code);
			if (outcome.status.kind !== 'committed') throw new Error('Annotations could not be updated.');
			setActionFeedback({
				attemptId: summary.attemptId,
				failed: false,
				message: 'Annotations marked as not handled.',
			});
		} catch (error: unknown) {
			// The originating card may disappear when its session becomes unavailable.
			toast.error(error instanceof Error ? error.message : 'Annotations could not be updated.');
			setActionFeedback({
				attemptId: summary.attemptId,
				failed: true,
				message: error instanceof Error ? error.message : 'Annotations could not be updated.',
			});
		} finally {
			setMarkingAttemptId(null);
			pendingLease.release();
		}
	};
	const repeatOutput = async (attemptId: string): Promise<void> => {
		const pendingLease = outputPendingController.tryAcquire();
		if (pendingLease === null) return;
		try {
			const outcome = await annotationClient.execute({ attemptId, kind: 'output.repeat' });
			if (outcome.status.kind === 'failed') throw new Error(outcome.status.code);
			if (outcome.status.kind !== 'output') {
				throw new Error('Annotation output command returned no output result.');
			}
			const feedback = annotationOutputFeedback(outcome.status.outcome);
			if (feedback.toast !== null) toast.success(feedback.toast);
		} catch (error: unknown) {
			toast.error(error instanceof Error ? error.message : 'Output repetition failed.');
		} finally {
			pendingLease.release();
		}
	};

	return (
		<Collapsible>
			<section
				aria-label="Output history"
				className={cn(props.embedded === true ? 'mt-4' : bridgeViewerActionToolbarSurfaceClassName)}
			>
				<CollapsibleHeading>History ({history.length})</CollapsibleHeading>
				<CollapsibleContent className="mt-2">
					<WorktreeAnnotationOutputHistory
						history={history}
						markingAttemptId={markingAttemptId}
						actionFeedback={actionFeedback}
						inspection={inspection}
						isOutputPending={outputPendingController.isPending}
						onInspect={(attemptId) => void inspectOutput(attemptId)}
						onMarkNotHandled={(summary) => void markNotHandled(summary)}
						onRepeat={(attemptId) => void repeatOutput(attemptId)}
					/>
				</CollapsibleContent>
			</section>
		</Collapsible>
	);
}

function WorktreeAnnotationOutputHistory(props: {
	readonly history: readonly WorktreeAnnotationOutputHistorySummary[];
	readonly markingAttemptId: string | null;
	readonly actionFeedback: HistoryActionFeedback | null;
	readonly inspection: WorktreeAnnotationOutputInspectionState | null;
	readonly isOutputPending: boolean;
	readonly onInspect: (attemptId: string) => void;
	readonly onMarkNotHandled: (summary: WorktreeAnnotationOutputHistorySummary) => void;
	readonly onRepeat: (attemptId: string) => void;
}): ReactElement {
	return (
		<div className="space-y-2">
			{props.history.map((summary, attemptIndex) => (
				<Card
					aria-labelledby={`annotation-output-history-title-${summary.attemptId}`}
					data-testid="annotation-output-history-entry"
					key={summary.attemptId}
					role="group"
				>
					<CardHeader>
						<div className="flex min-w-0 items-center justify-between gap-2">
							<CardTitle
								id={`annotation-output-history-title-${summary.attemptId}`}
								className="truncate"
								title={
									summary.outputKind === 'clipboard_markdown' ? 'Clipboard Markdown' : 'JSON file'
								}
							>
								{summary.outputKind === 'clipboard_markdown' ? 'Clipboard Markdown' : 'JSON file'}
							</CardTitle>
							<ItemDescription className="shrink-0">
								<ItemMetadata>{annotationCountLabel(summary.messageCount)}</ItemMetadata>
							</ItemDescription>
						</div>
						<div className="flex min-w-0 items-center justify-between gap-2">
							<CardDescription
								truncateFrom="end"
								className="flex-1"
								title={formatOutputAttemptTime(summary.createdAt)}
							>
								<time dateTime={new Date(summary.createdAt).toISOString()}>
									{formatOutputAttemptTime(summary.createdAt)}
								</time>
							</CardDescription>
							<ItemDescription className="shrink-0">
								<ItemMetadataIcon
									icon={
										summary.state === 'succeeded'
											? Check
											: summary.state === 'prepared'
												? Clock3
												: TriangleAlert
									}
									label={annotationOutputHistoryStatus(summary.state, summary.outputKind)}
									tone={
										summary.state === 'unknown' || summary.state === 'finalization_failed'
											? 'warning'
											: 'normal'
									}
								/>
								<ItemMetadata>{historyStatusLabel(summary)}</ItemMetadata>
							</ItemDescription>
						</div>
					</CardHeader>
					{summary.state === 'succeeded' ? null : (
						<CardContent>
							<Alert layout="inline" variant="warning">
								{annotationOutputHistoryStatus(summary.state, summary.outputKind)}
							</Alert>
						</CardContent>
					)}
					{props.actionFeedback?.attemptId !== summary.attemptId ? null : (
						<CardContent>
							{props.actionFeedback.failed ? (
								<Alert layout="inline" variant="destructive">
									{props.actionFeedback.message}
								</Alert>
							) : (
								<CardDescription role="status">{props.actionFeedback.message}</CardDescription>
							)}
						</CardContent>
					)}
					{props.inspection?.attemptId !== summary.attemptId ? null : (
						<CardContent>
							{props.inspection.kind === 'loading' ? (
								<p aria-live="polite" className="text-xs text-muted-foreground" role="status">
									Loading exact bytes…
								</p>
							) : props.inspection.kind === 'failed' ? (
								<Alert layout="inline" variant="destructive">
									{props.inspection.message}
								</Alert>
							) : (
								<div data-testid="annotation-output-inspection">
									<p className="text-xs text-muted-foreground">
										Exact saved output · {props.inspection.byteLength} bytes ·{' '}
										{props.inspection.contentType}
									</p>
									<pre className="mt-1 max-h-36 overflow-auto whitespace-pre-wrap rounded bg-muted p-1.5 font-mono text-xs text-annotation-foreground">
										{props.inspection.content}
									</pre>
								</div>
							)}
						</CardContent>
					)}
					<CardFooter>
						<BridgeViewerButton
							aria-label={`Inspect output attempt ${attemptIndex + 1}`}
							variant="outline"
							disabled={
								props.isOutputPending ||
								(props.inspection?.attemptId === summary.attemptId &&
									props.inspection.kind === 'loading')
							}
							onClick={() => props.onInspect(summary.attemptId)}
						>
							{props.inspection?.attemptId === summary.attemptId &&
							props.inspection.kind === 'loading' ? (
								<LoaderCircle data-busy="true" />
							) : (
								<Search aria-hidden="true" />
							)}
							{props.inspection?.attemptId === summary.attemptId &&
							props.inspection.kind === 'loading'
								? 'Inspecting…'
								: 'Inspect'}
						</BridgeViewerButton>
						{summary.state === 'unknown' ? (
							<BridgeViewerButton
								aria-label={`Repeat output attempt ${attemptIndex + 1}`}
								variant="outline"
								disabled={props.isOutputPending}
								onClick={() => props.onRepeat(summary.attemptId)}
							>
								<RotateCcw aria-hidden="true" /> Repeat
							</BridgeViewerButton>
						) : null}
						{summary.canMarkNotHandled ? (
							<BridgeViewerButton
								ariaLabel="Mark as not handled"
								variant="outline"
								disabled={props.isOutputPending}
								onClick={() => props.onMarkNotHandled(summary)}
							>
								{props.markingAttemptId === summary.attemptId ? (
									<LoaderCircle data-busy="true" />
								) : (
									<Undo2 aria-hidden="true" />
								)}
								{props.markingAttemptId === summary.attemptId ? 'Updating…' : 'Mark as not handled'}
							</BridgeViewerButton>
						) : null}
					</CardFooter>
				</Card>
			))}
		</div>
	);
}

function historyStatusLabel(summary: WorktreeAnnotationOutputHistorySummary): string {
	if (summary.state === 'succeeded') {
		return annotationOutputHistoryStatus(summary.state, summary.outputKind);
	}
	const labels = {
		unknown: 'Unknown',
		prepared: 'Prepared',
		finalization_failed: 'Partial success',
	};
	return labels[summary.state];
}

function formatOutputAttemptTime(timestamp: number): string {
	return new Intl.DateTimeFormat(undefined, {
		dateStyle: 'medium',
		timeStyle: 'short',
	}).format(new Date(timestamp));
}
