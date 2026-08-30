import type { Page, Request } from 'playwright';

interface WorktreeFileContentRouteTimingObservation {
	readonly requestStartedMilliseconds: Promise<number>;
	readonly responseStartedMilliseconds: Promise<number>;
}

export function observeWorktreeFileContentRouteTiming(props: {
	readonly page: Page;
	readonly startedAt: number;
	readonly timeoutMilliseconds: number;
}): WorktreeFileContentRouteTimingObservation {
	const requestStartedMilliseconds = props.page
		.waitForRequest(requestIsWorktreeFileContent, { timeout: props.timeoutMilliseconds })
		.then((): number => Math.max(0, performance.now() - props.startedAt));
	const responseStartedMilliseconds = props.page
		.waitForResponse((response): boolean => requestIsWorktreeFileContent(response.request()), {
			timeout: props.timeoutMilliseconds,
		})
		.then((): number => Math.max(0, performance.now() - props.startedAt));
	return { requestStartedMilliseconds, responseStartedMilliseconds };
}

function requestIsWorktreeFileContent(request: Request): boolean {
	if (
		request.method() !== 'POST' ||
		new URL(request.url()).pathname !== '/__bridge-product/content'
	) {
		return false;
	}
	const encodedBody = request.postData();
	if (encodedBody === null) return false;
	try {
		const decodedBody: unknown = JSON.parse(encodedBody);
		return (
			typeof decodedBody === 'object' &&
			decodedBody !== null &&
			'kind' in decodedBody &&
			decodedBody.kind === 'content.open' &&
			'contentKind' in decodedBody &&
			decodedBody.contentKind === 'file.content'
		);
	} catch {
		return false;
	}
}
