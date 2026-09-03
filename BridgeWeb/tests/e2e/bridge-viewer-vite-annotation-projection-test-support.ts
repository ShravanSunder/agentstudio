import { type Page, type Response } from 'playwright';
import { expect } from 'vitest';

const annotationProjectionResponseTimeoutMilliseconds = 30_000;

export async function annotationProjectionUiDiagnostic(
	page: Page,
	savedBody: string | null,
): Promise<{
	readonly committedPreviewCount: number;
	readonly composerCount: number;
	readonly refreshingCount: number;
	readonly savedBodyCount: number;
	readonly threadCount: number;
	readonly unavailableCount: number;
}> {
	return {
		committedPreviewCount: await page
			.getByTestId('worktree-annotation-committed-pending-projection')
			.count(),
		composerCount: await page
			.getByRole('textbox', { name: 'Write an annotation in Markdown' })
			.count(),
		refreshingCount: await page.getByText('Refreshing', { exact: true }).count(),
		savedBodyCount:
			savedBody === null ? 0 : await page.getByText(savedBody, { exact: true }).count(),
		threadCount: await page.getByTestId('worktree-annotation-thread').count(),
		unavailableCount: await page.getByText('Updates unavailable', { exact: true }).count(),
	};
}

export function annotationProjectionContentRequestDiagnostic(value: unknown): unknown {
	if (!isUnknownRecord(value) || value['contentKind'] !== 'annotation.projection') return null;
	const descriptor = value['descriptor'];
	const page = isUnknownRecord(descriptor) ? descriptor['page'] : null;
	return {
		contentRequestId: value['contentRequestId'],
		descriptorId: isUnknownRecord(descriptor) ? descriptor['descriptorId'] : null,
		page: isUnknownRecord(page)
			? {
					operationCorrelationId: page['operationCorrelationId'],
					projectionRevision: page['projectionRevision'],
					snapshotId: page['snapshotId'],
				}
			: null,
	};
}

export function annotationProjectionQueryResultDiagnostic(
	value: unknown,
	request: unknown,
): unknown {
	if (!isUnknownRecord(value)) return { shape: typeof value };
	if (value['kind'] === 'request.error') {
		return {
			code: value['code'],
			kind: value['kind'],
			nextExpectedRequestSequence: value['nextExpectedRequestSequence'],
			requestSequence: value['requestSequence'],
			retryable: value['retryable'],
			safeMessage: value['safeMessage'],
		};
	}
	const call = value['call'];
	if (!isUnknownRecord(call)) return { kind: value['kind'] };
	const result = call['result'];
	if (!isUnknownRecord(result)) return { kind: value['kind'], resultShape: typeof result };
	const descriptor = result['descriptor'];
	if (!isUnknownRecord(descriptor)) {
		return {
			code: result['code'],
			kind: value['kind'],
			resultKind: result['kind'],
		};
	}
	const page = descriptor['page'];
	return {
		descriptorPresent: true,
		kind: value['kind'],
		request: isUnknownRecord(request)
			? {
					cursor: request['cursor'],
					operationCorrelationId: request['operationCorrelationId'],
					sessionIds: request['sessionIds'],
					sourceGeneration: request['sourceGeneration'],
				}
			: null,
		requestSequence: value['requestSequence'],
		page: isUnknownRecord(page)
			? {
					descriptorId: descriptor['descriptorId'],
					expectedMessageCount: page['expectedMessageCount'],
					expectedSessionCount: page['expectedSessionCount'],
					expectedThreadCount: page['expectedThreadCount'],
					operationCorrelationId: page['operationCorrelationId'],
					pageOrdinal: page['pageOrdinal'],
					projectionRevision: page['projectionRevision'],
					snapshotId: page['snapshotId'],
					sourceGeneration: page['sourceGeneration'],
				}
			: null,
	};
}

export async function waitForDemandedAnnotationProjectionContent(props: {
	readonly afterRequestSequence: Promise<number>;
	readonly page: Page;
	readonly sessionId: Promise<string>;
}): Promise<void> {
	const matchingDescriptorIds = new Set<string>();
	const completedDescriptorIds = new Set<string>();
	let resolveMatch: (() => void) | null = null;
	let rejectMatch: ((error: Error) => void) | null = null;
	let settled = false;
	const completion = new Promise<void>((resolve, reject): void => {
		resolveMatch = resolve;
		rejectMatch = reject;
	});
	const settleIfMatched = (descriptorId: string): void => {
		if (settled || !matchingDescriptorIds.has(descriptorId)) return;
		if (!completedDescriptorIds.has(descriptorId)) return;
		settled = true;
		resolveMatch?.();
	};
	const inspectResponse = async (response: Response): Promise<void> => {
		const request = response.request();
		const path = new URL(request.url()).pathname;
		const requestBody: unknown = request.postDataJSON();
		if (path === '/__bridge-product/content') {
			if (!response.ok()) return;
			const descriptorId = annotationProjectionContentDescriptorId(requestBody);
			if (descriptorId === null) return;
			completedDescriptorIds.add(descriptorId);
			settleIfMatched(descriptorId);
			return;
		}
		if (path !== '/__bridge-product/command' || !response.ok()) return;
		if (!isUnknownRecord(requestBody) || !isUnknownRecord(requestBody['call'])) return;
		const call = requestBody['call'];
		if (
			call['method'] !== 'file.annotations.projection.query' &&
			call['method'] !== 'review.annotations.projection.query'
		) {
			return;
		}
		if (!isUnknownRecord(call['request'])) return;
		const queryRequest = call['request'];
		const [afterRequestSequence, sessionId, responseBody] = await Promise.all([
			props.afterRequestSequence,
			props.sessionId,
			response.json() as Promise<unknown>,
		]);
		if (
			!Array.isArray(queryRequest['sessionIds']) ||
			!queryRequest['sessionIds'].includes(sessionId) ||
			!isUnknownRecord(responseBody) ||
			typeof responseBody['requestSequence'] !== 'number' ||
			responseBody['requestSequence'] <= afterRequestSequence ||
			!isUnknownRecord(responseBody['call']) ||
			!isUnknownRecord(responseBody['call']['result']) ||
			!isUnknownRecord(responseBody['call']['result']['descriptor'])
		) {
			return;
		}
		const descriptorId = responseBody['call']['result']['descriptor']['descriptorId'];
		if (typeof descriptorId !== 'string') return;
		matchingDescriptorIds.add(descriptorId);
		settleIfMatched(descriptorId);
	};
	const responseListener = (response: Response): void => {
		void inspectResponse(response).catch((error: unknown): void => {
			if (settled) return;
			settled = true;
			rejectMatch?.(
				error instanceof Error
					? error
					: new Error('Demanded annotation projection inspection failed.'),
			);
		});
	};
	props.page.on('response', responseListener);
	try {
		await expect
			.poll((): boolean => settled, {
				timeout: annotationProjectionResponseTimeoutMilliseconds,
			})
			.toBe(true);
		await completion;
	} finally {
		props.page.off('response', responseListener);
	}
}

function annotationProjectionContentDescriptorId(value: unknown): string | null {
	if (!isUnknownRecord(value) || value['contentKind'] !== 'annotation.projection') return null;
	const descriptor = value['descriptor'];
	return isUnknownRecord(descriptor) && typeof descriptor['descriptorId'] === 'string'
		? descriptor['descriptorId']
		: null;
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
