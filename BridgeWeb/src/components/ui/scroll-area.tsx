'use client';

import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

function ScrollArea({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="scroll-area"
			className={cn('relative overflow-auto overscroll-contain', className)}
			{...props}
		/>
	);
}

export { ScrollArea };
