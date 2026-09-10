export const worktreeAnnotationMaximumBodyUTF8Bytes = 16 * 1024;

export type WorktreeAnnotationMarkdownValidation =
	| { readonly ok: true }
	| {
			readonly code:
				| 'bodyTooLarge'
				| 'emptyBody'
				| 'levelOneHeading'
				| 'rawHtml'
				| 'unsafeLinkDestination';
			readonly ok: false;
	  };

export function validateWorktreeAnnotationMarkdown(
	body: string,
): WorktreeAnnotationMarkdownValidation {
	if (body.trim().length === 0) return { code: 'emptyBody', ok: false };
	if (new TextEncoder().encode(body).byteLength > worktreeAnnotationMaximumBodyUTF8Bytes) {
		return { code: 'bodyTooLarge', ok: false };
	}
	const visibleMarkdown = markdownOutsideFencedCode(body);
	if (containsLevelOneHeading(visibleMarkdown)) {
		return { code: 'levelOneHeading', ok: false };
	}
	if (containsRawHtml(visibleMarkdown)) return { code: 'rawHtml', ok: false };
	if (containsUnsafeLinkDestination(visibleMarkdown)) {
		return { code: 'unsafeLinkDestination', ok: false };
	}
	return { ok: true };
}

function markdownOutsideFencedCode(body: string): string {
	let activeFence: { readonly marker: '`' | '~'; readonly length: number } | null = null;
	return body
		.split('\n')
		.map((line): string => {
			const fence = fenceRun(line);
			if (fence === null) return activeFence === null ? stripInlineCode(line) : '';
			if (activeFence !== null) {
				if (fence.marker === activeFence.marker && fence.length >= activeFence.length) {
					activeFence = null;
				}
				return '';
			}
			activeFence = fence;
			return '';
		})
		.join('\n');
}

function fenceRun(line: string): { readonly marker: '`' | '~'; readonly length: number } | null {
	const leadingSpaces = line.match(/^ */u)?.[0].length ?? 0;
	if (leadingSpaces > 3) return null;
	const marker = line[leadingSpaces];
	if (marker !== '`' && marker !== '~') return null;
	let length = 0;
	while (line[leadingSpaces + length] === marker) length += 1;
	return length >= 3 ? { length, marker } : null;
}

function stripInlineCode(line: string): string {
	let result = '';
	let index = 0;
	while (index < line.length) {
		if (line[index] !== '`') {
			result += line[index] ?? '';
			index += 1;
			continue;
		}
		const runStart = index;
		while (line[index] === '`') index += 1;
		const delimiter = line.slice(runStart, index);
		const closingIndex = line.indexOf(delimiter, index);
		if (closingIndex < 0) {
			result += delimiter;
			continue;
		}
		const closingEnd = closingIndex + delimiter.length;
		result += ' '.repeat(closingEnd - runStart);
		index = closingEnd;
	}
	return result;
}

function containsLevelOneHeading(markdown: string): boolean {
	const lines = markdown.split('\n');
	for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
		const line = lines[lineIndex] ?? '';
		if (/^[ ]{0,3}#(?:[\t ]+|$)/u.test(line)) return true;
		if (
			lineIndex > 0 &&
			(lines[lineIndex - 1]?.trim().length ?? 0) > 0 &&
			/^[ ]{0,3}=+[\t ]*$/u.test(line)
		) {
			return true;
		}
	}
	return false;
}

function containsRawHtml(markdown: string): boolean {
	return /<!--.*?-->|<\/?[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*)?\s*\/?>|<\?.*?\?>|<![A-Z]+[^>]*>/isu.test(
		markdown,
	);
}

function containsUnsafeLinkDestination(markdown: string): boolean {
	const linkDestination = /\]\(\s*<?([^\s>)]+)/gu;
	for (const match of markdown.matchAll(linkDestination)) {
		const destination = match[1];
		if (destination === undefined || !isAbsoluteHTTPURL(destination)) return true;
	}
	return false;
}

export function isAbsoluteHTTPURL(value: string): boolean {
	try {
		const url = new URL(value);
		return (url.protocol === 'http:' || url.protocol === 'https:') && url.hostname.length > 0;
	} catch {
		return false;
	}
}
