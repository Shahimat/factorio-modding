import type { Check } from './protocol.ts';
import { markerPoints, type Point, type Viewport } from './profiles.ts';

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

export interface WindowProof {
  readonly origin: Point | undefined;
  readonly scale: number | undefined;
  readonly crop: Bounds | undefined;
}

function frameFits(frame: Bounds, viewport: Viewport): boolean {
  return Object.values(frame).every(Number.isFinite) && frame.x >= 0 && frame.y >= 0
    && frame.width > 0 && frame.height > 0 && frame.x + frame.width <= viewport.width && frame.y + frame.height <= viewport.height;
}

function projectWindow(image: Raster, frame: Bounds, viewport: Viewport): WindowProof {
  validate(image);
  const area = { x: 0, y: 0, width: image.width, height: image.height };
  const first = colorPixels(image, 'anchor', area);
  const last = colorPixels(image, 'cyan', area);
  const a = first.bounds;
  const b = last.bounds;
  const missing: WindowProof = { origin: undefined, scale: undefined, crop: undefined };
  if (a === undefined || b === undefined || first.count < 4 || last.count < 4
    || a.width > 32 || a.height > 32 || b.width > 32 || b.height > 32) return missing;
  const [start, end] = markerPoints(viewport);
  const sx = (b.x - a.x) / (end.x - start.x);
  const sy = (b.y - a.y) / (end.y - start.y);
  if (sx < 0.5 || sx > 2 || Math.abs(sx - sy) > 0.01 || !frameFits(frame, viewport)) return missing;
  // Equal '+' glyphs cancel font bearings in the scale. A small fixed padding
  // keeps the original window title/borders inside the diagnostic crop.
  const origin = { x: a.x - start.x * sx, y: a.y - start.y * sy };
  const bounds = {
    x: Math.round(origin.x + (frame.x - 24) * sx),
    y: Math.round(origin.y + (frame.y - 24) * sy),
    width: Math.round((frame.width + 48) * sx), height: Math.round((frame.height + 48) * sy),
  };
  if (bounds.x < 0 || bounds.y < 0 || bounds.x + bounds.width > image.width || bounds.y + bounds.height > image.height) return missing;
  return { origin, scale: sx, crop: bounds };
}

function changedPixels(before: Raster, after: Raster, area: Bounds): number {
  let changed = 0;
  for (let y = area.y; y < area.y + area.height; y += 1) {
    for (let x = area.x; x < area.x + area.width; x += 1) {
      const at = (y * before.width + x) * 4;
      if ([0, 1, 2].some((channel) => Math.abs((before.data[at + channel] ?? 0) - (after.data[at + channel] ?? 0)) >= 16)) changed += 1;
    }
  }
  return changed;
}

function neutralBackground(image: Raster, area: Bounds): number {
  let count = 0;
  for (let y = area.y; y < area.y + area.height; y += 1) {
    for (let x = area.x; x < area.x + area.width; x += 1) {
      const at = (y * image.width + x) * 4;
      const channels = [image.data[at] ?? 0, image.data[at + 1] ?? 0, image.data[at + 2] ?? 0];
      const low = Math.min(...channels);
      const high = Math.max(...channels);
      if (low >= 16 && high <= 100 && high - low <= 6 && (image.data[at + 3] ?? 0) >= 250) count += 1;
    }
  }
  return count / (area.width * area.height);
}

interface TitleMask { readonly width: number; readonly height: number; readonly pixels: Uint8Array; readonly ink: number }

function titleInk(image: Raster, x: number, y: number): boolean {
  const at = (y * image.width + x) * 4;
  return (image.data[at] ?? 0) >= 200 && (image.data[at + 1] ?? 0) >= 180
    && (image.data[at + 2] ?? 0) >= 140 && (image.data[at + 3] ?? 0) >= 250;
}

function titleMask(image: Raster, area: Bounds): TitleMask | undefined {
  let x0 = area.x + area.width;
  let y0 = area.y + area.height;
  let x1 = -1;
  let y1 = -1;
  let ink = 0;
  for (let y = area.y; y < area.y + area.height; y += 1) {
    for (let x = area.x; x < area.x + area.width; x += 1) {
      if (!titleInk(image, x, y)) continue;
      x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); ink += 1;
    }
  }
  const width = x1 - x0 + 1;
  const height = y1 - y0 + 1;
  if (ink < 80 || width < 30 || height < 6 || height > 32) return undefined;
  const pixels = new Uint8Array(width * height);
  for (let y = 0; y < height; y += 1) for (let x = 0; x < width; x += 1) pixels[y * width + x] = titleInk(image, x0 + x, y0 + y) ? 1 : 0;
  return { width, height, pixels, ink };
}

