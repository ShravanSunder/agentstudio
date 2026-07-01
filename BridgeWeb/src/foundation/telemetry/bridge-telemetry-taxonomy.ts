import { z } from 'zod';

export const bridgeTelemetryPlaneSchema = z.enum(['data', 'control', 'observability']);
export const bridgeTelemetryPrioritySchema = z.enum(['hot', 'warm', 'cold', 'best_effort']);
export const bridgeTelemetrySliceSchema = z.enum([
	'diff_status',
	'diff_files',
	'review_threads',
	'review_viewed_files',
	'review_metadata',
	'review_delta',
	'review_invalidation',
	'review_reset',
	'connection_health',
	'command_acks',
	'review_rpc',
	'content_fetch',
	'review_projection',
	'tree_prepare_input',
	'code_view_item',
	'code_view_scroll',
	'code_view_virtual_range',
	'shiki_highlight',
	'worker_task',
	'telemetry_batch',
	'telemetry_ingest',
	'telemetry_drop',
	'unknown',
]);

export type BridgeTelemetryPlane = z.infer<typeof bridgeTelemetryPlaneSchema>;
export type BridgeTelemetryPriority = z.infer<typeof bridgeTelemetryPrioritySchema>;
export type BridgeTelemetrySlice = z.infer<typeof bridgeTelemetrySliceSchema>;

export function planeForBridgeTelemetrySlice(slice: BridgeTelemetrySlice): BridgeTelemetryPlane {
	switch (slice) {
		case 'connection_health':
		case 'command_acks':
		case 'review_rpc':
			return 'control';
		case 'telemetry_batch':
		case 'telemetry_ingest':
		case 'telemetry_drop':
			return 'observability';
		case 'code_view_scroll':
			return 'control';
		case 'diff_status':
		case 'diff_files':
		case 'review_threads':
		case 'review_viewed_files':
		case 'review_metadata':
		case 'review_delta':
		case 'review_invalidation':
		case 'review_reset':
		case 'content_fetch':
		case 'review_projection':
		case 'tree_prepare_input':
		case 'code_view_item':
		case 'code_view_virtual_range':
		case 'shiki_highlight':
		case 'worker_task':
		case 'unknown':
			return 'data';
	}
	return 'data';
}

export function priorityForBridgeTelemetrySlice(
	slice: BridgeTelemetrySlice,
): BridgeTelemetryPriority {
	switch (slice) {
		case 'diff_status':
		case 'connection_health':
		case 'content_fetch':
			return 'hot';
		case 'review_delta':
		case 'review_invalidation':
		case 'review_reset':
		case 'review_threads':
		case 'review_viewed_files':
		case 'command_acks':
		case 'review_rpc':
		case 'review_projection':
		case 'tree_prepare_input':
		case 'worker_task':
			return 'warm';
		case 'code_view_item':
		case 'code_view_scroll':
		case 'code_view_virtual_range':
		case 'shiki_highlight':
			return 'hot';
		case 'telemetry_batch':
		case 'telemetry_ingest':
		case 'telemetry_drop':
			return 'best_effort';
		case 'review_metadata':
		case 'diff_files':
		case 'unknown':
			return 'cold';
	}
	return 'cold';
}
