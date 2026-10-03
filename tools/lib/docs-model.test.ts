import assert from 'node:assert/strict';
import { test } from 'node:test';

import { asRecord, asString, asStringArray } from './docs-model.ts';

test('asRecord принимает только объект', () => {
  assert.deepEqual(asRecord({ a: 1 }), { a: 1 });
  assert.equal(asRecord([]), null);
  assert.equal(asRecord(null), null);
  assert.equal(asRecord('x'), null);
  assert.equal(asRecord(42), null);
  assert.equal(asRecord(undefined), null);
});

test('asString принимает только строку', () => {
  assert.equal(asString('x'), 'x');
  assert.equal(asString(''), '');
  assert.equal(asString(42), null);
  assert.equal(asString(null), null);
  assert.equal(asString(['x']), null);
});

test('asStringArray отбрасывает нестроковые элементы', () => {
  assert.deepEqual(asStringArray(['a', 1, null, 'b']), ['a', 'b']);
  assert.deepEqual(asStringArray([]), []);
});

test('asStringArray на не-массиве возвращает пустой массив', () => {
  assert.deepEqual(asStringArray('a'), []);
  assert.deepEqual(asStringArray(null), []);
  assert.deepEqual(asStringArray(undefined), []);
  assert.deepEqual(asStringArray({ 0: 'a' }), []);
});
