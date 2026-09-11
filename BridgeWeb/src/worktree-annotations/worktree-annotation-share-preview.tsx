import type { ReactElement } from 'react';

import { Avatar, AvatarFallback } from '@/components/ui/avatar.js';
import { Card, CardContent } from '@/components/ui/card.js';
import {
	ItemContent,
	ItemDescription,
	ItemLabel,
	ItemMetadata,
} from '@/components/ui/item-content.js';
import { Separator } from '@/components/ui/separator.js';

import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';

export type WorktreeAnnotationSharePreviewReadiness = 'current' | 'unconfirmed' | 'unknown';

const threadPlacementLabels = {
	exact: null,
	outdated: 'Outdated',
	relocated: 'Relocated',
	unavailable: 'Source unavailable',
} satisfies Record<WorktreeAnnotationThreadProjection['context']['placement'], string | null>;

export function WorktreeAnnotationSharePreview(props: {
	readonly scope: 'pending' | 'all';
	readonly inlineThreads: readonly WorktreeAnnotationThreadProjection[];
	readonly otherThreads: readonly WorktreeAnnotationThreadProjection[];
	readonly readiness: WorktreeAnnotationSharePreviewReadiness;
}): ReactElement {
	if (props.readiness === 'unknown') {
		return <p className="mt-4 text-sm text-muted-foreground">Loading comments…</p>;
	}

	const participatingThreads = [...props.inlineThreads, ...props.otherThreads];
	const messageCount = participatingThreads.reduce(
		(totalCount, thread) => totalCount + thread.messages.length,
		0,
	);
	if (messageCount === 0) {
		return (
			<p className="mt-4 text-sm text-muted-foreground">
				{props.readiness === 'current'
					? props.scope === 'pending'
						? 'No pending comments.'
						: 'No annotations yet.'
					: 'Comments are still being confirmed.'}
			</p>
		);
	}

	return (
		<section aria-label="Comments to share" className="mt-4">
			{props.readiness === 'unconfirmed' ? (
				<p className="mb-2 text-sm text-muted-foreground">Last known comments</p>
			) : null}
			<div className="flex min-w-0 flex-col gap-3">
				{participatingThreads.map((thread) => (
					<div data-thread-id={thread.context.threadId} key={thread.context.threadId}>
						<ItemContent data-thread-path>
							<ItemLabel title={threadPathLabel(thread)}>{threadPathLabel(thread)}</ItemLabel>
							{threadPlacementLabel(thread) === null &&
							thread.context.resolution !== 'resolved' ? null : (
								<ItemDescription>
									{threadPlacementLabel(thread) === null ? null : (
										<ItemMetadata>{threadPlacementLabel(thread)}</ItemMetadata>
									)}
									{thread.context.resolution === 'resolved' ? (
										<ItemMetadata>Resolved</ItemMetadata>
									) : null}
								</ItemDescription>
							)}
						</ItemContent>
						<Card className="mt-1.5">
							<CardContent className="flex flex-col gap-3">
								{thread.messages.map((message, messageIndex) => {
									const authorLabel = message.authorKind === 'agent' ? 'Agent' : 'You';
									return (
										<div data-message-id={message.messageId} key={message.messageId}>
											{messageIndex === 0 ? null : <Separator className="mb-3" />}
											<div className="mb-1.5 flex min-w-0 items-center gap-2">
												<Avatar aria-label={authorLabel}>
													<AvatarFallback>{authorLabel.charAt(0)}</AvatarFallback>
												</Avatar>
												<ItemContent>
													<ItemDescription>
														<ItemMetadata emphasis="strong">{authorLabel}</ItemMetadata>
														<ItemMetadata>{threadLineRangeLabel(thread)}</ItemMetadata>
													</ItemDescription>
												</ItemContent>
											</div>
											<p className="break-words whitespace-pre-wrap text-sm text-foreground">
												{message.savedBody}
											</p>
										</div>
									);
								})}
							</CardContent>
						</Card>
					</div>
				))}
			</div>
		</section>
	);
}

function threadPathLabel(thread: WorktreeAnnotationThreadProjection): string {
	return thread.context.path ?? 'Session comments';
}

function threadLineRangeLabel(thread: WorktreeAnnotationThreadProjection): string {
	const { endLine, startLine } = thread.context;
	return startLine === endLine ? `Line ${startLine}` : `Lines ${startLine}–${endLine}`;
}

function threadPlacementLabel(thread: WorktreeAnnotationThreadProjection): string | null {
	return threadPlacementLabels[thread.context.placement];
}
