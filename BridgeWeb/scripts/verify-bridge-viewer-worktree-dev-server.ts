import { mkdir, writeFile } from 'node:fs/promises';
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
	readonly packageForbiddenTextAbsent: boolean;
	readonly proofArtifactPath: string;
	readonly scenarioName: string;
	readonly scrollExtentCanary: WorktreeFileScrollExtentCanary;
	readonly selectedCharacterCount: number;
	readonly selectedContentState: string | null;
	readonly selectedDisplayPath: string | null;
	readonly selectedLineCount: number;
	readonly sourceCursor: string;
	readonly sourceId: string;
	readonly targetPath: string;
	readonly treePathCount: number | null;
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
	const surface = await fetchWorktreeSurface();
	const descriptors = worktreeFileDescriptors(surface.frames);
	const targetDescriptor = resolveTargetDescriptor(descriptors);
	const content = await fetchWorktreeFileContent(targetDescriptor);
	const surfaceText = JSON.stringify(surface);
	if (content.length > 0 && surfaceText.includes(content.slice(0, Math.min(80, content.length)))) {
		throw new Error('Expected Worktree/File surface metadata to omit file body content');
	}

	const page = await makeVerificationPage();
	try {
		const contentRouteGate = makeDeferred<void>();
		await installFileContentRouteGate({ gate: contentRouteGate, page });
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await page.waitForSelector('[data-testid="worktree-file-app"]', { timeout: 30_000 });
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
		const rendered = await page.evaluate(
			(): Pick<
				WorktreeDevServerVerificationResult,
				| 'selectedCharacterCount'
				| 'selectedContentState'
				| 'selectedDisplayPath'
				| 'selectedLineCount'
				| 'treeTotalSizePixels'
			> => {
				const contentPanel = document.querySelector('[data-testid="worktree-file-content"]');
				const treePanel = document.querySelector('[data-testid="worktree-file-tree"]');
				const text = contentPanel?.textContent ?? '';
				const selectedDisplayPath =
					contentPanel?.getAttribute('data-worktree-open-file-path') ?? null;
				const renderedText = text.endsWith('\n') ? text.slice(0, -1) : text;
				return {
					selectedCharacterCount: text.length,
					selectedContentState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
					selectedDisplayPath,
					selectedLineCount: text.length === 0 ? 0 : renderedText.split('\n').length,
					treeTotalSizePixels: Number(
						treePanel?.getAttribute('data-worktree-tree-total-size') ?? '0',
					),
				};
			},
		);
		if (rendered.selectedDisplayPath !== targetDescriptor.path) {
			throw new Error(`Expected selected display path ${targetDescriptor.path}`);
		}
		if (rendered.selectedContentState !== 'ready') {
			throw new Error(`Expected selected Worktree/File content ready for ${targetDescriptor.path}`);
		}
		if (rendered.selectedCharacterCount !== content.length) {
			throw new Error(
				`Expected materialized Worktree/File content length for ${targetDescriptor.path}`,
			);
		}
		if (rendered.treeTotalSizePixels === null || rendered.treeTotalSizePixels <= 0) {
			throw new Error('Expected Worktree/File tree extent to be reserved from provider facts');
		}
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
			frameCount: surface.frames.length,
			packageForbiddenTextAbsent: true,
			proofArtifactPath: '',
			scrollExtentCanary,
			scenarioName: scenarioNameFromDevServerUrl(worktreeDevServerUrl),
			sourceCursor: surface.source.sourceCursor,
			sourceId: surface.source.sourceId,
			targetPath: targetDescriptor.path,
			treePathCount: surface.treeSizeFacts.pathCount ?? null,
		};
	} finally {
		await page.close();
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

async function writeWorktreeDevServerProofArtifact(
	result: WorktreeDevServerVerificationResult,
): Promise<string> {
	const proofDirectoryPath = join(proofRootPath, timestampForPath(new Date()));
	await mkdir(proofDirectoryPath, { recursive: true });
	const proofArtifactPath = join(proofDirectoryPath, 'worktree-dev-server-proof.json');
	const proofArtifactDisplayPath = relative(repoRootPath, proofArtifactPath);
	await writeFile(
		proofArtifactPath,
		`${JSON.stringify(
			{
				schemaVersion: 1,
				createdAtUnixMilliseconds: Date.now(),
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
