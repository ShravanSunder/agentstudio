import { resolve } from 'node:path';

import { z } from 'zod';

import { resolveAllowedWorktreeRoot, resolveDefaultBaseRef } from './files.ts';

export const bridgeWorktreeDevScenarioNameSchema = z.enum(['current-worktree']);
export type BridgeWorktreeDevScenarioName = z.infer<typeof bridgeWorktreeDevScenarioNameSchema>;

export const bridgeWorktreeDevProviderConfigSchema = z
	.object({
		baseRef: z.string().min(1),
		scenarioName: bridgeWorktreeDevScenarioNameSchema,
		worktreeRoot: z.string().min(1),
	})
	.strict();

export type BridgeWorktreeDevProviderConfig = z.infer<typeof bridgeWorktreeDevProviderConfigSchema>;

export interface ResolveBridgeWorktreeDevProviderConfigProps {
	readonly env: Readonly<Record<string, string | undefined>>;
	readonly packageRoot: string;
	readonly requestUrl: string | null;
}

export async function resolveBridgeWorktreeDevProviderConfig(
	props: ResolveBridgeWorktreeDevProviderConfigProps,
): Promise<BridgeWorktreeDevProviderConfig> {
	const requestSearchParams = searchParamsForRequestUrl(props.requestUrl);
	rejectRawPathOverrides(requestSearchParams);
	const scenarioName = parseBridgeWorktreeDevScenarioName(
		firstNonEmptyStringOrNull([
			requestSearchParams.get('scenario'),
			props.env['BRIDGE_WEB_DEV_SCENARIO'],
			'current-worktree',
		]) ?? 'current-worktree',
	);
	const worktreeRoot = await resolveAllowedWorktreeRoot(
		firstNonEmptyStringOrNull([
			props.env['BRIDGE_WEB_DEV_WORKTREE'],
			resolve(props.packageRoot, '..'),
		]) ?? resolve(props.packageRoot, '..'),
	);
	const baseRef =
		firstNonEmptyStringOrNull([
			requestSearchParams.get('base'),
			props.env['BRIDGE_WEB_DEV_BASE'],
			null,
		]) ?? (await resolveDefaultBaseRef(worktreeRoot));
	return bridgeWorktreeDevProviderConfigSchema.parse({ baseRef, scenarioName, worktreeRoot });
}

function searchParamsForRequestUrl(requestUrl: string | null): URLSearchParams {
	if (requestUrl === null) {
		return new URLSearchParams();
	}
	const parsedUrl = new URL(requestUrl, 'http://127.0.0.1');
	if (requestUrl.includes('://') && !isLoopbackHostname(parsedUrl.hostname)) {
		throw new Error('Bridge worktree dev provider request URL must use a loopback host');
	}
	return parsedUrl.searchParams;
}

function isLoopbackHostname(hostname: string): boolean {
	return hostname === '127.0.0.1' || hostname === 'localhost' || hostname === '[::1]';
}

function rejectRawPathOverrides(searchParams: URLSearchParams): void {
	for (const rawPathOverrideName of ['worktree', 'repo', 'base']) {
		if (searchParams.has(rawPathOverrideName)) {
			throw new Error(
				'Bridge worktree dev provider rejects raw worktree, repo, or base query parameters; use scenario instead',
			);
		}
	}
}

function parseBridgeWorktreeDevScenarioName(
	rawScenarioName: string,
): BridgeWorktreeDevScenarioName {
	const parsedScenarioName = bridgeWorktreeDevScenarioNameSchema.safeParse(rawScenarioName);
	if (!parsedScenarioName.success) {
		throw new Error(
			`Invalid Bridge worktree dev provider config: unknown scenario ${rawScenarioName}`,
		);
	}
	return parsedScenarioName.data;
}

function firstNonEmptyStringOrNull(values: readonly (string | null | undefined)[]): string | null {
	return (
		values.find(
			(candidate): candidate is string =>
				candidate !== null && candidate !== undefined && candidate.length > 0,
		) ?? null
	);
}
