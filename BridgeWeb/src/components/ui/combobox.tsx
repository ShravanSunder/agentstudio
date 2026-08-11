'use client';

import { Combobox as ComboboxPrimitive } from '@base-ui/react/combobox';
import { forwardRef, type ComponentProps, type ReactElement } from 'react';

import { cn } from '@/lib/utils';

const Combobox = ComboboxPrimitive.Root;

function ComboboxInput({ className, ...props }: ComboboxPrimitive.Input.Props): ReactElement {
	return (
		<ComboboxPrimitive.Input
			className={cn(
				'h-7 w-full rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)] px-2 text-xs text-[var(--bridge-text-primary)] outline-none placeholder:text-[var(--bridge-text-muted)] focus:border-[var(--bridge-focus-border)]',
				className,
			)}
			data-slot="combobox-input"
			{...props}
		/>
	);
}

const ComboboxList = forwardRef<HTMLDivElement, ComboboxPrimitive.List.Props>(
	({ className, ...props }, ref): ReactElement => (
		<ComboboxPrimitive.List
			className={cn('mt-1 max-h-64 overflow-y-auto outline-none', className)}
			data-slot="combobox-list"
			ref={ref}
			{...props}
		/>
	),
);

const ComboboxItem = forwardRef<HTMLDivElement, ComboboxPrimitive.Item.Props>(
	({ className, ...props }, ref): ReactElement => (
		<ComboboxPrimitive.Item
			className={cn(
				'flex cursor-default items-center rounded-md px-2 py-1.5 text-xs text-[var(--bridge-text-secondary)] outline-none data-highlighted:bg-[var(--bridge-list-hover-bg)] data-highlighted:text-[var(--bridge-text-primary)] data-selected:bg-[var(--bridge-header-control-active-bg)]',
				className,
			)}
			data-slot="combobox-item"
			ref={ref}
			{...props}
		/>
	),
);

function ComboboxEmpty({ className, ...props }: ComponentProps<'div'>): ReactElement {
	return (
		<div
			className={cn('px-2 py-3 text-center text-xs text-[var(--bridge-text-muted)]', className)}
			data-slot="combobox-empty"
			{...props}
		/>
	);
}

export { Combobox, ComboboxEmpty, ComboboxInput, ComboboxItem, ComboboxList };
