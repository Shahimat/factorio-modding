import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { test } from 'node:test';

import { checkProject } from './check-docs-context.ts';
import { checkLayers } from './check-docs-layers.ts';
import { DIRS, docsDirs } from './docs-model.ts';
import { REPO_ROOT } from './packages.ts';

test('docs checker uses the v2 docs/context layout', () => {
  assert.deepEqual(
    Object.fromEntries(Object.entries(DIRS).map(([key, dir]) => [key, relative(REPO_ROOT, dir)])),
    {
      entities: 'docs/entities',
      behaviors: 'docs/behavior',
      manuals: 'docs/manuals',
      conventions: 'context/conventions',
      modules: 'context/modules',
      specs: 'specs',
    },
  );
});

test('docs checker discovers nonempty real migrated layers', async () => {
  const layers = await checkLayers();
  for (const [name, items] of Object.entries({
    entities: layers.entityIds,
    behaviors: layers.behaviorIds,
    manuals: layers.manualNames,
    conventions: layers.conventionKeys,
  })) {
    assert.ok(items.length > 0, `${name} must not silently disappear`);
  }
});

test('migrated fixture detects a broken backlink and missing project.yml', async (t) => {
  const root = await mkdtemp(join(tmpdir(), 'docs-layout-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const dirs = docsDirs(root);
  await Promise.all(Object.values(dirs).map((dir) => mkdir(dir, { recursive: true })));
  await writeFile(join(dirs.entities, 'sample.yml'), [
    'id: sample', 'namespace: fixture', 'summary: Sample', 'behaviors: [works]', '',
  ].join('\n'));
  const behavior = [
    'id: works', 'namespace: fixture', 'title: Works', 'entities: [sample]',
    'verified: false', 'verified_note: Fixture', 'scenarios:',
    '  - given: input', '    when: action', '    then: output', '',
  ].join('\n');
  await writeFile(join(dirs.behaviors, 'works.yml'), behavior);
  assert.deepEqual((await checkLayers(dirs)).problems, []);

  await writeFile(join(dirs.behaviors, 'works.yml'), behavior.replace('entities: [sample]', 'entities: []'));
  const broken = await checkLayers(dirs);
  assert.ok(broken.problems.some((problem) =>
    problem.file.endsWith('sample.yml') && problem.message.includes('обратной ссылки')));

  const missing = await checkProject(root);
  assert.equal(missing.length, 1);
  assert.equal(missing[0]?.file, 'context/project.yml');
  assert.match(missing[0]?.message ?? '', /не читается/);

  const project = join(root, 'context/project.yml');
  await writeFile(project, [
    'sync:', '  index_source: https://example.invalid/index.yml', '  index_sha: fixture',
    '  contract:', '    key: agent-operational-contract-v2',
    '    synced_sha: fixture', 'namespaces:', '  fixture: {}', '',
  ].join('\n'));
  assert.deepEqual(await checkProject(root), []);
  await writeFile(project, 'sync: {}\n');
  const invalid = await checkProject(root);
  for (const field of ['index_source', 'index_sha', 'sync.contract', 'namespaces']) {
    assert.ok(invalid.some((problem) => problem.message.includes(field)), field);
  }
});
