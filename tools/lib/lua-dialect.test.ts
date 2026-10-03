import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  blankStringsAndComments,
  LUA_DIALECT_RULES,
  scanLuaDialect,
} from './lua-dialect.ts';

/** Идентификаторы правил, сработавших на тексте. */
function ids(text: string): string[] {
  return scanLuaDialect('mods/shm-x/control.lua', text).map((p) => {
    const match = /^\[([a-z0-9-]+)\]/.exec(p.message);
    return match?.[1] ?? '';
  });
}

test('код в границах Lua 5.2 проходит без находок', () => {
  const source = [
    'local M = {}',
    'function M.half(n)',
    '  return math.floor(n / 2)',
    'end',
    'function M.differs(a, b)',
    '  return a ~= b',
    'end',
    'function M.join(parts)',
    '  return table.concat(parts, ", ")',
    'end',
    'local tag = ("%s/%s"):format("a", "b")',
    'local unpacked = table.unpack({ 1, 2 })',
    'return M',
  ].join('\n');
  assert.deepEqual(ids(source), []);
});

test('каждое правило диалекта имеет срабатывание', () => {
  const samples: Record<string, string> = {
    'integer-division': 'local n = 7 // 2',
    'bitwise-operator': 'local mask = a & b',
    'integer-math': 'if math.type(n) == "integer" then end',
    'table-move': 'table.move(a, 1, 2, 1, b)',
    'string-pack': 'local blob = string.pack("i4", 1)',
    'utf8-library': 'local n = utf8.len("ы")',
    'variable-attribute': 'local x <const> = 1',
    'coroutine-close': 'coroutine.close(co)',
    'removed-in-5-2': 'setfenv(f, {})',
    'global-unpack': 'local a, b = unpack(list)',
  };

  for (const rule of LUA_DIALECT_RULES) {
    const sample = samples[rule.id];
    assert.ok(sample !== undefined, `нет образца для правила ${rule.id}`);
    assert.ok(
      ids(sample).includes(rule.id),
      `правило ${rule.id} не сработало на своём образце`,
    );
  }
});

test('`~=` не считается побитовой операцией', () => {
  assert.deepEqual(ids('if a ~= b then return 1 end'), []);
  assert.deepEqual(ids('local x = ~a'), ['bitwise-operator']);
});

test('`table.unpack` разрешён, глобальный `unpack` — нет', () => {
  assert.deepEqual(ids('local a = table.unpack(t)'), []);
  assert.deepEqual(ids('local a = unpack(t)'), ['global-unpack']);
});

test('находки в строках и комментариях не считаются', () => {
  const source = [
    '-- деление // в комментарии',
    'local s = "a | b"',
    "local q = 'c & d'",
    '--[[ блочный комментарий с << и >> ]]',
    'local long = [[литерал с | и // внутри]]',
    'local lvl = [==[и с уровнем: &]==]',
    'return s, q, long, lvl',
  ].join('\n');
  assert.deepEqual(ids(source), []);
});

test('blankStringsAndComments сохраняет длину и номера строк', () => {
  const source = 'local s = "x | y"\nlocal n = 1 // 2\n';
  const blanked = blankStringsAndComments(source);
  assert.equal(blanked.length, source.length);
  assert.equal(blanked.split('\n').length, source.split('\n').length);

  const found = scanLuaDialect('f.lua', source);
  assert.equal(found.length, 1);
  assert.equal(found[0]?.line, 2);
});

test('незакрытая строка не глотает остаток файла', () => {
  // Регрессия: при наивном поиске закрывающей кавычки незакрытая строка
  // съедала все последующие строки, и находки за ней пропадали.
  const source = 'local broken = "oops\nlocal n = 7 // 2\n';
  assert.deepEqual(ids(source), ['integer-division']);
});

test('одно правило на строке даёт одну находку', () => {
  assert.deepEqual(ids('local x = a & b & c'), ['bitwise-operator']);
  assert.deepEqual(ids('local x = a & b\nlocal y = c | d'), [
    'bitwise-operator',
    'bitwise-operator',
  ]);
});

test('находки отсортированы по строкам и несут путь файла', () => {
  const found = scanLuaDialect(
    'mods/shm-x/control.lua',
    'local a = unpack(t)\nlocal b = 1 // 2\n',
  );
  assert.deepEqual(
    found.map((p) => p.line),
    [1, 2],
  );
  assert.equal(found[0]?.file, 'mods/shm-x/control.lua');
  assert.equal(found[0]?.severity, 'error');
});
