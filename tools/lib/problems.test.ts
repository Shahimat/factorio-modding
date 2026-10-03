import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  countErrors,
  error,
  formatProblem,
  warning,
} from './problems.ts';

test('error без строки не заводит поле line', () => {
  const p = error('a.yml', 'сломано');
  assert.equal(p.severity, 'error');
  assert.equal(p.file, 'a.yml');
  assert.equal('line' in p, false);
});

test('error со строкой сохраняет номер', () => {
  assert.equal(error('a.yml', 'сломано', 7).line, 7);
});

test('warning помечается как warning', () => {
  assert.equal(warning('a.yml', 'сомнительно').severity, 'warning');
});

test('formatProblem добавляет номер строки только когда он есть', () => {
  assert.match(formatProblem(error('a.yml', 'x', 3)), /a\.yml:3/);
  assert.doesNotMatch(formatProblem(error('a.yml', 'x')), /a\.yml:/);
});

test('formatProblem различает ошибку и замечание', () => {
  assert.match(formatProblem(error('a', 'x')), /ошибка/);
  assert.match(formatProblem(warning('a', 'x')), /внимание/);
});

test('countErrors считает только ошибки', () => {
  const list = [error('a', '1'), warning('a', '2'), error('a', '3')];
  assert.equal(countErrors(list), 2);
  assert.equal(countErrors([]), 0);
  assert.equal(countErrors([warning('a', '1')]), 0);
});
