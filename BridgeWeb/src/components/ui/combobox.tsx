import { Combobox as ComboboxPrimitive } from '@base-ui/react';
import { ChevronDownIcon, XIcon, CheckIcon } from 'lucide-react';
import * as React from 'react';

import { Button } from '@/components/ui/button.js';
import {
	InputGroup,
	InputGroupAddon,
	InputGroupButton,
	InputGroupInput,
} from '@/components/ui/input-group.js';
import { cn } from '@/lib/utils.js';

const Combobox = ComboboxPrimitive.Root;

function ComboboxValue({ ...props }: ComboboxPrimitive.Value.Props): React.ReactElement {
	return <ComboboxPrimitive.Value data-slot="combobox-value" {...props} />;
}

function ComboboxTrigger({
	className,
	children,
	...props
}: ComboboxPrimitive.Trigger.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Trigger
			data-slot="combobox-trigger"
			className={cn("[&_svg:not([class*='size-'])]:size-3.5", className)}
			{...props}
		>
			{children}
			<ChevronDownIcon className="pointer-events-none size-3.5 text-muted-foreground" />
		</ComboboxPrimitive.Trigger>
	);
}

function ComboboxClear({ className, ...props }: ComboboxPrimitive.Clear.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Clear
			data-slot="combobox-clear"
			render={<InputGroupButton variant="ghost" size="icon-xs" />}
			className={cn(className)}
			{...props}
		>
			<XIcon className="pointer-events-none" />
		</ComboboxPrimitive.Clear>
	);
}

function ComboboxInput({
	className,
	children,
	disabled = false,
	size = 'default',
	showTrigger = true,
	showClear = false,
	...props
}: Omit<ComboboxPrimitive.Input.Props, 'size'> & {
	size?: 'sm' | 'default';
	showTrigger?: boolean;
	showClear?: boolean;
}): React.ReactElement {
	return (
		<InputGroup className={cn('w-auto', className)} size={size}>
			<ComboboxPrimitive.Input render={<InputGroupInput disabled={disabled} />} {...props} />
			<InputGroupAddon align="inline-end">
				{showTrigger && (
					<InputGroupButton
						size="icon-xs"
						variant="ghost"
						render={<ComboboxTrigger />}
						data-slot="input-group-button"
						className="group-has-data-[slot=combobox-clear]/input-group:hidden"
						disabled={disabled}
					/>
				)}
				{showClear && <ComboboxClear disabled={disabled} />}
			</InputGroupAddon>
			{children}
		</InputGroup>
	);
}

function ComboboxContent({
	className,
	side = 'bottom',
	sideOffset = 6,
	align = 'start',
	alignOffset = 0,
	anchor,
	...props
}: ComboboxPrimitive.Popup.Props &
	Pick<
		ComboboxPrimitive.Positioner.Props,
		'side' | 'align' | 'sideOffset' | 'alignOffset' | 'anchor'
	>): React.ReactElement {
	return (
		<ComboboxPrimitive.Portal>
			<ComboboxPrimitive.Positioner
				side={side}
				sideOffset={sideOffset}
				align={align}
				alignOffset={alignOffset}
				anchor={anchor}
				className="isolate z-50"
			>
				<ComboboxPrimitive.Popup
					data-slot="combobox-content"
					data-chips={!!anchor}
					className={cn(
						'group/combobox-content relative max-h-(--available-height) w-(--anchor-width) max-w-(--available-width) min-w-[calc(var(--anchor-width)+--spacing(7))] origin-(--transform-origin) overflow-hidden rounded-lg border border-popover-border bg-popover text-xs text-popover-foreground shadow-popover duration-[var(--motion-fast)] data-[chips=true]:min-w-(--anchor-width) data-[side=bottom]:slide-in-from-top-2 data-[side=inline-end]:slide-in-from-left-2 data-[side=inline-start]:slide-in-from-right-2 data-[side=left]:slide-in-from-right-2 data-[side=right]:slide-in-from-left-2 data-[side=top]:slide-in-from-bottom-2 *:data-[slot=input-group]:m-1 *:data-[slot=input-group]:mb-0 *:data-[slot=input-group]:border-none *:data-[slot=input-group]:bg-input/30 *:data-[slot=input-group]:shadow-none data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95',
						className,
					)}
					{...props}
				/>
			</ComboboxPrimitive.Positioner>
		</ComboboxPrimitive.Portal>
	);
}

function ComboboxList({ className, ...props }: ComboboxPrimitive.List.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.List
			data-slot="combobox-list"
			className={cn(
				'no-scrollbar max-h-[min(calc(--spacing(72)---spacing(9)),calc(var(--available-height)---spacing(9)))] scroll-py-1 overflow-y-auto overscroll-contain p-1 data-empty:p-0',
				className,
			)}
			{...props}
		/>
	);
}

