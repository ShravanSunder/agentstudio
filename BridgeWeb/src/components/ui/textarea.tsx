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
				'flex field-sizing-content min-h-16 w-full resize-none rounded-md border border-input bg-input/20 px-2 py-2 text-sm transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/30 disabled:cursor-not-allowed disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-2 aria-invalid:ring-destructive/20 md:text-xs/relaxed dark:bg-input/30 dark:aria-invalid:border-destructive/50 dark:aria-invalid:ring-destructive/40',
				appearance === 'embedded'
					? 'rounded-none border-0 bg-transparent px-0 py-0 shadow-none focus-visible:border-transparent focus-visible:ring-0 dark:bg-transparent'
					: undefined,
				className,
			)}
			{...props}
		/>
	);
}

export { Textarea };
