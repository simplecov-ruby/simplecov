// Guarded localStorage access for the report's remembered preferences
// (theme, colorblind palette, sort order).
//
// localStorage can throw in locked-down contexts (Safari private mode,
// sandboxed iframes, browsers with storage disabled), and the report is a
// static file people open from anywhere, so every read falls back to null
// and every write is best-effort. The head-script preflight in index.html
// carries its own copy of this guard because it runs before the bundle.

export function readPreference(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function writePreference(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // No-op: the preference just doesn't survive the reload.
  }
}
