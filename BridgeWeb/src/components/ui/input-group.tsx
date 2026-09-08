'use client';

import { cva, type VariantProps } from 'class-variance-authority';
import * as React from 'react';

import { Button } from '@/components/ui/button.js';
import { Input, type InputProps } from '@/components/ui/input.js';
import { Textarea } from '@/components/ui/textarea.js';
import { cn } from '@/lib/utils.js';

type InputGroupSize = 'sm' | 'default';

interface InputGroupContextValue {
	readonly size: InputGroupSize;
}

const InputGroupContext = React.createContext<InputGroupContextValue>({ size: 'default' });

function InputGroup({
	className,
	size = 'default',
	...props
}: React.ComponentProps<'div'> & { readonly size?: InputGroupSize }): React.ReactElement {
	const contextValue = React.useMemo<InputGroupContextValue>(() => ({ size }), [size]);
	return (
		<InputGroupContext.Provider value={contextValue}>
			<div
				data-slot="input-group"
				data-size={size}
				role="group"
				className={cn(
					'group/input-group relative flex h-7 w-full min-w-0 items-center rounded-md border border-input bg-control-fill text-sm text-foreground transition-colors outline-none data-[size=sm]:h-6 has-data-[align=block-end]:rounded-md has-data-[align=block-start]:rounded-md has-[[data-slot=input-group-control]:focus-visible]:border-ring has-[[data-slot=input-group-control]:focus-visible]:ring-2 has-[[data-slot=input-group-control]:focus-visible]:ring-ring has-[[data-slot][aria-invalid=true]]:border-destructive has-[[data-slot][aria-invalid=true]]:ring-2 has-[[data-slot][aria-invalid=true]]:ring-destructive/20 has-[[data-slot=input-group-control][aria-invalid=true]:focus-visible]:ring-ring has-[[data-slot=input-group-control][disabled]]:bg-transparent has-[[data-slot=input-group-control][disabled]]:text-faint-foreground has-[textarea]:rounded-md has-[>[data-align=block-end]]:h-auto has-[>[data-align=block-end]]:flex-col has-[>[data-align=block-start]]:h-auto has-[>[data-align=block-start]]:flex-col has-[>textarea]:h-auto has-[>[data-align=block-end]]:[&>input]:pt-3 has-[>[data-align=block-start]]:[&>input]:pb-3 has-[>[data-align=inline-end]]:[&>input]:pr-1.5 has-[>[data-align=inline-start]]:[&>input]:pl-1.5',
					className,
				)}
				{...props}
			/>
		</InputGroupContext.Provider>
	);
}

const inputGroupAddonVariants = cva(
	"flex h-auto cursor-text items-center justify-center gap-1 py-2 text-xs font-medium text-muted-foreground select-none group-has-[[data-slot=input-group-control][disabled]]/input-group:text-faint-foreground **:data-[slot=kbd]:rounded-sm **:data-[slot=kbd]:bg-muted-foreground/10 **:data-[slot=kbd]:px-1 **:data-[slot=kbd]:text-2xs [&>svg:not([class*='size-'])]:size-3.5",
	{
		variants: {
			align: {
				'inline-start': 'order-first pr-1 pl-2 has-[>button]:pl-1.5 has-[>kbd]:pl-1.5',
				'inline-end': 'order-last pr-2 pl-1 has-[>button]:pr-1.5 has-[>kbd]:pr-1.5',
				'block-start':
					'order-first w-full justify-start px-2 pt-2 group-has-[>input]/input-group:pt-2 [.border-b]:pb-2',
				'block-end':
					'order-last w-full justify-start px-2 pb-2 group-has-[>input]/input-group:pb-2 [.border-t]:pt-2',
			},
		},
		defaultVariants: {
			align: 'inline-start',
		},
	},
);

function InputGroupAddon({
	className,
	align = 'inline-start',
	...props
}: React.ComponentProps<'div'> & VariantProps<typeof inputGroupAddonVariants>): React.ReactElement {
	return (
		<div
			role="group"
			data-slot="input-group-addon"
			data-align={align}
			className={cn(inputGroupAddonVariants({ align }), className)}
			onClick={(event: React.MouseEvent<HTMLDivElement>): void => {
				if (event.target instanceof Element && event.target.closest('button') !== null) {
					return;
				}
				event.currentTarget.parentElement?.querySelector('input')?.focus();
			}}
			{...props}
		/>
	);
}

function InputGroupButton({
	className,
	type = 'button',
	variant = 'ghost',
	size = 'xs',
	...props
}: Omit<React.ComponentProps<typeof Button>, 'type'> & {
	type?: 'button' | 'submit' | 'reset';
}): React.ReactElement {
	return (
		<Button
			type={type}
			data-size={size}
			variant={variant}
			size={size}
			className={cn('shadow-none', className)}
			{...props}
		/>
	);
}

function InputGroupText({ className, ...props }: React.ComponentProps<'span'>): React.ReactElement {
	return (
		<span
			className={cn(
				"flex items-center gap-2 text-xs/relaxed text-muted-foreground [&_svg]:pointer-events-none [&_svg:not([class*='size-'])]:size-4",
				className,
			)}
			{...props}
		/>
	);
}

function InputGroupInput({ className, size, ...props }: InputProps): React.ReactElement {
	const context = React.useContext(InputGroupContext);
	return (
		<Input
			size={size ?? context.size}
			data-slot="input-group-control"
			className={cn(
				'flex-1 rounded-none border-0 bg-transparent shadow-none ring-0 focus-visible:ring-0 aria-invalid:ring-0',
				className,
			)}
			{...props}
		/>
	);
}

function InputGroupTextarea({
	className,
	...props
}: React.ComponentProps<'textarea'>): React.ReactElement {
	return (
		<Textarea
			data-slot="input-group-control"
			className={cn(
				'flex-1 resize-none rounded-none border-0 bg-transparent py-2 shadow-none ring-0 focus-visible:ring-0 aria-invalid:ring-0',
				className,
			)}
			{...props}
		/>
	);
}

export {
	InputGroup,
	InputGroupAddon,
	InputGroupButton,
	InputGroupText,
	InputGroupInput,
	InputGroupTextarea,
};
