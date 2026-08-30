import type { ComponentProps, ReactElement, ReactNode } from 'react';

import { PopoverContent, PopoverTitle } from '../components/ui/popover.js';

export interface BridgeViewerHeaderShelfProps {
	readonly anchor: ComponentProps<typeof PopoverContent>['anchor'];
	readonly ariaLabel: string;
	readonly children: ReactNode;
	readonly finalFocus: ComponentProps<typeof PopoverContent>['finalFocus'];
	readonly testId: string;
}

export function BridgeViewerHeaderShelf(props: BridgeViewerHeaderShelfProps): ReactElement {
	return (
		<PopoverContent
			align="center"
			anchor={props.anchor}
			className="w-[calc(var(--anchor-width)*0.9)] max-w-[var(--available-width)] gap-0 p-2"
			data-testid={props.testId}
			finalFocus={props.finalFocus}
			initialFocus
			motion="shelf"
			side="bottom"
			sideOffset={0}
		>
			<PopoverTitle className="sr-only">{props.ariaLabel}</PopoverTitle>
			{props.children}
		</PopoverContent>
	);
}
