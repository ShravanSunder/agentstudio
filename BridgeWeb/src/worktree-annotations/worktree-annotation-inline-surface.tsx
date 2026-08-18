import type { FocusEvent, MouseEvent, ReactElement, ReactNode } from 'react';

import { Avatar, AvatarFallback } from '@/components/ui/avatar.js';
import { Button } from '@/components/ui/button.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';
import { cn } from '@/lib/utils.js';

export interface WorktreeAnnotationInlineSurfaceProps {
	readonly active?: boolean | undefined;
	readonly children: ReactNode;
	readonly commands?: ReactNode | undefined;
	readonly continueTimeline?: boolean | undefined;
	readonly draft?: boolean | undefined;
	readonly metadata: ReactNode;
	readonly onBlurCapture?: ((event: FocusEvent<HTMLElement>) => void) | undefined;
	readonly onFocusCapture?: ((event: FocusEvent<HTMLElement>) => void) | undefined;
	readonly timelineActions?: ReactNode | undefined;
}

export function WorktreeAnnotationInlineSurface(
	props: WorktreeAnnotationInlineSurfaceProps,
): ReactElement {
	return (
		<article
			className="grid min-w-0 grid-cols-[1.5rem_minmax(0,1fr)] gap-x-2"
			data-annotation-active={props.active === true ? 'true' : 'false'}
			data-annotation-draft={props.draft === true ? 'present' : 'absent'}
			data-testid="worktree-annotation-message"
			data-worktree-annotation-interaction
			onBlurCapture={props.onBlurCapture}
			onFocusCapture={props.onFocusCapture}
			tabIndex={0}
		>
			<Avatar aria-label="You">
				<AvatarFallback>Y</AvatarFallback>
			</Avatar>
			<div className="flex min-w-0 items-center gap-1.5 self-center text-xs/relaxed text-comment-muted">
				<div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">{props.metadata}</div>
				{props.timelineActions === undefined ? null : (
					<div aria-label="Comment timeline actions" className="flex shrink-0 items-center gap-0.5">
						{props.timelineActions}
					</div>
				)}
			</div>
			<div className="flex justify-center" aria-hidden="true">
				{props.continueTimeline === false ? null : (
					<span className="h-full w-px bg-comment-divider" />
				)}
			</div>
			<div
				className={cn(
					'relative mt-1 min-h-16 min-w-0 overflow-hidden rounded-2xl border bg-comment-surface text-comment-foreground shadow-sm transition-colors',
					props.active === true ? 'border-comment-active' : 'border-comment-border',
				)}
			>
				<div className="min-w-0 p-3 pr-8">{props.children}</div>
				{props.commands === undefined ? null : (
					<div
						aria-label="Comment commands"
						className="absolute right-1 bottom-1 flex flex-col items-center gap-0.5"
					>
						{props.commands}
					</div>
				)}
			</div>
		</article>
	);
}

export interface WorktreeAnnotationCommandButtonProps {
	readonly children: ReactNode;
	readonly disabled?: boolean | undefined;
	readonly label: string;
	readonly onClick: (event: MouseEvent<HTMLButtonElement>) => void;
	readonly preserveEditorFocus?: boolean | undefined;
	readonly primary?: boolean | undefined;
}

export function WorktreeAnnotationCommandButton(
	props: WorktreeAnnotationCommandButtonProps,
): ReactElement {
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<Button
						aria-label={props.label}
						disabled={props.disabled}
						size="icon-xs"
						variant={props.primary === true ? 'default' : 'ghost'}
						onClick={props.onClick}
						onPointerDown={(event) => {
							if (props.preserveEditorFocus === true) event.preventDefault();
						}}
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side="right">{props.label}</TooltipContent>
		</Tooltip>
	);
}
