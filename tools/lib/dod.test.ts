import assert from 'node:assert/strict';
import { test } from 'node:test';

import { checkDod, type DodContext } from './dod.ts';
import { countErrors } from './problems.ts';

const BEHAVIORS = ['mod-loads-in-target-factorio'];

function ctx(overrides: Partial<DodContext> = {}): DodContext {
  return {
    file: 'context/views/goal--x.yaml',
    isProgram: false,
    isSubgoal: true,
    behaviorIds: BEHAVIORS,
    ...overrides,
  };
}

const UNIT_ITEM = {
  id: 'd1',
  what: 'логистический режим включается на здании с инвентарём',
  kind: 'unit',
  how: 'npm test -w shm-logistic-buildings → tests/mode.test.lua',
};

const PROOF_ITEM = {
  id: 'd2',
  what: 'мод грузится в Factorio 2.0 без ошибок в логе',
  kind: 'proof',
  how: '.work/proofs/logistic-buildings/mode/d2-factorio-log.txt',
  behavior: 'mod-loads-in-target-factorio',
};

test('корректный dod подцели проходит без находок', () => {
  assert.deepEqual(checkDod({ dod: [UNIT_ITEM, PROOF_ITEM] }, ctx()), []);
});

test('подцель без dod — ошибка, цель вне программы — нет', () => {
  assert.equal(countErrors(checkDod({}, ctx())), 1);
  assert.deepEqual(checkDod({}, ctx({ isSubgoal: false })), []);
});

test('программа без dod — ошибка', () => {
  const problems = checkDod({}, ctx({ isProgram: true, isSubgoal: false }));
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /критерии приёмки обязательны/);
});

test('dod должен быть непустым списком', () => {
  assert.equal(countErrors(checkDod({ dod: [] }, ctx())), 1);
  assert.equal(countErrors(checkDod({ dod: 'd1 — готово' }, ctx())), 1);
  assert.equal(countErrors(checkDod({ dod: ['строка'] }, ctx())), 2);
});

test('обязательные поля пункта проверяются по отдельности', () => {
  const problems = checkDod({ dod: [{ kind: 'unit' }] }, ctx());
  const messages = problems.map((p) => p.message).join('\n');
  assert.match(messages, /нет поля "id"/);
  assert.match(messages, /нет непустого поля "what"/);
  assert.match(messages, /нет непустого поля "how"/);
});

test('kind вне набора отбивается, отсутствие kind — тоже', () => {
  const bad = checkDod(
    { dod: [{ ...UNIT_ITEM, kind: 'manual' }] },
    ctx(),
  );
  assert.match(bad.map((p) => p.message).join('\n'), /вне набора/);

  const missing = checkDod(
    { dod: [{ id: 'd1', what: 'что-то', how: 'как-то' }] },
    ctx(),
  );
  assert.match(missing.map((p) => p.message).join('\n'), /нет поля "kind"/);
});

test('у подцели обязателен хотя бы один машинный пункт', () => {
  const problems = checkDod({ dod: [PROOF_ITEM] }, ctx());
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /unit или check/);

  // Программа собирает критерии из спеки, в том числе целиком ручные.
  assert.deepEqual(
    checkDod({ dod: [PROOF_ITEM] }, ctx({ isProgram: true, isSubgoal: false })),
    [],
  );

  // `check` закрывает требование наравне с `unit`.
  const withCheck = checkDod(
    { dod: [PROOF_ITEM, { ...UNIT_ITEM, kind: 'check', how: 'npm run check' }] },
    ctx(),
  );
  assert.deepEqual(withCheck, []);
});

test('id ограничен набором символов для имён файлов пруфов', () => {
  const problems = checkDod({ dod: [{ ...UNIT_ITEM, id: 'D 1' }] }, ctx());
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /строчные латинские/);
});

test('повтор id в одном файле — ошибка', () => {
  const problems = checkDod(
    { dod: [UNIT_ITEM, { ...PROOF_ITEM, id: 'd1' }] },
    ctx(),
  );
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /уже занят/);
});

test('ссылка на несуществующий behavior — ошибка', () => {
  const problems = checkDod(
    { dod: [{ ...UNIT_ITEM, behavior: 'нет-такого' }] },
    ctx(),
  );
  assert.equal(countErrors(problems), 1);
  assert.match(problems[0]?.message ?? '', /несуществующий behavior/);
});

test('пруф без пути в .work/proofs — замечание, не ошибка', () => {
  const problems = checkDod(
    { dod: [UNIT_ITEM, { ...PROOF_ITEM, how: 'посмотреть в игре' }] },
    ctx(),
  );
  assert.equal(countErrors(problems), 0);
  assert.equal(problems.length, 1);
  assert.equal(problems[0]?.severity, 'warning');
});
