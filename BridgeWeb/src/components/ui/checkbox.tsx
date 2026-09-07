import { Checkbox as CheckboxPrimitive } from '@base-ui/react/checkbox';
import { CheckIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils';

function Checkbox({ className, ...props }: CheckboxPrimitive.Root.Props): ReactElement {
	return (
		<CheckboxPrimitive.Root
			data-slot="checkbox"
			className={cn(
				'peer relative flex size-3.5 shrink-0 items-center justify-center rounded-sm border border-input bg-transparent text-primary-foreground transition-shadow outline-none after:absolute after:-inset-x-2 after:-inset-y-1.5 focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/30 disabled:cursor-not-allowed disabled:border-input disabled:bg-transparent disabled:text-faint-foreground disabled:opacity-100 data-checked:border-primary data-checked:bg-primary disabled:data-checked:border-input disabled:data-checked:bg-muted',
				className,
			)}
			{...props}
		>
			<CheckboxPrimitive.Indicator
				data-slot="checkbox-indicator"
				className="grid place-content-center text-current transition-none [&>svg]:size-2.5"
			>
				<CheckIcon />
			</CheckboxPrimitive.Indicator>
		</CheckboxPrimitive.Root>
	);
}

export { Checkbox };
