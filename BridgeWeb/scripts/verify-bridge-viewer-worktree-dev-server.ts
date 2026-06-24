import { mkdir, unlink, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { chromium, type Page } from 'playwright';
import { z } from 'zod';

import { parseBridgeCoreResourceUrl } from '../src/core/resources/bridge-resource-url.ts';

const defaultWorktreeDevServerUrl =
	'http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree';
const repoRootPath = fileURLToPath(new URL('../..', import.meta.url));
const proofRootPath =
	process.env['AGENTSTUDIO_BRIDGE_WORKTREE_DEV_SERVER_PROOF_ROOT'] ??
	join(repoRootPath, 'tmp/bridge-viewer-worktree-dev-server');
const proofRunCreatedAtUnixMilliseconds = Date.now();
const proofRunDirectoryPath = join(
	proofRootPath,
	timestampForPath(new Date(proofRunCreatedAtUnixMilliseconds)),
);
const worktreeDevServerUrl =
	process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] ?? defaultWorktreeDevServerUrl;
const targetPathOverride = process.env['BRIDGE_VIEWER_WORKTREE_TARGET_PATH'] ?? null;

const bridgeWorktreeSurfaceResponseSchema = z
	.object({
		frames: z.array(z.unknown()),
		source: z
			.object({
				sourceId: z.string().min(1),
				sourceCursor: z.string().min(1),
			})
			.passthrough(),
		treeSizeFacts: z
			.object({
				pathCount: z.number().int().nonnegative().optional(),
				estimatedTotalHeightPixels: z.number().nonnegative().optional(),
			})
			.passthrough(),
	})
	.strict();

const worktreeFileDescriptorFrameSchema = z
	.object({
		frameKind: z.literal('worktree.fileDescriptor'),
		descriptor: z
			.object({
				path: z.string().min(1),
				contentDescriptor: z
					.object({
						descriptor: z
							.object({
								resourceUrl: z.string().min(1),
							})
							.passthrough(),
					})
					.passthrough(),
			})
			.passthrough(),
	})
	.passthrough();

type WorktreeFileDescriptor = z.infer<typeof worktreeFileDescriptorFrameSchema>['descriptor'];

interface WorktreeDevServerVerificationResult {
	readonly descriptorCount: number;
	readonly frameCount: number;
	readonly firstLoadContentState: string | null;
	readonly firstLoadDisplayPath: string | null;
	readonly firstLoadLineCount: number;
	readonly packageForbiddenTextAbsent: boolean;
	readonly proofArtifactPath: string;
	readonly scenarioName: string;
	readonly scrollExtentCanary: WorktreeFileScrollExtentCanary;
	readonly selectedCharacterCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedLineCount: number;
	readonly screenshotPaths: WorktreeDevServerScreenshotPaths;
	readonly sourceCursor: string;
	readonly sourceId: string;
	readonly staleRefreshProof: WorktreeFileStaleRefreshProof;
	readonly targetPath: string;
	readonly treePathCount: number | null;
	readonly treeTotalSizePixels: number | null;
	readonly productControlsProof: WorktreeFileProductControlsProof;
	readonly visibleAppProof: WorktreeFileVisibleAppProof;
}

interface WorktreeDevServerScreenshotPaths {
	readonly ready: string;
	readonly search: string;
	readonly stale: string;
}

interface WorktreeFileStaleRefreshProof {
	readonly initialContentStillVisibleWhileStale: boolean;
	readonly proofPath: string;
	readonly refreshReturnedReady: boolean;
	readonly refreshedContentVisible: boolean;
	readonly staleContentState: string | null;
	readonly staleMessageVisible: boolean;
	readonly staleScreenshotPath: string;
}

interface WorktreeFileProductControlsProof {
	readonly allFilterVisibleCount: number;
	readonly fetchableFilterActive: boolean;
	readonly fetchableFilterVisibleCount: number;
	readonly initialVisibleCount: number;
	readonly regexModeActive: boolean;
	readonly regexVisibleCount: number;
	readonly searchScreenshotPath: string;
	readonly searchResultIncludesTarget: boolean;
	readonly searchStatusText: string;
	readonly searchVisibleCount: number;
	readonly targetPath: string;
	readonly unavailableFilterActive: boolean;
	readonly unavailableFilterVisibleCount: number;
}

interface WorktreeFileVisibleAppProof {
	readonly appRootRect: WorktreeFileVisibleRect;
	readonly contentPaneRect: WorktreeFileVisibleRect;
	readonly contentVisibleLineCount: number;
	readonly cssLayoutApplied: boolean;
	readonly filterControlCount: number;
	readonly forbiddenTextAbsentOutsideIntentionalUi: boolean;
	readonly regexToggleCount: number;
	readonly sampledTreeRowCount: number;
	readonly sampledTreeRowsHaveDistinctVerticalPositions: boolean;
	readonly searchInputCount: number;
	readonly treePaneRect: WorktreeFileVisibleRect;
}

interface WorktreeFileVisibleRect {
	readonly height: number;
	readonly width: number;
}

interface WorktreeRenderedContentState {
	readonly selectedCharacterCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedLineCount: number;
	readonly treeTotalSizePixels: number | null;
}

interface WorktreeFileScrollExtentCanary {
	readonly contentDeclaredTotalSizePixelsAfterReady: number | null;
	readonly contentDeclaredTotalSizePixelsAfterSelection: number | null;
	readonly contentHeightDeltaPixels: number;
	readonly contentScrollClientHeightAfterReady: number;
	readonly contentScrollClientHeightAfterSelection: number;
	readonly contentScrollHeightAfterReady: number;
	readonly contentScrollHeightAfterSelection: number;
	readonly contentScrollTopAfterReady: number;
	readonly contentScrollTopAfterSelection: number;
	readonly exactSizeTolerancePass: boolean;
	readonly stableAnchorPass: boolean;
	readonly stableAnchorReadout: WorktreeFileScrollExtentReadout;
	readonly selectedAnchorPath: string;
	readonly treeAnchorReadout: WorktreeFileTreeAnchorReadout;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeHeightDeltaPixels: number;
	readonly treeScrollClientHeightAfterReady: number;
	readonly treeScrollHeightAfterReady: number;
	readonly treeScrollHeightBeforeSelection: number;
	readonly treeScrollTopAfterReady: number;
	readonly treeScrollTopBeforeSelection: number;
}

