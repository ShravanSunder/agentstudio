import type { CodeViewOptions } from '@pierre/diffs';

import type {
	BridgeReviewChangeIndicators,
	BridgeReviewViewSettings,
} from '../../app/bridge-viewer-view-settings.js';
import { bridgePierreDarkThemeName } from './bridge-code-view-theme.js';

export type BridgeReviewCodeViewOptions = Readonly<CodeViewOptions<undefined>>;

export function createBridgeReviewViewSettingsDefaults(
	compatibilityOptions: BridgeReviewCodeViewOptions,
): Readonly<BridgeReviewViewSettings> {
	return Object.freeze({
		changeBackgrounds: compatibilityOptions.disableBackground !== true,
		changeIndicators: bridgeReviewChangeIndicatorsFromCodeViewOptions(compatibilityOptions),
		diffLayout: compatibilityOptions.diffStyle ?? 'split',
		lineNumbers: compatibilityOptions.disableLineNumbers !== true,
		wordWrap: compatibilityOptions.overflow === 'wrap',
	});
}

export function deriveBridgeReviewCodeViewOptions(props: {
	readonly compatibilityOptions: BridgeReviewCodeViewOptions;
	readonly viewSettings: BridgeReviewViewSettings;
}): BridgeReviewCodeViewOptions {
	return Object.freeze({
		...props.compatibilityOptions,
		diffIndicators:
			props.viewSettings.changeIndicators === 'symbols'
				? 'classic'
				: props.viewSettings.changeIndicators,
		diffStyle: props.viewSettings.diffLayout,
		disableBackground: !props.viewSettings.changeBackgrounds,
		disableLineNumbers: !props.viewSettings.lineNumbers,
		overflow: props.viewSettings.wordWrap ? 'wrap' : 'scroll',
	});
}

function bridgeReviewChangeIndicatorsFromCodeViewOptions(
	compatibilityOptions: BridgeReviewCodeViewOptions,
): BridgeReviewChangeIndicators {
	if (compatibilityOptions.diffIndicators === 'classic') return 'symbols';
	return compatibilityOptions.diffIndicators ?? 'bars';
}

export const bridgeCodeViewOptions: CodeViewOptions<undefined> = {
	theme: {
		dark: bridgePierreDarkThemeName,
		light: bridgePierreDarkThemeName,
	},
	themeType: 'dark',
	// F1 height truth: give Pierre estimate metrics that match the rendered CSS instead of
	// its 20/44/8 defaults, so an unhydrated item reserves the height it will measure. The
	// header estimate must match the `[data-diffs-header] { height: 40px }` below; the
	// line height matches Pierre's own `--diffs-line-height` default (20px), and spacing
	// stays at the package default because the layout does not override hunk/file padding.
	itemMetrics: {
		lineHeight: 20,
		diffHeaderHeight: 40,
		spacing: 8,
	},
	diffStyle: 'split',
	diffIndicators: 'bars',
	overflow: 'wrap',
	useTokenTransformer: false,
	tokenizeMaxLineLength: 20_000,
	lineDiffType: 'word',
	maxLineDiffLength: 1000,
	hunkSeparators: 'line-info-basic',
	collapsedContextThreshold: 2,
	expansionLineCount: 100,
	expandUnchanged: false,
	disableVirtualizationBuffers: false,
	stickyHeaders: true,
	layout: {
		paddingTop: 0,
		paddingBottom: 0,
		gap: 1,
	},
	unsafeCSS: `
		[data-diffs-header] {
			--diffs-addition-base: var(--bridge-added);
			--diffs-deletion-base: var(--bridge-deleted);
			--diffs-modified-base: var(--bridge-accent);
			--diffs-fg: var(--bridge-text-primary);
			--diffs-fg-number: var(--bridge-text-muted);
			container-type: scroll-state;
			container-name: bridge-code-view-sticky-header;
			background-color: var(--bridge-surface-bg);
			cursor: default;
			height: 40px;
			min-height: 40px;
			user-select: none;
		}

		[data-diffs-header] * {
			cursor: default;
			user-select: none;
		}

		[data-diffs-header] button,
		[data-diffs-header] [role='button'] {
			cursor: pointer;
		}

		[data-line-annotation][data-selected-line],
		[data-gutter-buffer='annotation'][data-selected-line] {
			--mix-selection-light: 86%;
			--mix-selection-dark: 86%;
		}

		[data-diffs-header] [data-additions-count],
		[data-diffs-header] [data-deletions-count] {
			display: none;
		}

		[data-diffs-header='default'] {
			align-items: center;
			border-block: 1px solid var(--bridge-border-subtle);
			color: var(--bridge-text-secondary);
			padding-inline: 12px;
		}

		[data-diffs-header='default'] [data-title],
		[data-diffs-header='default'] [data-prev-name] {
			color: var(--bridge-text-secondary);
			font-weight: 500;
		}

		@container bridge-code-view-sticky-header scroll-state(stuck: top) {
			[data-diffs-header]::after {
				position: absolute;
				bottom: -1px;
				left: 0;
				width: 100%;
				height: 1px;
				content: '';
				background-color: var(--bridge-border-opaque);
			}
		}
	`,
};
