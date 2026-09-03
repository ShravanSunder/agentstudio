'use client';

import { Collapsible as CollapsiblePrimitive } from '@base-ui/react/collapsible';
import type { ReactElement } from 'react';

import { cn } from '@/lib/utils.js';

function Collapsible(props: CollapsiblePrimitive.Root.Props): ReactElement {
	return <CollapsiblePrimitive.Root data-slot="collapsible" {...props} />;
}

function CollapsibleTrigger(props: CollapsiblePrimitive.Trigger.Props): ReactElement {
	return <CollapsiblePrimitive.Trigger data-slot="collapsible-trigger" {...props} />;
}

function CollapsibleContent({
	className,
	...props
}: CollapsiblePrimitive.Panel.Props): ReactElement {
	return (
		<CollapsiblePrimitive.Panel
			data-slot="collapsible-content"
			className={cn(
				'h-[var(--collapsible-panel-height)] overflow-hidden transition-[height] duration-200 ease-out',
				'data-ending-style:h-0 data-ending-style:duration-150 data-starting-style:h-0',
				'motion-reduce:transition-none',
				className,
			)}
			{...props}
		/>
	);
}

export { Collapsible, CollapsibleContent, CollapsibleTrigger };
