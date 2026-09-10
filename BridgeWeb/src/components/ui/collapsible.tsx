'use client';

import { Collapsible as CollapsiblePrimitive } from '@base-ui/react/collapsible';
import { ChevronRightIcon } from 'lucide-react';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

import { Button } from './button.js';

function Collapsible(props: CollapsiblePrimitive.Root.Props): ReactElement {
	return <CollapsiblePrimitive.Root data-slot="collapsible" {...props} />;
}

function CollapsibleTrigger(props: CollapsiblePrimitive.Trigger.Props): ReactElement {
	return <CollapsiblePrimitive.Trigger data-slot="collapsible-trigger" {...props} />;
}

/** Section-heading hierarchy with the same action and focus recipe as other controls. */
function CollapsibleHeading({
	children,
	...props
}: Omit<CollapsiblePrimitive.Trigger.Props, 'render'>): ReactElement {
	return (
		<h3>
			<CollapsibleTrigger
				{...props}
				render={
					<Button
						size="sm"
						variant="ghost"
						className="group w-full justify-between px-0 text-base"
					/>
				}
			>
				{children}
				<ChevronRightIcon
					aria-hidden="true"
					className="transition-transform group-aria-expanded:rotate-90"
				/>
			</CollapsibleTrigger>
		</h3>
	);
}

function CollapsibleContent({
	className,
	...props
}: CollapsiblePrimitive.Panel.Props): ReactElement {
	return (
		<CollapsiblePrimitive.Panel
			data-slot="collapsible-content"
			className={cn(
				'h-[var(--collapsible-panel-height)] overflow-hidden transition-[height] duration-[var(--motion-standard)] ease-out',
				'data-ending-style:h-0 data-ending-style:duration-[var(--motion-fast)] data-starting-style:h-0',
				'motion-reduce:transition-none',
				className,
			)}
			{...props}
		/>
	);
}

export { Collapsible, CollapsibleContent, CollapsibleHeading, CollapsibleTrigger };
