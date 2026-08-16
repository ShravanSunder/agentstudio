import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const annotationConversationFrameVariants = cva(
	'min-w-0 overflow-hidden font-sans text-[var(--bridge-annotation-foreground)]',
	{
		variants: {
			placement: {
				embedded: 'm-0 w-full max-w-none',
				standalone:
					'm-2 w-[min(600px,calc(100%-1rem))] max-w-[600px] rounded-xl border border-[var(--bridge-annotation-border)] bg-[var(--bridge-annotation-surface)] bg-clip-padding shadow-sm outline-none transition-[border-color,box-shadow] focus-within:border-[var(--bridge-focus-border)] focus-within:ring-2 focus-within:ring-[var(--bridge-focus-ring)]',
			},
		},
		defaultVariants: { placement: 'standalone' },
	},
);

export interface WorktreeAnnotationConversationFrameProps
	extends ComponentProps<'section'>, VariantProps<typeof annotationConversationFrameVariants> {}

export function WorktreeAnnotationConversationFrame({
	className,
	placement,
	...props
}: WorktreeAnnotationConversationFrameProps): ReactElement {
	return (
		<section
			className={cn(annotationConversationFrameVariants({ placement }), className)}
			data-annotation-frame-placement={placement ?? 'standalone'}
			data-testid="worktree-annotation-conversation-frame"
			{...props}
		/>
	);
}
