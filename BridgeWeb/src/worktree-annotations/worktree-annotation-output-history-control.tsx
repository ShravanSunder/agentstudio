import { useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import {
	Collapsible,
	CollapsibleContent,
	CollapsibleTrigger,
} from '@/components/ui/collapsible.js';

import { bridgeViewerActionToolbarSurfaceClassName } from '../app/bridge-viewer-action-toolbar.js';
import { BridgeViewerButton } from '../app/bridge-viewer-button.js';
import { cn } from '../app/class-name.js';
import { clearWorktreeAnnotationOutputHandled } from './worktree-annotation-output-handled-clear.js';
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
	| {
			readonly attemptId: string;
			readonly byteLength: number;
			readonly content: string;
			readonly contentType: string;
			readonly kind: 'ready';
	  };

export function WorktreeAnnotationOutputHistoryControl(props: {
	readonly embedded?: boolean | undefined;
}): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const selection = useWorktreeAnnotationSessionSelection();
	const [inspection, setInspection] = useState<WorktreeAnnotationOutputInspectionState | null>(
		null,
	);
	const [isOutputPending, setIsOutputPending] = useState(false);
	const history = projection.outputHistory.filter(
		(summary) => summary.sessionId === selection.activeSessionId,
	);
	if (history.length === 0) return null;

	const inspectOutput = async (attemptId: string): Promise<void> => {
		setInspection({ attemptId, kind: 'loading' });
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
			toast.error(error instanceof Error ? error.message : 'Output inspection failed.');
		}
	};
	const markNotHandled = async (summary: (typeof history)[number]): Promise<void> => {
		try {
			const outcome = await clearWorktreeAnnotationOutputHandled({
				attemptId: summary.attemptId,
				client: annotationClient,
				sessionId: summary.sessionId,
			});
			if (outcome.status.kind === 'failed') toast.error(outcome.status.code);
			else toast.success('Annotations marked as not handled.');
		} catch (error: unknown) {
			toast.error(error instanceof Error ? error.message : 'Annotations could not be updated.');
		}
	};
	const repeatOutput = async (attemptId: string): Promise<void> => {
		if (isOutputPending) return;
		setIsOutputPending(true);
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
			setIsOutputPending(false);
		}
	};

	return (
		<Collapsible>
			<section
				aria-label="Output history"
				className={cn(
					props.embedded === true
						? 'mt-2 border-t border-[var(--bridge-border-subtle)] pt-1.5'
						: bridgeViewerActionToolbarSurfaceClassName,
				)}
			>
				<CollapsibleTrigger render={<BridgeViewerButton />}>
					History ({history.length})
				</CollapsibleTrigger>
				<CollapsibleContent className="mt-2">
					<WorktreeAnnotationOutputHistory
						history={history}
						inspection={inspection}
						isOutputPending={isOutputPending}
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
	readonly inspection: WorktreeAnnotationOutputInspectionState | null;
	readonly isOutputPending: boolean;
	readonly onInspect: (attemptId: string) => void;
	readonly onMarkNotHandled: (summary: WorktreeAnnotationOutputHistorySummary) => void;
	readonly onRepeat: (attemptId: string) => void;
}): ReactElement {
	return (
		<div className="space-y-1">
			{props.history.map((summary, attemptIndex) => (
				<div
					className="border-t border-[var(--bridge-border-subtle)] pt-1.5"
					data-testid="annotation-output-history-entry"
					key={summary.attemptId}
				>
					<p className="text-[11px] font-medium text-[var(--bridge-text-primary)]">
						{summary.outputKind === 'clipboard_markdown' ? 'Clipboard Markdown' : 'JSON file'} ·{' '}
						{annotationCountLabel(summary.messageCount)}
					</p>
					<p className="text-[11px] text-[var(--bridge-text-secondary)]">
						<time dateTime={new Date(summary.createdAt).toISOString()}>
							{formatOutputAttemptTime(summary.createdAt)}
						</time>{' '}
						· {annotationOutputHistoryStatus(summary.state, summary.outputKind)}
					</p>
					<div className="flex gap-1">
						<BridgeViewerButton
							aria-label={`Inspect output attempt ${attemptIndex + 1}`}
							onClick={() => props.onInspect(summary.attemptId)}
						>
							Inspect
						</BridgeViewerButton>
						{summary.state === 'unknown' ? (
							<BridgeViewerButton
								aria-label={`Repeat output attempt ${attemptIndex + 1}`}
								disabled={props.isOutputPending}
								onClick={() => props.onRepeat(summary.attemptId)}
							>
								Repeat
							</BridgeViewerButton>
						) : null}
						{summary.canMarkNotHandled ? (
							<BridgeViewerButton onClick={() => props.onMarkNotHandled(summary)}>
								Mark as not handled
							</BridgeViewerButton>
						) : null}
					</div>
					{props.inspection?.attemptId !== summary.attemptId ? null : props.inspection.kind ===
					  'loading' ? (
						<p className="mt-1 text-[11px] text-[var(--bridge-text-secondary)]">
							Loading exact bytes…
						</p>
					) : (
						<div className="mt-1" data-testid="annotation-output-inspection">
							<p className="text-[11px] text-[var(--bridge-text-secondary)]">
								Exact saved output · {props.inspection.byteLength} bytes ·{' '}
								{props.inspection.contentType}
							</p>
							<pre className="mt-1 max-h-36 overflow-auto whitespace-pre-wrap rounded bg-muted p-1.5 font-mono text-xs text-comment-foreground">
								{props.inspection.content}
							</pre>
						</div>
					)}
				</div>
			))}
		</div>
	);
}

function formatOutputAttemptTime(timestamp: number): string {
	return new Intl.DateTimeFormat(undefined, {
		dateStyle: 'medium',
		timeStyle: 'short',
	}).format(new Date(timestamp));
}
