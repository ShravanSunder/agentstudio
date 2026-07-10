const bridgeProductStrictJSONMaximumInputBytes = 256 * 1024;
const bridgeProductStrictJSONMaximumNestingDepth = 64;
const bridgeProductStrictJSONMaximumObjectMembers = 64;

export type BridgeProductStrictJSONFailureCode =
	| 'duplicate_object_member'
	| 'input_exceeds_ceiling'
	| 'invalid_json'
	| 'invalid_utf8'
	| 'nesting_exceeds_ceiling'
	| 'object_member_count_exceeds_ceiling';

export class BridgeProductStrictJSONError extends Error {
	readonly failureCode: BridgeProductStrictJSONFailureCode;

	constructor(failureCode: BridgeProductStrictJSONFailureCode, message: string) {
		super(message);
		this.name = 'BridgeProductStrictJSONError';
		this.failureCode = failureCode;
	}
}

type BridgeProductJSONContainerScope =
	| { readonly kind: 'array' }
	| {
			readonly decodedMemberNames: Set<string>;
			readonly kind: 'object';
			memberCount: number;
	  };

export function parseBridgeProductStrictJSON(rawBytes: Uint8Array): unknown {
	if (rawBytes.byteLength > bridgeProductStrictJSONMaximumInputBytes) {
		throw new BridgeProductStrictJSONError(
			'input_exceeds_ceiling',
			'Bridge product JSON exceeds its byte ceiling.',
		);
	}

	let rawJSON: string;
	try {
		rawJSON = new TextDecoder('utf-8', { fatal: true }).decode(rawBytes);
	} catch {
		throw new BridgeProductStrictJSONError(
			'invalid_utf8',
			'Bridge product JSON is not strict UTF-8.',
		);
	}

	validateBridgeProductJSONMemberUniqueness(rawJSON);
	try {
		return JSON.parse(rawJSON) as unknown;
	} catch {
		throw new BridgeProductStrictJSONError(
			'invalid_json',
			'Bridge product JSON is not valid JSON.',
		);
	}
}

function validateBridgeProductJSONMemberUniqueness(rawJSON: string): void {
	const scopes: BridgeProductJSONContainerScope[] = [];
	let cursor = 0;
	while (cursor < rawJSON.length) {
		const codeUnit = rawJSON.charCodeAt(cursor);
		switch (codeUnit) {
			case 0x22: {
				const stringEnd = findBridgeProductJSONStringEnd(rawJSON, cursor);
				const enclosingScope = scopes.at(-1);
				if (
					stringEnd < rawJSON.length &&
					enclosingScope?.kind === 'object' &&
					rawJSON.charCodeAt(skipBridgeProductJSONWhitespace(rawJSON, stringEnd + 1)) === 0x3a
				) {
					recordBridgeProductJSONObjectMember(enclosingScope, rawJSON.slice(cursor, stringEnd + 1));
				}
				cursor = stringEnd + 1;
				break;
			}
			case 0x7b:
				pushBridgeProductJSONScope(scopes, {
					decodedMemberNames: new Set<string>(),
					kind: 'object',
					memberCount: 0,
				});
				cursor += 1;
				break;
			case 0x5b:
				pushBridgeProductJSONScope(scopes, { kind: 'array' });
				cursor += 1;
				break;
			case 0x7d:
				if (scopes.at(-1)?.kind === 'object') {
					scopes.pop();
				}
				cursor += 1;
				break;
			case 0x5d:
				if (scopes.at(-1)?.kind === 'array') {
					scopes.pop();
				}
				cursor += 1;
				break;
			default:
				cursor += 1;
		}
	}
}

function pushBridgeProductJSONScope(
	scopes: BridgeProductJSONContainerScope[],
	scope: BridgeProductJSONContainerScope,
): void {
	if (scopes.length >= bridgeProductStrictJSONMaximumNestingDepth) {
		throw new BridgeProductStrictJSONError(
			'nesting_exceeds_ceiling',
			'Bridge product JSON exceeds its nesting ceiling.',
		);
	}
	scopes.push(scope);
}

function recordBridgeProductJSONObjectMember(
	scope: Extract<BridgeProductJSONContainerScope, { readonly kind: 'object' }>,
	rawMemberName: string,
): void {
	let decodedMemberName: unknown;
	try {
		decodedMemberName = JSON.parse(rawMemberName) as unknown;
	} catch {
		return;
	}
	if (typeof decodedMemberName !== 'string') {
		return;
	}

	scope.memberCount += 1;
	if (scope.memberCount > bridgeProductStrictJSONMaximumObjectMembers) {
		throw new BridgeProductStrictJSONError(
			'object_member_count_exceeds_ceiling',
			'Bridge product JSON object exceeds its member ceiling.',
		);
	}
	if (scope.decodedMemberNames.has(decodedMemberName)) {
		throw new BridgeProductStrictJSONError(
			'duplicate_object_member',
			'Bridge product JSON contains a duplicate object member.',
		);
	}
	scope.decodedMemberNames.add(decodedMemberName);
}

function findBridgeProductJSONStringEnd(rawJSON: string, openingQuote: number): number {
	let cursor = openingQuote + 1;
	while (cursor < rawJSON.length) {
		const codeUnit = rawJSON.charCodeAt(cursor);
		if (codeUnit === 0x22) {
			return cursor;
		}
		cursor += codeUnit === 0x5c ? 2 : 1;
	}
	return rawJSON.length;
}

function skipBridgeProductJSONWhitespace(rawJSON: string, start: number): number {
	let cursor = start;
	while (cursor < rawJSON.length) {
		const codeUnit = rawJSON.charCodeAt(cursor);
		if (codeUnit !== 0x20 && codeUnit !== 0x09 && codeUnit !== 0x0a && codeUnit !== 0x0d) {
			return cursor;
		}
		cursor += 1;
	}
	return cursor;
}
