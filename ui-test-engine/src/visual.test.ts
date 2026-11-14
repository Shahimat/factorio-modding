import assert from 'node:assert/strict';
import { test } from 'node:test';

import { checkImages, crop, inspectFrame, type Raster } from './visual.ts';

function image(): Raster {
  const data = new Uint8Array(480 * 320 * 4);
  for (let at = 3; at < data.length; at += 4) data[at] = 255;
  return { width: 480, height: 320, data };
}

function paint(raster: Raster, x: number, y: number, width: number, height: number, color: readonly number[]): void {
  for (let row = y; row < y + height; row += 1) {
    for (let col = x; col < x + width; col += 1) {
      raster.data.set(color, (row * raster.width + col) * 4);
    }
  }
}

function fixture(clicked: boolean): Raster {
  const raster = image();
  paint(raster, 100, 40, 80, 10, [255, 0, 255, 255]);
  paint(raster, 100, 60, 60, 10, clicked ? [51, 255, 51, 255] : [255, 51, 51, 255]);
  paint(raster, 100, 110, 70, 5, [0, 255, 255, 255]);
  return raster;
}

test('both real GUI markers, visible button and red-to-green transition are required', () => {
  const proof = checkImages(fixture(false), fixture(true));
  assert.ok(proof.checks.every((check) => check.passed));
  assert.equal(proof.before.red, 600);
  assert.equal(proof.after.green, 600);
  assert.equal(proof.after.cyan, 350);
});

test('world-only PNGs, unchanged counter and invisible button fail independently', () => {
  assert.equal(checkImages(image(), image()).checks.find((check) => check.name === 'GUI visible in both PNGs')?.passed, false);
  assert.equal(checkImages(fixture(false), fixture(false)).checks.find((check) => check.name === 'counter visibly changes red to green')?.passed, false);
  const hidden = fixture(true);
  paint(hidden, 100, 110, 70, 5, [0, 0, 0, 255]);
  assert.equal(checkImages(fixture(false), hidden).checks.find((check) => check.name === 'button visible in both PNGs')?.passed, false);
  const foreignGreen = fixture(false);
  paint(foreignGreen, 0, 250, 100, 20, [51, 255, 51, 255]);
  assert.equal(checkImages(fixture(false), foreignGreen).checks.find((check) => check.name === 'counter visibly changes red to green')?.passed, false);
});

test('dimension changes, unrelated magenta regions and transparent markers do not pass', () => {
  const resized = { ...fixture(true), width: 320, height: 480 };
  assert.equal(checkImages(fixture(false), resized).checks[0]?.passed, false);
  const scattered = fixture(true);
  paint(scattered, 450, 250, 20, 10, [255, 0, 255, 255]);
  assert.equal(inspectFrame(scattered).anchor, undefined);
  const transparent = fixture(true);
  paint(transparent, 100, 40, 80, 10, [255, 0, 255, 0]);
  assert.equal(inspectFrame(transparent).anchor, undefined);
});

test('RGBA and crop bounds are validated, cropping preserves pixels without mutating input', () => {
  assert.throws(() => inspectFrame({ width: 0, height: 1, data: new Uint8Array() }), /\[image\]/);
  assert.throws(() => inspectFrame({ width: 1, height: 1, data: new Uint8Array(3) }), /\[image\]/);
  const source = fixture(false);
  const clipped = crop(source, { x: 100, y: 60, width: 2, height: 1 });
  assert.deepEqual([...clipped.data], [255, 51, 51, 255, 255, 51, 51, 255]);
  clipped.data[0] = 0;
  assert.equal(source.data[(60 * 480 + 100) * 4], 255);
  for (const bounds of [
    { x: -1, y: 0, width: 1, height: 1 }, { x: 0, y: 0, width: 0, height: 1 },
    { x: 479, y: 0, width: 2, height: 1 }, { x: 0.5, y: 0, width: 1, height: 1 },
  ]) assert.throws(() => crop(source, bounds), /\[image\]/);
});
