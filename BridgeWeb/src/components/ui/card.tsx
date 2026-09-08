import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

function Card({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card"
			className={cn(
				'flex min-w-0 flex-col rounded-lg border border-border bg-card text-card-foreground',
				className,
			)}
			{...props}
		/>
	);
}

function CardHeader({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card-header"
			className={cn(
				'grid min-w-0 grid-cols-[minmax(0,1fr)] gap-1 p-2 has-data-[slot=card-action]:grid-cols-[minmax(0,1fr)_auto]',
				className,
			)}
			{...props}
		/>
	);
}

function CardTitle({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card-title"
			className={cn('min-w-0 text-base font-medium text-foreground', className)}
			{...props}
		/>
	);
}

function CardDescription({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card-description"
			className={cn('min-w-0 text-sm text-muted-foreground', className)}
			{...props}
		/>
	);
}

function CardAction({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card-action"
			className={cn('col-start-2 row-span-2 row-start-1 self-start', className)}
			{...props}
		/>
	);
}

function CardContent({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return <div data-slot="card-content" className={cn('min-w-0 p-2', className)} {...props} />;
}

function CardFooter({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card-footer"
			className={cn('flex min-w-0 items-center p-2 pt-0', className)}
			{...props}
		/>
	);
}

export { Card, CardAction, CardContent, CardDescription, CardFooter, CardHeader, CardTitle };
