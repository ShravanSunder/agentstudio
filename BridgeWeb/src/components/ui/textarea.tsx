import * as React from 'react';

import { cn } from '@/lib/utils.js';

export interface TextareaProps extends React.ComponentProps<'textarea'> {
	readonly appearance?: 'default' | 'embedded' | undefined;
}

function Textarea({
	appearance = 'default',
	className,
	...props
}: TextareaProps): React.ReactElement {
	return (
		<textarea
			data-slot="textarea"
			className={cn(
				'flex field-sizing-content min-h-12 w-full resize-none rounded-md border border-input bg-input/30 px-2 py-2 text-sm text-foreground transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring disabled:cursor-not-allowed disabled:border-input disabled:bg-transparent disabled:text-faint-foreground disabled:opacity-100 aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/20 aria-invalid:focus-visible:ring-ring',
				appearance === 'embedded'
					? 'rounded-none border-0 bg-transparent px-0 py-0 shadow-none focus-visible:border-transparent focus-visible:ring-0'
					: undefined,
				className,
			)}
			{...props}
		/>
	);
}

export { Textarea };
