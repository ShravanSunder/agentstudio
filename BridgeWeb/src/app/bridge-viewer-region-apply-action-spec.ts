import { RefreshCwIcon, type LucideIcon } from 'lucide-react';

export interface BridgeViewerRegionApplyActionSpec {
	readonly accessibleName: string;
	readonly label: string;
	readonly icon: LucideIcon;
	readonly tooltip: string;
	readonly statusLabel: string;
}

export function bridgeViewerRegionApplyActionSpec(
	surface: 'file' | 'markdown',
	failed: boolean,
): BridgeViewerRegionApplyActionSpec {
	return {
		accessibleName: surface === 'file' ? 'Update file' : 'Update Markdown file',
		label: 'Apply now',
		icon: RefreshCwIcon,
		statusLabel: failed ? 'Update failed' : 'File changed',
		tooltip: failed
			? 'Finish or cancel the open annotation, then retry.'
			: 'Keep the draft and load the latest file.',
	};
}
