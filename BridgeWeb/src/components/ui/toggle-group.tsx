import { cva, type VariantProps } from 'class-variance-authority';
import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils';

import { Button } from './button.js';

const toggleGroupVariants = cva(
	'inline-flex shrink-0 items-center rounded-md border border-[var(--bridge-border-subtle)] bg-[var(--bridge-header-control-bg)]',
	{
		variants: {
			size: {
				default: 'h-7 gap-0.5 p-0.5',
				sm: 'h-6 gap-0.5 p-px',
			},
		},
		defaultVariants: {
			size: 'default',
		},
	},
);

export interface ToggleGroupProps
	extends ComponentProps<'div'>, VariantProps<typeof toggleGroupVariants> {}

function ToggleGroup({ className, size, ...props }: ToggleGroupProps): ReactElement {
	return (
		<div
			data-slot="toggle-group"
			className={cn(toggleGroupVariants({ size, className }))}
			{...props}
		/>
	);
}

export interface ToggleGroupItemProps extends ComponentProps<typeof Button> {
	readonly pressed?: boolean;
}

function ToggleGroupItem({
	className,
	pressed = false,
	size = 'sm',
	variant = 'ghost',
	...props
}: ToggleGroupItemProps): ReactElement {
	return (
		<Button
			aria-pressed={pressed}
			data-state={pressed ? 'on' : 'off'}
			data-toggle-group-slot="toggle-group-item"
			className={cn(
				'text-[var(--bridge-text-secondary)] transition-colors',
				'hover:border-[var(--bridge-border-opaque)] hover:bg-[var(--bridge-list-hover-bg)] hover:text-[var(--bridge-text-primary)]',
				'focus-visible:border-[var(--bridge-focus-border)] focus-visible:outline-none',
				'data-[state=on]:border-transparent data-[state=on]:bg-[var(--bridge-header-control-active-bg)] data-[state=on]:text-[var(--bridge-text-primary)]',
				className,
			)}
			size={size}
			type="button"
			variant={variant}
			{...props}
		/>
	);
}

export { ToggleGroup, ToggleGroupItem, toggleGroupVariants };
