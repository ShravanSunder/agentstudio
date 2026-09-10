import type { Page } from 'playwright';

export interface AnnotationPreviewEntryCapture {
	readonly authorKind: 'agent' | 'human';
	readonly body: string;
	readonly endLine: number;
	readonly messageId: string;
	readonly path: string;
	readonly startLine: number;
}

export async function captureSharePreview(
	page: Page,
): Promise<readonly AnnotationPreviewEntryCapture[]> {
	return await page
		.getByRole('region', { name: 'Comments to share' })
		.locator('[data-message-id]')
		.evaluateAll((elements) =>
			elements.map((element) => {
				const messageId = element.getAttribute('data-message-id');
				const body = element.querySelector('p')?.textContent;
				const thread = element.closest('[data-thread-id]');
				const path = thread
					?.querySelector('[data-thread-path] [data-slot="item-label"]')
					?.textContent?.trim();
				const metadata = [...element.querySelectorAll('[data-slot="item-metadata"]')].map(
					(candidate) => candidate.textContent?.trim() ?? '',
				);
				const authorLabel = metadata.find((value) => value === 'Agent' || value === 'You');
				const lineRange = metadata.find((value) => /^Lines? \d+(?:–\d+)?$/u.test(value));
				if (
					messageId === null ||
					body === undefined ||
					body === null ||
					path === undefined ||
					authorLabel === undefined ||
					lineRange === undefined
				) {
					throw new Error('Share preview omitted message identity, body, author, path, or range.');
				}
				const rangeMatch = /^Line (\d+)$|^Lines (\d+)–(\d+)$/u.exec(lineRange);
				if (rangeMatch === null) throw new Error('Share preview contained a malformed line range.');
				const startLine = Number(rangeMatch[1] ?? rangeMatch[2]);
				const endLine = Number(rangeMatch[1] ?? rangeMatch[3]);
				return {
					authorKind: authorLabel === 'Agent' ? ('agent' as const) : ('human' as const),
					body,
					endLine,
					messageId,
					path,
					startLine,
				};
			}),
		);
}

export function normalizedAnnotationEntries(
	entries: readonly AnnotationPreviewEntryCapture[],
): ReadonlyMap<string, Omit<AnnotationPreviewEntryCapture, 'messageId'>> {
	return new Map(
		entries.map(({ messageId, ...entry }) => [messageId.toLowerCase(), entry] as const),
	);
}
