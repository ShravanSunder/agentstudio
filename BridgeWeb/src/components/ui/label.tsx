import * as React from 'react';

import { cn } from '@/lib/utils.js';

function Label({ className, ...props }: React.ComponentProps<'label'>): React.ReactElement {
	return (
		<label
			data-slot="label"
			className={cn(
				'flex items-center gap-2 text-xs font-medium select-none group-data-[disabled=true]:pointer-events-none group-data-[disabled=true]:text-faint-foreground peer-disabled:cursor-not-allowed peer-disabled:text-faint-foreground',
				className,
			)}
			{...props}
		/>
	);
}

export { Label };
