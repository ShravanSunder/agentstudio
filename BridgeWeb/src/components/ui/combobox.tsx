'use client';

import { Combobox as ComboboxPrimitive } from '@base-ui/react/combobox';
import type { ComponentProps, ReactElement } from 'react';

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

function ComboboxList({ className, ...props }: ComboboxPrimitive.List.Props): ReactElement {
	return (
		<ComboboxPrimitive.List
			className={cn('mt-1 max-h-64 overflow-y-auto outline-none', className)}
			data-slot="combobox-list"
			{...props}
		/>
	);
}

function ComboboxItem({ className, ...props }: ComboboxPrimitive.Item.Props): ReactElement {
	return (
		<ComboboxPrimitive.Item
			className={cn(
				'flex cursor-default items-center rounded-md px-2 py-1.5 text-xs text-[var(--bridge-text-secondary)] outline-none data-highlighted:bg-[var(--bridge-list-hover-bg)] data-highlighted:text-[var(--bridge-text-primary)] data-selected:bg-[var(--bridge-header-control-active-bg)]',
				className,
			)}
			data-slot="combobox-item"
			{...props}
		/>
	);
}

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
