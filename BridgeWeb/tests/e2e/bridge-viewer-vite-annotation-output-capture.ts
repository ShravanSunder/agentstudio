import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { Page } from 'playwright';
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
	const pendingScope = props.page.locator('[aria-label^="Pending comments, "]');
	await pendingScope.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await props.page.getByRole('button', { name: 'Copy Markdown' }).press('Enter');
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
	const history = props.page.getByRole('button', { name: /^History \([1-9][0-9]*\)$/u });
	await history.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await history.press('Enter');
	await props.page
		.getByRole('region', { name: 'Output history' })
		.getByRole('button', { name: 'Mark as not handled' })
		.first()
		.press('Enter');
	await waitForPendingCommentMembership(props.page, props.timeoutMilliseconds);

	const jsonNamesBefore = await outputCaptureNames(outputDirectory, '.json');
	await props.page.getByRole('button', { name: 'Export JSON' }).press('Enter');
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
		formatVersion: 1,
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
		if (!isRecord(entry) || !isRecord(entry['message'])) {
			throw new Error(`Annotation JSON entry ${entryIndex} was malformed.`);
		}
		expect(entry['batchOrdinal']).toBe(entryIndex);
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
	const completedHistory = props.page.getByRole('button', { name: /^History \([2-9][0-9]*\)$/u });
	await completedHistory.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await completedHistory.press('Enter');
	await props.page
		.getByRole('region', { name: 'Output history' })
		.getByRole('button', { name: 'Mark as not handled' })
		.first()
		.press('Enter');
	await waitForPendingCommentMembership(props.page, props.timeoutMilliseconds);
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

async function waitForPendingCommentMembership(
	page: Page,
	timeoutMilliseconds: number,
): Promise<void> {
	await page.waitForFunction(
		(): boolean => {
			const label = document
				.querySelector('[aria-label^="Pending comments, "]')
				?.getAttribute('aria-label');
			if (label === undefined || label === null) return false;
			const count = Number(label.slice('Pending comments, '.length));
			return Number.isInteger(count) && count > 0;
		},
		undefined,
		{ timeout: timeoutMilliseconds },
	);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
