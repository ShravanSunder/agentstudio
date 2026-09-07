'use client';

import { Drawer as DrawerPrimitive } from '@base-ui/react/drawer';
import * as React from 'react';

import { cn } from '@/lib/utils.js';

interface DrawerContextValue {
	readonly hasSnapPoints: boolean;
	readonly modal: DrawerPrimitive.Root.Props['modal'];
	readonly showSwipeHandle: boolean;
	readonly swipeDirection: NonNullable<DrawerPrimitive.Root.Props['swipeDirection']>;
}

const DrawerContext = React.createContext<DrawerContextValue | null>(null);

function useDrawer(): DrawerContextValue {
	const context = React.useContext(DrawerContext);
	if (context === null) throw new Error('useDrawer must be used within a Drawer.');
	return context;
}

function Drawer({
	modal = true,
	showSwipeHandle = false,
	snapPoints,
	swipeDirection = 'down',
	...props
}: DrawerPrimitive.Root.Props & { readonly showSwipeHandle?: boolean }): React.ReactElement {
	const hasSnapPoints = snapPoints !== undefined && snapPoints.length > 0;
	const contextValue = React.useMemo<DrawerContextValue>(
		() => ({ hasSnapPoints, modal, showSwipeHandle, swipeDirection }),
		[hasSnapPoints, modal, showSwipeHandle, swipeDirection],
	);
	return (
		<DrawerContext.Provider value={contextValue}>
			<DrawerPrimitive.Root
				data-slot="drawer"
				modal={modal}
				snapPoints={snapPoints}
				swipeDirection={swipeDirection}
				{...props}
			/>
		</DrawerContext.Provider>
	);
}

function DrawerTrigger(props: DrawerPrimitive.Trigger.Props): React.ReactElement {
	return <DrawerPrimitive.Trigger data-slot="drawer-trigger" {...props} />;
}

function DrawerClose(props: DrawerPrimitive.Close.Props): React.ReactElement {
	return <DrawerPrimitive.Close data-slot="drawer-close" {...props} />;
}

function DrawerOverlay({
	className,
	...props
}: DrawerPrimitive.Backdrop.Props): React.ReactElement {
	return (
		<DrawerPrimitive.Backdrop
			data-slot="drawer-overlay"
			className={cn(
				'fixed inset-0 z-50 bg-overlay/50 opacity-[calc(1-var(--drawer-swipe-progress))] transition-opacity duration-[var(--motion-fast)] data-ending-style:pointer-events-none data-ending-style:opacity-0 data-starting-style:opacity-0 data-swiping:duration-0',
				className,
			)}
			{...props}
		/>
	);
}

function DrawerSwipeHandle({
	className,
	...props
}: React.ComponentProps<'div'>): React.ReactElement {
	return (
		<div
			aria-hidden="true"
			data-slot="drawer-swipe-handle"
			className={cn(
				'relative z-10 flex shrink-0 cursor-grab transition-opacity duration-[var(--motion-fast)] group-data-[swipe-direction=left]/drawer-popup:order-last group-data-[swipe-direction=up]/drawer-popup:order-last active:cursor-grabbing',
				className,
			)}
			{...props}
		/>
	);
}

type DrawerContentPositioning = 'container' | 'viewport';
type DrawerFrame = 'none' | 'context-panel';

