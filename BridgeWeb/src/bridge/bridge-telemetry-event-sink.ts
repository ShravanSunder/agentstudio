import type { BridgeTelemetryBatch } from '../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetrySink } from '../foundation/telemetry/bridge-telemetry-sink.js';

export interface CreateBridgeTelemetryEventSinkProps {
	readonly endpointUrl?: string;
	readonly fetch?: (input: RequestInfo | URL, init?: RequestInit) => boolean | Promise<Response>;
}

interface PendingTelemetryPost {
	readonly body: string;
}

export function createBridgeTelemetryEventSink(
	props: CreateBridgeTelemetryEventSinkProps,
): BridgeTelemetrySink {
	const endpointUrl = props.endpointUrl ?? 'agentstudio://telemetry/batch';
	const fetchTelemetry = props.fetch ?? globalThis.fetch.bind(globalThis);
	const pendingPosts: PendingTelemetryPost[] = [];
	let isPostInFlight = false;
	const startNextPost = (startProps: {
		readonly currentFlushPost?: PendingTelemetryPost;
	}): void => {
		if (isPostInFlight) {
			return;
		}
		const post = pendingPosts[0];
		if (post === undefined) {
			return;
		}
		isPostInFlight = true;
		let postResult: boolean | Promise<Response>;
		try {
			postResult = fetchTelemetry(endpointUrl, {
				body: post.body,
				headers: { 'Content-Type': 'application/json' },
				method: 'POST',
			});
		} catch (error) {
			isPostInFlight = false;
			if (startProps.currentFlushPost === post) {
				pendingPosts.shift();
				throw error;
			}
			return;
		}
		pendingPosts.shift();
		void Promise.resolve(postResult)
			.catch(() => undefined)
			.finally((): void => {
				isPostInFlight = false;
				startNextPost({});
			});
	};
	const enqueuePost = (body: string): void => {
		const post = { body };
		pendingPosts.push(post);
		startNextPost({ currentFlushPost: post });
	};
	return {
		flush: (batch: BridgeTelemetryBatch): boolean => {
			try {
				enqueuePost(JSON.stringify(batch));
				return true;
			} catch {
				return false;
			}
		},
	};
}
