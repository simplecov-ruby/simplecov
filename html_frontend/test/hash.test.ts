import { describe, expect, test } from 'bun:test';
import { hash } from '../src/hash';

describe('hash', () => {
  test('returns the first 8 hex chars of the SHA-1 digest', async () => {
    expect(await hash('')).toBe('da39a3ee');
    expect(await hash('abc')).toBe('a9993e36');
  });

  test('hashes the UTF-8 encoding of non-ASCII input', async () => {
    expect(await hash('é')).toHaveLength(8);
    expect(await hash('é')).not.toBe(await hash('e'));
  });
});
