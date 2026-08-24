import type { FocusEvent, KeyboardEvent, MouseEvent, ReactElement, ReactNode, Ref } from 'react';

import { Avatar, AvatarFallback } from '@/components/ui/avatar.js';
import { Button } from '@/components/ui/button.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';

export interface WorktreeAnnotationInlineSurfaceProps {
	readonly active?: boolean | undefined;
	readonly appearance?: 'card' | 'chronology' | undefined;
	readonly children: ReactNode;
	readonly commands?: ReactNode | undefined;
	readonly continueTimeline?: boolean | undefined;
	readonly draft?: boolean | undefined;
	readonly embedded?: boolean | undefined;
	readonly metadata: ReactNode;
	readonly onBlurCapture?: ((event: FocusEvent<HTMLElement>) => void) | undefined;
	readonly onClickCapture?: ((event: MouseEvent<HTMLElement>) => void) | undefined;
	readonly onFocusCapture?: ((event: FocusEvent<HTMLElement>) => void) | undefined;
	readonly onKeyDownCapture?: ((event: KeyboardEvent<HTMLElement>) => void) | undefined;
	readonly timelineActions?: ReactNode | undefined;
}

export function WorktreeAnnotationInlineSurface(
	props: WorktreeAnnotationInlineSurfaceProps,
): ReactElement {
	if (props.embedded === true) {
		return (
			<section
				className="relative min-w-0"
				data-annotation-active={props.active === true ? 'true' : 'false'}
				data-annotation-draft={props.draft === true ? 'present' : 'absent'}
				data-testid="worktree-annotation-message"
				data-worktree-annotation-interaction
				onBlurCapture={props.onBlurCapture}
				onClickCapture={props.onClickCapture}
				onFocusCapture={props.onFocusCapture}
				onKeyDownCapture={props.onKeyDownCapture}
			>
				<div className="mb-1 flex min-w-0 items-center gap-1.5 text-xs/relaxed text-comment-muted">
					{props.metadata}
				</div>
				<div className="min-w-0 pr-8">{props.children}</div>
				{props.commands === undefined ? null : (
					<div
						aria-label="Comment commands"
						className="absolute right-0 bottom-0 flex flex-col items-center gap-1"
					>
						{props.commands}
					</div>
				)}
			</section>
		);
	}
	return (
		<article
			className="grid min-w-0 grid-cols-[1.5rem_minmax(0,1fr)] gap-x-2"
			data-annotation-active={props.active === true ? 'true' : 'false'}
			data-annotation-draft={props.draft === true ? 'present' : 'absent'}
			data-testid="worktree-annotation-message"
			data-worktree-annotation-interaction
			onBlurCapture={props.onBlurCapture}
			onClickCapture={props.onClickCapture}
			onFocusCapture={props.onFocusCapture}
			onKeyDownCapture={props.onKeyDownCapture}
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
				{props.continueTimeline === true ? (
					<span className="h-full w-px bg-comment-border" />
				) : null}
			</div>
			{props.appearance === 'chronology' ? (
				<div className="relative min-w-0 rounded-md py-1 pr-8 focus-within:ring-1 focus-within:ring-ring/30">
					{props.children}
					{props.commands === undefined ? null : (
						<div
							aria-label="Comment commands"
							className="absolute right-0 bottom-0 flex flex-col items-center gap-1"
						>
							{props.commands}
						</div>
					)}
				</div>
			) : (
				<WorktreeAnnotationSurfaceCard commands={props.commands}>
					{props.children}
				</WorktreeAnnotationSurfaceCard>
			)}
		</article>
	);
}

interface WorktreeAnnotationSurfaceCardProps {
	readonly children: ReactNode;
	readonly commands?: ReactNode | undefined;
}

function WorktreeAnnotationSurfaceCard(props: WorktreeAnnotationSurfaceCardProps): ReactElement {
	return (
		<div className="relative mt-1 min-h-20 min-w-0 overflow-hidden rounded-2xl border border-comment-border bg-comment-surface text-comment-foreground transition-colors focus-within:border-ring focus-within:ring-1 focus-within:ring-ring/30">
			<div className="min-w-0 p-2.5 pr-8">{props.children}</div>
			{props.commands === undefined ? null : (
				<div
					aria-label="Comment commands"
					className="absolute right-2 bottom-2 flex flex-col items-center gap-0.5"
				>
					{props.commands}
				</div>
			)}
		</div>
	);
}

export interface WorktreeAnnotationCommandButtonProps {
	readonly appearance?: 'message' | 'primary' | 'timeline' | 'toolbar' | undefined;
	readonly buttonRef?: Ref<HTMLButtonElement> | undefined;
	readonly children: ReactNode;
	readonly disabled?: boolean | undefined;
	readonly expanded?: boolean | undefined;
	readonly label: string;
	readonly onClick: (event: MouseEvent<HTMLButtonElement>) => void;
	readonly preserveEditorFocus?: boolean | undefined;
}

export function WorktreeAnnotationCommandButton(
	props: WorktreeAnnotationCommandButtonProps,
): ReactElement {
	const appearance = props.appearance ?? 'message';
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<Button
						aria-label={props.label}
						aria-expanded={props.expanded}
						className={
							appearance === 'primary'
								? undefined
								: appearance === 'timeline'
									? 'text-comment-muted aria-expanded:bg-transparent aria-expanded:text-comment-muted hover:bg-comment-hover hover:text-comment-foreground'
									: appearance === 'toolbar'
										? 'text-comment-muted hover:bg-comment-hover hover:text-comment-foreground'
										: 'border-comment-border bg-comment-surface text-comment-muted hover:bg-comment-hover hover:text-comment-foreground'
						}
						disabled={props.disabled}
						ref={props.buttonRef}
						shape={appearance === 'toolbar' || appearance === 'timeline' ? 'default' : 'circle'}
						size={appearance === 'timeline' ? 'icon' : 'icon-sm'}
						variant={
							appearance === 'primary'
								? 'tint'
								: appearance === 'toolbar' || appearance === 'timeline'
									? 'ghost'
									: 'outline'
						}
						onClick={props.onClick}
						onPointerDown={(event) => {
							if (props.preserveEditorFocus === true) event.preventDefault();
						}}
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side={appearance === 'toolbar' ? 'bottom' : 'right'}>
				{props.label}
			</TooltipContent>
		</Tooltip>
	);
}
