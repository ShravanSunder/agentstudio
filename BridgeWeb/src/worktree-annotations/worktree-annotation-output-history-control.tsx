import { useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import {
	Collapsible,
	CollapsibleContent,
	CollapsibleTrigger,
} from '@/components/ui/collapsible.js';

import { bridgeViewerActionToolbarSurfaceClassName } from '../app/bridge-viewer-action-toolbar.js';
import { BridgeViewerButton } from '../app/bridge-viewer-button.js';
import {
	annotationOutputFeedback,
	annotationOutputHistoryStatus,
	commentCountLabel,
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

export function WorktreeAnnotationOutputHistoryControl(): ReactElement | null {
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
		const session = annotationClient
			.getSnapshot()
			.sessions.find(({ sessionId }) => sessionId === summary.sessionId);
		if (session === undefined) return;
		try {
			const outcome = await annotationClient.execute({
				attemptId: summary.attemptId,
				expectedSessionRevision: session.semanticRevision,
				kind: 'output.handled.clear',
			});
			if (outcome.status.kind === 'failed') toast.error(outcome.status.code);
			else toast.success('Comments marked as not handled.');
		} catch (error: unknown) {
			toast.error(error instanceof Error ? error.message : 'Comments could not be updated.');
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
			<section aria-label="Output history" className={bridgeViewerActionToolbarSurfaceClassName}>
				<CollapsibleTrigger render={<BridgeViewerButton />}>
					History ({history.length})
				</CollapsibleTrigger>
				<CollapsibleContent className="mt-2 space-y-2">
					<p className="text-[11px] text-[var(--bridge-text-secondary)]">
						Inspect or repeat exact durable output. History never changes comment placement.
					</p>
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
		<div className="space-y-2">
			{props.history.map((summary, attemptIndex) => (
				<div
					className="rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)] p-1.5"
					key={summary.attemptId}
				>
					<p className="text-[11px] font-medium text-[var(--bridge-text-primary)]">
						{summary.outputKind === 'clipboard_markdown' ? 'Clipboard Markdown' : 'JSON file'} ·{' '}
						{commentCountLabel(summary.messageCount)}
					</p>
					<p className="text-[11px] text-[var(--bridge-text-secondary)]">
						{annotationOutputHistoryStatus(summary.state, summary.outputKind)}
					</p>
					<div className="flex gap-1">
						<BridgeViewerButton
							aria-label={`Inspect output attempt ${attemptIndex + 1}`}
							onClick={() => props.onInspect(summary.attemptId)}
						>
							Inspect
						</BridgeViewerButton>
						<BridgeViewerButton
							aria-label={`Repeat output attempt ${attemptIndex + 1}`}
							disabled={props.isOutputPending || summary.state !== 'unknown'}
							onClick={() => props.onRepeat(summary.attemptId)}
						>
							Repeat
						</BridgeViewerButton>
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
