import { chromium, type Page } from 'playwright';
import { z } from 'zod';

import { parseBridgeCoreResourceUrl } from '../src/core/resources/bridge-resource-url.ts';

const defaultWorktreeDevServerUrl =
	'http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree';
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
	readonly contentScrollHeightAfterReady: number;
	readonly contentScrollHeightAfterSelection: number;
	readonly contentScrollTopAfterReady: number;
	readonly contentScrollTopAfterSelection: number;
	readonly selectedAnchorPath: string;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeHeightDeltaPixels: number;
	readonly treeScrollHeightAfterReady: number;
	readonly treeScrollHeightBeforeSelection: number;
	readonly treeScrollTopAfterReady: number;
	readonly treeScrollTopBeforeSelection: number;
}

interface WorktreeFileScrollExtentSnapshot {
	readonly contentDeclaredTotalSizePixels: number | null;
	readonly contentScrollHeight: number;
	readonly contentScrollTop: number;
	readonly treeDeclaredTotalSizePixels: number | null;
	readonly treeScrollHeight: number;
	readonly treeScrollTop: number;
}

const defaultFileLineHeightPixels = 20;

const browser = await chromium.launch({ headless: true });

try {
	const result = await verifyWorktreeDevServer();
	console.log(
		JSON.stringify(
			{
				ok: true,
				devServerUrl: worktreeDevServerUrl,
				...result,
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
	if (content.length === 0) {
		throw new Error(`Expected non-empty Worktree/File content for ${targetDescriptor.path}`);
	}
	if (surfaceText.includes(content.slice(0, Math.min(80, content.length)))) {
		throw new Error('Expected Worktree/File surface metadata to omit file body content');
	}

	const page = await makeVerificationPage();
	try {
		await page.goto(worktreeDevServerUrl, { waitUntil: 'domcontentloaded', timeout: 30_000 });
		await page.waitForSelector('[data-testid="worktree-file-app"]', { timeout: 30_000 });
		const scrollExtentBeforeSelection = await readWorktreeFileScrollExtentSnapshot(page);
		await clickWorktreeFilePath(page, targetDescriptor.path);
		await page.waitForFunction(
			(path: string): boolean =>
				document
					.querySelector('[data-worktree-open-file-path]')
					?.getAttribute('data-worktree-open-file-path') === path,
			targetDescriptor.path,
			{ timeout: 10_000 },
		);
		const scrollExtentAfterSelection = await readWorktreeFileScrollExtentSnapshot(page);
		await page.waitForFunction(
			(): boolean =>
				document
					.querySelector('[data-worktree-open-file-state]')
					?.getAttribute('data-worktree-open-file-state') === 'ready',
			{ timeout: 20_000 },
		);
		const scrollExtentAfterReady = await readWorktreeFileScrollExtentSnapshot(page);
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
				return {
					selectedCharacterCount: text.length,
					selectedContentState: contentPanel?.getAttribute('data-worktree-open-file-state') ?? null,
					selectedDisplayPath,
					selectedLineCount: text.split('\n').filter((line) => line.length > 0).length,
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
		if (rendered.selectedCharacterCount <= 0 || rendered.selectedLineCount <= 0) {
			throw new Error(`Expected materialized Worktree/File content for ${targetDescriptor.path}`);
		}
		if (rendered.treeTotalSizePixels === null || rendered.treeTotalSizePixels <= 0) {
			throw new Error('Expected Worktree/File tree extent to be reserved from provider facts');
		}
		const scrollExtentCanary = makeScrollExtentCanary({
			afterReady: scrollExtentAfterReady,
			afterSelection: scrollExtentAfterSelection,
			beforeSelection: scrollExtentBeforeSelection,
			selectedAnchorPath: targetDescriptor.path,
		});
		assertWorktreeScrollExtentCanary(scrollExtentCanary);
		return {
			...rendered,
			descriptorCount: descriptors.length,
			frameCount: surface.frames.length,
			packageForbiddenTextAbsent: true,
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
		descriptors.find((candidate) =>
			targetPathOverride === null ? true : candidate.path === targetPathOverride,
		) ?? null;
	if (descriptor === null) {
		throw new Error(
			targetPathOverride === null
				? 'Expected at least one Worktree/File descriptor'
				: `Expected Worktree/File descriptor for ${targetPathOverride}`,
		);
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
			contentScrollHeight: contentPanel.scrollHeight,
			contentScrollTop: contentPanel.scrollTop,
			treeDeclaredTotalSizePixels:
				treeDeclaredTotalSize === null || Number.isFinite(treeDeclaredTotalSize)
					? treeDeclaredTotalSize
					: null,
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
}): WorktreeFileScrollExtentCanary {
	return {
		contentDeclaredTotalSizePixelsAfterReady: props.afterReady.contentDeclaredTotalSizePixels,
		contentDeclaredTotalSizePixelsAfterSelection:
			props.afterSelection.contentDeclaredTotalSizePixels,
		contentHeightDeltaPixels:
			props.afterReady.contentScrollHeight - props.afterSelection.contentScrollHeight,
		contentScrollHeightAfterReady: props.afterReady.contentScrollHeight,
		contentScrollHeightAfterSelection: props.afterSelection.contentScrollHeight,
		contentScrollTopAfterReady: props.afterReady.contentScrollTop,
		contentScrollTopAfterSelection: props.afterSelection.contentScrollTop,
		selectedAnchorPath: props.selectedAnchorPath,
		treeDeclaredTotalSizePixels: props.afterReady.treeDeclaredTotalSizePixels,
		treeHeightDeltaPixels:
			props.afterReady.treeScrollHeight - props.beforeSelection.treeScrollHeight,
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
	if (
		Math.abs(canary.treeScrollHeightAfterReady - canary.treeDeclaredTotalSizePixels) >
		defaultFileLineHeightPixels
	) {
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
	if (Math.abs(canary.contentHeightDeltaPixels) > defaultFileLineHeightPixels) {
		throw new Error(
			`Expected Worktree/File content hydration to keep scroll extent bounded: ${JSON.stringify(canary)}`,
		);
	}
}

function cssAttributeEscape(value: string): string {
	return value.replace(/["\\]/gu, '\\$&');
}

function scenarioNameFromDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	return parsedUrl.searchParams.get('scenario') ?? 'current-worktree';
}
