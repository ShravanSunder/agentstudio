export const controlGeometryAllowlist = {
	'src/app/bridge-app.css': 13,
	'src/app/bridge-viewer-content-header.tsx': 2,
	'src/app/bridge-viewer-filter-menu.tsx': 8,
	'src/app/bridge-viewer-search-field.tsx': 3,
	'src/app/bridge-viewer-view-settings-menu.tsx': 1,
	'src/file-viewer/bridge-file-viewer-app.browser.startup-suite.tsx': 1,
	'src/review-viewer/chrome/bridge-review-facet-menu.tsx': 1,
	'src/review-viewer/code-view/bridge-code-view-options.ts': 3,
	'src/review-viewer/markdown/bridge-markdown-preview.tsx': 1,
	'src/review-viewer/shell/review-viewer-fallback-shells.tsx': 6,
	'src/review-viewer/shell/review-viewer-shell.tsx': 1,
	'src/review-viewer/workers/pierre/bridge-pierre-worker-pool.tsx': 4,
} as const satisfies Readonly<Record<string, number>>;
