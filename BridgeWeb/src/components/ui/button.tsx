import { Button as ButtonPrimitive } from '@base-ui/react/button';
import { cva, type VariantProps } from 'class-variance-authority';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const buttonVariants = cva(
	'group/button [&_[data-busy=true]]:animate-spin motion-reduce:[&_[data-busy=true]]:animate-none [&_[data-disclosure=true]]:transition-transform [&_[data-disclosure=true]]:duration-[var(--motion-fast)] [&_[data-disclosure=true][data-expanded=true]]:rotate-180 motion-reduce:[&_[data-disclosure=true]]:transition-none inline-flex shrink-0 items-center justify-center border border-transparent bg-clip-padding text-xs font-medium whitespace-nowrap transition-all outline-none select-none focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring active:not-aria-[haspopup]:translate-y-px disabled:pointer-events-none disabled:cursor-not-allowed disabled:opacity-100 disabled:text-faint-foreground disabled:aria-expanded:bg-transparent disabled:aria-expanded:text-faint-foreground disabled:aria-pressed:bg-transparent disabled:aria-pressed:text-faint-foreground disabled:data-popup-open:bg-transparent disabled:data-popup-open:text-faint-foreground aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/20 aria-invalid:focus-visible:ring-ring [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg]:text-current',
	{
		variants: {
			shape: {
				default: '',
				circle: 'rounded-full',
			},
			variant: {
				default:
					'bg-primary text-primary-foreground hover:border-ring disabled:border-input disabled:bg-muted disabled:hover:border-input',
				tint: 'bg-primary/15 text-foreground hover:bg-primary/15 hover:text-foreground disabled:border-transparent disabled:bg-muted [&_svg]:text-primary disabled:[&_svg]:text-faint-foreground',
				'success-outline':
					'border-success/50 bg-success/10 text-success hover:border-success/70 hover:bg-success/15 hover:text-success disabled:border-input disabled:bg-transparent disabled:hover:border-input disabled:hover:bg-transparent disabled:hover:text-faint-foreground',
				outline:
					'border-input bg-transparent text-foreground hover:bg-control-hover hover:text-accent-foreground aria-expanded:bg-control-hover aria-expanded:text-accent-foreground aria-pressed:bg-control-hover aria-pressed:text-accent-foreground data-popup-open:bg-control-hover data-popup-open:text-accent-foreground disabled:border-input disabled:bg-transparent disabled:hover:border-input disabled:hover:bg-transparent disabled:hover:text-faint-foreground',
				secondary:
					'bg-control-fill text-secondary-foreground hover:bg-control-hover hover:text-accent-foreground aria-expanded:bg-control-hover aria-expanded:text-accent-foreground data-popup-open:bg-control-hover data-popup-open:text-accent-foreground disabled:border-input disabled:bg-muted',
				ghost:
					'bg-transparent text-foreground hover:bg-control-hover hover:text-accent-foreground aria-expanded:bg-control-fill aria-expanded:hover:bg-control-hover aria-expanded:text-accent-foreground aria-pressed:bg-control-hover aria-pressed:text-accent-foreground data-popup-open:bg-control-hover data-popup-open:text-accent-foreground disabled:border-transparent disabled:bg-transparent disabled:hover:border-transparent disabled:hover:bg-transparent disabled:hover:text-faint-foreground',
				destructive:
					'bg-destructive/10 text-destructive hover:bg-destructive/20 disabled:border-input disabled:bg-muted disabled:hover:border-input disabled:hover:bg-muted disabled:hover:text-faint-foreground',
				link: 'bg-transparent text-primary underline-offset-4 hover:underline disabled:bg-transparent',
			},
			size: {
				default:
					"h-7 gap-1 rounded-md px-2 text-xs has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3.5",
				xs: "h-5 gap-1 rounded-sm px-1.5 text-xs has-data-[icon=inline-end]:pr-1 has-data-[icon=inline-start]:pl-1 [&_svg:not([class*='size-'])]:size-2.5",
				sm: "h-6 gap-1 rounded-md px-2 text-xs has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5 [&_svg:not([class*='size-'])]:size-3",
				lg: "h-8 gap-1 rounded-md px-2.5 text-xs has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2 [&_svg:not([class*='size-'])]:size-4",
				icon: "size-7 rounded-md [&_svg:not([class*='size-'])]:size-3.5",
				'icon-xs': "size-5 rounded-sm [&_svg:not([class*='size-'])]:size-2.5",
				'icon-sm': "size-6 rounded-md [&_svg:not([class*='size-'])]:size-3",
				'icon-lg': "size-8 rounded-md [&_svg:not([class*='size-'])]:size-4",
			},
		},
		defaultVariants: {
			shape: 'default',
			variant: 'default',
			size: 'default',
		},
	},
);

function Button({
	className,
	shape = 'default',
	variant = 'default',
	size = 'default',
	...props
}: ButtonPrimitive.Props & VariantProps<typeof buttonVariants>): ReactElement {
	return (
		<ButtonPrimitive
			data-slot="button"
			className={cn(buttonVariants({ shape, variant, size, className }))}
			{...props}
		/>
	);
}

export { Button, buttonVariants };
