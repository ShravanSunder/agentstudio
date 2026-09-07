import { themeToTreeStyles, type TreeThemeInput, type TreeThemeStyles } from '@pierre/trees';
import type { CSSProperties } from 'react';

import { bridgeDesignPalette } from '../design-tokens/bridge-design-palette.js';

export const bridgeGhosttyCatppuccinTreeTheme = {
	type: 'dark',
	fg: bridgeDesignPalette['--palette-text-primary'],
	bg: bridgeDesignPalette['--palette-neutral-n1'],
	colors: {
		'editor.background': bridgeDesignPalette['--palette-neutral-n1'],
		'editor.foreground': bridgeDesignPalette['--palette-text-primary'],
		'gitDecoration.addedResourceForeground': bridgeDesignPalette['--palette-green'],
		'gitDecoration.deletedResourceForeground': bridgeDesignPalette['--palette-red'],
		'gitDecoration.modifiedResourceForeground': bridgeDesignPalette['--palette-blue'],
	},
} as const satisfies TreeThemeInput;

export const bridgeGhosttyCatppuccinTreeStyles: TreeThemeStyles = themeToTreeStyles(
	bridgeGhosttyCatppuccinTreeTheme,
);

export type BridgeViewerTreeStyle = CSSProperties &
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
		| '--trees-font-family-override'
		| '--trees-font-size-override'
		| '--trees-level-gap-override'
		| '--trees-padding-inline-override'
		| '--trees-git-renamed-color-override',
		number | string
	>;

export const bridgeViewerTreeStyle: BridgeViewerTreeStyle = {
	...bridgeGhosttyCatppuccinTreeStyles,
	backgroundColor: 'var(--sidebar)',
	colorScheme: 'dark',
	color: 'var(--foreground)',
	display: 'block',
	height: '100%',
	'--trees-bg-override': 'var(--sidebar)',
	'--trees-fg-override': 'var(--foreground)',
	'--trees-fg-muted-override': 'var(--faint-foreground)',
	'--trees-bg-muted-override': 'var(--muted)',
	'--trees-search-fg-override': 'var(--foreground)',
	'--trees-search-bg-override': 'var(--surface)',
	'--trees-border-color-override': 'var(--border)',
	'--trees-selected-fg-override': 'var(--foreground)',
	'--trees-selected-bg-override': 'var(--selection)',
	'--trees-selected-focused-border-color-override': 'var(--ring)',
	'--trees-focus-ring-color-override': 'var(--ring)',
	'--trees-font-family-override': 'var(--font-sans)',
	'--trees-font-size-override': '12px',
	'--trees-level-gap-override': '4px',
	'--trees-padding-inline-override': 8,
	'--trees-git-renamed-color-override': 'var(--primary)',
};

export const bridgeViewerTreeUnsafeCSS = `
  [data-file-tree-virtualized-scroll="true"] {
    padding-inline-start: 0;
    padding-inline-end: 2px;
    margin-inline-end: 2px;
    scrollbar-width: thin;
    scrollbar-color: var(--scrollbar-thumb) var(--scrollbar-track);
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar {
    width: var(--scrollbar-size);
    height: var(--scrollbar-size);
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar-track {
    background: var(--scrollbar-track);
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar-thumb {
    border: 1px solid transparent;
    border-radius: 999px;
    background: var(--scrollbar-thumb);
    background-clip: content-box;
  }

  [data-file-tree-virtualized-scroll="true"]::-webkit-scrollbar-thumb:hover {
    background: var(--scrollbar-thumb-hover);
    background-clip: content-box;
  }

  [data-file-tree-search-container][data-open='false'] {
    display: none;
  }

  [data-file-tree-search-container] {
    margin: 0 4px 8px 0;
    padding: 0 4px 8px 1px;
    border-bottom: 1px solid var(--border);
  }

  [role='treeitem'][data-item-path] {
    pointer-events: auto !important;
  }

  [data-file-tree-sticky-overlay-content] {
    box-shadow: var(--shadow-tree-sticky);
  }

  [data-item-type='folder'] {
    color: var(--foreground);
    font-weight: 500;
  }
`;
