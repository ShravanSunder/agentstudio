import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const statusBadgeVariants = cva(
	'inline-flex size-5 shrink-0 items-center justify-center rounded-md text-2xs font-semibold leading-none',
	{
		variants: {
			appearance: {
				badge: '',
				indicator: 'size-1.5 rounded-full bg-ring shadow-[var(--shadow-focus-dot)]',
			},
			tone: {
				neutral: 'bg-muted text-muted-foreground',
				success: 'bg-success/15 text-success',
				primary: 'bg-primary/15 text-primary',
				warning: 'bg-warning/15 text-warning',
				destructive: 'bg-destructive/15 text-destructive',
			},
		},
		defaultVariants: { tone: 'neutral', appearance: 'badge' },
	},
);

function StatusBadge({
	className,
	tone,
	appearance,
	...props
}: ComponentProps<'span'> & VariantProps<typeof statusBadgeVariants>): ReactElement {
	return (
		<span
			data-slot="status-badge"
			className={cn(
				statusBadgeVariants({ tone, appearance }),
				appearance === 'indicator' ? 'bg-ring' : undefined,
				className,
			)}
			{...props}
		/>
	);
}

export { StatusBadge };
