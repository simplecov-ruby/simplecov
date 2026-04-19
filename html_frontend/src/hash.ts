// SHA-1 via Web Crypto, truncated to 8 hex characters.
//
// Used to derive stable, fixed-length, URL/HTML-safe IDs from source-file
// paths. Those IDs become HTML element ids and URL hash fragments
// (e.g. `#a1b2c3d4-L42`), where raw filenames would be unsafe (slashes,
// dots, spaces, non-ASCII characters) and unwieldy in URLs.
//
// SHA-1 is overkill in the security sense — collisions are not a threat
// model here — but Web Crypto is the only built-in browser hash and it
// happens to deliver one. Callers must await; resolve every id once
// upfront so the synchronous render path can look them up freely.
export async function hash(str: string): Promise<string> {
  const bytes = new TextEncoder().encode(str);
  const buf = await crypto.subtle.digest('SHA-1', bytes);
  let out = '';
  for (const b of new Uint8Array(buf, 0, 4)) {
    out += ('0' + b.toString(16)).slice(-2);
  }
  return out;
}