function DrawerContent({
	className,
	children,
	frame = 'none',
	portalContainer,
	positioning = 'viewport',
	viewportClassName,
	...props
}: DrawerPrimitive.Popup.Props & {
	readonly portalContainer?: DrawerPrimitive.Portal.Props['container'];
	readonly frame?: DrawerFrame;
	readonly positioning?: DrawerContentPositioning;
	readonly viewportClassName?: string;
}): React.ReactElement {
	const { hasSnapPoints, modal, showSwipeHandle, swipeDirection } = useDrawer();
	const swipeAxis = swipeDirection === 'down' || swipeDirection === 'up' ? 'y' : 'x';
	const isContainerPositioned = positioning === 'container';
	return (
		<DrawerPrimitive.Portal
			container={portalContainer}
			data-slot="drawer-portal"
			className={isContainerPositioned ? 'pointer-events-none absolute inset-0 z-50' : undefined}
		>
			{modal === true ? <DrawerOverlay data-snap-points={hasSnapPoints ? '' : undefined} /> : null}
			<DrawerPrimitive.Viewport
				data-modal={modal}
				data-slot="drawer-viewport"
				className={cn(
					'pointer-events-none inset-0 z-50 select-none data-[modal=true]:pointer-events-auto',
					isContainerPositioned ? 'absolute' : 'fixed',
					viewportClassName,
				)}
			>
				<DrawerPrimitive.Popup
					data-slot="drawer-popup"
					data-snap-points={hasSnapPoints ? '' : undefined}
					data-swipe-axis={swipeAxis}
					className={cn(
						'group/drawer-popup pointer-events-auto z-50 m-(--drawer-inset,0px) flex h-(--drawer-content-height) max-h-(--drawer-content-max-height,none) min-h-0 w-(--drawer-content-width,auto) transform-[translate3d(var(--translate-x,0px),var(--translate-y,0px),0)_scale(var(--stack-scale))] flex-col transition-[transform,height,opacity,filter] duration-[var(--motion-fast)] ease-out will-change-transform outline-none select-none [interpolate-size:allow-keywords]',
						isContainerPositioned ? 'absolute' : 'fixed',
						'data-nested-drawer-open:overflow-hidden data-nested-drawer-open:brightness-95',
						'after:pointer-events-none after:absolute after:bg-(--drawer-bleed-background,var(--color-popover)) data-[swipe-axis=x]:after:inset-y-0 data-[swipe-axis=x]:after:w-(--bleed) data-[swipe-axis=y]:after:inset-x-0 data-[swipe-axis=y]:after:h-(--bleed) data-[swipe-direction=down]:after:top-full data-[swipe-direction=left]:after:right-full data-[swipe-direction=right]:after:left-full data-[swipe-direction=up]:after:bottom-full',
						'[--drawer-content-height:var(--drawer-height,auto)] data-[swipe-axis=x]:[--drawer-content-width:75%] data-[swipe-axis=y]:[--drawer-content-max-height:calc(100dvh-6rem)] data-[swipe-axis=x]:sm:[--drawer-content-width:24rem]',
						'[--bleed:3rem] [--peek:1rem] [--stack-height:var(--drawer-frontmost-height,var(--drawer-height,0px))] [--stack-peek-offset:max(0px,calc((var(--nested-drawers)-var(--stack-progress))*var(--peek)))] [--stack-progress:clamp(0,var(--drawer-swipe-progress),1)] [--stack-scale-base:max(0,calc(1-(var(--nested-drawers)*var(--stack-step))))] [--stack-scale:clamp(0,calc(var(--stack-scale-base)+(var(--stack-step)*var(--stack-progress))),1)] [--stack-shrink:calc(1-var(--stack-scale))] [--stack-step:0.05]',
						'data-ending-style:transform-(--closed-transform) data-ending-style:opacity-[0.9999] data-starting-style:transform-(--closed-transform) data-swiping:duration-0',
						frame === 'context-panel'
							? 'rounded-xl border border-popover-border bg-popover text-popover-foreground shadow-context-panel'
							: undefined,
						'data-[swipe-axis=y]:inset-x-0 data-[swipe-axis=y]:data-nested-drawer-open:h-(--stack-height)',
						'data-[swipe-axis=x]:inset-y-0 data-[swipe-axis=x]:flex-row',
						'data-[swipe-direction=down]:bottom-0 data-[swipe-direction=down]:origin-bottom data-[swipe-direction=down]:[--closed-transform:translate3d(0,calc(100%+var(--drawer-inset,0px)+2px),0)] data-[swipe-direction=down]:[--translate-y:calc(var(--drawer-snap-point-offset,0px)+var(--drawer-swipe-movement-y)-var(--stack-peek-offset)-(var(--stack-shrink)*var(--stack-height)))]',
						'data-[swipe-direction=up]:top-0 data-[swipe-direction=up]:origin-top data-[swipe-direction=up]:[--closed-transform:translate3d(0,calc(-100%-var(--drawer-inset,0px)-2px),0)] data-[swipe-direction=up]:[--translate-y:calc(var(--drawer-snap-point-offset,0px)+var(--drawer-swipe-movement-y)+var(--stack-peek-offset)+(var(--stack-shrink)*var(--stack-height)))]',
						'data-[swipe-direction=left]:left-0 data-[swipe-direction=left]:origin-left data-[swipe-direction=left]:[--closed-transform:translate3d(calc(-100%-var(--drawer-inset,0px)-2px),0,0)] data-[swipe-direction=left]:[--translate-x:calc(var(--drawer-swipe-movement-x)+var(--stack-peek-offset)+(var(--stack-shrink)*100%))]',
						'data-[swipe-direction=right]:right-0 data-[swipe-direction=right]:origin-right data-[swipe-direction=right]:[--closed-transform:translate3d(calc(100%+var(--drawer-inset,0px)+2px),0,0)] data-[swipe-direction=right]:[--translate-x:calc(var(--drawer-swipe-movement-x)-var(--stack-peek-offset)-(var(--stack-shrink)*100%))]',
						className,
					)}
					{...props}
				>
					{showSwipeHandle ? <DrawerSwipeHandle /> : null}
					<DrawerPrimitive.Content
						data-slot="drawer-content"
						className="flex min-h-0 flex-1 flex-col overflow-hidden overscroll-contain rounded-[inherit] transition-opacity duration-[var(--motion-fast)] select-text group-data-swiping/drawer-popup:select-none"
					>
						{children}
					</DrawerPrimitive.Content>
				</DrawerPrimitive.Popup>
			</DrawerPrimitive.Viewport>
		</DrawerPrimitive.Portal>
	);
}

function DrawerHeader({ className, ...props }: React.ComponentProps<'div'>): React.ReactElement {
	return (
		<div
			data-slot="drawer-header"
			className={cn(
				'flex shrink-0 flex-col border-b border-border p-2 text-xs font-medium text-foreground [&_svg]:size-3 [&_svg]:shrink-0',
				className,
			)}
			{...props}
		/>
	);
}

function DrawerFooter({ className, ...props }: React.ComponentProps<'div'>): React.ReactElement {
	return (
		<div
			data-slot="drawer-footer"
			className={cn(
				'mt-auto flex shrink-0 items-center justify-end gap-2 border-t border-border p-2',
				className,
			)}
			{...props}
		/>
	);
}

function DrawerTitle({ className, ...props }: DrawerPrimitive.Title.Props): React.ReactElement {
	return (
		<DrawerPrimitive.Title
			data-slot="drawer-title"
			className={cn('font-heading', className)}
			{...props}
		/>
	);
}

function DrawerDescription({
	className,
	...props
}: DrawerPrimitive.Description.Props): React.ReactElement {
	return (
		<DrawerPrimitive.Description
			data-slot="drawer-description"
			className={cn('text-balance', className)}
			{...props}
		/>
	);
}

export {
	Drawer,
	DrawerClose,
	DrawerContent,
	DrawerDescription,
	DrawerFooter,
	DrawerHeader,
	DrawerOverlay,
	DrawerSwipeHandle,
	DrawerTitle,
	DrawerTrigger,
};
