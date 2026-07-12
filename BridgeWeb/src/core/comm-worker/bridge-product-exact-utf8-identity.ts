const bridgeProductExactUtf8IdentityEncoder = new TextEncoder();

export function bridgeProductExactUtf8IdentitySet(values: readonly string[]): Set<string> {
	return new Set(values.map((value) => bridgeProductExactUtf8IdentityKey(value)));
}

function bridgeProductExactUtf8IdentityKey(value: string): string {
	const identityBytes = bridgeProductExactUtf8IdentityEncoder.encode(value);
	const hexadecimalOctets: string[] = [];
	for (const identityByte of identityBytes) {
		hexadecimalOctets.push(identityByte.toString(16).padStart(2, '0'));
	}
	return hexadecimalOctets.join('');
}
