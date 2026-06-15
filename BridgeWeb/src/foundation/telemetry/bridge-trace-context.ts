import { z } from 'zod';

export interface BridgeTraceContext {
	readonly traceId: string;
	readonly spanId: string;
	readonly parentSpanId: string | null;
	readonly sampled: boolean;
}

const lowercaseTraceIdPattern = /^[0-9a-f]{32}$/u;
const lowercaseSpanIdPattern = /^[0-9a-f]{16}$/u;

const bridgeTraceContextSchema = z.object({
	traceId: z
		.string()
		.regex(lowercaseTraceIdPattern)
		.refine((value: string): boolean => !isAllZero(value)),
	spanId: z
		.string()
		.regex(lowercaseSpanIdPattern)
		.refine((value: string): boolean => !isAllZero(value)),
	parentSpanId: z
		.string()
		.regex(lowercaseSpanIdPattern)
		.refine((value: string): boolean => !isAllZero(value))
		.nullable(),
	sampled: z.boolean(),
});

export function decodeBridgeTraceContext(value: unknown): BridgeTraceContext | null {
	const result = bridgeTraceContextSchema.safeParse(value);
	return result.success ? result.data : null;
}

export function bridgeTraceparent(context: BridgeTraceContext): string {
	return `00-${context.traceId}-${context.spanId}-${context.sampled ? '01' : '00'}`;
}

export function parseBridgeTraceparent(value: string): BridgeTraceContext | null {
	const parts = value.split('-');
	if (parts.length !== 4 || parts[0] !== '00' || !/^[0-9a-f]{2}$/u.test(parts[3] ?? '')) {
		return null;
	}
	return decodeBridgeTraceContext({
		traceId: parts[1],
		spanId: parts[2],
		parentSpanId: null,
		sampled: (Number.parseInt(parts[3] ?? '00', 16) & 1) === 1,
	});
}

export function createBridgeChildTraceContext(
	parent: BridgeTraceContext,
	createSpanId: () => string = createRandomSpanId,
): BridgeTraceContext | null {
	return decodeBridgeTraceContext({
		traceId: parent.traceId,
		spanId: createSpanId(),
		parentSpanId: parent.spanId,
		sampled: parent.sampled,
	});
}

function createRandomSpanId(): string {
	return createRandomHex(8);
}

function createRandomHex(byteCount: number): string {
	const bytes = new Uint8Array(byteCount);
	crypto.getRandomValues(bytes);
	return Array.from(bytes, (byte: number): string => byte.toString(16).padStart(2, '0')).join('');
}

function isAllZero(value: string): boolean {
	return /^0+$/u.test(value);
}
