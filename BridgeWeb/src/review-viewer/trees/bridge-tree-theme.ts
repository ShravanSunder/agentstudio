import { themeToTreeStyles, type TreeThemeInput, type TreeThemeStyles } from '@pierre/trees';
import type { CSSProperties } from 'react';

export const bridgeCatppuccinMochaTreeTheme = {
	type: 'dark',
	fg: '#CDD6F4',
	bg: '#1E1E2E',
	colors: {
		descriptionForeground: '#6C7086',
		focusBorder: '#B4BEFE',
		'editor.background': '#1E1E2E',
		'editor.foreground': '#CDD6F4',
		'gitDecoration.addedResourceForeground': '#A6E3A1',
		'gitDecoration.deletedResourceForeground': '#F38BA8',
		'gitDecoration.modifiedResourceForeground': '#89B4FA',
		'input.background': '#181825',
		'list.activeSelectionBackground': '#45475A',
		'list.activeSelectionForeground': '#CDD6F4',
		'list.focusOutline': '#00000000',
		'list.hoverBackground': '#313244',
		'sideBar.background': '#181825',
		'sideBar.foreground': '#CDD6F4',
		'sideBarSectionHeader.foreground': '#BAC2DE',
	},
} as const satisfies TreeThemeInput;

export const bridgeCatppuccinMochaTreeStyles: TreeThemeStyles = themeToTreeStyles(
	bridgeCatppuccinMochaTreeTheme,
);

export type BridgeReviewTreeStyle = CSSProperties &
	Record<
		| '--trees-bg-override'
		| '--trees-fg-override'
		| '--trees-fg-muted-override'
		| '--trees-bg-muted-override'
		| '--trees-search-fg-override'
		| '--trees-search-bg-override'
		| '--trees-border-color-override'
		| '--trees-selected-fg-override'
		| '--trees-selected-bg-override'
		| '--trees-selected-focused-border-color-override'
		| '--trees-focus-ring-color-override'
		| '--trees-padding-inline-override'
		| '--trees-git-renamed-color-override',
		number | string
	>;

export const bridgeReviewTreeStyle: BridgeReviewTreeStyle = {
	...bridgeCatppuccinMochaTreeStyles,
	colorScheme: 'dark',
	display: 'block',
	height: '100%',
	'--trees-bg-override': 'var(--bridge-surface-bg)',
	'--trees-fg-override': 'var(--bridge-text-primary)',
	'--trees-fg-muted-override': 'var(--bridge-text-muted)',
	'--trees-bg-muted-override': 'var(--bridge-surface-raised-bg)',
	'--trees-search-fg-override': 'var(--bridge-text-primary)',
	'--trees-search-bg-override': 'var(--bridge-header-control-bg)',
	'--trees-border-color-override': 'var(--bridge-border-subtle)',
	'--trees-selected-fg-override': 'var(--bridge-text-primary)',
	'--trees-selected-bg-override': 'color-mix(in oklch, var(--bridge-accent) 18%, transparent)',
	'--trees-selected-focused-border-color-override':
		'color-mix(in oklch, var(--bridge-accent) 82%, white 8%)',
	'--trees-focus-ring-color-override': 'var(--bridge-accent)',
	'--trees-padding-inline-override': 8,
	'--trees-git-renamed-color-override': 'var(--bridge-accent)',
};

export const bridgeReviewTreeUnsafeCSS = `
  [data-file-tree-virtualized-scroll="true"] {
    padding-inline-start: 0;
    padding-inline-end: 2px;
    margin-inline-end: 2px;
    scrollbar-width: thin;
    scrollbar-color: rgb(205 214 244 / 0.24) transparent;
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar {
    width: 4px;
    height: 4px;
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar-track {
    background: transparent;
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar-thumb {
    border-radius: 999px;
    background: rgb(205 214 244 / 0.22);
  }

  [data-file-tree-search-container][data-open='false'] {
    display: none;
  }

  [data-file-tree-search-container] {
    margin: 0 4px 8px 0;
    padding: 0 4px 8px 1px;
    border-bottom: 1px solid var(--bridge-border-subtle);
  }

  [data-file-tree-sticky-overlay-content] {
    box-shadow: 0 2px 4px -4px rgb(0 0 0 / 90%);
  }

  [data-item-type='folder'] {
    color: var(--bridge-text-primary);
    font-weight: 500;
  }
`;