interface WorktreeFileTreeAnchorReadout {
	readonly anchorItemId: string;
	readonly anchorOffsetAfterReady: number;
	readonly anchorOffsetBeforeSelection: number;
	readonly measuredItemIdsAfterReady: readonly string[];
	readonly measuredItemIdsBeforeSelection: readonly string[];
	readonly scrollTopAfterReady: number;
	readonly scrollTopBeforeSelection: number;
	readonly visibleRangeAfterReady: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
	readonly visibleRangeBeforeSelection: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
}

interface WorktreeFileTreeAnchorSnapshot {
	readonly anchorItemId: string;
	readonly anchorOffset: number;
	readonly measuredItemIds: readonly string[];
	readonly scrollTop: number;
	readonly visibleRange: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
}

interface WorktreeFileScrollExtentReadout {
	readonly anchorItemId: string;
	readonly anchorOffset: number;
	readonly measuredItemIds: readonly string[];
	readonly reconciliationReason: 'exactLineCount';
	readonly scrollHeightAfter: number;
	readonly scrollHeightBefore: number;
	readonly scrollTopAfter: number;
	readonly scrollTopBefore: number;
	readonly totalContentHeightAfter: number | null;
	readonly totalContentHeightBefore: number | null;
	readonly virtualizerTotalSizeAfter: number | null;
	readonly virtualizerTotalSizeBefore: number | null;
	readonly visibleRange: {
		readonly endIndex: number;
		readonly startIndex: number;
	};
}

interface WorktreeFileScrollExtentSnapshot {
	readonly contentDeclaredTotalSizePixels: number | null;
	readonly contentScrollClientHeight: number;
	readonly contentScrollHeight: number;
	readonly contentScrollTop: number;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeScrollClientHeight: number;
	readonly treeScrollHeight: number;
	readonly treeScrollTop: number;
}

const defaultFileLineHeightPixels = 20;

const browser = await chromium.launch({ headless: true });

try {
	const result = await verifyWorktreeDevServer();
	const proofArtifactPath = await writeWorktreeDevServerProofArtifact(result);
	console.log(
		JSON.stringify(
			{
				ok: true,
				devServerUrl: worktreeDevServerUrl,
				...result,
				proofArtifactPath,
			},
			null,
			2,
		),
	);
} finally {
	await browser.close();
}

async function verifyWorktreeDevServer(): Promise<WorktreeDevServerVerificationResult> {
	const staleRefreshFixture = worktreeFileStaleRefreshFixture();
	await writeFile(staleRefreshFixture.absolutePath, staleRefreshFixture.initialContent);
	const page = await makeVerificationPage();
	try {
		const surface = await fetchWorktreeSurface();
		const descriptors = worktreeFileDescriptors(surface.frames);
		const initialDescriptor = firstFetchableDescriptor(descriptors);
		const targetDescriptor = resolveTargetDescriptor(descriptors);
		const staleRefreshDescriptor = descriptorForPath({
			descriptors,
			path: staleRefreshFixture.relativePath,
		});
		const initialContent = await fetchWorktreeFileContent(initialDescriptor);
		const content = await fetchWorktreeFileContent(targetDescriptor);
		const surfaceText = JSON.stringify(surface);
		if (
			content.length > 0 &&
			surfaceText.includes(content.slice(0, Math.min(80, content.length)))
		) {
			throw new Error('Expected Worktree/File surface metadata to omit file body content');
		}
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await page.waitForSelector('[data-testid="worktree-file-app"]', { timeout: 30_000 });
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') === path,
			initialDescriptor.path,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'ready',
			{ timeout: 20_000 },
		);
		const firstLoadRendered = await readWorktreeRenderedContentState(page);
		assertRenderedWorktreeContent({
			content: initialContent,
			label: 'first-load Worktree/File content',
			rendered: firstLoadRendered,
			targetPath: initialDescriptor.path,
		});
		const contentRouteGate = makeDeferred<void>();
		await installFileContentRouteGate({ gate: contentRouteGate, page });
		await scrollTreeToFilePath(page, targetDescriptor.path);
		const scrollExtentBeforeSelection = await readWorktreeFileScrollExtentSnapshot(page);
		const treeAnchorBeforeSelection = await readWorktreeFileTreeAnchorSnapshot(
			page,
			targetDescriptor.path,
		);
		await clickWorktreeFilePath(page, targetDescriptor.path);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') === path,
			targetDescriptor.path,
			{ timeout: 10_000 },
		);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'loading',
			{ timeout: 10_000 },
		);
		const scrollExtentAfterSelection = await readWorktreeFileScrollExtentSnapshot(page);
		contentRouteGate.resolve();
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'ready',
			{ timeout: 20_000 },
		);
		const scrollExtentAfterReady = await readWorktreeFileScrollExtentSnapshot(page);
		const treeAnchorAfterReady = await readWorktreeFileTreeAnchorSnapshot(
			page,
			targetDescriptor.path,
		);
		const rendered = await readWorktreeRenderedContentState(page);
		assertRenderedWorktreeContent({
			content,
			label: 'selected Worktree/File content',
			rendered,
			targetPath: targetDescriptor.path,
		});
		if (rendered.treeTotalSizePixels === null || rendered.treeTotalSizePixels <= 0) {
			throw new Error('Expected Worktree/File tree extent to be reserved from provider facts');
		}
		const visibleAppProof = await readWorktreeFileVisibleAppProof(page);
		assertWorktreeFileVisibleAppProof(visibleAppProof);
		const readyScreenshotPath = await captureWorktreeDevServerScreenshot({
			name: 'worktree-file-ready.png',
			page,
		});
		const productControlsProof = await verifyWorktreeFileProductControls({
			descriptorCount: descriptors.length,
			page,
			targetPath: targetDescriptor.path,
		});
		const staleRefreshProof = await verifyWorktreeFileStaleRefresh({
			descriptor: staleRefreshDescriptor,
			fixture: staleRefreshFixture,
			page,
		});
		const scrollExtentCanary = makeScrollExtentCanary({
			afterReady: scrollExtentAfterReady,
			afterSelection: scrollExtentAfterSelection,
			beforeSelection: scrollExtentBeforeSelection,
			selectedAnchorPath: targetDescriptor.path,
			treeAnchorAfterReady,
			treeAnchorBeforeSelection,
		});
		assertWorktreeScrollExtentCanary(scrollExtentCanary);
		return {
			...rendered,
			descriptorCount: descriptors.length,
			firstLoadContentState: firstLoadRendered.selectedContentState,
			firstLoadDisplayPath: firstLoadRendered.selectedDisplayPath,
			firstLoadLineCount: firstLoadRendered.selectedLineCount,
			frameCount: surface.frames.length,
			packageForbiddenTextAbsent: true,
			proofArtifactPath: '',
			scrollExtentCanary,
			scenarioName: scenarioNameFromDevServerUrl(worktreeDevServerUrl),
			screenshotPaths: {
				ready: readyScreenshotPath,
				search: productControlsProof.searchScreenshotPath,
				stale: staleRefreshProof.staleScreenshotPath,
			},
			sourceCursor: surface.source.sourceCursor,
			sourceId: surface.source.sourceId,
			staleRefreshProof,
			targetPath: targetDescriptor.path,
			treePathCount: surface.treeSizeFacts.pathCount ?? null,
			visibleAppProof,
			productControlsProof,
		};
	} finally {
		await page.close();
		await unlink(staleRefreshFixture.absolutePath).catch(() => undefined);
	}
}

