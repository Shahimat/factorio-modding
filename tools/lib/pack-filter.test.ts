import assert from 'node:assert/strict';
import { test } from 'node:test';

import { PACK_EXCLUDED } from './conventions.ts';
import { isExcludedFromPack } from './pack-filter.ts';

test('файлы мода попадают в архив', () => {
  for (const rel of [
    'info.json',
    'control.lua',
    'data.lua',
    'changelog.txt',
    'LICENSE',
    'thumbnail.png',
    'logic/demand.lua',
    'locale/en/strings.cfg',
    'graphics/icons/chest.png',
    'migrations/1-0-0.lua',
  ]) {
    assert.equal(isExcludedFromPack(rel), false, `${rel} должен попадать в zip`);
  }
});

test('корень пакета исключением не считается', () => {
  assert.equal(isExcludedFromPack(''), false);
});

test('каждое имя из PACK_EXCLUDED отбивается на любом уровне', () => {
  for (const name of PACK_EXCLUDED) {
    assert.equal(isExcludedFromPack(name), true, name);
    assert.equal(isExcludedFromPack(`logic/${name}`), true, `logic/${name}`);
    assert.equal(
      isExcludedFromPack(`${name}/внутри.lua`),
      true,
      `${name}/внутри.lua`,
    );
  }
});

test('тесты не уезжают на портал', () => {
  // Это и есть причина существования модуля: пакет мода версионируется с
  // тестами, а zip уходит публично.
  assert.equal(isExcludedFromPack('tests/demand.test.lua'), true);
  assert.equal(isExcludedFromPack('logic/demand.test.lua'), true);
  assert.equal(isExcludedFromPack('package.json'), true);
});

test('вложенные архивы исключаются, прочие расширения — нет', () => {
  assert.equal(isExcludedFromPack('shm-x_0.1.0.zip'), true);
  assert.equal(isExcludedFromPack('graphics/sprites.zip'), true);
  assert.equal(isExcludedFromPack('graphics/sprites.png'), false);
});

test('разделитель Windows разбирается так же, как posix', () => {
  assert.equal(isExcludedFromPack('tests\\demand.test.lua'), true);
  assert.equal(isExcludedFromPack('logic\\demand.lua'), false);
});

test('имя, лишь начинающееся с исключённого, не отбивается', () => {
  // Регрессия: сравнение по префиксу вместо сравнения сегментов выкидывало
  // из архива легитимный файл.
  assert.equal(isExcludedFromPack('tests-helper.lua'), false);
  assert.equal(isExcludedFromPack('distribution/plan.lua'), false);
  assert.equal(isExcludedFromPack('package.json.lua'), false);
});
