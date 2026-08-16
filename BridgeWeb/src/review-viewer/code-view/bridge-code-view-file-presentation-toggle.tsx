import { FileDiff, FileSpreadsheet } from 'lucide-react';
import type { ReactElement } from 'react';

import {
	bridgeViewerChromeLucideIconClassName,
	bridgeViewerChromeSegmentIconButtonClassName,
	bridgeViewerChromeSegmentedControlClassName,
} from '../../app/bridge-viewer-chrome.js';
import { ToggleGroup, ToggleGroupItem } from '../../components/ui/toggle-group.js';
import { cn } from '../../lib/utils.js';

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
			className={cn(bridgeViewerChromeSegmentedControlClassName, 'h-8')}
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
				className={cn(bridgeViewerChromeSegmentIconButtonClassName, 'h-7 min-h-7 w-7 min-w-7')}
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
				className={cn(bridgeViewerChromeSegmentIconButtonClassName, 'h-7 min-h-7 w-7 min-w-7')}
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
