import assert from 'node:assert/strict';
import { test } from 'node:test';

import { BUILTINS, isScenarioName, markerPoints, modList, profileFor, runOptions } from './profiles.ts';
import { isExcludedFromPack } from '../../tools/lib/pack-filter.ts';

test('counter stays base-only while orbital loads the real mod and installed expansion', () => {
  const counter = modList(profileFor('counter')).mods;
  assert.ok(counter.some((item) => item.name === 'shm-ui-test-fixture' && item.enabled));
  assert.ok(BUILTINS.every((name) => counter.some((item) => item.name === name && !item.enabled)));
  const orbital = profileFor('orbital');
  assert.deepEqual(orbital.mods, [{ name: 'shm-orbital-logistics', source: 'mods/shm-orbital-logistics' }]);
  assert.ok(BUILTINS.every((name) => modList(orbital).mods.some((item) => item.name === name && item.enabled)));
  assert.ok(!modList(orbital).mods.some((item) => item.name === 'shm-ui-test-fixture'));
  assert.ok(orbital.simulationMods.includes('shm-orbital-logistics'));
  assert.ok(orbital.simulationMods.includes('space-age'));
});

test('only registered scenarios are accepted; run options are local generated Lua data', () => {
  assert.equal(isScenarioName('orbital'), true);
  assert.equal(isScenarioName('counter'), true);
  assert.equal(isScenarioName('__proto__'), false);
  assert.equal(isScenarioName('../mod'), false);
  const options = runOptions(profileFor('orbital'), 'run-test', true);
  assert.match(options, /negative=true/);
  assert.match(options, /"shm-orbital-logistics"/);
  assert.match(options, /viewport=\{width=1920, height=1080\}/);
  assert.match(options, /markers=\{\{x=64, y=0\}/);
  assert.match(runOptions(profileFor('counter'), 'run-test', false), /viewport=nil/);
  assert.deepEqual(markerPoints({ width: 1920, height: 1080 }), [{ x: 64, y: 0 }, { x: 1896, y: 1056 }]);
  assert.throws(() => runOptions(profileFor('counter'), 'bad"; code()', false), /\[profile\]/);
});

test('the simulation setup adapter and debug marker stay outside the release archive', () => {
  assert.equal(isExcludedFromPack('tests/ui/adapter.lua'), true);
  assert.equal(isExcludedFromPack('tests/debug.lua'), true);
  assert.equal(isExcludedFromPack('runtime/overview_gui.lua'), false);
  assert.equal(isExcludedFromPack('control.lua'), false);
});