async function fetchWorktreeSurface(): Promise<
	z.infer<typeof bridgeWorktreeSurfaceResponseSchema>
> {
	const surfaceUrl = new URL('/__bridge-worktree/surface', worktreeDevServerUrl);
	copyScenarioSearchParam(surfaceUrl);
	const response = await fetch(surfaceUrl);
	if (!response.ok) {
		throw new Error(`Worktree/File surface request failed: ${response.status}`);
	}
	return bridgeWorktreeSurfaceResponseSchema.parse(await response.json());
}

function worktreeFileDescriptors(frames: readonly unknown[]): readonly WorktreeFileDescriptor[] {
	const descriptors: WorktreeFileDescriptor[] = [];
	for (const frame of frames) {
		const parsedFrame = worktreeFileDescriptorFrameSchema.safeParse(frame);
		if (parsedFrame.success) {
			descriptors.push(parsedFrame.data.descriptor);
		}
	}
	return descriptors;
}

function resolveTargetDescriptor(
	descriptors: readonly WorktreeFileDescriptor[],
): WorktreeFileDescriptor {
	const descriptor =
		targetPathOverride === null
			? deepFetchableDescriptor(descriptors)
			: (descriptors.find((candidate) => candidate.path === targetPathOverride) ?? null);
	if (descriptor === null) {
		throw new Error(
			targetPathOverride === null
				? 'Expected at least one Worktree/File descriptor'
				: `Expected Worktree/File descriptor for ${targetPathOverride}`,
		);
	}
	return descriptor;
}

function firstFetchableDescriptor(
	descriptors: readonly WorktreeFileDescriptor[],
): WorktreeFileDescriptor {
	const descriptor = descriptors.find(
		(candidate) =>
			!candidate['isBinary'] && candidate['virtualizedExtentKind'] === 'exactLineCount',
	);
	if (descriptor === undefined) {
		throw new Error('Expected at least one fetchable Worktree/File descriptor');
	}
	return descriptor;
}

function deepFetchableDescriptor(
	descriptors: readonly WorktreeFileDescriptor[],
): WorktreeFileDescriptor | null {
	const fetchableDescriptors = descriptors.filter(
		(descriptor) =>
			!descriptor['isBinary'] && descriptor['virtualizedExtentKind'] === 'exactLineCount',
	);
	if (fetchableDescriptors.length === 0) {
		return null;
	}
	const targetIndex = Math.min(
		fetchableDescriptors.length - 1,
		Math.floor(fetchableDescriptors.length * 0.75),
	);
	return fetchableDescriptors[targetIndex] ?? null;
}

interface WorktreeFileStaleRefreshFixture {
	readonly absolutePath: string;
	readonly initialContent: string;
	readonly relativePath: string;
	readonly updatedContent: string;
}

function worktreeFileStaleRefreshFixture(): WorktreeFileStaleRefreshFixture {
	const fileStem = `zzzz_bridge_worktree_devserver_proof_${proofRunCreatedAtUnixMilliseconds}`;
	const relativePath = `${fileStem}.ts`;
	return {
		absolutePath: join(repoRootPath, relativePath),
		initialContent: `export const ${fileStem} = 'initial';\n`,
		relativePath,
		updatedContent: `export const ${fileStem} = 'updated';\nexport const ${fileStem}_line2 = true;\n`,
	};
}

function descriptorForPath(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly path: string;
}): WorktreeFileDescriptor {
	const descriptor = props.descriptors.find((candidate) => candidate.path === props.path);
	if (descriptor === undefined) {
		throw new Error(`Expected Worktree/File descriptor for ${props.path}`);
	}
	return descriptor;
}

async function fetchWorktreeFileContent(descriptor: WorktreeFileDescriptor): Promise<string> {
	const parsedResourceUrl = parseBridgeCoreResourceUrl(
		descriptor.contentDescriptor.descriptor.resourceUrl,
		{
			allowedResourceKindsByProtocol: {
				'worktree-file': new Set(['worktree.fileContent']),
			},
		},
	);
	if (parsedResourceUrl === null) {
		throw new Error(`Invalid Worktree/File resource URL for ${descriptor.path}`);
	}
	const contentUrl = new URL(
		`/__bridge-worktree/file-content/${encodeURIComponent(parsedResourceUrl.opaqueId)}`,
		worktreeDevServerUrl,
	);
	copyScenarioSearchParam(contentUrl);
	if (parsedResourceUrl.generation !== undefined) {
		contentUrl.searchParams.set('generation', String(parsedResourceUrl.generation));
	}
	if (parsedResourceUrl.cursor !== undefined) {
		contentUrl.searchParams.set('cursor', parsedResourceUrl.cursor);
	}
	const response = await fetch(contentUrl);
	if (!response.ok) {
		throw new Error(`Worktree/File content request failed: ${response.status}`);
	}
	return await response.text();
}

function copyScenarioSearchParam(url: URL): void {
	const scenario = new URL(worktreeDevServerUrl).searchParams.get('scenario');
	if (scenario !== null) {
		url.searchParams.set('scenario', scenario);
	}
}

