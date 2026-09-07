import { LoaderCircle, LockKeyhole } from 'lucide-react';
import type { FocusEvent, KeyboardEvent, MouseEvent, ReactElement, ReactNode, Ref } from 'react';

import { Avatar, AvatarFallback } from '@/components/ui/avatar.js';
import { Button } from '@/components/ui/button.js';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip.js';
import { cn } from '@/lib/utils.js';

import {
	worktreeAnnotationActionSpec,
	type WorktreeAnnotationActionId,
} from './worktree-annotation-action-spec.js';

const annotationEditingSurfaceClassName = 'border-ring ring-2 ring-inset ring-ring/30';

export function WorktreeAnnotationLockedStatus(props: {
	readonly summary?: boolean;
}): ReactElement {
	const label =
		props.summary === true ? 'Contains copied or exported comments' : 'Comment editing locked';
	return (
		<Tooltip>
			<TooltipTrigger
				render={<span aria-label={label} role="img" tabIndex={0} className="inline-flex" />}
			>
				<LockKeyhole aria-hidden="true" className="size-3" />
			</TooltipTrigger>
			<TooltipContent>Copied or exported comments cannot be edited.</TooltipContent>
		</Tooltip>
	);
}

export interface WorktreeAnnotationInlineSurfaceProps {
	readonly active?: boolean | undefined;
	readonly ariaLabel?: string | undefined;
	readonly appearance?: 'card' | 'chronology' | undefined;
	readonly authorKind?: 'agent' | 'human' | undefined;
	readonly children: ReactNode;
	readonly commands?: ReactNode | undefined;
	readonly continueTimeline?: boolean | undefined;
	readonly draft?: boolean | undefined;
	readonly embedded?: boolean | undefined;
	readonly editing?: boolean | undefined;
	readonly metadata: ReactNode;
	readonly messageId?: string | undefined;
	readonly onBlurCapture?: ((event: FocusEvent<HTMLElement>) => void) | undefined;
	readonly onClickCapture?: ((event: MouseEvent<HTMLElement>) => void) | undefined;
	readonly onFocusCapture?: ((event: FocusEvent<HTMLElement>) => void) | undefined;
	readonly onKeyDownCapture?: ((event: KeyboardEvent<HTMLElement>) => void) | undefined;
	readonly timelineActions?: ReactNode | undefined;
}

