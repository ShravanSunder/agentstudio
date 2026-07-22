import type { Page } from 'playwright';

import { worktreeDevServerUrl } from './config.ts';
import type {
	WorktreeFileDescriptor,
	WorktreeFileSharedShellProof,
	WorktreeFileSubstituteGuardProof,
} from './types.ts';

export async function assertNoStandaloneWorktreeFileApp(
	page: Page,
): Promise<WorktreeFileSubstituteGuardProof> {
	const standaloneWorktreeFileAppCount = await page
		.locator('[data-testid="worktree-file-app"]')
		.count();
	const reviewEmptyShellCount = await page.evaluate((): number => {
		const emptyShells = Array.from(
			document.querySelectorAll('[data-testid="bridge-review-empty-shell"]'),
		).filter((element): element is HTMLElement => element instanceof HTMLElement);
		return emptyShells.filter((element): boolean => {
			const reviewModeHost = element.closest('[data-testid="bridge-viewer-mode-host-review"]');
			const reviewModeIsActive =
				reviewModeHost instanceof HTMLElement &&
				reviewModeHost.getAttribute('data-bridge-viewer-mode-active') === 'true';
			const rect = element.getBoundingClientRect();
			const style = window.getComputedStyle(element);
			return (
				reviewModeIsActive &&
				style.display !== 'none' &&
				style.visibility !== 'hidden' &&
				rect.width > 0 &&
				rect.height > 0
			);
		}).length;
	});
	if (standaloneWorktreeFileAppCount > 0) {
		throw new Error(
			'Gate 0.a forbids standalone WorktreeFileApp; expected shared BridgeViewer FileViewer shell',
		);
	}
	if (reviewEmptyShellCount > 0) {
		throw new Error('Expected Worktree/File route to avoid an active Review empty shell');
	}
	return {
		reviewEmptyShellCount,
		standaloneWorktreeFileAppCount,
	};
}

export async function assertObservedWorktreeDevServerUrl(page: Page): Promise<{
	readonly locationHref: string;
	readonly pageUrl: string;
}> {
	const pageUrl = page.url();
	const locationHref = await page.evaluate(() => window.location.href);
	const expectedUrl = new URL(worktreeDevServerUrl).href;
	if (pageUrl !== expectedUrl || locationHref !== expectedUrl) {
		throw new Error(
			`Expected exact Worktree/File dev-server URL ${expectedUrl}, got page=${pageUrl} location=${locationHref}`,
		);
	}
	return { locationHref, pageUrl };
}

export async function reloadWorktreeDevServerPage(page: Page): Promise<void> {
	await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
	await page.waitForSelector('[data-testid="bridge-file-viewer-shell"]', { timeout: 30_000 });
	await waitForWorktreeFileViewerSurfaceReady(page);
	await assertObservedWorktreeDevServerUrl(page);
}

export async function waitForWorktreeFileViewerSurfaceReady(page: Page): Promise<void> {
	await page.waitForFunction(
		(): boolean => {
			const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			const filterCountText =
				document.querySelector('[data-testid="worktree-file-filter-count"]')?.textContent ?? '';
			const [visibleCountText, totalCountText] = filterCountText.split('/');
			const visibleCount = Number(visibleCountText);
			const totalCount = Number(totalCountText);
			return (
				shell?.getAttribute('data-file-display-status') === 'ready' &&
				Number.isInteger(visibleCount) &&
				Number.isInteger(totalCount) &&
				totalCount > 0 &&
				visibleCount > 0
			);
		},
		undefined,
		{ timeout: 30_000 },
	);
}

