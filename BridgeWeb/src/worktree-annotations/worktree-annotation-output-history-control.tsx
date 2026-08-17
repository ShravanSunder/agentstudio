import { HistoryIcon } from 'lucide-react';
import { useRef, useState, type ReactElement } from 'react';
import { toast } from 'sonner';

import { Button } from '@/components/ui/button.js';
import {
	Popover,
	PopoverContent,
	PopoverDescription,
	PopoverHeader,
	PopoverTitle,
} from '@/components/ui/popover.js';

import {
	WorktreeAnnotationOutputHistory,
	type WorktreeAnnotationOutputInspectionState,
} from './worktree-annotation-output-controls.js';
import { annotationOutputFeedback } from './worktree-annotation-output-presentation.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationSurfaceClient,
} from './worktree-annotation-surface-provider.js';

export function WorktreeAnnotationOutputHistoryControl(props: {
	readonly 'data-testid'?: string | undefined;
}): ReactElement | null {
	const annotationClient = useWorktreeAnnotationSurfaceClient();
	const projection = useWorktreeAnnotationProjection();
	const [inspection, setInspection] = useState<WorktreeAnnotationOutputInspectionState | null>(
		null,
	);
	const [isOpen, setIsOpen] = useState(false);
	const [isOutputPending, setIsOutputPending] = useState(false);
	const triggerRef = useRef<HTMLButtonElement | null>(null);
	const history = projection.outputHistory;

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
		<Popover
			onOpenChange={(nextOpen): void => {
				setIsOpen(nextOpen);
				if (!nextOpen) setInspection(null);
			}}
			open={isOpen}
		>
			<Button
				aria-label="Output history"
				data-testid={props['data-testid']}
				onClick={() => setIsOpen(true)}
				ref={triggerRef}
				size="icon-xs"
				title="Output history"
				variant="ghost"
			>
				<HistoryIcon />
			</Button>
			<PopoverContent
				align="end"
				anchor={triggerRef}
				className="max-h-[min(36rem,var(--available-height))] w-96 gap-2 overflow-y-auto"
			>
				<PopoverHeader>
					<PopoverTitle>Output history</PopoverTitle>
					<PopoverDescription>
						Inspect or repeat exact durable output. This view does not navigate comments.
					</PopoverDescription>
				</PopoverHeader>
				<WorktreeAnnotationOutputHistory
					history={history}
					inspection={inspection}
					isOutputPending={isOutputPending}
					onInspect={inspectOutput}
					onRepeat={repeatOutput}
				/>
			</PopoverContent>
		</Popover>
	);
}
