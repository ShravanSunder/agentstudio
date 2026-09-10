import { SearchIcon } from 'lucide-react';
import type { ReactElement, Ref } from 'react';

import { Toggle } from '../components/ui/toggle.js';
import {
	bridgeViewerSearchShortcut,
	bridgeViewerShortcutTitle,
} from './bridge-viewer-local-shortcuts.js';

export interface BridgeViewerSearchControlProps {
	readonly isActive: boolean;
	readonly onToggleSearch: () => void;
	readonly searchToggleTestId: string;
	readonly testId: string;
	readonly triggerRef?: Ref<HTMLButtonElement>;
}

export function BridgeViewerSearchControl(props: BridgeViewerSearchControlProps): ReactElement {
	return (
		<div className="relative flex min-w-0 items-center" data-testid={props.testId}>
			<Toggle
				aria-label="Search files"
				pressed={props.isActive}
				size="icon-sm"
				variant="disclosure"
				onClick={props.onToggleSearch}
				data-testid={props.searchToggleTestId}
				title={bridgeViewerShortcutTitle(
					props.isActive ? 'Close file search' : 'Search files',
					bridgeViewerSearchShortcut,
				)}
				ref={props.triggerRef}
			>
				<SearchIcon aria-hidden="true" />
			</Toggle>
		</div>
	);
}
