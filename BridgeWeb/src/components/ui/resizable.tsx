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
	resizeTargetMinimumSize = { coarse: 28, fine: 16 },
	...props
}: ComponentProps<typeof ResizablePanelGroupPrimitive>): ReactElement {
	return (
		<ResizablePanelGroupPrimitive
			data-slot="resizable-panel-group"
			data-panel-group-direction={orientation}
			className={cn('flex h-full w-full data-[panel-group-direction=vertical]:flex-col', className)}
			orientation={orientation}
			resizeTargetMinimumSize={resizeTargetMinimumSize}
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
				'group/resize relative flex w-px shrink-0 items-center justify-center bg-separator outline-none transition-colors data-[separator=hover]:bg-ring data-[separator=active]:bg-ring data-[separator=focus]:bg-ring focus-visible:ring-2 focus-visible:ring-ring aria-[orientation=horizontal]:h-px aria-[orientation=horizontal]:w-full',
				className,
			)}
			{...props}
		>
			{withHandle ? (
				<div className="pointer-events-none z-10 h-8 w-1 rounded-full bg-ring opacity-0 transition-opacity group-data-[separator=hover]/resize:opacity-100 group-data-[separator=active]/resize:opacity-100 group-data-[separator=focus]/resize:opacity-100" />
			) : null}
		</ResizableHandlePrimitive>
	);
}

export { ResizableHandle, ResizablePanel, ResizablePanelGroup };
export { useResizablePanelLayoutPrimitive as useResizablePanelLayout };
