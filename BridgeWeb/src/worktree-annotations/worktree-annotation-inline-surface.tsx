import type { ReactElement, ReactNode, Ref } from 'react';

import { Avatar, AvatarFallback } from '@/components/ui/avatar.js';
import { Button } from '@/components/ui/button.js';
import { CollapsibleTrigger } from '@/components/ui/collapsible.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';
import { cn } from '@/lib/utils.js';

export interface WorktreeAnnotationInlineSurfaceProps {
	readonly active?: boolean | undefined;
	readonly children: ReactNode;
	readonly commands?: ReactNode | undefined;
	readonly continueTimeline?: boolean | undefined;
	readonly draft?: boolean | undefined;
	readonly metadata: ReactNode;
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
		>
			<Avatar aria-label="You">
				<AvatarFallback>Y</AvatarFallback>
			</Avatar>
			<div className="flex min-w-0 flex-wrap items-center gap-1.5 self-center text-xs/relaxed text-comment-muted">
				{props.metadata}
			</div>
			<div className="flex justify-center" aria-hidden="true">
				{props.continueTimeline === false ? null : (
					<span className="h-full w-px bg-comment-divider" />
				)}
			</div>
			<div
				className={cn(
					'mt-1 grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-end overflow-hidden rounded-2xl border bg-comment-surface text-comment-foreground shadow-sm transition-colors',
					props.active === true ? 'border-comment-active' : 'border-comment-border',
				)}
			>
				<div className="min-w-0 p-3">{props.children}</div>
				{props.commands === undefined ? null : (
					<div aria-label="Comment commands" className="flex flex-col items-center gap-0.5 p-1">
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
	readonly onClick: () => void;
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
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side="right">{props.label}</TooltipContent>
		</Tooltip>
	);
}

export interface WorktreeAnnotationDisclosureButtonProps {
	readonly buttonRef?: Ref<HTMLButtonElement> | undefined;
	readonly children: ReactNode;
	readonly disabled?: boolean | undefined;
	readonly label: string;
}

export function WorktreeAnnotationDisclosureButton(
	props: WorktreeAnnotationDisclosureButtonProps,
): ReactElement {
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<CollapsibleTrigger
						render={
							<Button
								aria-label={props.label}
								disabled={props.disabled}
								ref={props.buttonRef}
								size="icon-xs"
								variant="ghost"
							/>
						}
					/>
				}
			>
				{props.children}
			</TooltipTrigger>
			<TooltipContent side="right">{props.label}</TooltipContent>
		</Tooltip>
	);
}