export async function readBridgePierreWorkerFileSuccessCount(page: Page): Promise<number> {
	return await page.evaluate(() =>
		Number(document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0'),
	);
}

export async function waitForBridgePierreWorkerFileSuccessForCacheKey(props: {
	readonly expectedFileCacheKey: string;
	readonly page: Page;
	readonly previousFileSuccessCount: number;
}): Promise<void> {
	await props.page.waitForFunction(
		(waitProps: {
			readonly expectedFileCacheKey: string;
			readonly previousFileSuccessCount: number;
		}): boolean => {
			const fileSuccessCount = Number(
				document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0',
			);
			return (
				Number.isInteger(fileSuccessCount) &&
				fileSuccessCount > waitProps.previousFileSuccessCount &&
				document.documentElement.dataset['bridgePierreWorkerDiagnosticLastFileSuccessCacheKey'] ===
					waitProps.expectedFileCacheKey
			);
		},
		{
			expectedFileCacheKey: props.expectedFileCacheKey,
			previousFileSuccessCount: props.previousFileSuccessCount,
		},
		{ timeout: 20_000 },
	);
}

export async function assertSharedBridgeFileViewerShell(props: {
	readonly page: Page;
	readonly targetDescriptor: WorktreeFileDescriptor;
	readonly workerFileSuccessCountBeforeTargetSelection: number;
}): Promise<WorktreeFileSharedShellProof> {
	await props.page.waitForFunction(
		(): boolean => {
			const fileSuccessCount = Number(
				document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0',
			);
			return Number.isInteger(fileSuccessCount) && fileSuccessCount > 0;
		},
		{ timeout: 20_000 },
	);
	const proof = await props.page.evaluate(() => {
		const appRoots = [...document.querySelectorAll('[data-testid="bridge-app-root"]')];
		const shells = [...document.querySelectorAll('[data-testid="bridge-file-viewer-shell"]')];
		const codeCanvases = [
			...document.querySelectorAll('[data-testid="bridge-file-viewer-code-canvas"]'),
		];
		const sidebars = [...document.querySelectorAll('[data-testid="bridge-file-viewer-sidebar"]')];
		const appRoot = appRoots[0];
		const modeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
		const shell = shells[0];
		const codeCanvas = codeCanvases[0];
		const sidebar = sidebars[0];
		const contentTopbars =
			modeHost instanceof HTMLElement
				? [...modeHost.querySelectorAll('[data-testid="bridge-viewer-content-topbar"]')]
				: [];
		const contentTopbar = contentTopbars[0];
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const contextFileButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const contextReviewButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		const contentTitle = document.querySelector('[data-testid="bridge-viewer-content-title"]');
		const pierreTree = document.querySelector(
			'[data-testid="bridge-file-viewer-pierre-file-tree"]',
		);
		const railToolbar = document.querySelector('[data-testid="bridge-file-viewer-rail-toolbar"]');
		const railFilterButton = document.querySelector('[data-testid="worktree-file-filter-menu"]');
		const railSearchButton = document.querySelector('[data-testid="worktree-file-search-toggle"]');
		const railOpenReviewButton = document.querySelector(
			'[data-testid="worktree-file-open-review-comparison"]',
		);
		if (
			!(appRoot instanceof HTMLElement) ||
			!(modeHost instanceof HTMLElement) ||
			!(shell instanceof HTMLElement) ||
			!(codeCanvas instanceof HTMLElement) ||
			!(sidebar instanceof HTMLElement) ||
			!(contentTopbar instanceof HTMLElement) ||
			!(contextSwitcher instanceof HTMLElement) ||
			!(contextFileButton instanceof HTMLElement) ||
			!(contextReviewButton instanceof HTMLElement) ||
			!(contentTitle instanceof HTMLElement) ||
			!(pierreTree instanceof HTMLElement) ||
			!(railToolbar instanceof HTMLElement) ||
			!(railFilterButton instanceof HTMLElement) ||
			!(railSearchButton instanceof HTMLElement) ||
			!(railOpenReviewButton instanceof HTMLElement)
		) {
			return null;
		}
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- this helper must execute inside the browser context.
		const elementOwnsCenterPoint = (element: HTMLElement): boolean => {
			const rect = element.getBoundingClientRect();
			const centerX = rect.left + rect.width / 2;
			const centerY = rect.top + rect.height / 2;
			const topElement = document.elementFromPoint(centerX, centerY);
			return topElement !== null && (topElement === element || element.contains(topElement));
		};
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- this helper must execute inside the browser context.
		const visibleContextButtonSelection = (testId: string): string | null => {
			const buttons = [...document.querySelectorAll(`[data-testid="${testId}"]`)];
			const visibleButton = buttons.find(
				(button): button is HTMLElement =>
					button instanceof HTMLElement && button.getClientRects().length > 0,
			);
			return visibleButton?.getAttribute('data-bridge-viewer-context-selected') ?? null;
		};
		const codeRect = codeCanvas.getBoundingClientRect();
		const sidebarRect = sidebar.getBoundingClientRect();
		const contentTopbarRect = contentTopbar.getBoundingClientRect();
		const contextSwitcherRect = contextSwitcher.getBoundingClientRect();
		const contextFileButtonRect = contextFileButton.getBoundingClientRect();
		const contextReviewButtonRect = contextReviewButton.getBoundingClientRect();
		const railToolbarRect = railToolbar.getBoundingClientRect();
		const railFilterButtonRect = railFilterButton.getBoundingClientRect();
		const railSearchButtonRect = railSearchButton.getBoundingClientRect();
		const railOpenReviewButtonRect = railOpenReviewButton.getBoundingClientRect();
		const sameHeight = (left: number, right: number): boolean => Math.abs(left - right) <= 1;
		const contentHeaderBackground = getComputedStyle(contentTopbar).backgroundColor;
		const railToolbarBackground = getComputedStyle(railToolbar).backgroundColor;
		return {
			appOwner: appRoot.getAttribute('data-bridge-app-owner'),
			appRootCount: appRoots.length,
			appRootOwnsCenterPoint: elementOwnsCenterPoint(appRoot),
			codeCanvasCount: codeCanvases.length,
			codeCanvasOwnsCenterPoint: elementOwnsCenterPoint(codeCanvas),
			codeOwner: codeCanvas.getAttribute('data-pierre-code-view-owner'),
			codeViewOverflow: codeCanvas.getAttribute('data-bridge-code-view-overflow'),
			contentPaneStartsBelowTopbar: codeRect.top >= contentTopbarRect.bottom - 1,
			contentHeaderAndRailToolbarTopAligned:
				Math.abs(contentTopbarRect.top - railToolbarRect.top) <= 1,
			contentHeaderBackground,
			contentHeaderMatchesRailToolbarBackground: contentHeaderBackground === railToolbarBackground,
			contentHeaderHeight: contentTopbarRect.height,
			contentHeaderMatchesRailToolbarHeight: sameHeight(
				contentTopbarRect.height,
				railToolbarRect.height,
			),
			contentTopbarCount: contentTopbars.length,
			contentTopbarOwnsCenterPoint: elementOwnsCenterPoint(contentTopbar),
			contentTopbarStopsBeforeSidebar: contentTopbarRect.right <= sidebarRect.left + 1,
			contentTopbarVisible: contentTopbarRect.width > 0 && contentTopbarRect.height > 0,
			contextFileButtonHeight: contextFileButtonRect.height,
			contextReviewButtonHeight: contextReviewButtonRect.height,
			contextSegmentMatchesRailButtonHeight:
				sameHeight(contextSwitcherRect.height, railFilterButtonRect.height) &&
				sameHeight(contextSwitcherRect.height, railSearchButtonRect.height) &&
				sameHeight(contextSwitcherRect.height, railOpenReviewButtonRect.height),
			contextSwitcherHeight: contextSwitcherRect.height,
			contentTitleText: contentTitle.textContent ?? '',
			contextSwitcherInsideContentTopbar: contentTopbar.contains(contextSwitcher),
			fileContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-file'),
			hasPierreTreeShadowRoot: pierreTree.querySelector('file-tree-container')?.shadowRoot !== null,
			modeHostActive: modeHost.getAttribute('data-bridge-viewer-mode-active'),
			modeHostCount: document.querySelectorAll('[data-testid="bridge-viewer-mode-host-file"]')
				.length,
			modeHostParentIsSharedRoot: modeHost.parentElement === appRoot,
			rootVisible: appRoot.getBoundingClientRect().width > 0,
			railButtonHeightsMatch:
				sameHeight(railFilterButtonRect.height, railSearchButtonRect.height) &&
				sameHeight(railFilterButtonRect.height, railOpenReviewButtonRect.height),
			railFilterButtonHeight: railFilterButtonRect.height,
			railOpenReviewButtonHeight: railOpenReviewButtonRect.height,
			railSearchButtonHeight: railSearchButtonRect.height,
			railToolbarBackground,
			railToolbarBackgroundIsOpaque: !railToolbarBackground.startsWith('rgba(0, 0, 0, 0'),
			railToolbarHeight: railToolbarRect.height,
			reviewContextButtonSelected: visibleContextButtonSelection('bridge-viewer-context-review'),
			sharedShellMode: appRoot.getAttribute('data-bridge-viewer-mode'),
			sharedShellOwner: appRoot.getAttribute('data-bridge-viewer-shell-owner'),
			shellCount: shells.length,
			shellOwnsCenterPoint: elementOwnsCenterPoint(shell),
			shellParentIsModeHost: shell.parentElement === modeHost,
			shellOwner: shell.getAttribute('data-file-viewer-owner'),
			sidebarCount: sidebars.length,
			sidebarIsRight: sidebarRect.left > codeRect.left,
			sidebarOwnsCenterPoint: elementOwnsCenterPoint(sidebar),
			sidebarPosition: shell.getAttribute('data-sidebar-position'),
			sidebarStartsAtContentTopbar: Math.abs(sidebarRect.top - contentTopbarRect.top) <= 1,
			shikiRendering: codeCanvas.getAttribute('data-shiki-rendering'),
			treeOwner: sidebar.getAttribute('data-pierre-file-tree-owner'),
			workerRequestedState: codeCanvas.getAttribute('data-worker-backed-highlighting'),
			workerDiagnosticFileSuccessCount: Number(
				document.documentElement.dataset['bridgePierreWorkerDiagnosticFileSuccessCount'] ?? '0',
			),
			workerDiagnosticLastSuccessRequestType:
				document.documentElement.dataset['bridgePierreWorkerDiagnosticLastSuccessRequestType'] ??
				null,
			workerDiagnosticLastFileSuccessCacheKey:
				document.documentElement.dataset['bridgePierreWorkerDiagnosticLastFileSuccessCacheKey'] ??
				null,
			workerPoolFileCacheSize: Number(
				document.documentElement.dataset['bridgePierreWorkerPoolFileCacheSize'] ?? '0',
			),
			workerPoolManagerState:
				document.documentElement.dataset['bridgePierreWorkerPoolManagerState'] ?? null,
			workerPoolState: document.documentElement.dataset['bridgePierreWorkerPoolState'] ?? null,
			codeViewThemeState:
				document.documentElement.dataset['bridgePierreCodeViewThemeState'] ?? null,
		};
	});
	if (proof === null) {
		throw new Error('Expected shared BridgeViewer FileViewer shell with code canvas and sidebar');
	}
	const proofWithWorkerBaseline = {
		...proof,
		workerDiagnosticFileSuccessCountBeforeTargetSelection:
			props.workerFileSuccessCountBeforeTargetSelection,
	} satisfies WorktreeFileSharedShellProof;
	const expectedTargetWorkerCacheKey = worktreeFilePierreCacheKey(props.targetDescriptor);
	if (
		proofWithWorkerBaseline.sharedShellOwner !== 'BridgeViewerAppShell' ||
		proofWithWorkerBaseline.appOwner !== 'BridgeApp' ||
		proofWithWorkerBaseline.sharedShellMode !== 'file' ||
		proofWithWorkerBaseline.appRootCount !== 1 ||
		!proofWithWorkerBaseline.appRootOwnsCenterPoint ||
		proofWithWorkerBaseline.modeHostCount !== 1 ||
		proofWithWorkerBaseline.modeHostActive !== 'true' ||
		!proofWithWorkerBaseline.modeHostParentIsSharedRoot ||
		proofWithWorkerBaseline.fileContextButtonSelected !== 'true' ||
		proofWithWorkerBaseline.reviewContextButtonSelected !== 'false' ||
		proofWithWorkerBaseline.shellCount !== 1 ||
		!proofWithWorkerBaseline.shellOwnsCenterPoint ||
		proofWithWorkerBaseline.codeCanvasCount !== 1 ||
		!proofWithWorkerBaseline.codeCanvasOwnsCenterPoint ||
		proofWithWorkerBaseline.contentTopbarCount !== 1 ||
		!proofWithWorkerBaseline.contentTopbarVisible ||
		!proofWithWorkerBaseline.contentTopbarOwnsCenterPoint ||
		!proofWithWorkerBaseline.contentHeaderAndRailToolbarTopAligned ||
		!proofWithWorkerBaseline.contentHeaderMatchesRailToolbarBackground ||
		!proofWithWorkerBaseline.contentHeaderMatchesRailToolbarHeight ||
		!proofWithWorkerBaseline.contextSwitcherInsideContentTopbar ||
		!proofWithWorkerBaseline.contextSegmentMatchesRailButtonHeight ||
		!proofWithWorkerBaseline.contentTopbarStopsBeforeSidebar ||
		!proofWithWorkerBaseline.contentPaneStartsBelowTopbar ||
		!proofWithWorkerBaseline.contentTitleText.includes(' / ') ||
		!proofWithWorkerBaseline.railButtonHeightsMatch ||
		!proofWithWorkerBaseline.railToolbarBackgroundIsOpaque ||
		proofWithWorkerBaseline.sidebarCount !== 1 ||
		!proofWithWorkerBaseline.sidebarOwnsCenterPoint ||
		!proofWithWorkerBaseline.sidebarStartsAtContentTopbar ||
		!proofWithWorkerBaseline.shellParentIsModeHost ||
		proofWithWorkerBaseline.shellOwner !== 'BridgeViewerApp.FileViewer' ||
		proofWithWorkerBaseline.sidebarPosition !== 'right' ||
		!proofWithWorkerBaseline.sidebarIsRight ||
		proofWithWorkerBaseline.codeOwner !== 'CodeView.file' ||
		proofWithWorkerBaseline.codeViewOverflow !== 'wrap' ||
		proofWithWorkerBaseline.shikiRendering !== 'pierre' ||
		proofWithWorkerBaseline.treeOwner !== 'FileTree' ||
		!proofWithWorkerBaseline.hasPierreTreeShadowRoot ||
		!proofWithWorkerBaseline.rootVisible ||
		proofWithWorkerBaseline.workerRequestedState !== 'requested' ||
		proofWithWorkerBaseline.workerDiagnosticFileSuccessCount <=
			props.workerFileSuccessCountBeforeTargetSelection ||
		proofWithWorkerBaseline.workerDiagnosticLastSuccessRequestType !== 'file' ||
		proofWithWorkerBaseline.workerDiagnosticLastFileSuccessCacheKey !==
			expectedTargetWorkerCacheKey ||
		proofWithWorkerBaseline.workerPoolFileCacheSize <= 0 ||
		proofWithWorkerBaseline.workerPoolManagerState !== 'initialized' ||
		proofWithWorkerBaseline.workerPoolState !== 'ready' ||
		proofWithWorkerBaseline.codeViewThemeState !== 'ready'
	) {
		throw new Error(
			`Expected shared BridgeViewer/Pierre FileViewer proof: ${JSON.stringify(proofWithWorkerBaseline)}`,
		);
	}
	return proofWithWorkerBaseline;
}

export function worktreeFilePierreCacheKey(descriptor: WorktreeFileDescriptor): string {
	return `${descriptor.contentHandle}:${descriptor['contentHash'] ?? 'unknown'}`;
}
