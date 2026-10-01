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
		statusLabel: failed ? "Couldn't apply update" : 'File changed',
		tooltip: failed
			? 'Save or close the protected annotation editor, then apply again.'
			: 'Keep the draft and load the latest file.',
	};
}
