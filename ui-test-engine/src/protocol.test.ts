import assert from 'node:assert/strict';
import { test } from 'node:test';

import { checkTrace, parseEvent, type NativeEvent } from './protocol.ts';

function event(fields: Readonly<Record<string, unknown>>): NativeEvent {
  const parsed = parseEvent(`  12.3 Script control.lua: SHM_UI_TEST ${JSON.stringify({ protocol: 1, run_id: 'run-test', tick: 12, ...fields })}`);
  assert.notEqual(parsed, undefined);
  assert.ok(parsed);
  return parsed;
}

function trace(actual = 1): NativeEvent[] {
  return [
    event({ type: 'started', scenario: 'counter' }),
    event({ type: 'capture', role: 'before' }),
    event({ type: 'located', position: { x: 1.5, y: -2 } }),
    event({ type: 'input', action: 'mouse_click' }),
    event({ type: 'result', checks: [{ name: 'clicks', expected: 1, actual }] }),
    event({ type: 'capture', role: 'after' }),
    event({ type: 'complete' }),
  ];
}

test('a complete native trace passes and a disabled-button result fails', () => {
  assert.ok(checkTrace(trace(), 'run-test').every((check) => check.passed));
  const negative = checkTrace(trace(0), 'run-test');
  assert.equal(negative.find((check) => check.name === 'clicks')?.passed, false);
  assert.equal(negative.find((check) => check.name === 'native lifecycle')?.passed, true);
});

test('missing, reordered, duplicated and foreign-run events cannot pass', () => {
  for (let i = 0; i < trace().length; i += 1) {
    assert.ok(checkTrace(trace().filter((_, index) => index !== i), 'run-test').some((check) => !check.passed));
  }
  const reordered = trace();
  [reordered[1], reordered[3]] = [reordered[3]!, reordered[1]!];
  assert.equal(checkTrace(reordered, 'run-test')[0]?.passed, false);
  assert.equal(checkTrace([...trace(), event({ type: 'complete' })], 'run-test')[0]?.passed, false);
  assert.ok(checkTrace(trace(), 'another-run').some((check) => !check.passed));
  assert.ok(checkTrace([], 'run-test').some((check) => !check.passed));
});

test('native errors are fatal even if a complete sequence was also printed', () => {
  const checks = checkTrace([...trace(), event({ type: 'error', source: 'simulation', message: 'no widget' })], 'run-test');
  assert.equal(checks.find((check) => check.name === 'native simulation')?.passed, false);
});

test('ordinary logs are ignored; malformed or unsupported protocol data is rejected', () => {
  assert.equal(parseEvent('Factorio initialised'), undefined);
  assert.throws(() => parseEvent('SHM_UI_TEST {'), /\[protocol\]/);
  for (const fields of [
    { type: 'complete', protocol: 2 }, { type: 'complete', run_id: '' },
    { type: 'complete', tick: null }, { type: 'mystery' },
    { type: 'started', scenario: '' }, { type: 'located', position: { x: '1', y: 2 } },
    { type: 'input', action: 'invoke_handler' }, { type: 'capture', role: 'other' },
    { type: 'result', checks: [] }, { type: 'result', checks: [{}] },
    { type: 'result', checks: [{ name: 'x', actual: {}, expected: 1 }] },
    { type: 'result', checks: [{ name: 'x', actual: 1, expected: 1 }, { name: 'x', actual: 1, expected: 1 }] },
    { type: 'error', source: 'host', message: '' },
  ]) assert.throws(() => event(fields), /\[protocol\]/);
  assert.throws(() => parseEvent('SHM_UI_TEST []'), /\[protocol\]/);
});

test('assertions compare primitive values without coercion', () => {
  const result = event({ type: 'result', checks: [
    { name: 'caption', actual: 'Clicks: 1', expected: 'Clicks: 1' },
    { name: 'bool', actual: true, expected: true },
    { name: 'null', actual: null, expected: null },
    { name: 'number versus text', actual: '1', expected: 1 },
  ] });
  const checks = checkTrace([result], 'run-test');
  assert.equal(checks.find((check) => check.name === 'caption')?.passed, true);
  assert.equal(checks.find((check) => check.name === 'bool')?.passed, true);
  assert.equal(checks.find((check) => check.name === 'null')?.passed, true);
  assert.equal(checks.find((check) => check.name === 'number versus text')?.passed, false);
});