async function makeVerificationPage(): Promise<Page> {
	return await browser.newPage({
		deviceScaleFactor: 1,
		viewport: {
			width: 1728,
			height: 980,
		},
	});
}

async function installFileContentRouteGate(props: {
	readonly gate: Deferred<void>;
	readonly page: Page;
}): Promise<void> {
	await props.page.route('**/__bridge-worktree/file-content/**', async (route) => {
		await props.gate.promise;
		await route.continue();
	});
}

async function readWorktreeRenderedContentState(page: Page): Promise<WorktreeRenderedContentState> {
	return await page.evaluate((): WorktreeRenderedContentState => {
		const contentPanel = document.querySelector('[data-testid="worktree-file-content"]');
		const treePanel = document.querySelector('[data-testid="worktree-file-tree"]');
		const text = contentPanel?.textContent ?? '';
		const selectedDisplayPath = contentPanel?.getAttribute('data-worktree-open-file-path') ?? null;
		const renderedText = text.endsWith('\n') ? text.slice(0, -1) : text;
		return {
			selectedCharacterCount: text.length,
			selectedContentState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
			selectedDisplayPath,
			selectedLineCount: text.length === 0 ? 0 : renderedText.split('\n').length,
			treeTotalSizePixels: Number(treePanel?.getAttribute('data-worktree-tree-total-size') ?? '0'),
		};
	});
}

function assertRenderedWorktreeContent(props: {
	readonly content: string;
	readonly label: string;
	readonly rendered: WorktreeRenderedContentState;
	readonly targetPath: string;
}): void {
	if (props.rendered.selectedDisplayPath !== props.targetPath) {
		throw new Error(`Expected ${props.label} path ${props.targetPath}`);
	}
	if (props.rendered.selectedContentState !== 'ready') {
		throw new Error(`Expected ${props.label} to be ready for ${props.targetPath}`);
	}
	if (props.rendered.selectedCharacterCount !== props.content.length) {
		throw new Error(`Expected ${props.label} length for ${props.targetPath}`);
	}
	const expectedLineCount = countTextLines(props.content);
	if (props.rendered.selectedLineCount !== expectedLineCount) {
		throw new Error(
			`Expected ${props.label} line count ${expectedLineCount}, got ${props.rendered.selectedLineCount}`,
		);
	}
}

async function scrollTreeToFilePath(page: Page, path: string): Promise<void> {
	await page.waitForSelector(`[data-worktree-file-path="${cssAttributeEscape(path)}"]`, {
		timeout: 30_000,
	});
	await page.evaluate((targetPath: string): void => {
		const button = document.querySelector(`[data-worktree-file-path="${CSS.escape(targetPath)}"]`);
		const treePanel = document.querySelector('[data-testid="worktree-file-tree"]');
		if (!(button instanceof HTMLElement) || !(treePanel instanceof HTMLElement)) {
			throw new Error(`Expected Worktree/File tree row for ${targetPath}`);
		}
		button.scrollIntoView({ block: 'center' });
		if (treePanel.scrollTop <= 0) {
			treePanel.scrollTop = Math.min(treePanel.scrollHeight - treePanel.clientHeight, 160);
		}
	}, path);
}

async function clickWorktreeFilePath(page: Page, path: string): Promise<void> {
	await page.waitForSelector(`[data-worktree-file-path="${cssAttributeEscape(path)}"]`, {
		timeout: 30_000,
	});
	const didClick = await page.evaluate((targetPath: string): boolean => {
		const button = document.querySelector(`[data-worktree-file-path="${CSS.escape(targetPath)}"]`);
		if (!(button instanceof HTMLButtonElement)) {
			return false;
		}
		button.click();
		return true;
	}, path);
	if (!didClick) {
		throw new Error(`Expected Worktree/File row for ${path}`);
	}
}

async function readWorktreeFileTreeAnchorSnapshot(
	page: Page,
	path: string,
): Promise<WorktreeFileTreeAnchorSnapshot> {
	return await page.evaluate((targetPath: string): WorktreeFileTreeAnchorSnapshot => {
		const treePanel = document.querySelector('[data-testid="worktree-file-tree"]');
		const anchor = document.querySelector(`[data-worktree-file-path="${CSS.escape(targetPath)}"]`);
		if (!(treePanel instanceof HTMLElement) || !(anchor instanceof HTMLElement)) {
			throw new Error(`Expected Worktree/File anchor row for ${targetPath}`);
		}
		const treeRect = treePanel.getBoundingClientRect();
		const anchorRect = anchor.getBoundingClientRect();
		const visibleButtons = [...treePanel.querySelectorAll('[data-worktree-file-path]')].filter(
			(candidate): candidate is HTMLElement => {
				if (!(candidate instanceof HTMLElement)) {
					return false;
				}
				const candidateRect = candidate.getBoundingClientRect();
				return candidateRect.bottom >= treeRect.top && candidateRect.top <= treeRect.bottom;
			},
		);
		const allButtons = [...treePanel.querySelectorAll('[data-worktree-file-path]')];
		const visibleIndexes = visibleButtons.map((button) => allButtons.indexOf(button));
		return {
			anchorItemId: targetPath,
			anchorOffset: anchorRect.top - treeRect.top,
			measuredItemIds: visibleButtons.map(
				(button) => button.getAttribute('data-worktree-file-path') ?? '',
			),
			scrollTop: treePanel.scrollTop,
			visibleRange: {
				startIndex: Math.min(...visibleIndexes),
				endIndex: Math.max(...visibleIndexes),
			},
		};
	}, path);
}

