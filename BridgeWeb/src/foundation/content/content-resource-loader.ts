import type { BridgeContentHandle } from '../review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../telemetry/bridge-telemetry-recorder.js';
import { bridgeTraceparent, type BridgeTraceContext } from '../telemetry/bridge-trace-context.js';

export interface BridgeContentResource {
	readonly handle: BridgeContentHandle;
	readonly text: string;
}

export interface BridgeContentFetch {
	(url: string, init?: RequestInit): Promise<Response>;
}

export interface LoadBridgeContentResourceProps {
	readonly handle: BridgeContentHandle;
	readonly fetchContent?: BridgeContentFetch;
	readonly traceContext?: BridgeTraceContext | null;
	readonly sendTraceparentHeader?: boolean;
	readonly signal?: AbortSignal;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
}

export async function loadBridgeContentResource(
	props: LoadBridgeContentResourceProps,
): Promise<BridgeContentResource> {
	const fetchContent = props.fetchContent ?? fetch;
	const traceContext = props.traceContext ?? null;
	const start = performance.now();
	try {
		const response = await fetchContent(
			props.handle.resourceUrl,
			requestInitForContentFetch({
				traceContext,
				sendTraceparentHeader: props.sendTraceparentHeader ?? false,
				signal: props.signal,
			}),
		);
		if (!response.ok) {
			throw new Error(`Bridge content request failed: ${response.status}`);
		}
		return {
			handle: props.handle,
			text: await response.text(),
		};
	} finally {
		props.telemetryRecorder?.record({
			scope: 'web',
			name: 'performance.bridge.web.content_fetch',
			durationMilliseconds: Math.max(0, performance.now() - start),
			traceContext,
			stringAttributes: {
				'agentstudio.bridge.content.correlation_mode':
					props.sendTraceparentHeader === true && traceContext !== null ? 'traceparent' : 'summary',
				'agentstudio.bridge.content.role': props.handle.role,
				'agentstudio.bridge.phase': 'fetch',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.slice': 'content_fetch',
				'agentstudio.bridge.transport': 'content',
			},
			numericAttributes: {},
			booleanAttributes: {
				'agentstudio.bridge.header_missing': props.sendTraceparentHeader !== true,
				'agentstudio.bridge.header_supported': props.sendTraceparentHeader === true,
			},
		});
		props.telemetryRecorder?.flush();
	}
}

interface RequestInitForContentFetchProps {
	readonly traceContext: BridgeTraceContext | null;
	readonly sendTraceparentHeader: boolean;
	readonly signal: AbortSignal | undefined;
}

function requestInitForContentFetch(
	props: RequestInitForContentFetchProps,
): RequestInit | undefined {
	const headers =
		props.sendTraceparentHeader && props.traceContext !== null
			? { traceparent: bridgeTraceparent(props.traceContext) }
			: undefined;
	if (headers === undefined && props.signal === undefined) {
		return undefined;
	}
	return {
		...(headers === undefined ? {} : { headers }),
		...(props.signal === undefined ? {} : { signal: props.signal }),
	};
}
