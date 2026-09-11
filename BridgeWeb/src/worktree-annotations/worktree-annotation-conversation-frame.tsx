import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const annotationConversationFrameVariants = cva(
	'min-w-0 rounded-xl bg-background font-sans text-annotation-foreground ring-inset transition-colors outline-none',
	{
		variants: {
			active: {
				false: 'ring-annotation-border',
				true: 'ring-warning',
			},
			placement: {
				embedded: 'm-0 w-full max-w-none',
				standalone: 'm-2 w-[calc(100%-1rem)] max-w-3xl p-3 ring-1',
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
