import {
	createContext,
	useContext,
	useRef,
	type ReactElement,
	type ReactNode,
	type RefObject,
} from 'react';

const BridgeViewerContextPanelPortalContext =
	createContext<RefObject<HTMLDivElement | null> | null>(null);

export function BridgeViewerContextPanelProvider(props: {
	readonly children: ReactNode;
}): ReactElement {
	const portalContainerRef = useRef<HTMLDivElement | null>(null);
	return (
		<BridgeViewerContextPanelPortalContext.Provider value={portalContainerRef}>
			{props.children}
		</BridgeViewerContextPanelPortalContext.Provider>
	);
}

export function BridgeViewerContextPanelViewport(props: {
	readonly children: ReactNode;
	readonly testId: string;
}): ReactElement {
	const portalContainerRef = requireBridgeViewerContextPanelPortalContainer();
	return (
		<section
			className="relative h-full min-h-0 min-w-0 overflow-clip"
			data-testid={props.testId}
			ref={portalContainerRef}
		>
			{props.children}
		</section>
	);
}

export function requireBridgeViewerContextPanelPortalContainer(): RefObject<HTMLDivElement | null> {
	const portalContainerRef = useContext(BridgeViewerContextPanelPortalContext);
	if (portalContainerRef === null) {
		throw new Error('Bridge viewer context panels require BridgeViewerContextPanelProvider.');
	}
	return portalContainerRef;
}
