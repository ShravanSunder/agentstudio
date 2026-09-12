import type { ComponentProps, ReactElement, ReactNode } from 'react';

import { DrawerContent } from '../components/ui/drawer.js';
import { requireBridgeViewerContextPanelPortalContainer } from './bridge-viewer-context-panel-host.js';

export interface BridgeViewerContextPanelProps {
	readonly ariaLabel: string;
	readonly children: ReactNode;
	readonly finalFocus: ComponentProps<typeof DrawerContent>['finalFocus'];
	readonly height?: 'full' | 'half';
	readonly width?: 'default' | 'wide';
	readonly initialFocus?: ComponentProps<typeof DrawerContent>['initialFocus'];
	readonly inert?: boolean;
	readonly testId: string;
}

export function BridgeViewerContextPanel(props: BridgeViewerContextPanelProps): ReactElement {
	const portalContainerRef = requireBridgeViewerContextPanelPortalContainer();
	return (
		<DrawerContent
			aria-label={props.ariaLabel}
			className={`data-[swipe-axis=x]:top-2 data-[swipe-axis=x]:[--bleed:0px] ${props.width === 'wide' ? 'data-[swipe-axis=x]:[--drawer-content-width:min(480px,calc(100%_-_32px))] data-[swipe-axis=x]:sm:[--drawer-content-width:min(480px,calc(100%_-_32px))]' : 'data-[swipe-axis=x]:[--drawer-content-width:min(384px,calc(100%_-_32px))] data-[swipe-axis=x]:sm:[--drawer-content-width:min(384px,calc(100%_-_32px))]'} data-[swipe-direction=right]:right-2 ${
				props.height === 'full'
					? 'data-[swipe-axis=x]:bottom-2'
					: 'data-[swipe-axis=x]:bottom-auto data-[swipe-axis=x]:h-1/2'
			}`}
			data-testid={props.testId}
			frame="context-panel"
			finalFocus={props.finalFocus}
			initialFocus={props.initialFocus ?? true}
			inert={props.inert}
			portalContainer={portalContainerRef}
			positioning="container"
		>
			{props.children}
		</DrawerContent>
	);
}