async function readWorktreeFileScrollExtentSnapshot(
	page: Page,
): Promise<WorktreeFileScrollExtentSnapshot> {
	return await page.evaluate((): WorktreeFileScrollExtentSnapshot => {
		const treePanel = document.querySelector('[data-testid="worktree-file-tree"]');
		const contentPanel = document.querySelector('[data-testid="worktree-file-content"]');
		if (!(treePanel instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File tree panel for extent canary');
		}
		if (!(contentPanel instanceof HTMLElement)) {
			throw new Error('Expected Worktree/File content panel for extent canary');
		}
		const contentDeclaredTotalSizeRaw = contentPanel.getAttribute(
			'data-worktree-open-file-total-size',
		);
		const contentDeclaredTotalSize =
			contentDeclaredTotalSizeRaw === null ? null : Number(contentDeclaredTotalSizeRaw);
		const treeDeclaredTotalSizeRaw = treePanel.getAttribute('data-worktree-tree-total-size');
		const treeDeclaredTotalSize =
			treeDeclaredTotalSizeRaw === null ? null : Number(treeDeclaredTotalSizeRaw);
		return {
			contentDeclaredTotalSizePixels:
				contentDeclaredTotalSize === null || Number.isFinite(contentDeclaredTotalSize)
					? contentDeclaredTotalSize
					: null,
			contentScrollClientHeight: contentPanel.clientHeight,
			contentScrollHeight: contentPanel.scrollHeight,
			contentScrollTop: contentPanel.scrollTop,
			treeDeclaredTotalSizePixels:
				treeDeclaredTotalSize === null || Number.isFinite(treeDeclaredTotalSize)
					? treeDeclaredTotalSize
					: null,
			treeScrollClientHeight: treePanel.clientHeight,
			treeScrollHeight: treePanel.scrollHeight,
			treeScrollTop: treePanel.scrollTop,
		};
	});
}

function makeScrollExtentCanary(props: {
	readonly afterReady: WorktreeFileScrollExtentSnapshot;
	readonly afterSelection: WorktreeFileScrollExtentSnapshot;
	readonly beforeSelection: WorktreeFileScrollExtentSnapshot;
	readonly selectedAnchorPath: string;
	readonly treeAnchorAfterReady: WorktreeFileTreeAnchorSnapshot;
	readonly treeAnchorBeforeSelection: WorktreeFileTreeAnchorSnapshot;
}): WorktreeFileScrollExtentCanary {
	const treeAnchorOffsetDelta =
		props.treeAnchorAfterReady.anchorOffset - props.treeAnchorBeforeSelection.anchorOffset;
	return {
		contentDeclaredTotalSizePixelsAfterReady: props.afterReady.contentDeclaredTotalSizePixels,
		contentDeclaredTotalSizePixelsAfterSelection:
			props.afterSelection.contentDeclaredTotalSizePixels,
		contentHeightDeltaPixels:
			props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight,
		contentScrollClientHeightAfterReady: props.afterReady.contentScrollClientHeight,
		contentScrollClientHeightAfterSelection: props.afterSelection.contentScrollClientHeight,
		contentScrollHeightAfterReady: props.afterReady.contentScrollHeight,
		contentScrollHeightAfterSelection: props.afterSelection.contentScrollHeight,
		contentScrollTopAfterReady: props.afterReady.contentScrollTop,
		contentScrollTopAfterSelection: props.afterSelection.contentScrollTop,
		exactSizeTolerancePass:
			Math.abs(props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight) <=
			1,
		stableAnchorPass:
			Math.abs(treeAnchorOffsetDelta) <= 1 &&
			Math.abs(props.treeAnchorAfterReady.scrollTop - props.treeAnchorBeforeSelection.scrollTop) <=
				1 &&
			props.afterReady.contentScrollTop === props.afterSelection.contentScrollTop,
		stableAnchorReadout: {
			anchorItemId: props.selectedAnchorPath,
			anchorOffset: props.treeAnchorBeforeSelection.anchorOffset,
			measuredItemIds: props.treeAnchorBeforeSelection.measuredItemIds,
			reconciliationReason: 'exactLineCount',
			scrollHeightAfter: props.afterReady.contentScrollHeight,
			scrollHeightBefore: props.afterSelection.contentScrollHeight,
			scrollTopAfter: props.afterReady.contentScrollTop,
			scrollTopBefore: props.afterSelection.contentScrollTop,
			totalContentHeightAfter: props.afterReady.contentDeclaredTotalSizePixels,
			totalContentHeightBefore: props.afterSelection.contentDeclaredTotalSizePixels,
			virtualizerTotalSizeAfter: props.afterReady.contentDeclaredTotalSizePixels,
			virtualizerTotalSizeBefore: props.afterSelection.contentDeclaredTotalSizePixels,
			visibleRange: {
				endIndex: Math.ceil(
					(props.afterReady.contentScrollTop + props.afterReady.contentScrollClientHeight) /
						defaultFileLineHeightPixels,
				),
				startIndex: Math.floor(props.afterReady.contentScrollTop / defaultFileLineHeightPixels),
			},
		},
		selectedAnchorPath: props.selectedAnchorPath,
		treeAnchorReadout: {
			anchorItemId: props.selectedAnchorPath,
			anchorOffsetAfterReady: props.treeAnchorAfterReady.anchorOffset,
			anchorOffsetBeforeSelection: props.treeAnchorBeforeSelection.anchorOffset,
			measuredItemIdsAfterReady: props.treeAnchorAfterReady.measuredItemIds,
			measuredItemIdsBeforeSelection: props.treeAnchorBeforeSelection.measuredItemIds,
			scrollTopAfterReady: props.treeAnchorAfterReady.scrollTop,
			scrollTopBeforeSelection: props.treeAnchorBeforeSelection.scrollTop,
			visibleRangeAfterReady: props.treeAnchorAfterReady.visibleRange,
			visibleRangeBeforeSelection: props.treeAnchorBeforeSelection.visibleRange,
		},
		treeDeclaredTotalSizePixels: props.afterReady.treeDeclaredTotalSizePixels,
		treeHeightDeltaPixels:
			props.afterReady.treeScrollHeight - props.beforeSelection.treeScrollHeight,
		treeScrollClientHeightAfterReady: props.afterReady.treeScrollClientHeight,
		treeScrollHeightAfterReady: props.afterReady.treeScrollHeight,
		treeScrollHeightBeforeSelection: props.beforeSelection.treeScrollHeight,
		treeScrollTopAfterReady: props.afterReady.treeScrollTop,
		treeScrollTopBeforeSelection: props.beforeSelection.treeScrollTop,
	};
}

function assertWorktreeScrollExtentCanary(canary: WorktreeFileScrollExtentCanary): void {
	if (canary.treeDeclaredTotalSizePixels === null || canary.treeDeclaredTotalSizePixels <= 0) {
		throw new Error('Expected Worktree/File tree declared extent in scroll canary');
	}
	if (Math.abs(canary.treeScrollHeightAfterReady - canary.treeDeclaredTotalSizePixels) > 1) {
		throw new Error(
			`Expected Worktree/File tree scroll extent near declared size: ${JSON.stringify(canary)}`,
		);
	}
	if (
		canary.contentDeclaredTotalSizePixelsAfterSelection === null ||
		canary.contentDeclaredTotalSizePixelsAfterReady === null
	) {
		throw new Error('Expected Worktree/File content declared extent in scroll canary');
	}
	if (
		canary.contentDeclaredTotalSizePixelsAfterSelection !==
		canary.contentDeclaredTotalSizePixelsAfterReady
	) {
		throw new Error(
			`Expected Worktree/File declared content extent to stay stable: ${JSON.stringify(canary)}`,
		);
	}
	if (Math.abs(canary.treeHeightDeltaPixels) > 1) {
		throw new Error(
			`Expected Worktree/File tree hydration to keep scroll extent bounded: ${JSON.stringify(canary)}`,
		);
	}
	if (canary.treeScrollTopBeforeSelection <= 0 || canary.treeScrollTopAfterReady <= 0) {
		throw new Error(
			`Expected Worktree/File tree canary to exercise non-zero scroll: ${JSON.stringify(canary)}`,
		);
	}
	if (Math.abs(canary.contentHeightDeltaPixels) > 1) {
		throw new Error(
			`Expected Worktree/File content hydration to keep scroll extent bounded: ${JSON.stringify(canary)}`,
		);
	}
	if (!canary.stableAnchorPass || !canary.exactSizeTolerancePass) {
		throw new Error(`Expected Worktree/File scroll extent pass readout: ${JSON.stringify(canary)}`);
	}
}

async function readWorktreeFileVisibleAppProof(page: Page): Promise<WorktreeFileVisibleAppProof> {
	return await page.evaluate((): WorktreeFileVisibleAppProof => {
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Runs inside the Playwright page context.
		const visibleRectForPageElement = (element: HTMLElement): WorktreeFileVisibleRect => {
			const rect = element.getBoundingClientRect();
			return {
				height: rect.height,
				width: rect.width,
			};
		};
		// oxlint-disable-next-line unicorn/consistent-function-scoping -- Runs inside the Playwright page context.
		const countPageTextLines = (text: string): number => {
			const trimmedText = text.endsWith('\n') ? text.slice(0, -1) : text;
			return trimmedText.length === 0 ? 0 : trimmedText.split('\n').length;
		};
		const appRoot = document.querySelector('[data-testid="worktree-file-app"]');
		const treePane = document.querySelector('[data-testid="worktree-file-tree"]');
		const contentPane = document.querySelector('[data-testid="worktree-file-content"]');
		if (!(appRoot instanceof HTMLElement)) {
			throw new Error('Expected visible Worktree/File app root');
		}
		if (!(treePane instanceof HTMLElement)) {
			throw new Error('Expected visible Worktree/File tree pane');
		}
		if (!(contentPane instanceof HTMLElement)) {
			throw new Error('Expected visible Worktree/File content pane');
		}
		const sampledRows = [...treePane.querySelectorAll('[data-worktree-file-path]')]
			.filter((candidate): candidate is HTMLElement => candidate instanceof HTMLElement)
			.slice(0, 24);
		const sampledRowTops = sampledRows.map((row) => Math.round(row.getBoundingClientRect().top));
		const distinctSampledRowTops = new Set(sampledRowTops);
		const contentPre = contentPane.querySelector('pre');
		const outsideIntentionalUi = document.body.cloneNode(true);
		if (!(outsideIntentionalUi instanceof HTMLElement)) {
			throw new Error('Expected cloneable page body');
		}
		outsideIntentionalUi
			.querySelectorAll('[data-testid="worktree-file-tree"], [data-testid="worktree-file-content"]')
			.forEach((node) => {
				node.remove();
			});
		const outsideText = outsideIntentionalUi.textContent ?? '';
		const appRootStyle = window.getComputedStyle(appRoot);
		return {
			appRootRect: visibleRectForPageElement(appRoot),
			contentPaneRect: visibleRectForPageElement(contentPane),
			contentVisibleLineCount: countPageTextLines(contentPre?.textContent ?? ''),
			cssLayoutApplied:
				appRootStyle.display === 'grid' &&
				appRootStyle.getPropertyValue('--bridge-worktree-file-layout-proof').trim() === 'applied',
			filterControlCount: appRoot.querySelectorAll('[data-testid^="worktree-file-filter-"]').length,
			forbiddenTextAbsentOutsideIntentionalUi:
				!outsideText.includes('"frames"') &&
				!outsideText.includes('frameKind') &&
				!outsideText.includes('resourceUrl') &&
				!outsideText.includes('agentstudio://resource/') &&
				!outsideText.includes('BridgeWeb/src/'),
			regexToggleCount: appRoot.querySelectorAll('[data-testid="worktree-file-regex-toggle"]')
				.length,
			sampledTreeRowCount: sampledRows.length,
			sampledTreeRowsHaveDistinctVerticalPositions:
				sampledRows.length >= 8 && distinctSampledRowTops.size === sampledRows.length,
			searchInputCount: appRoot.querySelectorAll('[data-testid="worktree-file-search-input"]')
				.length,
			treePaneRect: visibleRectForPageElement(treePane),
		};
	});
}

function assertWorktreeFileVisibleAppProof(proof: WorktreeFileVisibleAppProof): void {
	assertVisibleRect('Worktree/File app root', proof.appRootRect);
	assertVisibleRect('Worktree/File tree pane', proof.treePaneRect);
	assertVisibleRect('Worktree/File content pane', proof.contentPaneRect);
	if (!proof.cssLayoutApplied) {
		throw new Error(`Expected Worktree/File packaged CSS layout proof: ${JSON.stringify(proof)}`);
	}
	if (proof.searchInputCount !== 1) {
		throw new Error(`Expected Worktree/File product search input: ${JSON.stringify(proof)}`);
	}
	if (proof.regexToggleCount !== 1) {
		throw new Error(`Expected Worktree/File regex toggle: ${JSON.stringify(proof)}`);
	}
	if (proof.filterControlCount < 3) {
		throw new Error(`Expected Worktree/File filter/status controls: ${JSON.stringify(proof)}`);
	}
	if (!proof.sampledTreeRowsHaveDistinctVerticalPositions) {
		throw new Error(
			`Expected Worktree/File tree rows to occupy distinct rows: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.contentVisibleLineCount <= 1) {
		throw new Error(
			`Expected Worktree/File selected content to preserve line structure: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.forbiddenTextAbsentOutsideIntentionalUi) {
		throw new Error(
			`Expected no raw Worktree/File payload text outside intended UI: ${JSON.stringify(proof)}`,
		);
	}
}

function assertVisibleRect(label: string, rect: WorktreeFileVisibleRect): void {
	if (rect.width <= 0 || rect.height <= 0) {
		throw new Error(`Expected visible ${label} rect: ${JSON.stringify(rect)}`);
	}
}

async function verifyWorktreeFileProductControls(props: {
	readonly descriptorCount: number;
	readonly page: Page;
	readonly targetPath: string;
}): Promise<WorktreeFileProductControlsProof> {
	const initialVisibleCount = await visibleWorktreeFileRowCount(props.page);
	await fillWorktreeFileSearch(props.page, props.targetPath);
	await waitForVisibleWorktreeFileRowCount(props.page, 1);
	const searchStatusText = await worktreeFileFilterStatusText(props.page);
	const searchResultIncludesTarget = await worktreeFileRowExists(props.page, props.targetPath);
	const searchScreenshotPath = await captureWorktreeDevServerScreenshot({
		name: 'worktree-file-search-result.png',
		page: props.page,
	});
	await clickWorktreeFileControl(props.page, 'worktree-file-regex-toggle');
	await fillWorktreeFileSearch(props.page, `^${escapeRegExp(props.targetPath)}$`);
	await waitForVisibleWorktreeFileRowCount(props.page, 1);
	const regexModeActive = await worktreeFileControlPressed(
		props.page,
		'worktree-file-regex-toggle',
	);
	const regexVisibleCount = await visibleWorktreeFileRowCount(props.page);
	await clickWorktreeFileControl(props.page, 'worktree-file-filter-fetchable');
	const fetchableFilterActive = await worktreeFileControlPressed(
		props.page,
		'worktree-file-filter-fetchable',
	);
	const fetchableFilterVisibleCount = await visibleWorktreeFileRowCount(props.page);
	await clickWorktreeFileControl(props.page, 'worktree-file-filter-unavailable');
	const unavailableFilterActive = await worktreeFileControlPressed(
		props.page,
		'worktree-file-filter-unavailable',
	);
	const unavailableFilterVisibleCount = await visibleWorktreeFileRowCount(props.page);
	await clickWorktreeFileControl(props.page, 'worktree-file-filter-all');
	await fillWorktreeFileSearch(props.page, '');
	await props.page.waitForFunction(
		(expectedMinimumCount: number): boolean =>
			document.querySelectorAll('[data-worktree-file-path]').length >= expectedMinimumCount,
		Math.min(8, props.descriptorCount),
		{ timeout: 10_000 },
	);
	const allFilterVisibleCount = await visibleWorktreeFileRowCount(props.page);
	const proof: WorktreeFileProductControlsProof = {
		allFilterVisibleCount,
		fetchableFilterActive,
		fetchableFilterVisibleCount,
		initialVisibleCount,
		regexModeActive,
		regexVisibleCount,
		searchScreenshotPath,
		searchResultIncludesTarget,
		searchStatusText,
		searchVisibleCount: 1,
		targetPath: props.targetPath,
		unavailableFilterActive,
		unavailableFilterVisibleCount,
	};
	assertWorktreeFileProductControlsProof(proof);
	return proof;
}

async function verifyWorktreeFileStaleRefresh(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly fixture: WorktreeFileStaleRefreshFixture;
	readonly page: Page;
}): Promise<WorktreeFileStaleRefreshProof> {
	await fillWorktreeFileSearch(props.page, props.fixture.relativePath);
	await waitForVisibleWorktreeFileRowCount(props.page, 1);
	await clickWorktreeFilePath(props.page, props.fixture.relativePath);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'ready',
	});
	await assertWorktreeVisibleContentText({
		expectedText: props.fixture.initialContent,
		label: 'initial stale-refresh proof content',
		page: props.page,
	});
	await writeFile(props.fixture.absolutePath, props.fixture.updatedContent);
	await dispatchWorktreeDevReload(props.page);
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'stale',
	});
	const staleText = await worktreeVisibleContentText(props.page);
	const staleScreenshotPath = await captureWorktreeDevServerScreenshot({
		name: 'worktree-file-stale-refresh.png',
		page: props.page,
	});
	await clickWorktreeFileControl(props.page, 'worktree-file-refresh');
	await waitForWorktreeOpenFileState({
		page: props.page,
		path: props.fixture.relativePath,
		state: 'ready',
	});
	const refreshedText = await worktreeVisibleContentText(props.page);
	const proof: WorktreeFileStaleRefreshProof = {
		initialContentStillVisibleWhileStale: staleText.includes(props.fixture.initialContent.trim()),
		proofPath: props.descriptor.path,
		refreshReturnedReady: true,
		refreshedContentVisible: refreshedText.includes(props.fixture.updatedContent.trim()),
		staleContentState: 'stale',
		staleMessageVisible: staleText.includes('Content changed'),
		staleScreenshotPath,
	};
	assertWorktreeFileStaleRefreshProof(proof);
	return proof;
}

