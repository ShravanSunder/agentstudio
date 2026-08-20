import { Share2 } from 'lucide-react';
import type { KeyboardEvent, ReactElement } from 'react';

import { Alert, AlertDescription } from '@/components/ui/alert.js';
import { Button } from '@/components/ui/button.js';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group.js';

export type WorktreeAnnotationShareScope = 'new' | 'all';

export function WorktreeAnnotationShareTrigger(props: {
	readonly disabled: boolean;
	readonly onOpen: () => void;
}): ReactElement {
	return (
		<Button disabled={props.disabled} size="xs" variant="secondary" onClick={props.onOpen}>
			<Share2 aria-hidden="true" data-icon="inline-start" />
			Share comments
		</Button>
	);
}

export function WorktreeAnnotationShareModeRow(props: {
	readonly allCount: number;
	readonly error: string | null;
	readonly isOutputPending: boolean;
	readonly newCount: number;
	readonly onCopy: (scope: WorktreeAnnotationShareScope) => void;
	readonly onDone: () => void;
	readonly onExport: (scope: WorktreeAnnotationShareScope) => void;
	readonly onScopeChange: (scope: WorktreeAnnotationShareScope) => void;
	readonly scope: WorktreeAnnotationShareScope;
}): ReactElement {
	const displayedCount = props.scope === 'new' ? props.newCount : props.allCount;
	const outputDisabled = displayedCount === 0 || props.isOutputPending;
	const handleKeyDown = (event: KeyboardEvent<HTMLElement>): void => {
		if (event.key !== 'Escape') return;
		event.preventDefault();
		props.onDone();
	};

	return (
		<section
			aria-label="Share comments"
			className="w-full border-y border-comment-border bg-comment-surface px-3 py-2"
			data-testid="worktree-annotation-share-mode"
			onKeyDown={handleKeyDown}
		>
			<div className="flex flex-wrap items-center gap-2">
				<p className="mr-auto text-xs font-medium text-comment-foreground">Share comments</p>
				<ToggleGroup
					aria-label="Comments to share"
					onValueChange={(scopes): void => {
						const nextScope = scopes[0];
						if (nextScope === 'new' || nextScope === 'all') props.onScopeChange(nextScope);
					}}
					role="group"
					size="sm"
					spacing={0}
					value={[props.scope]}
					variant="outline"
				>
					<ToggleGroupItem aria-label={`New comments, ${props.newCount}`} value="new">
						New ({props.newCount})
					</ToggleGroupItem>
					<ToggleGroupItem aria-label={`All comments, ${props.allCount}`} value="all">
						All ({props.allCount})
					</ToggleGroupItem>
				</ToggleGroup>
				<div className="flex items-center gap-1">
					<Button
						disabled={outputDisabled}
						size="sm"
						variant="secondary"
						onClick={() => props.onCopy(props.scope)}
					>
						{props.isOutputPending ? 'Working…' : 'Copy Markdown'}
					</Button>
					<Button disabled={outputDisabled} size="sm" onClick={() => props.onExport(props.scope)}>
						Export JSON
					</Button>
					<Button disabled={props.isOutputPending} size="sm" variant="ghost" onClick={props.onDone}>
						Done
					</Button>
				</div>
			</div>
			{props.error === null ? null : (
				<Alert className="mt-2" variant="destructive">
					<AlertDescription>{props.error}</AlertDescription>
				</Alert>
			)}
		</section>
	);
}
