import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const annotationConversationFrameVariants = cva('min-w-0 font-sans text-comment-foreground', {
	variants: {
		placement: {
			embedded: 'm-0 w-full max-w-none',
			standalone: 'm-2 w-[calc(100%-1rem)] max-w-xl',
		},
	},
	defaultVariants: { placement: 'standalone' },
});

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
