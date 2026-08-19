export function bridgeViewerViteProductFileUrl(origin: string, path?: string): string {
	const url = new URL('/', origin);
	url.searchParams.set('fixture', 'worktree');
	url.searchParams.set('scenario', 'current-worktree');
	url.searchParams.set('viewer', 'file');
	url.searchParams.set('workers', 'on');
	if (path !== undefined) url.searchParams.set('path', path);
	return url.toString();
}

export function bridgeViewerViteProductReviewUrl(origin: string): string {
	const url = new URL(bridgeViewerViteProductFileUrl(origin));
	url.searchParams.set('viewer', 'review');
	return url.toString();
}