export function WorktreeAnnotationInlineSurface(
	props: WorktreeAnnotationInlineSurfaceProps,
): ReactElement {
	const authorLabel = props.authorKind === 'agent' ? 'Agent' : 'You';
	const authorInitial = props.authorKind === 'agent' ? 'A' : 'Y';
	if (props.embedded === true) {
		return (
			<section
				aria-label={props.ariaLabel}
				className="group/annotation-entry relative min-w-0 outline-none"
				data-annotation-active={props.active === true ? 'true' : 'false'}
				data-annotation-draft={props.draft === true ? 'present' : 'absent'}
				data-annotation-editing={props.editing === true ? 'true' : 'false'}
				data-annotation-message-id={props.messageId}
				data-testid="worktree-annotation-message"
				data-worktree-annotation-interaction
				onBlurCapture={props.onBlurCapture}
				onClickCapture={props.onClickCapture}
				onFocusCapture={props.onFocusCapture}
				onKeyDownCapture={props.onKeyDownCapture}
			>
				<div className="mb-1 flex min-w-0 items-center gap-1.5 text-xs/relaxed text-annotation-muted">
					{props.metadata}
				</div>
				<div
					className={cn(
						'min-w-0 rounded-md border border-transparent pr-8 transition-[border-color,box-shadow]',
						props.editing === true ? annotationEditingSurfaceClassName : undefined,
					)}
					data-annotation-editor-surface
				>
					{props.children}
				</div>
				{props.commands === undefined ? null : (
					<div
						aria-label="Annotation commands"
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
			aria-label={props.ariaLabel}
			className="group/annotation-entry grid min-w-0 grid-cols-[1.5rem_minmax(0,1fr)] gap-x-2 outline-none"
			data-annotation-active={props.active === true ? 'true' : 'false'}
			data-annotation-draft={props.draft === true ? 'present' : 'absent'}
			data-annotation-editing={props.editing === true ? 'true' : 'false'}
			data-annotation-message-id={props.messageId}
			data-testid="worktree-annotation-message"
			data-worktree-annotation-interaction
			onBlurCapture={props.onBlurCapture}
			onClickCapture={props.onClickCapture}
			onFocusCapture={props.onFocusCapture}
			onKeyDownCapture={props.onKeyDownCapture}
			tabIndex={-1}
		>
			<Avatar aria-label={authorLabel}>
				<AvatarFallback>{authorInitial}</AvatarFallback>
			</Avatar>
			<div className="flex min-w-0 items-center gap-1.5 self-center text-xs/relaxed text-annotation-muted">
				<div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">{props.metadata}</div>
				{props.timelineActions === undefined ? null : (
					<div
						aria-label="Annotation timeline actions"
						className="flex shrink-0 items-center gap-0.5"
					>
						{props.timelineActions}
					</div>
				)}
			</div>
			<div className="flex justify-center" aria-hidden="true">
				{props.continueTimeline === true ? (
					<span className="h-full w-px bg-annotation-border" />
				) : null}
			</div>
			{props.appearance === 'chronology' ? (
				<div
					className={cn(
						'relative min-w-0 rounded-md border border-transparent py-1 pr-8 transition-[border-color,box-shadow]',
						props.editing === true ? annotationEditingSurfaceClassName : undefined,
					)}
					data-annotation-editor-surface
				>
					{props.children}
					{props.commands === undefined ? null : (
						<div
							aria-label="Annotation commands"
							className="absolute right-0 bottom-0 flex flex-col items-center gap-1"
						>
							{props.commands}
						</div>
					)}
				</div>
			) : (
				<WorktreeAnnotationSurfaceCard commands={props.commands} editing={props.editing}>
					{props.children}
				</WorktreeAnnotationSurfaceCard>
			)}
		</article>
	);
}

interface WorktreeAnnotationSurfaceCardProps {
	readonly children: ReactNode;
	readonly commands?: ReactNode | undefined;
	readonly editing?: boolean | undefined;
}

function WorktreeAnnotationSurfaceCard(props: WorktreeAnnotationSurfaceCardProps): ReactElement {
	return (
		<div
			className={cn(
				'relative mt-1 min-w-0 overflow-hidden rounded-xl border text-annotation-foreground transition-[border-color,box-shadow]',
				props.editing === true
					? cn(
							'grid grid-cols-[minmax(0,1fr)_auto] gap-2 border-annotation-border bg-annotation-surface p-2',
							annotationEditingSurfaceClassName,
						)
					: 'border-transparent bg-transparent',
			)}
			data-annotation-editor-surface
		>
			<div className={props.editing === true ? 'min-w-0' : 'min-w-0 p-2 pr-10'}>
				{props.children}
			</div>
			{props.commands === undefined ? null : (
				<div
					aria-label="Annotation commands"
					className={
						props.editing === true
							? 'flex min-h-14 flex-col items-center justify-between gap-2'
							: 'absolute right-2 bottom-2 flex flex-col items-center gap-2'
					}
				>
					{props.commands}
				</div>
			)}
		</div>
	);
}

export interface WorktreeAnnotationCommandButtonProps {
	readonly action: WorktreeAnnotationActionId;
	readonly annotationCount?: number | undefined;
	readonly appearance?:
		| 'message'
		| 'primary'
		| 'success'
		| 'thread-action'
		| 'thread'
		| 'timeline'
		| 'toolbar'
		| undefined;
	readonly busy?: boolean | undefined;
	readonly buttonRef?: Ref<HTMLButtonElement> | undefined;
	readonly disabled?: boolean | undefined;
	readonly expanded?: boolean | undefined;
	readonly iconClassName?: string | undefined;
	readonly onClick: (event: MouseEvent<HTMLButtonElement>) => void;
	readonly preserveEditorFocus?: boolean | undefined;
}

export function WorktreeAnnotationCommandButton(
	props: WorktreeAnnotationCommandButtonProps,
): ReactElement {
	const appearance = props.appearance ?? 'message';
	const actionSpec = worktreeAnnotationActionSpec(props.action, props.annotationCount);
	const accessibleName =
		props.action === 'saveAnnotation' && props.busy === true
			? 'Saving annotation'
			: actionSpec.accessibleName;
	const ActionIcon = actionSpec.icon;
	return (
		<Tooltip>
			<TooltipTrigger
				render={
					<Button
						aria-label={accessibleName}
						aria-expanded={props.expanded}
						data-tooltip={actionSpec.tooltip}
						disabled={props.disabled}
						ref={props.buttonRef}
						shape="default"
						size={appearance === 'timeline' ? 'icon' : 'icon-sm'}
						variant={
							appearance === 'primary'
								? 'tint'
								: appearance === 'success'
									? 'success-outline'
									: appearance === 'thread' || appearance === 'thread-action'
										? 'outline'
										: 'ghost'
						}
						onClick={props.onClick}
						onPointerDown={(event) => {
							if (props.preserveEditorFocus === true) event.preventDefault();
						}}
					/>
				}
			>
				{props.busy === true ? (
					<LoaderCircle className="animate-spin" />
				) : (
					<ActionIcon className={props.iconClassName} />
				)}
			</TooltipTrigger>
			<TooltipContent side={appearance === 'toolbar' ? 'bottom' : 'right'}>
				{actionSpec.tooltip}
			</TooltipContent>
		</Tooltip>
	);
}
