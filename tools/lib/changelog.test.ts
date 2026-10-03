import assert from 'node:assert/strict';
import { test } from 'node:test';

import { parseChangelog } from './changelog.ts';
import { CHANGELOG_SEPARATOR_LENGTH } from './conventions.ts';
import { countErrors } from './problems.ts';

const SEP = '-'.repeat(CHANGELOG_SEPARATOR_LENGTH);

/** Корректный changelog с одной секцией. */
function valid(version = '0.1.0'): string {
  return [
    SEP,
    `Version: ${version}`,
    'Date: 2026-10-04',
    '  Features:',
    '    - Первая запись.',
    '',
  ].join('\n');
}

function ids(raw: string): string[] {
  return parseChangelog(raw, 'changelog.txt').problems.map((p) => p.message);
}

test('корректный changelog проходит без находок', () => {
  const result = parseChangelog(valid(), 'changelog.txt');
  assert.deepEqual(result.problems, []);
  assert.deepEqual(result.versions, ['0.1.0']);
  assert.equal(result.present, true);
});

test('многострочная запись с отступом шесть пробелов допустима', () => {
  const raw = [
    SEP,
    'Version: 0.1.0',
    '  Bugfixes:',
    '    - Первая строка записи.',
    '      Продолжение той же записи.',
  ].join('\n');
  assert.deepEqual(parseChangelog(raw, 'changelog.txt').problems, []);
});

test('разделитель не из 99 дефисов — находка', () => {
  const raw = valid().replace(SEP, '-'.repeat(97));
  assert.ok(ids(raw).some((m) => /97 дефисов вместо 99/.test(m)));
});

test('пустая строка после разделителя не ломает разбор остатка', () => {
  const raw = [SEP, '', 'Version: 0.1.0', '  Features:', '    - X.'].join('\n');
  const result = parseChangelog(raw, 'changelog.txt');
  assert.equal(countErrors(result.problems), 1);
  assert.ok(/не может быть пустой/.test(result.problems[0]?.message ?? ''));
  assert.deepEqual(result.versions, ['0.1.0']);
});

test('Version без пробела после двоеточия — находка', () => {
  const raw = valid().replace('Version: 0.1.0', 'Version:0.1.0');
  assert.ok(ids(raw).some((m) => /ожидается строка "Version: /.test(m)));
});

test('табуляция и пробел в конце строки запрещены', () => {
  const withTab = valid().replace('    - Первая запись.', '    - Таб\tвнутри.');
  assert.ok(ids(withTab).some((m) => /табуляция/.test(m)));

  const withTrailing = valid().replace('  Features:', '  Features: ');
  assert.ok(ids(withTrailing).some((m) => /пробел в конце строки/.test(m)));
});

test('запись до категории — находка', () => {
  const raw = [SEP, 'Version: 0.1.0', '    - Без категории.'].join('\n');
  assert.ok(ids(raw).some((m) => /до строки категории/.test(m)));
});

test('отступ категории не в два пробела — находка', () => {
  const raw = valid().replace('  Features:', '   Features:');
  assert.ok(ids(raw).some((m) => /некорректный отступ/.test(m)));
});

test('категория без двоеточия — находка', () => {
  const raw = valid().replace('  Features:', '  Features');
  assert.ok(ids(raw).some((m) => /заканчиваться двоеточием/.test(m)));
});

test('нераспознанная категория — замечание, не ошибка', () => {
  const raw = valid().replace('  Features:', '  Фичи:');
  const result = parseChangelog(raw, 'changelog.txt');
  assert.equal(countErrors(result.problems), 0);
  assert.ok(result.problems.some((p) => p.severity === 'warning'));
});

test('две секции с одной версией — находка', () => {
  const raw = valid() + valid();
  assert.ok(ids(raw).some((m) => /встречается повторно/.test(m)));
});

test('дубль записи внутри категории — находка', () => {
  const raw = [
    SEP,
    'Version: 0.1.0',
    '  Features:',
    '    - Одно и то же.',
    '    - Одно и то же.',
  ].join('\n');
  assert.ok(ids(raw).some((m) => /дубль записи/.test(m)));
});

test('две строки Date в одной секции — находка', () => {
  const raw = valid().replace(
    'Date: 2026-10-04',
    'Date: 2026-10-04\nDate: 2026-10-05',
  );
  assert.ok(ids(raw).some((m) => /две строки Date/.test(m)));
});

test('версия не из трёх чисел и версия 0.0.0 — находки', () => {
  assert.ok(ids(valid('1.0')).some((m) => /number\.number\.number/.test(m)));
  assert.ok(ids(valid('0.0.0')).some((m) => /0\.0\.0 недопустима/.test(m)));
});

test('число версии больше 65535 — находка', () => {
  assert.ok(ids(valid('1.0.70000')).some((m) => /больше 65535/.test(m)));
});

test('строка до первого разделителя — находка', () => {
  const raw = 'мусор\n' + valid();
  assert.ok(ids(raw).some((m) => /вне секции версии/.test(m)));
});

test('файл, оканчивающийся разделителем без Version — находка', () => {
  const raw = valid() + SEP + '\n';
  assert.ok(ids(raw).some((m) => /без строки Version/.test(m)));
});

test('порядок версий сохраняется, верхняя — первая', () => {
  const raw = valid('0.2.0') + valid('0.1.0');
  assert.deepEqual(
    parseChangelog(raw, 'changelog.txt').versions,
    ['0.2.0', '0.1.0'],
  );
});
