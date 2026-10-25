import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  colorWeight,
  composeTinted,
  crop,
  luminance,
  maskSprite,
  place,
  rgbToHsv,
  TURBO_SPLIT,
} from './recolor.ts';

function pixel(r: number, g: number, b: number, a = 255): Uint8Array {
  return Uint8Array.from([r, g, b, a]);
}

describe('rgbToHsv', () => {
  it('чистые цвета дают свой тон', () => {
    assert.equal(rgbToHsv(255, 0, 0).h, 0);
    assert.equal(rgbToHsv(0, 255, 0).h, 120);
    assert.equal(rgbToHsv(0, 0, 255).h, 240);
  });

  it('серый без насыщенности', () => {
    const hsv = rgbToHsv(128, 128, 128);
    assert.equal(hsv.s, 0);
  });
});

describe('colorWeight', () => {
  it('жёлто-зелёный турбо — полный вес', () => {
    assert.equal(colorWeight(160, 190, 30, TURBO_SPLIT), 1);
  });

  it('серый металл — нулевой вес', () => {
    assert.equal(colorWeight(120, 120, 125, TURBO_SPLIT), 0);
  });

  it('ржаво-коричневый вне полосы тона — нулевой вес', () => {
    assert.equal(colorWeight(150, 70, 40, TURBO_SPLIT), 0);
  });

  it('бледный жёлто-зелёный между порогами насыщенности — частичный вес', () => {
    const weight = colorWeight(150, 160, 120, TURBO_SPLIT);
    assert.ok(weight > 0 && weight < 1, `вес ${weight}`);
  });
});

describe('maskSprite', () => {
  it('цветной пиксель непрозрачен в маске и серый', () => {
    const mask = maskSprite(pixel(160, 190, 30), TURBO_SPLIT);
    assert.equal(mask[0], mask[1]);
    assert.equal(mask[1], mask[2]);
    assert.equal(mask[3], 255);
  });

  it('серый пиксель в маске прозрачен и обнулён', () => {
    assert.deepEqual([...maskSprite(pixel(90, 90, 95, 200), TURBO_SPLIT)], [0, 0, 0, 0]);
  });

  it('прозрачный пиксель прозрачен в маске', () => {
    assert.equal(maskSprite(pixel(160, 190, 30, 0), TURBO_SPLIT)[3], 0);
  });

  it('маска ярче исходной яркости на maskGain, но не выше 255', () => {
    const mask = maskSprite(pixel(100, 130, 20), TURBO_SPLIT);
    const expected = Math.round(luminance(100, 130, 20) * TURBO_SPLIT.maskGain);
    assert.equal(mask[0], Math.min(255, expected));
  });

  it('буфер не кратный 4 — ошибка', () => {
    assert.throws(() => maskSprite(Uint8Array.from([1, 2, 3]), TURBO_SPLIT), /кратна 4/);
  });
});

describe('composeTinted', () => {
  it('непрозрачная маска перекрывает спрайт цветом tint', () => {
    const out = composeTinted(pixel(10, 10, 10), pixel(255, 255, 255), { r: 200, g: 0, b: 100 });
    assert.deepEqual([...out], [200, 0, 100, 255]);
  });

  it('прозрачная маска оставляет спрайт', () => {
    const out = composeTinted(pixel(10, 20, 30), pixel(255, 255, 255, 0), { r: 200, g: 0, b: 100 });
    assert.deepEqual([...out], [10, 20, 30, 255]);
  });

  it('разный размер слоёв — ошибка', () => {
    assert.throws(() => composeTinted(pixel(0, 0, 0), new Uint8Array(8), { r: 0, g: 0, b: 0 }), /разного размера/);
  });
});

describe('crop и place', () => {
  const image = {
    width: 2,
    height: 2,
    data: Uint8Array.from([1, 1, 1, 255, 2, 2, 2, 255, 3, 3, 3, 255, 4, 4, 4, 255]),
  };

  it('crop вырезает нужный пиксель', () => {
    assert.deepEqual([...crop(image, 1, 1, 1, 1).data], [4, 4, 4, 255]);
  });

  it('crop за границей — ошибка', () => {
    assert.throws(() => crop(image, 1, 1, 2, 1), /вне картинки/);
  });

  it('place кладёт непрозрачное поверх холста', () => {
    const canvas = { width: 3, height: 3, data: new Uint8Array(36) };
    place(canvas, image, 1, 1);
    assert.deepEqual([...canvas.data.subarray(32, 36)], [4, 4, 4, 255]);
    assert.equal(canvas.data[3], 0);
  });

  it('place за границей холста — ошибка', () => {
    const canvas = { width: 2, height: 2, data: new Uint8Array(16) };
    assert.throws(() => place(canvas, image, 1, 0), /не помещается/);
  });
});
