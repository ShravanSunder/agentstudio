import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { Locator, Page } from 'playwright';
import { expect } from 'vitest';

interface AnnotationOutputCaptureJourneyProps {
	readonly dataRootPath: string;
	readonly page: Page;
	readonly savedBody: string;
	readonly timeoutMilliseconds: number;
	readonly worktreeRoot: string;
}

export async function verifyAnnotationOutputCaptures(
	props: AnnotationOutputCaptureJourneyProps,
): Promise<void> {
	const outputDirectory = join(props.dataRootPath, 'annotation-output-captures');
	const markdownNamesBefore = await outputCaptureNames(outputDirectory, '.md');

	await props.page.getByRole('button', { name: 'Share comments' }).press('Enter');
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count > 0);
	const copyButton = props.page.getByRole('button', { name: 'Copy Markdown' });
	await waitForEnabledOutputButton(copyButton, props.timeoutMilliseconds);
	await copyButton.press('Enter');
	await props.page
		.getByRole('region', { name: 'Share comments' })
		.waitFor({ state: 'hidden', timeout: props.timeoutMilliseconds });

	const markdownPath = await requireNewOutputCapture({
		extension: '.md',
		namesBefore: markdownNamesBefore,
		outputDirectory,
	});
	const markdown = await readFile(markdownPath, 'utf8');
	expect(markdown).toContain(props.savedBody);
	expect(markdown).not.toContain(props.worktreeRoot);
	expect(markdown.match(/^# /gmu)).toHaveLength(1);

	await props.page.getByRole('button', { name: 'Share comments' }).press('Enter');
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count === 0);
	const history = props.page.getByRole('button', { name: /^History \([1-9][0-9]*\)$/u });
	await history.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await history.press('Enter');
	await props.page
		.getByRole('region', { name: 'Output history' })
		.getByRole('button', { name: 'Mark as not handled' })
		.first()
		.press('Enter');
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count > 0);

	const jsonNamesBefore = await outputCaptureNames(outputDirectory, '.json');
	const exportButton = props.page.getByRole('button', { name: 'Export JSON' });
	await waitForEnabledOutputButton(exportButton, props.timeoutMilliseconds);
	await exportButton.press('Enter');
	await props.page
		.getByRole('region', { name: 'Share comments' })
		.waitFor({ state: 'hidden', timeout: props.timeoutMilliseconds });
	const jsonPath = await requireNewOutputCapture({
		extension: '.json',
		namesBefore: jsonNamesBefore,
		outputDirectory,
	});
	const document: unknown = JSON.parse(await readFile(jsonPath, 'utf8'));
	expect(document).toMatchObject({
		formatVersion: 2,
		schema: 'agentstudio.worktree-annotations.batch',
	});
	if (!isRecord(document) || !Array.isArray(document['entries'])) {
		throw new Error('Annotation JSON capture did not contain an entries array.');
	}
	const entries = document['entries'];
	expect(entries.length).toBeGreaterThan(0);
	const messageIds: string[] = [];
	const bodies: string[] = [];
	for (const [entryIndex, entry] of entries.entries()) {
		if (!isRecord(entry) || !isRecord(entry['message']) || !isRecord(entry['message']['author'])) {
			throw new Error(`Annotation JSON entry ${entryIndex} was malformed.`);
		}
		expect(entry['batchOrdinal']).toBe(entryIndex);
		expect(entry['message']['author']['kind']).toBe('human');
		const messageId = entry['message']['messageId'];
		const body = entry['message']['bodyMarkdown'];
		if (typeof messageId !== 'string' || typeof body !== 'string') {
			throw new Error(`Annotation JSON entry ${entryIndex} omitted message identity or body.`);
		}
		messageIds.push(messageId);
		bodies.push(body);
	}
	expect(new Set(messageIds).size).toBe(messageIds.length);
	expect(bodies).toContain(props.savedBody);

	await props.page.getByRole('button', { name: 'Share comments' }).press('Enter');
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count === 0);
	const completedHistory = props.page.getByRole('button', { name: /^History \([2-9][0-9]*\)$/u });
	await completedHistory.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await completedHistory.press('Enter');
	await props.page
		.getByRole('region', { name: 'Output history' })
		.getByRole('button', { name: 'Mark as not handled' })
		.first()
		.press('Enter');
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count > 0);
}

async function outputCaptureNames(
	outputDirectory: string,
	extension: string,
): Promise<Set<string>> {
	try {
		return new Set(
			(await readdir(outputDirectory)).filter((name): boolean => name.endsWith(extension)),
		);
	} catch (error: unknown) {
		if (isRecord(error) && error['code'] === 'ENOENT') return new Set();
		throw error;
	}
}

async function requireNewOutputCapture(props: {
	readonly extension: string;
	readonly namesBefore: ReadonlySet<string>;
	readonly outputDirectory: string;
}): Promise<string> {
	const namesAfter = await outputCaptureNames(props.outputDirectory, props.extension);
	const createdNames = [...namesAfter].filter((name): boolean => !props.namesBefore.has(name));
	if (createdNames.length !== 1) {
		throw new Error(
			`Expected one new ${props.extension} annotation capture, received ${JSON.stringify(createdNames)}.`,
		);
	}
	return join(props.outputDirectory, createdNames[0] ?? '');
}

async function waitForPendingCommentCount(
	page: Page,
	timeoutMilliseconds: number,
	accept: (count: number) => boolean,
): Promise<void> {
	await expect
		.poll(
			async (): Promise<number | null> => {
				const label = await page
					.locator('[aria-label^="Pending comments, "]')
					.getAttribute('aria-label');
				if (label === null) return null;
				const count = Number(label.slice('Pending comments, '.length));
				return Number.isInteger(count) && accept(count) ? count : null;
			},
			{ timeout: timeoutMilliseconds },
		)
		.not.toBeNull();
}

async function waitForEnabledOutputButton(
	button: Locator,
	timeoutMilliseconds: number,
): Promise<void> {
	await expect
		.poll(async (): Promise<boolean> => button.isEnabled(), { timeout: timeoutMilliseconds })
		.toBe(true);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
