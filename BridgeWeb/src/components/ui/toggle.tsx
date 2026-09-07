import { Toggle as TogglePrimitive } from '@base-ui/react/toggle';
import { cva, type VariantProps } from 'class-variance-authority';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const toggleVariants = cva(
	'group/toggle inline-flex items-center justify-center gap-1 border border-transparent bg-transparent text-xs font-medium whitespace-nowrap text-muted-foreground transition-all outline-none hover:bg-accent hover:text-accent-foreground focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/30 disabled:pointer-events-none disabled:cursor-not-allowed disabled:border-transparent disabled:bg-transparent disabled:text-faint-foreground disabled:opacity-100 disabled:hover:bg-transparent disabled:hover:text-faint-foreground aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/20 aria-pressed:bg-primary/15 aria-pressed:text-primary disabled:aria-pressed:bg-transparent disabled:aria-pressed:text-faint-foreground data-pressed:bg-primary/15 data-pressed:text-primary disabled:data-pressed:bg-transparent disabled:data-pressed:text-faint-foreground [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg]:text-current',
	{
		variants: {
			variant: {
				default: 'bg-transparent',
				outline: 'border-input bg-transparent disabled:border-input',
				segmented: 'bg-transparent',
			},
			size: {
				default:
					"h-7 min-w-7 rounded-md px-2 has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3.5",
				xs: "h-5 min-w-5 rounded-sm px-1.5 has-data-[icon=inline-end]:pr-1 has-data-[icon=inline-start]:pl-1 [&_svg:not([class*='size-'])]:size-2.5",
				sm: "h-6 min-w-6 rounded-md px-2 has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3",
				lg: "h-8 min-w-8 rounded-md px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2 [&_svg:not([class*='size-'])]:size-4",
				icon: "size-7 rounded-md [&_svg:not([class*='size-'])]:size-3.5",
				'icon-xs': "size-5 rounded-sm [&_svg:not([class*='size-'])]:size-2.5",
				'icon-sm': "size-6 rounded-md [&_svg:not([class*='size-'])]:size-3",
				'icon-lg': "size-8 rounded-md [&_svg:not([class*='size-'])]:size-4",
			},
		},
		defaultVariants: {
			variant: 'default',
			size: 'default',
		},
	},
);

function Toggle({
	className,
	variant = 'default',
	size = 'default',
	...props
}: TogglePrimitive.Props & VariantProps<typeof toggleVariants>): ReactElement {
	return (
		<TogglePrimitive
			data-slot="toggle"
			className={cn(toggleVariants({ variant, size, className }))}
			{...props}
		/>
	);
}

export { Toggle, toggleVariants };
