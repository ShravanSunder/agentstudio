import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

import type { Locator, Page, Response } from 'playwright';
import { expect } from 'vitest';

interface AnnotationOutputCaptureJourneyProps {
	readonly dataRootPath: string;
	readonly page: Page;
	readonly savedBody: string;
	readonly timeoutMilliseconds: number;
	readonly worktreeRoot: string;
}

export interface AnnotationOutputIdentityCapture {
	readonly messageId: string;
	readonly placement: unknown;
	readonly sessionId: string;
	readonly sessionLifecycle: unknown;
	readonly sourceRelationship: unknown;
	readonly threadId: string;
}

export async function verifyAnnotationOutputCaptures(
	props: AnnotationOutputCaptureJourneyProps,
): Promise<AnnotationOutputIdentityCapture> {
	const outputDirectory = join(props.dataRootPath, 'annotation-output-captures');
	const markdownNamesBefore = await outputCaptureNames(outputDirectory, '.md');

	await props.page.getByRole('button', { name: 'Share comments' }).click();
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count > 0);
	const copyButton = props.page.getByRole('button', { name: 'Copy Markdown' });
	await waitForEnabledOutputButton(copyButton, props.timeoutMilliseconds);
	await copyButton.click();
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

	await props.page.getByRole('button', { name: 'Share comments' }).click();
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count === 0);
	const history = props.page.getByRole('button', { name: /^History \([1-9][0-9]*\)$/u });
	await history.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await history.click();
	await props.page
		.getByRole('region', { name: 'Output history' })
		.getByRole('button', { name: 'Mark as not handled' })
		.first()
		.click();
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count > 0);

	const jsonNamesBefore = await outputCaptureNames(outputDirectory, '.json');
	const exportButton = props.page.getByRole('button', { name: 'Export JSON' });
	await waitForEnabledOutputButton(exportButton, props.timeoutMilliseconds);
	const exportResponsePromise = waitForOutputCommandResponse(
		props.page,
		'jsonFile',
		props.timeoutMilliseconds,
	);
	await exportButton.click();
	const exportResponse = await exportResponsePromise;
	const exportResponseBody = await exportResponse.text();
	try {
		await props.page
			.getByRole('region', { name: 'Share comments' })
			.waitFor({ state: 'hidden', timeout: props.timeoutMilliseconds });
	} catch (error: unknown) {
		const alerts = await props.page.getByRole('alert').allTextContents();
		const namesAfter = await outputCaptureNames(outputDirectory, '.json');
		const createdNames = [...namesAfter].filter((name): boolean => !jsonNamesBefore.has(name));
		throw new Error(
			`Export did not dismiss Share comments: status=${exportResponse.status()} body=${exportResponseBody} alerts=${JSON.stringify(alerts)} captures=${JSON.stringify(createdNames)}.`,
			{ cause: error },
		);
	}
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
	let matchingIdentity: AnnotationOutputIdentityCapture | null = null;
	for (const [entryIndex, entry] of entries.entries()) {
		if (
			!isRecord(entry) ||
			!isRecord(entry['message']) ||
			!isRecord(entry['message']['author']) ||
			!isRecord(entry['thread'])
		) {
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
		if (body === props.savedBody) {
			matchingIdentity = outputIdentityCapture(document, entry);
		}
	}
	expect(new Set(messageIds).size).toBe(messageIds.length);
	expect(bodies).toContain(props.savedBody);
	if (matchingIdentity === null) {
		throw new Error('Annotation JSON capture omitted the saved message identity.');
	}

	await props.page.getByRole('button', { name: 'Share comments' }).click();
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count === 0);
	const completedHistory = props.page.getByRole('button', { name: /^History \([2-9][0-9]*\)$/u });
	await completedHistory.waitFor({ state: 'visible', timeout: props.timeoutMilliseconds });
	await completedHistory.click();
	await props.page
		.getByRole('region', { name: 'Output history' })
		.getByRole('button', { name: 'Mark as not handled' })
		.first()
		.click();
	await waitForPendingCommentCount(props.page, props.timeoutMilliseconds, (count) => count > 0);
	return matchingIdentity;
}

function outputIdentityCapture(
	document: Readonly<Record<string, unknown>>,
	entry: Readonly<Record<string, unknown>>,
): AnnotationOutputIdentityCapture {
	const session = document['session'];
	const thread = entry['thread'];
	const message = entry['message'];
	if (!isRecord(session) || !isRecord(thread) || !isRecord(message)) {
		throw new Error('Annotation JSON capture omitted durable identity context.');
	}
	const sessionId = session['sessionId'];
	const sessionLifecycle = session['lifecycle'];
	const sourceRelationship = session['sourceRelationship'];
	const threadId = thread['threadId'];
	const placement = thread['placement'];
	const messageId = message['messageId'];
	if (
		typeof sessionId !== 'string' ||
		sessionLifecycle === undefined ||
		sourceRelationship === undefined ||
		typeof threadId !== 'string' ||
		placement === undefined ||
		typeof messageId !== 'string'
	) {
		throw new Error('Annotation JSON capture contained malformed durable identity context.');
	}
	return {
		messageId,
		placement,
		sessionId,
		sessionLifecycle,
		sourceRelationship,
		threadId,
	};
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

async function waitForOutputCommandResponse(
	page: Page,
	outputKind: 'clipboardMarkdown' | 'jsonFile',
	timeoutMilliseconds: number,
): Promise<Response> {
	return await page.waitForResponse(
		(response): boolean => {
			const request = response.request();
			if (
				request.method() !== 'POST' ||
				new URL(request.url()).pathname !== '/__bridge-product/command'
			) {
				return false;
			}
			const body: unknown = request.postDataJSON();
			if (!isRecord(body) || !isRecord(body['call'])) return false;
			const call = body['call'];
			if (!isRecord(call['request']) || !isRecord(call['request']['operation'])) return false;
			const operation = call['request']['operation'];
			return operation['kind'] === 'output.scope.commit' && operation['outputKind'] === outputKind;
		},
		{ timeout: timeoutMilliseconds },
	);
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
