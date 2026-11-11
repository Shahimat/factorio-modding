import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test, type TestContext } from 'node:test';

import { stringify } from 'yaml';

import { checkIndex, checkQueue } from './check-docs-navigation.ts';

async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), 'docs-navigation-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  async function put(file: string, value: unknown) {
    await mkdir(dirname(join(root, file)), { recursive: true });
    await writeFile(join(root, file), stringify(value));
  }
  return { root, put };
}

function entry(key: string, extra: Record<string, unknown> = {}) {
  return { key, file: `goal--${key}.yaml`, status: 'planned', one_liner: key, ...extra };
}

function goal(key: string, extra: Record<string, unknown> = {}) {
  return {
    key, title: key, status: 'planned', why: key, description: key,
    tasks: { blocker: [], high: ['Deliver result → feat → none'], medium: [], low: [] },
    depends_on: [], ...extra,
  };
}

test('queue accepts an empty ordered list and a program, subgoal and standalone goal', async (t) => {
  const { root, put } = await fixture(t);
  await put('context/views/goals.yaml', []);
  assert.deepEqual(await checkQueue(root), []);
  await put('context/views/goals.yaml', { goals: [
    entry('platform', { file: 'program--platform.yaml', kind: 'program', subgoals: [entry('child')] }),
    entry('solo'),
  ] });
  await put('context/views/program--platform.yaml', goal('platform', { kind: 'program' }));
  await put('context/views/goal--child.yaml', goal('child', { program: 'platform' }));
  await put('context/views/goal--solo.yaml', goal('solo', { depends_on: ['child'] }));
  assert.deepEqual(await checkQueue(root), []);
});

test('queue rejects missing index/file, duplicates, done, malformed tasks, membership and dependency errors', async (t) => {
  const cases: Array<[string, unknown[], Record<string, unknown>, RegExp]> = [
    ['missing file', [entry('a')], {}, /не читается/],
    ['duplicate key', [entry('a'), entry('a')], { 'goal--a.yaml': goal('a') }, /дубликат/],
    ['wrong filename', [entry('a', { file: '../goal--a.yaml' })], {}, /file должен/],
    ['wrong key', [entry('a')], { 'goal--a.yaml': goal('b') }, /key не совпадает/],
    ['done', [entry('a', { status: 'done' })], { 'goal--a.yaml': goal('a', { status: 'done' }) }, /status/],
    ['status mismatch', [entry('a')], { 'goal--a.yaml': goal('a', { status: 'active' }) }, /status/],
    ['bad tasks', [entry('a')], { 'goal--a.yaml': goal('a', { tasks: { high: [7], done: [] } }) }, /tasks/],
    ['unknown dependency', [entry('a')], { 'goal--a.yaml': goal('a', { depends_on: ['missing'] }) }, /неизвестный key/],
    ['self cycle', [entry('a')], { 'goal--a.yaml': goal('a', { depends_on: ['a'] }) }, /цикл/],
    ['cycle', [entry('a'), entry('b')], {
      'goal--a.yaml': goal('a', { depends_on: ['b'] }),
      'goal--b.yaml': goal('b', { depends_on: ['a'] }),
    }, /цикл/],
    ['membership', [entry('a')], { 'goal--a.yaml': goal('a', { program: 'missing' }) }, /membership/],
    ['unindexed file', [], { 'goal--a.yaml': goal('a') }, /не включён/],
  ];
  for (const [name, entries, files, expected] of cases) {
    await t.test(name, async (t) => {
      const { root, put } = await fixture(t);
      const missing = await checkQueue(root);
      assert.ok(missing.some((p) => /не читается/.test(p.message)));
      await put('context/views/goals.yaml', entries);
      for (const [file, data] of Object.entries(files)) await put(`context/views/${file}`, data);
      assert.ok((await checkQueue(root)).some((p) => expected.test(p.message)), name);
    });
  }
});

test('index validates classic sections without rejecting extension fields', async (t) => {
  const { root, put } = await fixture(t);
  assert.ok((await checkIndex(root)).some((p) => /не читается/.test(p.message)));
  await put('context/project.yml', { namespaces: { fixture: 'Fixture', other: 'Other' } });
  await put('docs/entities/sample.yml', { id: 'sample', namespace: 'fixture' });
  await put('docs/behavior/works.yml', { id: 'works', namespace: 'fixture' });
  await put('context/conventions/testing.yml', { key: 'testing' });
  await mkdir(join(root, 'docs/manuals'), { recursive: true });
  await writeFile(join(root, 'docs/manuals/setup.md'), '# Setup\n');
  const index = {
    conventions: { testing: 'Testing' },
    namespaces: { fixture: {
      entities: { sample: 'Sample' }, behaviors: { works: 'Works' }, manuals: { setup: 'Setup' },
    } },
    specs: { arbitrary_extension: ['not constrained by the classic checker'] },
  };
  await put('context/index.yml', index);
  assert.deepEqual(await checkIndex(root), []);
  await put('context/index.yml', { ...index, namespaces: {
    ...index.namespaces,
    other: { entities: { sample: 'Duplicate', missing: 'Missing' }, manuals: { absent: 'Absent' } },
    unknown: {},
  } });
  const broken = await checkIndex(root);
  for (const expected of [/дубликат id/, /namespace не совпадает/, /отсутствует файл/, /manuals\/absent/, /неизвестный namespace/]) {
    assert.ok(broken.some((p) => expected.test(p.message)), String(expected));
  }
  await put('context/index.yml', { conventions: {}, namespaces: { fixture: {} } });
  assert.ok((await checkIndex(root)).some((p) => /нет записи в индексе/.test(p.message)));
});
