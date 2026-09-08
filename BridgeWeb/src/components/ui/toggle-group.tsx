import { Toggle as TogglePrimitive } from '@base-ui/react/toggle';
import { ToggleGroup as ToggleGroupPrimitive } from '@base-ui/react/toggle-group';
import { type VariantProps } from 'class-variance-authority';
import * as React from 'react';

import { toggleVariants } from '@/components/ui/toggle.js';
import { cn } from '@/lib/utils.js';

type ToggleGroupContextValue = VariantProps<typeof toggleVariants> & {
	readonly spacing?: number;
	readonly orientation?: 'horizontal' | 'vertical';
};

interface ToggleGroupStyle extends React.CSSProperties {
	readonly '--gap': number;
}

const ToggleGroupContext = React.createContext<ToggleGroupContextValue>({
	size: 'default',
	variant: 'default',
	spacing: 2,
	orientation: 'horizontal',
});

function ToggleGroup({
	className,
	variant,
	size,
	spacing = 2,
	orientation = 'horizontal',
	children,
	...props
}: ToggleGroupPrimitive.Props &
	VariantProps<typeof toggleVariants> & {
		readonly spacing?: number;
		readonly orientation?: 'horizontal' | 'vertical';
	}): React.ReactElement {
	const contextValue = React.useMemo<ToggleGroupContextValue>(
		() => ({ orientation, size, spacing, variant }),
		[orientation, size, spacing, variant],
	);
	const style: ToggleGroupStyle = { '--gap': spacing };

	return (
		<ToggleGroupPrimitive
			data-slot="toggle-group"
			data-variant={variant}
			data-size={size}
			data-spacing={spacing}
			data-orientation={orientation}
			style={style}
			className={cn(
				'group/toggle-group flex w-fit flex-row items-center gap-[--spacing(var(--gap))] rounded-md data-[variant=segmented]:h-6 data-[variant=segmented]:gap-0.5 data-[variant=segmented]:border data-[variant=segmented]:border-input data-[variant=segmented]:bg-transparent data-[variant=segmented]:p-px data-vertical:flex-col data-vertical:items-stretch',
				className,
			)}
			{...props}
		>
			<ToggleGroupContext.Provider value={contextValue}>{children}</ToggleGroupContext.Provider>
		</ToggleGroupPrimitive>
	);
}

function ToggleGroupItem({
	className,
	children,
	variant = 'default',
	size = 'default',
	...props
}: TogglePrimitive.Props & VariantProps<typeof toggleVariants>): React.ReactElement {
	const context = React.useContext(ToggleGroupContext);
	const inheritedSize = size !== 'default' ? size : (context.size ?? size);
	const inheritedVariant =
		context.variant === 'segmented' ? 'default' : (context.variant ?? variant);

	return (
		<TogglePrimitive
			data-slot="toggle-group-item"
			data-variant={context.variant ?? variant}
			data-size={inheritedSize}
			data-spacing={context.spacing}
			className={cn(
				'shrink-0 focus:z-10 focus-visible:z-10 group-data-[variant=segmented]/toggle-group:px-1.5 group-data-[spacing=0]/toggle-group:rounded-none group-data-[spacing=0]/toggle-group:px-2 group-data-[spacing=0]/toggle-group:has-data-[icon=inline-end]:pr-1.5 group-data-[spacing=0]/toggle-group:has-data-[icon=inline-start]:pl-1.5 group-data-horizontal/toggle-group:data-[spacing=0]:first:rounded-l-md group-data-vertical/toggle-group:data-[spacing=0]:first:rounded-t-md group-data-horizontal/toggle-group:data-[spacing=0]:last:rounded-r-md group-data-vertical/toggle-group:data-[spacing=0]:last:rounded-b-md group-data-horizontal/toggle-group:data-[spacing=0]:data-[variant=outline]:border-l-0 group-data-vertical/toggle-group:data-[spacing=0]:data-[variant=outline]:border-t-0 group-data-horizontal/toggle-group:data-[spacing=0]:data-[variant=outline]:first:border-l group-data-vertical/toggle-group:data-[spacing=0]:data-[variant=outline]:first:border-t',
				toggleVariants({
					variant: inheritedVariant,
					size: inheritedSize,
				}),
				'group-data-[variant=segmented]/toggle-group:h-5',
				className,
			)}
			{...props}
		>
			{children}
		</TogglePrimitive>
	);
}

export { ToggleGroup, ToggleGroupItem };
