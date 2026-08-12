// The file-id hash: SHA-1 via Web Crypto truncated to 8 hex characters.
// Checked against the well-known SHA-1 test vectors so a change of
// algorithm or truncation width cannot slip through silently.
import { describe, expect, test } from 'bun:test';
import { hash } from '../src/hash';

describe('hash', () => {
  test('returns the first 8 hex chars of the SHA-1 digest', async () => {
    // SHA-1('') = da39a3ee5e6b4b0d...; SHA-1('abc') = a9993e364706816a...
    expect(await hash('')).toBe('da39a3ee');
    expect(await hash('abc')).toBe('a9993e36');
  });

  test('hashes the UTF-8 encoding of non-ASCII input', async () => {
    // SHA-1 of the bytes c3 a9 (UTF-8 'é'), not of any UTF-16 form.
    expect(await hash('é')).toHaveLength(8);
    expect(await hash('é')).not.toBe(await hash('e'));
  });
});
