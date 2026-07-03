import type { ReactElement, ReactNode } from 'react';

import {
	ResizableHandle,
	ResizablePanel,
	ResizablePanelGroup,
	useResizablePanelLayout,
} from '../components/ui/resizable.js';

export interface BridgeViewerResizableRailLayoutProps {
	readonly autosaveId: string;
	readonly content: ReactNode;
	readonly contentTestId: string;
	readonly defaultRailSize?: number;
	readonly handleTestId: string;
	readonly isActive?: boolean | undefined;
	readonly maxRailSize?: number;
	readonly minRailSize?: number;
	readonly rail: ReactNode;
	readonly railTestId: string;
}

const defaultBridgeViewerRailMinSize = 20;
const defaultBridgeViewerRailSize = 28;
const defaultBridgeViewerRailMaxSize = 45;
const bridgeViewerResizableContentPanelId = 'bridge-viewer-content-panel';
const bridgeViewerResizableRightRailPanelId = 'bridge-viewer-right-rail-panel';

type BridgeViewerPanelLayout = Record<string, number>;

export function BridgeViewerResizableRailLayout(
	props: BridgeViewerResizableRailLayoutProps,
): ReactElement {
	const minRailSize = props.minRailSize ?? defaultBridgeViewerRailMinSize;
	const defaultRailSize = props.defaultRailSize ?? defaultBridgeViewerRailSize;
	const maxRailSize = props.maxRailSize ?? defaultBridgeViewerRailMaxSize;
	const contentDefaultSize = Math.max(0, 100 - defaultRailSize);
	const contentPanelId = props.contentTestId;
	const railPanelId = props.railTestId;
	const groupId = `${props.autosaveId}-${props.railTestId}`;
	const persistedLayout = useResizablePanelLayout({
		id: props.autosaveId,
		onlySaveAfterUserInteractions: true,
		panelIds: [bridgeViewerResizableContentPanelId, bridgeViewerResizableRightRailPanelId],
	});
	const panelLayout = translatePanelLayout(
		persistedLayout.defaultLayout,
		[bridgeViewerResizableContentPanelId, bridgeViewerResizableRightRailPanelId],
		[contentPanelId, railPanelId],
	);

	if (props.isActive === false) {
		return <div data-bridge-viewer-resizable-layout-active="false">{props.content}</div>;
	}

	return (
		<ResizablePanelGroup
			className="min-h-0 flex-1"
			defaultLayout={panelLayout}
			id={groupId}
			onLayoutChanged={(layout, meta): void => {
				const storageLayout = translatePanelLayout(
					layout,
					[contentPanelId, railPanelId],
					[bridgeViewerResizableContentPanelId, bridgeViewerResizableRightRailPanelId],
				);
				if (storageLayout !== undefined) {
					persistedLayout.onLayoutChanged(storageLayout, meta);
				}
			}}
			orientation="horizontal"
		>
			<ResizablePanel
				className="h-full min-h-0 min-w-0"
				defaultSize={`${contentDefaultSize}%`}
				id={contentPanelId}
				minSize={`${100 - maxRailSize}%`}
				data-testid={props.contentTestId}
			>
				{props.content}
			</ResizablePanel>
			<ResizableHandle
				aria-label="Resize file tree sidebar"
				className="group bg-[var(--bridge-border-subtle)]"
				id={props.handleTestId}
				withHandle
			/>
			<ResizablePanel
				className="h-full min-h-0 min-w-[240px]"
				defaultSize={`${defaultRailSize}%`}
				id={railPanelId}
				maxSize={`${maxRailSize}%`}
				minSize={`${minRailSize}%`}
				data-testid={props.railTestId}
			>
				{props.rail}
			</ResizablePanel>
		</ResizablePanelGroup>
	);
}

function translatePanelLayout(
	layout: BridgeViewerPanelLayout | undefined,
	fromPanelIds: readonly [string, string],
	toPanelIds: readonly [string, string],
): BridgeViewerPanelLayout | undefined {
	if (layout === undefined) {
		return undefined;
	}

	const [fromContentPanelId, fromRailPanelId] = fromPanelIds;
	const [toContentPanelId, toRailPanelId] = toPanelIds;
	const contentPanelSize = layout[fromContentPanelId];
	const railPanelSize = layout[fromRailPanelId];
	if (contentPanelSize === undefined || railPanelSize === undefined) {
		return undefined;
	}

	return {
		[toContentPanelId]: contentPanelSize,
		[toRailPanelId]: railPanelSize,
	};
}
