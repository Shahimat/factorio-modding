import assert from 'node:assert/strict';
import { test } from 'node:test';

import { markerPoints } from './profiles.ts';
import { checkWindowImages, type Bounds, type Raster } from './visual.ts';

const viewport = { width: 960, height: 540 };
const frame: Bounds = { x: 120, y: 50, width: 700, height: 400 };
const origin = { x: 200, y: 100 };
const reference: Bounds = { x: 10, y: 10, width: 100, height: 32 };

function check(before: Raster, after: Raster, first = frame, last = frame) {
  return checkWindowImages(before, after, first, last, viewport, reference);
}

function paint(image: Raster, area: Bounds, color: readonly number[]): void {
  for (let y = area.y; y < area.y + area.height; y += 1) {
    for (let x = area.x; x < area.x + area.width; x += 1) image.data.set(color, (y * image.width + x) * 4);
  }
}

function fixture(expanded: boolean): Raster {
  const image: Raster = { width: 1500, height: 900, data: new Uint8Array(1500 * 900 * 4) };
  for (let at = 3; at < image.data.length; at += 4) image.data[at] = 255;
  const [start, end] = markerPoints(viewport);
  paint(image, { x: origin.x + start.x, y: origin.y + start.y, width: 6, height: 1 }, [255, 0, 255, 255]);
  paint(image, { x: origin.x + end.x, y: origin.y + end.y, width: 6, height: 1 }, [0, 255, 255, 255]);
  paint(image, { ...frame, x: origin.x + frame.x, y: origin.y + frame.y }, [50, 50, 50, 255]);
  if (expanded) paint(image, { x: origin.x + frame.x + 16, y: origin.y + frame.y + 96, width: frame.width - 32, height: frame.height - 120 }, [100, 100, 100, 255]);
  paint(image, { ...reference, x: origin.x + reference.x, y: origin.y + reference.y }, [50, 50, 50, 255]);
  for (const point of [{ x: reference.x + 12, y: reference.y + 4 }, { x: frame.x + 12, y: frame.y + 8 }]) {
    for (let y = 0; y < 8; y += 1) for (let x = 0; x < 40; x += 1) {
      if (x % 6 < 4 && (y === 0 || y === 7 || x % 3 === 0)) paint(image, { x: origin.x + point.x + x, y: origin.y + point.y + y, width: 1, height: 1 }, [255, 230, 190, 255]);
    }
  }
  return image;
}

test('native window proof uses unchanged edge markers and changed production content, not marker colors as state', () => {
  const proof = check(fixture(true), fixture(false));
  assert.ok(proof.checks.every((check) => check.passed));
  assert.deepEqual(proof.before.origin, origin);
  assert.ok(proof.before.crop);
});

test('unchanged content, a changed disabled-toggle and outside-world animation cannot pass', () => {
  const same = fixture(true);
  paint(same, { x: origin.x + frame.x + 8, y: origin.y + frame.y + 60, width: 20, height: 20 }, [200, 200, 200, 255]);
  paint(same, { x: 0, y: 0, width: 150, height: 900 }, [150, 0, 0, 255]);
  const checks = check(fixture(true), same).checks;
  assert.equal(checks.find((check) => check.name === 'card content visibly changes')?.passed, false);
});

test('missing markers, moved window, clipping, changed title and mismatched PNG dimensions fail', () => {
  const missing = fixture(false);
  const [start] = markerPoints(viewport);
  paint(missing, { x: origin.x + start.x, y: origin.y + start.y, width: 6, height: 1 }, [0, 0, 0, 255]);
  assert.ok(check(fixture(true), missing).checks.some((check) => !check.passed));
  assert.ok(check(fixture(true), fixture(false), frame, { ...frame, x: frame.x + 1 }).checks.some((check) => !check.passed));
  assert.ok(check(fixture(true), fixture(false), { ...frame, width: 2000 }).checks.some((check) => !check.passed));
  const corrupt = fixture(false);
  paint(corrupt, { x: origin.x + frame.x + 16, y: origin.y + frame.y + 2, width: frame.width - 32, height: 18 }, [200, 200, 200, 255]);
  assert.equal(check(fixture(true), corrupt).checks.find((check) => check.name === 'window title area stays stable')?.passed, false);
  const resized = { ...fixture(false), width: 900, height: 1500 };
  assert.equal(check(fixture(true), resized).checks[0]?.passed, false);
});

test('world-only content cannot pass by merely changing while both edge markers stay visible', () => {
  const world = fixture(false);
  paint(world, { x: origin.x + frame.x + 16, y: origin.y + frame.y + 96, width: frame.width - 32, height: frame.height - 120 }, [40, 100, 20, 255]);
  const checks = check(fixture(true), world).checks;
  assert.equal(checks.find((check) => check.name === 'card content visibly changes')?.passed, true);
  assert.equal(checks.find((check) => check.name === 'collapsed content area is cleared to GUI background')?.passed, false);
});

test('regression: static markers and a changing rectangle cannot prove a production title exists', () => {
  const before = fixture(false);
  const after = fixture(false);
  for (const image of [before, after]) paint(image, { ...frame, x: origin.x + frame.x, y: origin.y + frame.y }, [50, 50, 50, 255]);
  paint(after, { x: origin.x + frame.x + 20, y: origin.y + frame.y + 110, width: 100, height: 60 }, [80, 80, 80, 255]);
  const checks = check(before, after).checks;
  assert.equal(checks.find((item) => item.name === 'card content visibly changes')?.passed, true);
  assert.equal(checks.find((item) => item.name === 'collapsed content area is cleared to GUI background')?.passed, true);
  assert.equal(checks.find((item) => item.name === 'production title is rendered in both PNGs')?.passed, false);
  const white = fixture(false);
  paint(white, { x: origin.x + frame.x, y: origin.y + frame.y, width: frame.width, height: 50 }, [255, 255, 255, 255]);
  assert.equal(check(fixture(true), white).checks.find((item) => item.name === 'production title is rendered in both PNGs')?.passed, false);
});
