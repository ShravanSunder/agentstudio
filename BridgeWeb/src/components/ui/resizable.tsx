import type { ComponentProps, ReactElement } from 'react';
import {
	Group as ResizablePanelGroupPrimitive,
	Panel as ResizablePanelPrimitive,
	Separator as ResizableHandlePrimitive,
	useDefaultLayout as useResizablePanelLayoutPrimitive,
} from 'react-resizable-panels';

import { cn } from '@/lib/utils';

function ResizablePanelGroup({
	className,
	orientation = 'horizontal',
	...props
}: ComponentProps<typeof ResizablePanelGroupPrimitive>): ReactElement {
	return (
		<ResizablePanelGroupPrimitive
			data-slot="resizable-panel-group"
			data-panel-group-direction={orientation}
			className={cn('flex h-full w-full data-[panel-group-direction=vertical]:flex-col', className)}
			orientation={orientation}
			{...props}
		/>
	);
}

function ResizablePanel(props: ComponentProps<typeof ResizablePanelPrimitive>): ReactElement {
	return <ResizablePanelPrimitive data-slot="resizable-panel" {...props} />;
}

function ResizableHandle({
	className,
	withHandle = false,
	...props
}: ComponentProps<typeof ResizableHandlePrimitive> & {
	readonly withHandle?: boolean;
}): ReactElement {
	return (
		<ResizableHandlePrimitive
			data-slot="resizable-handle"
			className={cn(
				'relative flex w-px shrink-0 items-center justify-center bg-border outline-none transition-colors hover:bg-ring focus-visible:bg-ring focus-visible:ring-2 focus-visible:ring-ring/30 data-[resize-handle-state=drag]:bg-ring data-[panel-group-direction=vertical]:h-px data-[panel-group-direction=vertical]:w-full',
				className,
			)}
			{...props}
		>
			{withHandle ? (
				<div className="z-10 h-8 w-1 rounded-full bg-border transition-colors group-hover:bg-ring" />
			) : null}
		</ResizableHandlePrimitive>
	);
}

export { ResizableHandle, ResizablePanel, ResizablePanelGroup };
export { useResizablePanelLayoutPrimitive as useResizablePanelLayout };
