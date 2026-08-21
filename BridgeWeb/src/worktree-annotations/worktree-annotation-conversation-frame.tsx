import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const annotationConversationFrameVariants = cva(
	'min-w-0 rounded-2xl font-sans text-comment-foreground transition-colors',
	{
		variants: {
			active: {
				false: 'bg-transparent',
				true: 'bg-comment-active-surface',
			},
			placement: {
				embedded: 'm-0 w-full max-w-none',
				standalone: 'm-2 w-[calc(100%-1rem)] max-w-3xl p-2 pr-9 pb-9',
			},
		},
		defaultVariants: { active: false, placement: 'standalone' },
	},
);

export interface WorktreeAnnotationConversationFrameProps
	extends ComponentProps<'section'>, VariantProps<typeof annotationConversationFrameVariants> {}

export function WorktreeAnnotationConversationFrame({
	active,
	className,
	placement,
	...props
}: WorktreeAnnotationConversationFrameProps): ReactElement {
	return (
		<section
			className={cn(annotationConversationFrameVariants({ active, placement }), className)}
			data-annotation-active={active === true ? 'true' : 'false'}
			data-annotation-frame-placement={placement ?? 'standalone'}
			data-testid="worktree-annotation-conversation-frame"
			{...props}
		/>
	);
}
