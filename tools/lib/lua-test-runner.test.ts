import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  isLuaTestFile,
  luaRunProblems,
  parseHarnessOutput,
} from './lua-test-runner.ts';
import { countErrors } from './problems.ts';

test('isLuaTestFile отличает тест от обычного модуля', () => {
  assert.equal(isLuaTestFile('tests/demand.test.lua'), true);
  assert.equal(isLuaTestFile('logic/demand.lua'), false);
  assert.equal(isLuaTestFile('tests/demand.test.luac'), false);
});

test('разбор успешного прогона', () => {
  const parsed = parseHarnessOutput(
    ['TEST ok спрос: пустая сеть', 'TEST ok спрос: один заказ', 'TOTAL 2 0'].join(
      '\n',
    ),
  );
  assert.equal(parsed.passed, 2);
  assert.equal(parsed.failed, 0);
  assert.deepEqual(
    parsed.cases.map((c) => c.ok),
    [true, true],
  );
  assert.equal(parsed.cases[0]?.name, 'спрос: пустая сеть');
  assert.deepEqual(luaRunProblems('mods/shm-x', parsed, 0, ''), []);
});

test('упавший тест даёт ошибку с сообщением харнесса', () => {
  const parsed = parseHarnessOutput(
    ['TEST fail спрос: один заказ :: ожидалось 3, получено 4', 'TOTAL 0 1'].join(
      '\n',
    ),
  );
  assert.equal(parsed.cases[0]?.message, 'ожидалось 3, получено 4');

  const problems = luaRunProblems('mods/shm-x', parsed, 1, '');
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /ожидалось 3, получено 4/);
});

test('строки без разметки игнорируются', () => {
  const parsed = parseHarnessOutput(
    ['шум из интерпретатора', 'TEST ok один', '', 'TOTAL 1 0'].join('\n'),
  );
  assert.equal(parsed.cases.length, 1);
  assert.equal(parsed.passed, 1);
});

test('вывод без итоговой строки — находка, а не зелёный прогон', () => {
  // Регрессия: падение `lua` до первой строки вывода выглядело как
  // «тестов нет», то есть как успех.
  const parsed = parseHarnessOutput('');
  assert.equal(parsed.passed, null);

  const problems = luaRunProblems(
    'mods/shm-x',
    parsed,
    1,
    'lua: tools/lua/run.lua:12: attempt to index a nil value',
  );
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /нет итоговой строки/);
  assert.match(problems[0]?.message ?? '', /attempt to index a nil value/);
});

test('обрезанный вывод ловится сверкой числа строк с итогом', () => {
  const parsed = parseHarnessOutput(['TEST ok один', 'TOTAL 3 0'].join('\n'));
  const problems = luaRunProblems('mods/shm-x', parsed, 0, '');
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /вывод обрезан/);
});

test('ненулевой код возврата при зелёных тестах — находка', () => {
  const parsed = parseHarnessOutput(['TEST ok один', 'TOTAL 1 0'].join('\n'));
  const problems = luaRunProblems('mods/shm-x', parsed, 7, 'segfault');
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /код возврата 7/);
});

test('многословное имя с двоеточиями не ломает разбор сообщения', () => {
  const parsed = parseHarnessOutput(
    'TEST fail группа: случай: деталь :: причина\nTOTAL 0 1',
  );
  assert.equal(parsed.cases[0]?.name, 'группа: случай: деталь');
  assert.equal(parsed.cases[0]?.message, 'причина');
});
