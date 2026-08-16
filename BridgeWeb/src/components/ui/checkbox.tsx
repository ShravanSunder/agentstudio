import { Checkbox as CheckboxPrimitive } from '@base-ui/react/checkbox';
import { CheckIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils';

function Checkbox({ className, ...props }: CheckboxPrimitive.Root.Props): ReactElement {
	return (
		<CheckboxPrimitive.Root
			data-slot="checkbox"
			className={cn(
				'peer relative flex size-3.5 shrink-0 items-center justify-center rounded-[3px] border border-[var(--bridge-border-opaque)] bg-[var(--bridge-header-control-bg)] text-primary-foreground transition-shadow outline-none after:absolute after:-inset-x-2 after:-inset-y-1.5 focus-visible:border-[var(--bridge-focus-border)] focus-visible:ring-2 focus-visible:ring-[var(--bridge-focus-ring)] disabled:cursor-not-allowed disabled:opacity-50 data-checked:border-primary data-checked:bg-primary',
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
