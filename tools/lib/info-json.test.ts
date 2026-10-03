import assert from 'node:assert/strict';
import { test } from 'node:test';

import { MOD_NAME_PREFIX, MOD_TITLE_PREFIX } from './conventions.ts';
import { checkInfoJsonText } from './info-json.ts';
import { countErrors } from './problems.ts';

const NAME = `${MOD_NAME_PREFIX}fixture`;

function infoJson(overrides: Record<string, unknown> = {}): string {
  return JSON.stringify({
    name: NAME,
    version: '0.1.0',
    title: `${MOD_TITLE_PREFIX}Fixture`,
    author: 'Shahimat',
    factorio_version: '2.0',
    ...overrides,
  });
}

function check(raw: string, dirName: string = NAME) {
  return checkInfoJsonText(raw, dirName, 'info.json');
}

function messages(raw: string, dirName: string = NAME): string[] {
  return check(raw, dirName).problems.map((p) => p.message);
}

test('корректный info.json проходит и возвращает поля', () => {
  const { info, problems } = check(infoJson());
  assert.deepEqual(problems, []);
  assert.equal(info?.name, NAME);
  assert.equal(info?.version, '0.1.0');
  assert.equal(info?.factorio_version, '2.0');
  assert.deepEqual(info?.dependencies, []);
});

test('невалидный JSON даёт находку и info = null', () => {
  const { info, problems } = check('{ не json');
  assert.equal(info, null);
  assert.equal(countErrors(problems), 1);
});

test('не объект на верхнем уровне — находка', () => {
  assert.ok(messages('[]').some((m) => /JSON-объектом/.test(m)));
});

test('отсутствие обязательного поля — находка, info = null', () => {
  const raw = JSON.stringify({ name: NAME, version: '0.1.0' });
  const { info, problems } = check(raw);
  assert.equal(info, null);
  assert.ok(problems.length >= 2);
});

test('name без приставки проекта — находка', () => {
  assert.ok(
    messages(infoJson({ name: 'fixture' }), 'fixture').some((m) =>
      m.includes(MOD_NAME_PREFIX),
    ),
  );
});

test('недопустимый символ в name — находка', () => {
  const bad = `${MOD_NAME_PREFIX}a+b`;
  assert.ok(
    messages(infoJson({ name: bad }), bad).some((m) => /только латиницу/.test(m)),
  );
});

test('слишком короткое и слишком длинное name — находки', () => {
  assert.ok(messages(infoJson({ name: 'abc' }), 'abc').some((m) => /длина 3/.test(m)));
  const long = MOD_NAME_PREFIX + 'x'.repeat(50);
  assert.ok(messages(infoJson({ name: long }), long).some((m) => /длина 54/.test(m)));
});

test('имя каталога не совпадает с name — находка', () => {
  assert.ok(
    messages(infoJson(), 'other-dir').some((m) => /не совпадает с "name"/.test(m)),
  );
});

test('version не из трёх чисел и version 0.0.0 — находки', () => {
  assert.ok(messages(infoJson({ version: '1.0' })).some((m) => /3 числа/.test(m)));
  assert.ok(
    messages(infoJson({ version: '0.0.0' })).some((m) => /0\.0\.0 недопустима/.test(m)),
  );
});

test('число версии больше 65535 — находка', () => {
  assert.ok(
    messages(infoJson({ version: '1.0.70000' })).some((m) => /больше 65535/.test(m)),
  );
});

test('title без префикса и длиннее 100 символов — находки', () => {
  assert.ok(messages(infoJson({ title: 'Fixture' })).some((m) => /title/.test(m)));
  const long = MOD_TITLE_PREFIX + 'x'.repeat(100);
  assert.ok(messages(infoJson({ title: long })).some((m) => /игра отклоняет/.test(m)));
});

test('чужой author — находка', () => {
  assert.ok(messages(infoJson({ author: 'Someone' })).some((m) => /author/.test(m)));
});

test('factorio_version из трёх чисел — находка', () => {
  assert.ok(
    messages(infoJson({ factorio_version: '2.0.77' })).some((m) => /2 числа/.test(m)),
  );
});

test('отсутствие factorio_version — находка про дефолт 0.12', () => {
  const raw = JSON.stringify({
    name: NAME,
    version: '0.1.0',
    title: `${MOD_TITLE_PREFIX}F`,
    author: 'Shahimat',
  });
  assert.ok(messages(raw).some((m) => /0\.12/.test(m)));
});

test('factorio_version вне известных дорожек — замечание, не ошибка', () => {
  const { problems } = check(infoJson({ factorio_version: '1.1' }));
  assert.equal(countErrors(problems), 0);
  assert.ok(problems.some((p) => p.severity === 'warning'));
});

test('все формы префиксов зависимостей разбираются', () => {
  const deps = [
    'base',
    '? flib >= 0.16.0',
    '! some-conflict',
    '(?) hidden-opt',
    '~ no-order',
    'mod-a > 1.2.3',
  ];
  const { info, problems } = check(infoJson({ dependencies: deps }));
  assert.deepEqual(problems, []);
  assert.equal(info?.dependencies.length, deps.length);
});

test('неразбираемая зависимость и не массив — находки', () => {
  assert.ok(
    messages(infoJson({ dependencies: ['!! nope'] })).some((m) =>
      /не разбирается строка/.test(m),
    ),
  );
  assert.ok(
    messages(infoJson({ dependencies: 'base' })).some((m) => /массивом строк/.test(m)),
  );
});
