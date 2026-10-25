import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { maskPath, THUMBNAIL_ICON, THUMBNAIL_TINTS, TURBO_SOURCES } from './recolor-jobs.ts';

describe('maskPath', () => {
  it('убирает turbo- из каталога и имени и добавляет -mask', () => {
    assert.equal(
      maskPath('entity/turbo-splitter/turbo-splitter-east-top_patch.png'),
      'entity/splitter/splitter-east-top_patch-mask.png',
    );
  });

  it('не PNG — ошибка', () => {
    assert.throws(() => maskPath('entity/turbo-splitter/turbo-splitter-east.lua'), /не PNG/);
  });
});

describe('TURBO_SOURCES', () => {
  it('без замёрзших патчей и остатков', () => {
    for (const source of TURBO_SOURCES) {
      assert.ok(!source.includes('frozen') && !source.includes('remnants'), source);
    }
  });

  it('картинка мода собирается из перекрашиваемой иконки, цвет на каждый из четырёх тиров', () => {
    assert.ok(TURBO_SOURCES.includes(THUMBNAIL_ICON));
    assert.equal(THUMBNAIL_TINTS.length, 4);
  });
});
