import { FileDiff, FileSpreadsheet } from 'lucide-react';
import type { ReactElement } from 'react';

import {
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSegmentIconButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from '../../app/bridge-viewer-chrome.js';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group.js';

export type BridgeCodeViewFilePresentation = 'diff' | 'open';

export function BridgeCodeViewFilePresentationToggle(props: {
	readonly itemId: string;
	readonly onPresentationChange: (
		itemId: string,
		presentation: BridgeCodeViewFilePresentation,
	) => void;
	readonly presentation: BridgeCodeViewFilePresentation;
}): ReactElement {
	return (
		<ToggleGroup
			aria-label="File presentation"
			className={bridgeViewerChromeSegmentedControlClassName}
			data-testid="bridge-code-view-header-presentation-toggle"
			onValueChange={(presentations): void => {
				const presentation = presentations.at(-1);
				if (presentation === 'diff' || presentation === 'open') {
					props.onPresentationChange(props.itemId, presentation);
				}
			}}
			role="group"
			size="sm"
			value={[props.presentation]}
		>
			<ToggleGroupItem
				aria-label="Diff"
				className={bridgeViewerChromeSegmentIconButtonClassName}
				onClick={(event): void => {
					event.stopPropagation();
				}}
				title="Diff"
				value="diff"
			>
				<FileDiff aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
			</ToggleGroupItem>
			<ToggleGroupItem
				aria-label="Open"
				className={bridgeViewerChromeSegmentIconButtonClassName}
				onClick={(event): void => {
					event.stopPropagation();
				}}
				title="Open"
				value="open"
			>
				<FileSpreadsheet aria-hidden="true" className={bridgeViewerChromeLucideIconClassName} />
			</ToggleGroupItem>
		</ToggleGroup>
	);
}
