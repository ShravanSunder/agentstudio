import type { ComponentProps, ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

type ItemTextProps = ComponentProps<'span'>;

/** Shared content geometry; menu and combobox retain their own interaction state. */
function ItemContent({ className, ...props }: ItemTextProps): ReactElement {
	return (
		<span
			data-slot="item-content"
			className={cn('flex w-full min-w-0 flex-1 flex-col gap-0.5', className)}
			{...props}
		/>
	);
}

function ItemLabel({ className, ...props }: ItemTextProps): ReactElement {
	return (
		<span
			data-slot="item-label"
			className={cn(
				'block min-w-0 truncate text-base font-normal text-foreground group-data-disabled/combobox-item:text-faint-foreground group-data-disabled/dropdown-menu-item:text-faint-foreground',
				className,
			)}
			{...props}
		/>
	);
}

function ItemDescription({ className, ...props }: ItemTextProps): ReactElement {
	return (
		<span
			data-slot="item-description"
			className={cn(
				'flex min-w-0 items-baseline gap-1.5 overflow-hidden whitespace-nowrap text-sm font-normal text-muted-foreground group-data-disabled/combobox-item:text-faint-foreground group-data-disabled/dropdown-menu-item:text-faint-foreground',
				className,
			)}
			{...props}
		/>
	);
}

interface ItemMetadataProps extends ItemTextProps {
	readonly font?: 'normal' | 'mono';
	readonly emphasis?: 'normal' | 'strong';
}

function ItemMetadata({
	className,
	font = 'normal',
	emphasis = 'normal',
	...props
}: ItemMetadataProps): ReactElement {
	return (
		<span
			data-slot="item-metadata"
			className={cn(
				'min-w-0 truncate text-current',
				font === 'mono' ? 'font-mono' : 'font-sans',
				emphasis === 'strong' ? 'font-medium' : 'font-normal',
				className,
			)}
			{...props}
		/>
	);
}

export { ItemContent, ItemLabel, ItemDescription, ItemMetadata };
