import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const cardBaseClassName =
	'flex min-w-0 flex-col rounded-lg border border-border bg-card text-card-foreground';

function Card({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return <div data-slot="card" className={cn(cardBaseClassName, className)} {...props} />;
}

interface InteractiveCardProps extends Omit<
	ComponentProps<'div'>,
	'onClick' | 'onKeyDown' | 'role' | 'tabIndex'
> {
	readonly onActivate: () => void;
	readonly disabled?: boolean;
}

/** A navigable content card keeps its text selectable, unlike an ordinary button. */
function InteractiveCard({
	className,
	onActivate,
	disabled = false,
	...props
}: InteractiveCardProps): ReactElement {
	return (
		<div
			{...props}
			data-slot="card"
			role="button"
			tabIndex={disabled ? -1 : 0}
			aria-disabled={disabled}
			className={cn(
				cardBaseClassName,
				'outline-none transition-colors select-text focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring',
				disabled ? '' : 'cursor-pointer hover:border-ring',
				className,
			)}
			onClick={(event): void => {
				if (disabled || event.defaultPrevented) return;
				const selection = event.currentTarget.ownerDocument.getSelection();
				if (
					event.detail !== 0 &&
					selection !== null &&
					!selection.isCollapsed &&
					((selection.anchorNode !== null && event.currentTarget.contains(selection.anchorNode)) ||
						(selection.focusNode !== null && event.currentTarget.contains(selection.focusNode)))
				)
					return;
				onActivate();
			}}
			onKeyDown={(event): void => {
				if (event.target !== event.currentTarget || disabled || event.repeat) return;
				if (event.key === 'Enter' || event.key === ' ') {
					event.preventDefault();
					onActivate();
				}
			}}
		/>
	);
}

function CardHeader({
	className,
	variant = 'default',
	...props
}: ComponentProps<'div'> & { readonly variant?: 'default' | 'divided' }): ReactElement {
	return (
		<div
			data-slot="card-header"
			className={cn(
				'grid min-w-0 grid-cols-[minmax(0,1fr)] gap-1 p-2 has-data-[slot=card-action]:grid-cols-[minmax(0,1fr)_auto]',
				variant === 'divided' ? 'shadow-[inset_0_-1px_0_var(--separator)]' : undefined,
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

interface CardDescriptionProps extends ComponentProps<'div'> {
	readonly truncateFrom?: 'start' | 'end';
}

function CardDescription({
	className,
	children,
	truncateFrom,
	...props
}: CardDescriptionProps): ReactElement {
	return (
		<div
			data-slot="card-description"
			className={cn(
				'min-w-0 text-sm font-normal text-muted-foreground',
				truncateFrom === undefined ? '' : 'truncate',
				truncateFrom === 'start' ? 'text-left [direction:rtl]' : '',
				className,
			)}
			{...props}
		>
			{truncateFrom === 'start' ? <bdi dir="ltr">{children}</bdi> : children}
		</div>
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
	return (
		<div
			data-slot="card-content"
			className={cn('min-w-0 p-2 [&:not(:first-child)]:pt-0', className)}
			{...props}
		/>
	);
}

function CardFooter({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			data-slot="card-footer"
			className={cn('flex min-w-0 flex-wrap items-center gap-2 p-2 pt-0', className)}
			{...props}
		/>
	);
}

export {
	Card,
	InteractiveCard,
	CardAction,
	CardContent,
	CardDescription,
	CardFooter,
	CardHeader,
	CardTitle,
};
