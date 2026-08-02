import type { CodeViewOptions } from '@pierre/diffs';

import type { BridgeFilesViewSettings } from '../app/bridge-viewer-view-settings.js';
import { bridgeCodeViewOptions } from '../review-viewer/code-view/bridge-code-view-options.js';

export type BridgeFilesCodeViewOptions = Readonly<CodeViewOptions<undefined>>;

export function createBridgeFilesViewSettingsDefaults(
	compatibilityOptions: BridgeFilesCodeViewOptions,
): Readonly<BridgeFilesViewSettings> {
	return Object.freeze({
		lineNumbers: compatibilityOptions.disableLineNumbers !== true,
		wordWrap: compatibilityOptions.overflow === 'wrap',
	});
}

export function deriveBridgeFilesCodeViewOptions(props: {
	readonly compatibilityOptions: BridgeFilesCodeViewOptions;
	readonly viewSettings: BridgeFilesViewSettings;
}): BridgeFilesCodeViewOptions {
	return Object.freeze({
		...props.compatibilityOptions,
		disableLineNumbers: !props.viewSettings.lineNumbers,
		overflow: props.viewSettings.wordWrap ? 'wrap' : 'scroll',
	});
}

export const bridgeFileViewerCodeViewOptions: CodeViewOptions<undefined> = {
	...bridgeCodeViewOptions,
	disableFileHeader: true,
	itemMetrics: {
		paddingBottom: 0,
		paddingTop: 0,
		spacing: 0,
	},
	layout: {
		gap: bridgeCodeViewOptions.layout?.gap ?? 1,
		paddingTop: bridgeCodeViewOptions.layout?.paddingTop ?? 0,
		paddingBottom: 0,
	},
	stickyHeaders: false,
	unsafeCSS: `
		${bridgeCodeViewOptions.unsafeCSS ?? ''}

		[data-file] [data-code] {
			padding-bottom: 0;
			padding-top: 0;
		}
	`,
};
