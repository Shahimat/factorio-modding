import type { Check } from './protocol.ts';

export interface Raster {
  readonly width: number;
  readonly height: number;
  readonly data: Uint8Array;
}
export interface Bounds {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}
export interface FrameProof {
  readonly anchor: Bounds | undefined;
  readonly region: Bounds | undefined;
  readonly red: number;
  readonly green: number;
  readonly cyan: number;
}
type Color = 'anchor' | 'red' | 'green' | 'cyan';

function matches(red: number, green: number, blue: number, color: Color): boolean {
  switch (color) {
    case 'anchor': return red > 230 && green < 40 && blue > 230;
    case 'red': return red > 180 && green < 110 && blue < 110;
    case 'green': return green > 180 && red < 110 && blue < 110;
    case 'cyan': return red < 40 && green > 230 && blue > 230;
  }
}

function validate(image: Raster): void {
  if (!Number.isInteger(image.width) || !Number.isInteger(image.height) || image.width <= 0 || image.height <= 0
    || image.data.length !== image.width * image.height * 4) throw new Error('[image] invalid RGBA raster');
}

function colorPixels(image: Raster, color: Color, region: Bounds): { count: number; bounds: Bounds | undefined } {
  let count = 0;
  let left = image.width;
  let right = -1;
  let top = image.height;
  let bottom = -1;
  for (let y = region.y; y < region.y + region.height; y += 1) {
    for (let x = region.x; x < region.x + region.width; x += 1) {
      const at = (y * image.width + x) * 4;
      if ((image.data[at + 3] ?? 0) < 250 || !matches(image.data[at] ?? 0, image.data[at + 1] ?? 0, image.data[at + 2] ?? 0, color)) continue;
      count += 1;
      left = Math.min(left, x); right = Math.max(right, x);
      top = Math.min(top, y); bottom = Math.max(bottom, y);
    }
  }
  return { count, bounds: count === 0 ? undefined : { x: left, y: top, width: right - left + 1, height: bottom - top + 1 } };
}

/** Semantic PoC markers, not a general golden-image regression comparator. */
export function inspectFrame(image: Raster): FrameProof {
  validate(image);
  const anchor = colorPixels(image, 'anchor', { x: 0, y: 0, width: image.width, height: image.height });
  const bounds = anchor.bounds;
  if (bounds === undefined || anchor.count < 15 || bounds.width < 20 || bounds.width > 300 || bounds.height > 40) {
    return { anchor: undefined, region: undefined, red: 0, green: 0, cyan: 0 };
  }
  const region: Bounds = {
    x: bounds.x,
    y: bounds.y + bounds.height,
    width: Math.min(bounds.width * 4, image.width - bounds.x),
    height: Math.min(bounds.height * 10, image.height - bounds.y - bounds.height),
  };
  return {
    anchor: bounds, region,
    red: colorPixels(image, 'red', region).count,
    green: colorPixels(image, 'green', region).count,
    cyan: colorPixels(image, 'cyan', region).count,
  };
}

export function checkImages(before: Raster, after: Raster): { checks: Check[]; before: FrameProof; after: FrameProof } {
  const first = inspectFrame(before);
  const last = inspectFrame(after);
  const checks: Check[] = [
    { name: 'image dimensions', passed: before.width === after.width && before.height === after.height, detail: `${before.width}×${before.height} → ${after.width}×${after.height}` },
    { name: 'GUI visible in both PNGs', passed: first.anchor !== undefined && last.anchor !== undefined, detail: 'magenta UI-PROBE marker' },
    { name: 'button visible in both PNGs', passed: first.cyan >= 15 && last.cyan >= 15, detail: `cyan pixels ${first.cyan} → ${last.cyan}` },
    { name: 'counter visibly changes red to green', passed: first.red >= 15 && first.green < 10 && last.green >= 15 && last.red < first.red * 0.2, detail: `red ${first.red} → ${last.red}, green ${first.green} → ${last.green}` },
    { name: 'GUI anchor stays in place', passed: first.anchor !== undefined && JSON.stringify(first.anchor) === JSON.stringify(last.anchor), detail: 'same UI-PROBE bounds' },
  ];
  return { checks, before: first, after: last };
}

export function crop(image: Raster, bounds: Bounds): Raster {
  validate(image);
  if (![bounds.x, bounds.y, bounds.width, bounds.height].every(Number.isInteger)
    || bounds.x < 0 || bounds.y < 0 || bounds.width <= 0 || bounds.height <= 0
    || bounds.x + bounds.width > image.width || bounds.y + bounds.height > image.height) throw new Error('[image] crop outside raster');
  const data = new Uint8Array(bounds.width * bounds.height * 4);
  for (let y = 0; y < bounds.height; y += 1) {
    const at = ((bounds.y + y) * image.width + bounds.x) * 4;
    data.set(image.data.subarray(at, at + bounds.width * 4), y * bounds.width * 4);
  }
  return { width: bounds.width, height: bounds.height, data };
}
