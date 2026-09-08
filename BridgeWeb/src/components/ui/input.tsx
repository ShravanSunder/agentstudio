import { Input as InputPrimitive } from '@base-ui/react/input';
import { cva, type VariantProps } from 'class-variance-authority';
import * as React from 'react';

import { cn } from '@/lib/utils.js';

const inputVariants = cva(
	'w-full min-w-0 border border-input bg-control-fill px-2 text-sm text-foreground transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring disabled:pointer-events-none disabled:cursor-not-allowed disabled:border-input disabled:bg-transparent disabled:text-faint-foreground disabled:opacity-100 aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/20 aria-invalid:focus-visible:ring-ring',
	{
		variants: {
			size: {
				sm: 'h-6 rounded-md',
				default: 'h-7 rounded-md',
			},
		},
		defaultVariants: { size: 'default' },
	},
);

type InputProps = Omit<React.ComponentProps<'input'>, 'size'> & VariantProps<typeof inputVariants>;

function Input({ className, size = 'default', type, ...props }: InputProps): React.ReactElement {
	return (
		<InputPrimitive
			type={type}
			data-slot="input"
			className={cn(
				inputVariants({ size }),
				'file:inline-flex file:h-6 file:border-0 file:bg-transparent file:text-xs file:font-medium file:text-foreground',
				className,
			)}
			{...props}
		/>
	);
}

export { Input, inputVariants, type InputProps };
