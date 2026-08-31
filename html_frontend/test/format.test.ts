import { afterAll, beforeAll, describe, expect, test, setSystemTime } from 'bun:test';
import {
  fileId,
  fmtNum,
  fmtPct,
  pctClass,
  precomputeFileIds,
  timeago,
  timeagoNextTick,
  toHtmlId
} from '../src/format';

describe('fmtPct', () => {
  test('floors to two decimals instead of rounding up', () => {
    expect(fmtPct((37 / 42) * 100)).toBe('88.09');
  });

  test('shows 99.99 rather than rounding to a false 100.00', () => {
    expect(fmtPct(99.996)).toBe('99.99');
  });

  test('renders exact percentages without noise', () => {
    expect(fmtPct(100)).toBe('100.00');
    expect(fmtPct(80)).toBe('80.00');
  });
});

describe('pctClass', () => {
  test('maps percentages onto the green/yellow/red coverage bands', () => {
    expect(pctClass(100)).toBe('green');
    expect(pctClass(90)).toBe('green');
    expect(pctClass(89.99)).toBe('yellow');
    expect(pctClass(75)).toBe('yellow');
    expect(pctClass(74.99)).toBe('red');
    expect(pctClass(0)).toBe('red');
  });
});

describe('fmtNum', () => {
  test('inserts thousands separators without touching short numbers', () => {
    expect(fmtNum(999)).toBe('999');
    expect(fmtNum(1000)).toBe('1,000');
    expect(fmtNum(1234567)).toBe('1,234,567');
  });
});

describe('toHtmlId', () => {
  test('keeps letters, digits, and hyphens; prefixes with g-', () => {
    expect(toHtmlId('Libraries-2')).toBe('g-Libraries-2');
  });

  test('keeps titles distinct that differ only in escaped characters', () => {
    expect(toHtmlId('>100LOC')).toBe('g-_3e_100LOC');
    expect(toHtmlId('<10LOC')).toBe('g-_3c_10LOC');
    expect(toHtmlId('>100LOC')).not.toBe(toHtmlId('<10LOC'));
  });

  test('escapes underscores so escapes cannot be forged', () => {
    expect(toHtmlId('a/')).toBe('g-a_2f_');
    expect(toHtmlId('a_2f_')).toBe('g-a_5f_2f_5f_');
  });

  test('escapes non-ASCII characters by codepoint', () => {
    expect(toHtmlId('é')).toBe('g-_e9_');
  });
});

describe('timeago', () => {
  const NOW = new Date('2026-08-11T12:00:00Z');
  beforeAll(() => setSystemTime(NOW));
  afterAll(() => setSystemTime());

  function secondsAgo(seconds: number): Date {
    return new Date(NOW.getTime() - seconds * 1000);
  }

  test('picks the largest interval that fits', () => {
    expect(timeago(secondsAgo(2 * 31536000))).toBe('2 years ago');
    expect(timeago(secondsAgo(3 * 86400))).toBe('3 days ago');
    expect(timeago(secondsAgo(5 * 60))).toBe('5 minutes ago');
    expect(timeago(secondsAgo(30))).toBe('30 seconds ago');
  });

  test('uses the singular "about 1" form on exact single units', () => {
    expect(timeago(secondsAgo(2592000))).toBe('about 1 month ago');
    expect(timeago(secondsAgo(3600))).toBe('about 1 hour ago');
  });

  test('renders sub-second ages as just now', () => {
    expect(timeago(secondsAgo(0.5))).toBe('just now');
  });
});

describe('timeagoNextTick', () => {
  const NOW = new Date('2026-08-11T12:00:00Z');
  beforeAll(() => setSystemTime(NOW));
  afterAll(() => setSystemTime());

  function secondsAgo(seconds: number): Date {
    return new Date(NOW.getTime() - seconds * 1000);
  }

  test('waits until just past the next display boundary', () => {
    expect(timeagoNextTick(secondsAgo(90))).toBe(30500);
  });

  test('never schedules closer than one second out', () => {
    expect(timeagoNextTick(secondsAgo(59.9))).toBe(1000);
  });

  test('re-checks a just-now timestamp after one second', () => {
    expect(timeagoNextTick(secondsAgo(0.2))).toBe(1000);
  });
});

describe('file ids', () => {
  test('unknown files raise instead of rendering broken links', async () => {
    await precomputeFileIds([]);
    expect(() => fileId('never-registered.rb')).toThrow(
      'File ID was not precomputed for never-registered.rb'
    );
  });

  test('assigns each file the 8-hex-char truncated SHA-1 of its path', async () => {
    await precomputeFileIds(['lib/a.rb', 'lib/a.rb', 'lib/b.rb']);
    expect(fileId('lib/a.rb')).toMatch(/^[0-9a-f]{8}$/);
    expect(fileId('lib/b.rb')).toMatch(/^[0-9a-f]{8}$/);
    expect(fileId('lib/a.rb')).not.toBe(fileId('lib/b.rb'));
  });

  test('disambiguates truncated-hash collisions with a stable suffix', async () => {
    await precomputeFileIds(['file-80201.rb', 'file-18088.rb', 'other.rb']);
    expect(fileId('file-18088.rb')).toBe('0502b5a6');
    expect(fileId('file-80201.rb')).toBe('0502b5a6-1');
    expect(fileId('other.rb')).toMatch(/^[0-9a-f]{8}$/);
  });

  test('recomputing clears ids from the previous report', async () => {
    await precomputeFileIds(['lib/a.rb']);
    await precomputeFileIds(['lib/b.rb']);
    expect(() => fileId('lib/a.rb')).toThrow('File ID was not precomputed for lib/a.rb');
  });
});
