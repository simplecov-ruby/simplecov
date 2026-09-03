import { afterEach, describe, expect, test } from 'bun:test';
import { readPreference, writePreference } from '../src/prefs';

afterEach(() => {
  localStorage.clear();
});

function withLockedStorage(run: () => void): void {
  const descriptor = Object.getOwnPropertyDescriptor(window, 'localStorage')!;
  Object.defineProperty(window, 'localStorage', {
    configurable: true,
    get() {
      throw new Error('storage disabled');
    }
  });
  try {
    run();
  } finally {
    Object.defineProperty(window, 'localStorage', descriptor);
  }
}

describe('preferences', () => {
  test('round-trip through localStorage', () => {
    writePreference('simplecov-test-pref', 'on');
    expect(localStorage.getItem('simplecov-test-pref')).toBe('on');
    expect(readPreference('simplecov-test-pref')).toBe('on');
  });

  test('read as null when never written', () => {
    expect(readPreference('simplecov-test-missing')).toBeNull();
  });

  test('read as null and write silently when storage is locked down', () => {
    withLockedStorage(() => {
      expect(readPreference('simplecov-test-pref')).toBeNull();
      expect(() => writePreference('simplecov-test-pref', 'on')).not.toThrow();
    });
    expect(readPreference('simplecov-test-pref')).toBeNull();
  });
});