function ComboboxItem({
	className,
	children,
	presentation = 'default',
	...props
}: ComboboxPrimitive.Item.Props & {
	readonly presentation?: 'default' | 'descriptive';
}): React.ReactElement {
	return (
		<ComboboxPrimitive.Item
			data-slot="combobox-item"
			data-presentation={presentation}
			className={cn(
				"group/combobox-item relative flex h-7 w-full cursor-default items-center gap-2 rounded-md px-2 py-1 text-xs outline-hidden select-none data-highlighted:bg-accent data-highlighted:text-accent-foreground not-data-[variant=destructive]:data-highlighted:**:text-accent-foreground data-[presentation=descriptive]:flex-col data-[presentation=descriptive]:items-start data-[presentation=descriptive]:justify-center data-[presentation=descriptive]:gap-0 data-[presentation=descriptive]:py-px data-disabled:pointer-events-none data-disabled:text-faint-foreground data-disabled:opacity-100 [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-3.5",
				className,
			)}
			{...props}
		>
			{children}
			<ComboboxPrimitive.ItemIndicator
				render={
					<span className="pointer-events-none absolute right-2 flex items-center justify-center" />
				}
			>
				<CheckIcon className="pointer-events-none" />
			</ComboboxPrimitive.ItemIndicator>
		</ComboboxPrimitive.Item>
	);
}

function ComboboxItemDescription({
	className,
	...props
}: React.ComponentProps<'span'>): React.ReactElement {
	return (
		<span
			data-slot="combobox-item-description"
			className={cn(
				'text-2xs text-muted-foreground group-data-highlighted/combobox-item:text-current',
				className,
			)}
			{...props}
		/>
	);
}

function ComboboxGroup({ className, ...props }: ComboboxPrimitive.Group.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Group data-slot="combobox-group" className={cn(className)} {...props} />
	);
}

function ComboboxLabel({
	className,
	...props
}: ComboboxPrimitive.GroupLabel.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.GroupLabel
			data-slot="combobox-label"
			className={cn('px-2 py-1.5 text-xs text-muted-foreground', className)}
			{...props}
		/>
	);
}

function ComboboxCollection({ ...props }: ComboboxPrimitive.Collection.Props): React.ReactElement {
	return <ComboboxPrimitive.Collection data-slot="combobox-collection" {...props} />;
}

function ComboboxEmpty({ className, ...props }: ComboboxPrimitive.Empty.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Empty
			data-slot="combobox-empty"
			className={cn(
				'hidden w-full justify-center py-2 text-center text-xs text-muted-foreground group-data-empty/combobox-content:flex',
				className,
			)}
			{...props}
		/>
	);
}

function ComboboxSeparator({
	className,
	...props
}: ComboboxPrimitive.Separator.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Separator
			data-slot="combobox-separator"
			className={cn('-mx-1 my-1 h-px bg-border/50', className)}
			{...props}
		/>
	);
}

function ComboboxChips({
	className,
	...props
}: React.ComponentPropsWithRef<typeof ComboboxPrimitive.Chips> &
	ComboboxPrimitive.Chips.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Chips
			data-slot="combobox-chips"
			className={cn(
				'flex min-h-7 flex-wrap items-center gap-1 rounded-md border border-input bg-input/30 bg-clip-padding px-2 py-0.5 text-xs transition-colors focus-within:border-ring focus-within:ring-2 focus-within:ring-ring/30 has-aria-invalid:border-destructive has-aria-invalid:ring-2 has-aria-invalid:ring-destructive/20 has-disabled:bg-transparent has-disabled:text-faint-foreground has-data-[slot=combobox-chip]:px-1',
				className,
			)}
			{...props}
		/>
	);
}

function ComboboxChip({
	className,
	children,
	showRemove = true,
	...props
}: ComboboxPrimitive.Chip.Props & {
	showRemove?: boolean;
}): React.ReactElement {
	return (
		<ComboboxPrimitive.Chip
			data-slot="combobox-chip"
			className={cn(
				'flex h-5 w-fit items-center justify-center gap-1 rounded-sm bg-muted-foreground/10 px-1.5 text-xs font-medium whitespace-nowrap text-foreground has-disabled:pointer-events-none has-disabled:cursor-not-allowed has-disabled:bg-transparent has-disabled:text-faint-foreground has-disabled:opacity-100 has-data-[slot=combobox-chip-remove]:pr-0',
				className,
			)}
			{...props}
		>
			{children}
			{showRemove && (
				<ComboboxPrimitive.ChipRemove
					render={<Button variant="ghost" size="icon-xs" />}
					className="-ml-1"
					data-slot="combobox-chip-remove"
				>
					<XIcon className="pointer-events-none" />
				</ComboboxPrimitive.ChipRemove>
			)}
		</ComboboxPrimitive.Chip>
	);
}

function ComboboxChipsInput({
	className,
	...props
}: ComboboxPrimitive.Input.Props): React.ReactElement {
	return (
		<ComboboxPrimitive.Input
			data-slot="combobox-chip-input"
			className={cn('min-w-16 flex-1 outline-none', className)}
			{...props}
		/>
	);
}

function useComboboxAnchor(): React.RefObject<HTMLDivElement | null> {
	return React.useRef<HTMLDivElement | null>(null);
}

export {
	Combobox,
	ComboboxInput,
	ComboboxContent,
	ComboboxList,
	ComboboxItem,
	ComboboxItemDescription,
	ComboboxGroup,
	ComboboxLabel,
	ComboboxCollection,
	ComboboxEmpty,
	ComboboxSeparator,
	ComboboxChips,
	ComboboxChip,
	ComboboxChipsInput,
	ComboboxTrigger,
	ComboboxValue,
	useComboboxAnchor,
};
