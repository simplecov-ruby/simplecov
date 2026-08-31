export async function hash(str: string): Promise<string> {
  const bytes = new TextEncoder().encode(str);
  const digest = await crypto.subtle.digest('SHA-1', bytes);
  return Array.from(new Uint8Array(digest, 0, 4), (b) => b.toString(16).padStart(2, '0')).join('');
}
