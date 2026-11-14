import assert from 'node:assert/strict';
import { test } from 'node:test';

import { gameVersion, parseOptions } from './options.ts';

test('PoC defaults do not invert the negative case into a passing run', () => {
  assert.deepEqual(parseOptions([]), { negative: false, timeoutMs: 90_000, help: false });
  assert.deepEqual(parseOptions(['--negative', '--timeout', '12']), { negative: true, timeoutMs: 12_000, help: false });
  assert.equal(parseOptions(['--help']).help, true);
});

test('timeouts are bounded integers and unknown or repeated flags are rejected', () => {
  for (const value of ['', '0', '-1', '601', '1.5', 'NaN', 'Infinity', '1e2', '--negative']) {
    assert.throws(() => parseOptions(['--timeout', value]), /\[arguments\]/);
  }
  assert.equal(parseOptions(['--timeout', '1']).timeoutMs, 1000);
  assert.equal(parseOptions(['--timeout', '600']).timeoutMs, 600_000);
  assert.throws(() => parseOptions(['--timeout']), /\[arguments\]/);
  assert.throws(() => parseOptions(['--negative', '--negative']), /\[arguments\]/);
  assert.throws(() => parseOptions(['--timeout', '1', '--timeout', '2']), /\[arguments\]/);
  assert.throws(() => parseOptions(['--mod-directory', 'personal-profile']), /\[arguments\]/);
});

test('only the supported Factorio version track is accepted', () => {
  assert.equal(gameVersion('Version: 2.1.24 (build 87808, mac-arm64, steam)\nVersion: 64'), '2.1.24');
  for (const value of ['Version: 2.0.77', 'Version: 3.1.0', 'Version: 2.10.1', 'unrelated 2.1.24', '']) {
    assert.throws(() => gameVersion(value), /\[version\]/);
  }
});
