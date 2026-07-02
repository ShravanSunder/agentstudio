import type { MouseEventHandler, ReactElement, ReactNode } from 'react';

import { cn } from './class-name.js';

export type BridgeViewerRightRailDataAttributes = Readonly<
	Record<`data-${string}`, string | undefined>
>;

export interface BridgeViewerRightRailShellProps {
	readonly ariaLabel?: string;
	readonly body: ReactNode;
	readonly bodyAriaLabel?: string;
	readonly bodyClassName?: string;
	readonly bodyDataAttributes?: BridgeViewerRightRailDataAttributes;
	readonly bodyElement?: 'div' | 'section';
	readonly bodyOnClick?: MouseEventHandler<HTMLElement>;
	readonly bodyTestId: string;
	readonly border: 'opaque' | 'subtle';
	readonly className?: string;
	readonly headerTestId?: string;
	readonly layout: 'grid' | 'stack';
	readonly rootDataAttributes?: BridgeViewerRightRailDataAttributes;
	readonly testId: string;
	readonly toolbar: ReactNode;
	readonly toolbarBelow?: ReactNode;
	readonly toolbarFooter?: ReactNode;
}

export function BridgeViewerRightRailShell(props: BridgeViewerRightRailShellProps): ReactElement {
	const BodyElement = props.bodyElement ?? 'div';

	return (
		<aside
			aria-label={props.ariaLabel}
			className={cn(
				'min-h-0 min-w-0 border-l bg-[var(--bridge-surface-bg)]',
				props.border === 'opaque'
					? 'border-[var(--bridge-border-opaque)]'
					: 'border-[var(--bridge-border-subtle)]',
				props.layout === 'grid'
					? 'grid grid-rows-[auto_minmax(0,1fr)]'
					: 'order-last flex flex-col',
				props.className,
			)}
			{...props.rootDataAttributes}
			data-testid={props.testId}
		>
			<header
				className={props.toolbarBelow === undefined ? undefined : 'grid grid-rows-[auto_auto]'}
				data-testid={props.headerTestId}
			>
				{props.toolbar}
				{props.toolbarBelow}
				{props.toolbarFooter}
			</header>
			<BodyElement
				aria-label={props.bodyAriaLabel}
				className={props.bodyClassName}
				{...props.bodyDataAttributes}
				data-testid={props.bodyTestId}
				onClick={props.bodyOnClick}
			>
				{props.body}
			</BodyElement>
		</aside>
	);
}
