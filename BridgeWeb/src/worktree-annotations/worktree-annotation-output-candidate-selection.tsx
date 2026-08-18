import { type ReactElement } from 'react';

import { Button } from '@/components/ui/button.js';
import { Checkbox } from '@/components/ui/checkbox.js';
import { Label } from '@/components/ui/label.js';
import { ScrollArea } from '@/components/ui/scroll-area.js';

import type { BridgeProductCallResult } from '../core/comm-worker/bridge-product-call-contracts.js';
import {
	clearWorktreeAnnotationOutputSelection,
	selectAllEligibleWorktreeAnnotationOutput,
	toggleWorktreeAnnotationOutputMessage,
	type WorktreeAnnotationOutputSelection,
} from './worktree-annotation-output-selection.js';
type WorktreeAnnotationOutputCandidatePage =
	BridgeProductCallResult<'file.annotations.output.candidates.query'>;

export type WorktreeAnnotationOutputCandidate =
	WorktreeAnnotationOutputCandidatePage['candidates'][number];

export function WorktreeAnnotationOutputCandidateSelection(props: {
	readonly candidates: readonly WorktreeAnnotationOutputCandidate[];
	readonly eligibleMessageCount: number;
	readonly error: string | null;
	readonly isLoading: boolean;
	readonly nextCursor: WorktreeAnnotationOutputCandidatePage['nextCursor'];
	readonly onLoadMore: () => void;
	readonly onRetry: () => void;
	readonly onSelectionChange: (selection: WorktreeAnnotationOutputSelection) => void;
	readonly selection: WorktreeAnnotationOutputSelection;
}): ReactElement {
	const selectedMessageCount =
		props.selection.kind === 'allEligible'
			? Math.max(0, props.eligibleMessageCount - props.selection.excludedMessageIds.size)
			: props.selection.messageIds.size;
	const allAreSelected =
		props.eligibleMessageCount > 0 && selectedMessageCount === props.eligibleMessageCount;
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
			{props.error === null ? null : (
				<div className="flex items-center justify-between gap-2" role="alert">
					<p className="text-xs text-destructive">{props.error}</p>
					<Button size="xs" variant="ghost" onClick={props.onRetry}>
						Retry
					</Button>
				</div>
			)}
			{props.candidates.length === 0 ? (
				<p className="text-xs text-comment-muted">
					{props.isLoading ? 'Loading saved comments…' : 'No output-eligible saved comments.'}
				</p>
			) : (
				<ScrollArea className="max-h-44 pr-1">
					<div className="flex flex-col gap-1">
						{props.candidates.map((candidate) => {
							const checkboxId = `annotation-output-${candidate.messageId}`;
							const isSelected =
								props.selection.kind === 'explicit'
									? props.selection.messageIds.has(candidate.messageId)
									: !props.selection.excludedMessageIds.has(candidate.messageId);
							const lineLabel =
								candidate.startLine === candidate.endLine
									? `${candidate.startLine}`
									: `${candidate.startLine}-${candidate.endLine}`;
							return (
								<Label
									htmlFor={checkboxId}
									key={`${candidate.flatOrdinal}:${candidate.messageId}`}
									className="flex cursor-default items-start gap-2 rounded-md px-1.5 py-1 hover:bg-comment-hover"
								>
									<Checkbox
										aria-label={`Select message ${candidate.flatOrdinal + 1}, ${candidate.path}:${lineLabel}`}
										checked={isSelected}
										id={checkboxId}
										onCheckedChange={(checked): void => {
											props.onSelectionChange(
												toggleWorktreeAnnotationOutputMessage(
													props.selection,
													candidate.messageId,
													checked,
												),
											);
										}}
									/>
									<span className="min-w-0">
										<span className="block truncate text-xs text-comment-muted">
											{candidate.path}:{lineLabel} · {candidate.location} · {candidate.placement}
										</span>
										<span className="block truncate text-xs text-comment-muted">
											Message {candidate.flatOrdinal + 1} ·{' '}
											{new Date(candidate.authoredAt).toLocaleString()}
										</span>
										<span className="block truncate text-xs text-comment-foreground">
											{candidate.excerpt}
										</span>
									</span>
								</Label>
							);
						})}
						{props.nextCursor === null ? null : (
							<Button
								disabled={props.isLoading}
								size="xs"
								variant="ghost"
								onClick={props.onLoadMore}
							>
								Load more
							</Button>
						)}
					</div>
				</ScrollArea>
			)}
		</div>
	);
}
