import assert from 'node:assert/strict';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { setTimeout as pause } from 'node:timers/promises';

import { Lines, runProcess, type ProcessOptions } from './process.ts';

function options(script: string): ProcessOptions {
  return {
    binary: process.execPath, args: ['-e', script], cwd: tmpdir(), timeoutMs: 3000, killGraceMs: 100,
    onLine: (line) => line === 'complete' ? 'complete' : undefined,
  };
}

test('line decoding preserves fragmented UTF-8, CRLF and the final unterminated line', () => {
  const found: string[] = [];
  const lines = new Lines((line) => found.push(line));
  const bytes = Buffer.from('GUI: готово\r\nsecond\nlast', 'utf8');
  for (let i = 0; i < bytes.length; i += 1) lines.push(bytes.subarray(i, i + 1));
  lines.finish();
  assert.deepEqual(found, ['GUI: готово', 'second', 'last']);
});

test('native completion closes only its child and leaves no signal handlers behind', async () => {
  const listeners = process.listenerCount('SIGINT');
  const result = await runProcess(options('console.log("complete"); setInterval(() => {}, 1000);'));
  assert.equal(result.reason, 'complete');
  assert.match(result.log, /complete/);
  assert.equal(process.listenerCount('SIGINT'), listeners);
});

test('exit 0 without completion and process crashes are not native success', async () => {
  const empty = await runProcess(options('process.exit(0);'));
  assert.equal(empty.reason, 'exit');
  assert.equal(empty.code, 0);
  const crash = await runProcess(options('process.stderr.write("crashed"); process.exit(7);'));
  assert.equal(crash.reason, 'exit');
  assert.equal(crash.code, 7);
  assert.match(crash.log, /crashed/);
});

test('watchdog terminates a stalled child and escalates if SIGTERM is ignored', async () => {
  const stalled = await runProcess({ ...options('setInterval(() => {}, 1000);'), timeoutMs: 150 });
  assert.equal(stalled.reason, 'timeout');
  const stubborn = await runProcess(options('process.on("SIGTERM", () => {}); console.log("complete"); setInterval(() => {}, 1000);'));
  assert.equal(stubborn.reason, 'complete');
  assert.equal(stubborn.signal, 'SIGKILL');
});

test('spawn and protocol errors are contained and reported instead of hanging', async () => {
  const missing = await runProcess({ ...options(''), binary: join(tmpdir(), 'shm-ui-test-nonexistent-executable') });
  assert.equal(missing.reason, 'spawn-error');
  assert.ok(missing.diagnostics.length > 0);
  const invalid = await runProcess({
    ...options('console.log("malformed"); setInterval(() => {}, 1000);'),
    onLine: () => { throw new Error('[protocol] bad payload'); },
  });
  assert.equal(invalid.reason, 'protocol-error');
  assert.match(invalid.diagnostics.join(' '), /\[protocol\]/);
  const native = await runProcess({ ...options('console.log("error"); setInterval(() => {}, 1000);'), onLine: () => 'native-error' });
  assert.equal(native.reason, 'native-error');
});

test('an exited parent with inherited output pipes cannot bypass the watchdog', async () => {
  // Regression: waiting for close alone hung until the grandchild released pipes.
  const script = `
    const {spawn} = require('node:child_process');
    spawn(process.execPath, ['-e', 'setTimeout(() => {}, 3000)'], {stdio: ['ignore', 1, 2]});
    process.exit(3);
  `;
  const start = performance.now();
  const result = await runProcess({ ...options(script), timeoutMs: 100, killGraceMs: 25 });
  assert.ok(performance.now() - start < 2000);
  assert.equal(result.code, 3);
  assert.ok(result.diagnostics.some((line) => line.includes('pipes')));
  assert.notEqual(result.reason, 'complete');
});

test('leader close cannot cancel cleanup of a SIGTERM-ignoring descendant with no pipes', async () => {
  const script = `
    const {spawn} = require('node:child_process');
    const child = spawn(process.execPath, ['-e',
      'process.on("SIGTERM", () => {}); process.send("ready"); setInterval(() => {}, 1000);'
    ], {stdio: ['ignore', 'ignore', 'ignore', 'ipc']});
    child.on('message', () => { console.log('descendant=' + child.pid); console.log('complete'); });
  `;
  const result = await runProcess(options(script));
  const pid = Number(/descendant=(\d+)/.exec(result.log)?.[1]);
  assert.ok(Number.isInteger(pid) && pid > 0);
  const alive = (): boolean => {
    try { process.kill(pid, 0); return true; }
    catch (cause: unknown) {
      if (cause instanceof Error && 'code' in cause && cause.code === 'ESRCH') return false;
      throw cause;
    }
  };
  try {
    for (let attempt = 0; attempt < 50 && alive(); attempt += 1) await pause(20);
    assert.equal(result.reason, 'complete');
    assert.equal(alive(), false);
  } finally {
    if (alive()) process.kill(pid, 'SIGKILL');
  }
});
