import type { LucideIcon } from 'lucide-react';
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
				'flex min-w-0 items-baseline has-data-[slot=item-metadata-icon]:items-center gap-1.5 overflow-hidden whitespace-nowrap text-sm font-normal text-muted-foreground group-data-disabled/combobox-item:text-faint-foreground group-data-disabled/dropdown-menu-item:text-faint-foreground',
				className,
			)}
			{...props}
		/>
	);
}

interface ItemMetadataProps extends ItemTextProps {
	readonly font?: 'normal' | 'mono';
	readonly emphasis?: 'normal' | 'strong';
	readonly truncateFrom?: 'start' | 'end';
}

function ItemMetadata({
	className,
	children,
	truncateFrom = 'end',
	font = 'normal',
	emphasis = 'normal',
	...props
}: ItemMetadataProps): ReactElement {
	return (
		<span
			data-slot="item-metadata"
			className={cn(
				'min-w-0 truncate text-current',
				truncateFrom === 'start' ? 'text-left [direction:rtl]' : '',
				font === 'mono' ? 'font-mono' : 'font-sans',
				emphasis === 'strong' ? 'font-medium' : 'font-normal',
				className,
			)}
			{...props}
		>
			{truncateFrom === 'start' ? <bdi dir="ltr">{children}</bdi> : children}
		</span>
	);
}

/** A passive metadata symbol, with the same meaning available without recognizing its shape. */
function ItemMetadataIcon(props: {
	readonly icon: LucideIcon;
	readonly label: string;
	readonly tone?: 'normal' | 'warning';
}): ReactElement {
	const Icon = props.icon;
	return (
		<span
			data-slot="item-metadata-icon"
			role="img"
			aria-label={props.label}
			title={props.label}
			className={cn(
				'inline-flex shrink-0 items-center',
				props.tone === 'warning' ? 'text-warning' : 'text-current',
			)}
		>
			<Icon aria-hidden="true" className="size-3" />
		</span>
	);
}

export { ItemContent, ItemLabel, ItemDescription, ItemMetadata, ItemMetadataIcon };