function assertWorktreeFileStaleRefreshProof(proof: WorktreeFileStaleRefreshProof): void {
	if (proof.proofPath.length === 0) {
		throw new Error(`Expected Worktree/File stale-refresh proof path: ${JSON.stringify(proof)}`);
	}
	if (
		!proof.initialContentStillVisibleWhileStale ||
		!proof.staleMessageVisible ||
		proof.staleContentState !== 'stale'
	) {
		throw new Error(`Expected Worktree/File stale state before refresh: ${JSON.stringify(proof)}`);
	}
	if (!proof.refreshReturnedReady || !proof.refreshedContentVisible) {
		throw new Error(
			`Expected Worktree/File explicit refresh to render update: ${JSON.stringify(proof)}`,
		);
	}
}

async function captureWorktreeDevServerScreenshot(props: {
	readonly name: string;
	readonly page: Page;
}): Promise<string> {
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const screenshotPath = join(proofRunDirectoryPath, props.name);
	await props.page.screenshot({ fullPage: true, path: screenshotPath });
	return relative(repoRootPath, screenshotPath);
}

function assertWorktreeFileProductControlsProof(proof: WorktreeFileProductControlsProof): void {
	if (proof.initialVisibleCount <= 1) {
		throw new Error(
			`Expected Worktree/File initial tree to have multiple rows: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.searchResultIncludesTarget || proof.searchVisibleCount !== 1) {
		throw new Error(
			`Expected Worktree/File search to isolate target path: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.searchStatusText.startsWith('1/')) {
		throw new Error(
			`Expected Worktree/File search status to show result delta: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.regexModeActive || proof.regexVisibleCount !== 1) {
		throw new Error(
			`Expected Worktree/File regex search to isolate target path: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.fetchableFilterActive || proof.fetchableFilterVisibleCount !== 1) {
		throw new Error(
			`Expected Worktree/File fetchable filter to stay active with target: ${JSON.stringify(proof)}`,
		);
	}
	if (!proof.unavailableFilterActive || proof.unavailableFilterVisibleCount !== 0) {
		throw new Error(
			`Expected Worktree/File unavailable filter to hide text target: ${JSON.stringify(proof)}`,
		);
	}
	if (proof.allFilterVisibleCount < proof.initialVisibleCount) {
		throw new Error(
			`Expected Worktree/File all filter reset to restore visible rows: ${JSON.stringify(proof)}`,
		);
	}
}

async function fillWorktreeFileSearch(page: Page, value: string): Promise<void> {
	await page.locator('[data-testid="worktree-file-search-input"]').fill(value);
}

async function clickWorktreeFileControl(page: Page, testId: string): Promise<void> {
	await page.locator(`[data-testid="${testId}"]`).click();
}

async function visibleWorktreeFileRowCount(page: Page): Promise<number> {
	return await page.evaluate(
		(): number => document.querySelectorAll('[data-worktree-file-path]').length,
	);
}

async function waitForVisibleWorktreeFileRowCount(page: Page, count: number): Promise<void> {
	await page.waitForFunction(
		(expectedCount: number): boolean =>
			document.querySelectorAll('[data-worktree-file-path]').length === expectedCount,
		count,
		{ timeout: 10_000 },
	);
}

async function worktreeFileRowExists(page: Page, path: string): Promise<boolean> {
	return await page.evaluate(
		(targetPath: string): boolean =>
			document.querySelector(`[data-worktree-file-path="${CSS.escape(targetPath)}"]`) !== null,
		path,
	);
}

async function worktreeFileControlPressed(page: Page, testId: string): Promise<boolean> {
	return await page.evaluate((targetTestId: string): boolean => {
		const control = document.querySelector(`[data-testid="${CSS.escape(targetTestId)}"]`);
		return control?.getAttribute('aria-pressed') === 'true';
	}, testId);
}

async function worktreeFileFilterStatusText(page: Page): Promise<string> {
	return await page.evaluate(
		(): string =>
			document.querySelector('[data-testid="worktree-file-filter-status"]')?.textContent ?? '',
	);
}

async function waitForWorktreeOpenFileState(props: {
	readonly page: Page;
	readonly path: string;
	readonly state: 'loading' | 'ready' | 'stale' | 'unavailable';
}): Promise<void> {
	await props.page.waitForFunction(
		(expected: { readonly path: string; readonly state: string }): boolean => {
			const contentPanel = document.querySelector('[data-testid="worktree-file-content"]');
			return (
				contentPanel?.getAttribute('data-worktree-open-file-path') === expected.path &&
				contentPanel?.getAttribute('data-worktree-open-file-state') === expected.state
			);
		},
		{ path: props.path, state: props.state },
		{ timeout: 20_000 },
	);
}

async function dispatchWorktreeDevReload(page: Page): Promise<void> {
	await page.evaluate((): void => {
		window.dispatchEvent(new Event('bridge-worktree-dev-reload'));
	});
}

async function worktreeVisibleContentText(page: Page): Promise<string> {
	return await page.evaluate(
		(): string =>
			document.querySelector('[data-testid="worktree-file-content"]')?.textContent ?? '',
	);
}

async function assertWorktreeVisibleContentText(props: {
	readonly expectedText: string;
	readonly label: string;
	readonly page: Page;
}): Promise<void> {
	const text = await worktreeVisibleContentText(props.page);
	if (!text.includes(props.expectedText.trim())) {
		throw new Error(`Expected ${props.label} to be visible`);
	}
}

function countTextLines(text: string): number {
	const trimmedText = text.endsWith('\n') ? text.slice(0, -1) : text;
	return trimmedText.length === 0 ? 0 : trimmedText.split('\n').length;
}

async function writeWorktreeDevServerProofArtifact(
	result: WorktreeDevServerVerificationResult,
): Promise<string> {
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const proofArtifactPath = join(proofRunDirectoryPath, 'worktree-dev-server-proof.json');
	const proofArtifactDisplayPath = relative(repoRootPath, proofArtifactPath);
	await writeFile(
		proofArtifactPath,
		`${JSON.stringify(
			{
				schemaVersion: 1,
				createdAtUnixMilliseconds: proofRunCreatedAtUnixMilliseconds,
				devServerUrl: worktreeDevServerUrl,
				result: {
					...result,
					proofArtifactPath: proofArtifactDisplayPath,
				},
			},
			null,
			2,
		)}\n`,
	);
	return proofArtifactDisplayPath;
}

function cssAttributeEscape(value: string): string {
	return value.replace(/["\\]/gu, '\\$&');
}

function escapeRegExp(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

function scenarioNameFromDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	return parsedUrl.searchParams.get('scenario') ?? 'current-worktree';
}

function timestampForPath(date: Date): string {
	return date.toISOString().replace(/[:.]/gu, '-');
}

interface Deferred<TValue> {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
}

function makeDeferred<TValue>(): Deferred<TValue> {
	let resolve: ((value: TValue) => void) | null = null;
	const promise = new Promise<TValue>((promiseResolve) => {
		resolve = promiseResolve;
	});
	if (resolve === null) {
		throw new Error('Deferred promise did not initialize');
	}
	return { promise, resolve };
}