function containsTitle(image: Raster, mask: TitleMask, area: Bounds): boolean {
  for (let y = area.y; y <= area.y + area.height - mask.height; y += 1) {
    for (let x = area.x; x <= area.x + area.width - mask.width; x += 1) {
      let errors = 0;
      for (let row = 0; row < mask.height; row += 1) {
        for (let col = 0; col < mask.width; col += 1) {
          if (titleInk(image, x + col, y + row) !== (mask.pixels[row * mask.width + col] === 1)) errors += 1;
          if (errors > mask.ink * 0.1) break;
        }
        if (errors > mask.ink * 0.1) break;
      }
      if (errors <= mask.ink * 0.1) return true;
    }
  }
  return false;
}

function overlaps(a: Bounds, b: Bounds): boolean {
  return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
}

/** The edge markers locate the real window, they do not encode its state.
 * State is checked in Lua; this independently checks its actual rendered area. */
export function checkWindowImages(before: Raster, after: Raster, firstFrame: Bounds, lastFrame: Bounds, viewport: Viewport, reference: Bounds): {
  checks: Check[]; before: WindowProof; after: WindowProof;
} {
  const first = projectWindow(before, firstFrame, viewport);
  const last = projectWindow(after, lastFrame, viewport);
  const sameDimensions = before.width === after.width && before.height === after.height;
  const positioned = first.origin !== undefined && first.scale !== undefined && last.origin !== undefined && last.scale !== undefined;
  const stable = positioned && JSON.stringify(first) === JSON.stringify(last) && JSON.stringify(firstFrame) === JSON.stringify(lastFrame);
  const checks: Check[] = [
    { name: 'image dimensions', passed: sameDimensions, detail: `${before.width}×${before.height} → ${after.width}×${after.height}` },
    { name: 'viewport markers and unclipped GUI frame', passed: positioned, detail: 'two static edge markers and production frame geometry' },
    { name: 'GUI position and size stable', passed: stable, detail: 'same window and viewport in both screenshots' },
  ];
  let contentChanged = 0;
  let headerChanged = 1;
  let clearedBackground = 0;
  let titleVisible = false;
  if (stable && sameDimensions && first.origin !== undefined && first.scale !== undefined && frameFits(reference, viewport)) {
    const origin = first.origin;
    const scale = first.scale;
    const region = (x: number, y: number, width: number, height: number): Bounds => ({
      x: Math.round(origin.x + x * scale), y: Math.round(origin.y + y * scale),
      width: Math.round(width * scale), height: Math.round(height * scale),
    });
    const content = region(firstFrame.x + 16, firstFrame.y + 96, firstFrame.width - 32, firstFrame.height - 120);
    const header = region(firstFrame.x + 16, firstFrame.y + 2, firstFrame.width - 32, 18);
    const referenceArea = region(reference.x + 6, reference.y + 2, reference.width - 20, reference.height - 20);
    const firstTitle = titleMask(before, referenceArea);
    const lastTitle = titleMask(after, referenceArea);
    if (firstTitle !== undefined && lastTitle !== undefined && firstTitle.width === lastTitle.width && firstTitle.height === lastTitle.height
      && firstTitle.pixels.every((value, index) => value === lastTitle.pixels[index])) {
      const titleArea = region(firstFrame.x - 8, firstFrame.y - 16, Math.min(firstFrame.width, firstTitle.width / scale + 96), 72);
      titleVisible = !overlaps(referenceArea, titleArea)
        && containsTitle(before, firstTitle, titleArea) && containsTitle(after, firstTitle, titleArea);
    }
    if (content.width > 0 && content.height > 0 && header.width > 0) {
      contentChanged = changedPixels(before, after, content);
      clearedBackground = neutralBackground(after, content);
      headerChanged = changedPixels(before, after, header) / (header.width * header.height);
    }
  }
  checks.push({ name: 'production title is rendered in both PNGs', passed: titleVisible, detail: 'native font-calibration mask matched inside the original mod window, not at the reference pane' });
  checks.push({ name: 'window title area stays stable', passed: stable && headerChanged < 0.02, detail: `header changed ${(headerChanged * 100).toFixed(2)}%` });
  checks.push({ name: 'card content visibly changes', passed: contentChanged >= 5000, detail: `${contentChanged} changed content pixels (not the toggle or viewport markers)` });
  checks.push({ name: 'collapsed content area is cleared to GUI background', passed: clearedBackground >= 0.98, detail: `${(clearedBackground * 100).toFixed(2)}% neutral dark GUI pixels` });
  return { checks, before: first, after: last };
}
