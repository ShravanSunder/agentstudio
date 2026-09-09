'use client';

import { Switch as SwitchPrimitive } from '@base-ui/react/switch';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

const switchTrackClassName =
	'relative inline-flex h-4 w-7 shrink-0 rounded-full border border-input bg-field-background outline-none transition-colors data-checked:border-primary data-checked:bg-primary/15 data-disabled:pointer-events-none data-disabled:cursor-not-allowed data-disabled:border-input data-disabled:bg-muted data-disabled:opacity-100';
const switchThumbClassName =
	'absolute top-px left-px size-3 rounded-full bg-muted-foreground transition-transform duration-[var(--motion-fast)] data-checked:translate-x-3 data-checked:bg-primary data-disabled:bg-faint-foreground motion-reduce:transition-none';

function Switch({ className, ...props }: SwitchPrimitive.Root.Props): ReactElement {
	return (
		<SwitchPrimitive.Root
			data-slot="switch"
			className={cn(
				switchTrackClassName,
				'focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring',
				className,
			)}
			{...props}
		>
			<SwitchPrimitive.Thumb data-slot="switch-thumb" className={switchThumbClassName} />
		</SwitchPrimitive.Root>
	);
}

function SwitchIndicator(props: { readonly checked: boolean }): ReactElement {
	return (
		<span
			aria-hidden="true"
			className={cn(switchTrackClassName, 'pointer-events-none')}
			data-checked={props.checked ? '' : undefined}
			data-slot="switch-indicator"
		>
			<span
				className={switchThumbClassName}
				data-checked={props.checked ? '' : undefined}
				data-slot="switch-thumb"
			/>
		</span>
	);
}

export { Switch, SwitchIndicator };
