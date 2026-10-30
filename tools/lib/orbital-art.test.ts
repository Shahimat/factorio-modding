import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  blank,
  blendPixel,
  drawArc,
  drawArrowHead,
  route,
  ROUTE_HEIGHT,
  ROUTE_WIDTH,
  scale,
  thumbnail,
  THUMBNAIL_SIZE,
  withinArc,
} from './orbital-art.ts';

function alphaAt(image: { width: number; data: Uint8Array }, x: number, y: number): number {
  return image.data[(y * image.width + x) * 4 + 3] ?? 0;
}

function solid(width: number, height: number): ReturnType<typeof blank> {
  return blank(width, height, [200, 100, 50, 255]);
}

describe('orbital-art', () => {
  it('blendPixel кладёт цвет по покрытию и игнорирует выход за край', () => {
    const canvas = blank(2, 2);
    blendPixel(canvas, 0, 0, [255, 0, 0, 255], 1);
    blendPixel(canvas, 1, 0, [255, 0, 0, 255], 0.5);
    blendPixel(canvas, 5, 5, [255, 0, 0, 255], 1);
    assert.equal(alphaAt(canvas, 0, 0), 255);
    assert.equal(alphaAt(canvas, 1, 0), 128);
    assert.equal(alphaAt(canvas, 0, 1), 0);
  });

  it('scale усредняет по площади и даёт нужный размер', () => {
    const source = blank(4, 4);
    for (let i = 0; i < 8; i++) {
      source.data.set([255, 255, 255, 255], i * 4);
    }
    const small = scale(source, 2, 2);
    assert.equal(small.width, 2);
    assert.equal(small.height, 2);
    assert.equal(alphaAt(small, 0, 0), 255);
    assert.equal(alphaAt(small, 0, 1), 0);
  });

  it('withinArc учитывает переход через 0', () => {
    assert.equal(withinArc(0, -0.5, 0.5), true);
    assert.equal(withinArc(Math.PI, -0.5, 0.5), false);
    assert.equal(withinArc(-Math.PI / 2, -Math.PI, 0), true);
  });

  it('полный оборот — весь круг', () => {
    assert.equal(withinArc(1, -Math.PI, Math.PI), true);
    const canvas = blank(40, 40);
    drawArc(canvas, 20, 20, 15, -Math.PI, Math.PI, 2, [255, 255, 255, 255]);
    assert.ok(alphaAt(canvas, 20, 5) > 0 && alphaAt(canvas, 20, 34) > 0 && alphaAt(canvas, 5, 20) > 0, 'круг не замкнут');
  });

  it('drawArc рисует на окружности внутри дуги и не рисует вне её', () => {
    const canvas = blank(40, 40);
    drawArc(canvas, 20, 20, 15, -Math.PI / 2 - 0.3, -Math.PI / 2 + 0.3, 3, [255, 255, 255, 255]);
    assert.ok(alphaAt(canvas, 20, 5) > 0, 'нет пикселя на вершине дуги');
    assert.equal(alphaAt(canvas, 20, 20), 0, 'закрашен центр');
    assert.equal(alphaAt(canvas, 20, 34), 0, 'закрашена противоположная сторона');
  });

  it('пунктир оставляет пропуски', () => {
    const solidArc = blank(60, 60);
    const dashed = blank(60, 60);
    drawArc(solidArc, 30, 30, 25, 0, Math.PI, 3, [255, 255, 255, 255]);
    drawArc(dashed, 30, 30, 25, 0, Math.PI, 3, [255, 255, 255, 255], 6);
    const count = (image: typeof solidArc): number => {
      let n = 0;
      for (let i = 3; i < image.data.length; i += 4) {
        if ((image.data[i] ?? 0) > 0) {
          n++;
        }
      }
      return n;
    };
    assert.ok(count(dashed) < count(solidArc) * 0.75);
  });

  it('drawArrowHead закрашивает треугольник у острия', () => {
    const canvas = blank(30, 30);
    drawArrowHead(canvas, 25, 15, 0, 12, [255, 255, 255, 255]);
    assert.ok(alphaAt(canvas, 20, 15) > 200, 'нет заливки за остриём');
    assert.equal(alphaAt(canvas, 27, 15), 0, 'заливка впереди острия');
  });

  it('thumbnail и route дают размеры, которые ждут портал и подсказки', () => {
    const icon = solid(64, 64);
    const thumb = thumbnail(icon);
    assert.equal(thumb.width, THUMBNAIL_SIZE);
    assert.equal(thumb.height, THUMBNAIL_SIZE);
    assert.equal(alphaAt(thumb, 0, 0), 255, 'у картинки мода должен быть фон');
    const path = route(solid(128, 128), solid(128, 128), icon);
    assert.equal(path.width, ROUTE_WIDTH);
    assert.equal(path.height, ROUTE_HEIGHT);
    assert.equal(alphaAt(path, 0, 0), 0, 'фон подсказки прозрачный');
  });
});
