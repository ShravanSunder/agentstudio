import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils';

function Skeleton({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="skeleton"
			className={cn('animate-pulse rounded-md bg-muted', className)}
			{...props}
		/>
	);
}

export { Skeleton };
