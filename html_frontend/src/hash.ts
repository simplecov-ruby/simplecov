// SHA-1 via Web Crypto, truncated to 8 hex characters.
export async function hash(str: string): Promise<string> {
  const bytes = new TextEncoder().encode(str);
  const buf = await crypto.subtle.digest('SHA-1', bytes);
  let out = '';
  for (const b of new Uint8Array(buf, 0, 4)) {
    out += ('0' + b.toString(16)).slice(-2);
  }
  return out;
}
