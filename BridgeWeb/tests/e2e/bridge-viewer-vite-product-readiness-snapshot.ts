import type { Page } from 'playwright';

interface ProductContentRequestReadinessSnapshotInput {
	readonly contentKind: string;
	readonly descriptor: Readonly<Record<string, unknown>>;
	readonly responseStatus: number | null;
}

interface ProductFileReadinessBrowserSnapshot {
	readonly correlationsContainExpectedSha256: boolean;
	readonly documentVisibilityState: DocumentVisibilityState;
	readonly expectedLineCount: number;
	readonly openFileReady: boolean;
	readonly openPathMatchesTarget: boolean;
	readonly renderedContentState: string | null | undefined;
	readonly renderedLineCount: number;
	readonly renderedPathMatchesTarget: boolean;
}

export async function postMutationFileReadinessFailureSnapshot(props: {
	readonly contentRequests: readonly ProductContentRequestReadinessSnapshotInput[];
	readonly expectedLineCount: number;
	readonly expectedSha256: string;
	readonly page: Page;
	readonly path: string;
}): Promise<Readonly<Record<string, unknown>>> {
	const readiness = await props.page.evaluate(
		({ expectedLineCount, expectedSha256, path }): ProductFileReadinessBrowserSnapshot => {
			const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			const correlationElement = canvas?.querySelector(
				'diffs-container[data-bridge-painted-source-correlations]',
			);
			const encodedCorrelations =
				correlationElement?.getAttribute('data-bridge-painted-source-correlations') ?? '[]';
			return {
				correlationsContainExpectedSha256: encodedCorrelations.includes(expectedSha256),
				documentVisibilityState: document.visibilityState,
				expectedLineCount,
				openFileReady: canvas?.getAttribute('data-worktree-open-file-state') === 'ready',
				openPathMatchesTarget: canvas?.getAttribute('data-worktree-open-file-path') === path,
				renderedContentState: canvas?.getAttribute('data-worktree-rendered-content-state'),
				renderedLineCount: Number(canvas?.getAttribute('data-worktree-rendered-line-count') ?? '0'),
				renderedPathMatchesTarget:
					canvas?.getAttribute('data-worktree-rendered-file-path') === path,
			};
		},
		{
			expectedLineCount: props.expectedLineCount,
			expectedSha256: props.expectedSha256,
			path: props.path,
		},
	);
	const contentRequests = props.contentRequests.map(
		({ contentKind, descriptor, responseStatus }): Readonly<Record<string, unknown>> => ({
			contentKind,
			expectedSha256MatchesMutation: descriptor['expectedSha256'] === props.expectedSha256,
			responseStatus,
		}),
	);
	return { contentRequests, readiness };
}
