/**
 * Чистая логика перекраски спрайтов: из спрайта выделяется маска цветных
 * пикселей, которую в игре красит `tint` поверх исходного спрайта.
 * Пиксели — RGBA по байту на канал, построчно, как в pngjs.
 */

export interface HueBand {
  /** Центр полосы тона, градусы. */
  center: number;
  /** Полуширина, внутри которой вес полный, градусы. */
  inner: number;
  /** Полуширина, за которой вес нулевой, градусы. */
  outer: number;
}

export interface SplitOptions {
  band: HueBand;
  /** Насыщенность, ниже которой пиксель не цветной. */
  saturationLow: number;
  /** Насыщенность, с которой пиксель цветной полностью. */
  saturationHigh: number;
  /** Множитель яркости маски: `tint` только умножает, и тёмная маска дала бы тёмный цвет. */
  maskGain: number;
}

/** Полоса жёлто-зелёного цвета турбо-лент Space Age. */
export const TURBO_SPLIT: SplitOptions = {
  band: { center: 75, inner: 30, outer: 45 },
  saturationLow: 0.2,
  saturationHigh: 0.45,
  maskGain: 1.6,
};

export interface Rgb {
  r: number;
  g: number;
  b: number;
}

export interface Hsv {
  /** Градусы, 0–360. */
  h: number;
  s: number;
  v: number;
}

export function rgbToHsv(r: number, g: number, b: number): Hsv {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const max = Math.max(rn, gn, bn);
  const min = Math.min(rn, gn, bn);
  const delta = max - min;
  let h = 0;
  if (delta > 0) {
    if (max === rn) {
      h = 60 * (((gn - bn) / delta) % 6);
    } else if (max === gn) {
      h = 60 * ((bn - rn) / delta + 2);
    } else {
      h = 60 * ((rn - gn) / delta + 4);
    }
  }
  if (h < 0) h += 360;
  return { h, s: max === 0 ? 0 : delta / max, v: max };
}

/** Яркость по Rec. 709, 0–255. */
export function luminance(r: number, g: number, b: number): number {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function ramp(value: number, low: number, high: number): number {
  if (value <= low) return 0;
  if (value >= high) return 1;
  return (value - low) / (high - low);
}

function hueDistance(a: number, b: number): number {
  const d = Math.abs(a - b) % 360;
  return d > 180 ? 360 - d : d;
}

/** Насколько пиксель относится к перекрашиваемому цвету, 0–1. */
export function colorWeight(r: number, g: number, b: number, options: SplitOptions): number {
  const { h, s } = rgbToHsv(r, g, b);
  const { band } = options;
  const hueWeight = 1 - ramp(hueDistance(h, band.center), band.inner, band.outer);
  return hueWeight * ramp(s, options.saturationLow, options.saturationHigh);
}

function clampByte(value: number): number {
  return Math.max(0, Math.min(255, Math.round(value)));
}

/**
 * Маска цвета: серый по яркости исходного пикселя, усиленный `maskGain`, с
 * прозрачностью исходного пикселя, умноженной на вес цвета. В игре маска
 * ложится слоем поверх исходного спрайта и красится `tint`: где вес полный,
 * исходный цвет не виден вовсе.
 */
export function maskSprite(rgba: Uint8Array, options: SplitOptions): Uint8Array {
  if (rgba.length % 4 !== 0) {
    throw new Error(`длина буфера ${rgba.length} не кратна 4`);
  }
  const mask = new Uint8Array(rgba.length);
  for (let i = 0; i < rgba.length; i += 4) {
    const r = rgba[i] ?? 0;
    const g = rgba[i + 1] ?? 0;
    const b = rgba[i + 2] ?? 0;
    const a = rgba[i + 3] ?? 0;
    const alpha = a === 0 ? 0 : clampByte(a * colorWeight(r, g, b, options));
    // Цвет полностью прозрачного пикселя не виден, а случайные значения в
    // нём раздували бы PNG: оставляем нули.
    const lit = alpha === 0 ? 0 : clampByte(luminance(r, g, b) * options.maskGain);
    mask[i] = lit;
    mask[i + 1] = lit;
    mask[i + 2] = lit;
    mask[i + 3] = alpha;
  }
  return mask;
}

/**
 * Накладывает маску, умноженную на `tint`, поверх исходного спрайта — так,
 * как это делает игра со слоями. Нужна для картинки мода.
 */
export function composeTinted(sprite: Uint8Array, mask: Uint8Array, tint: Rgb): Uint8Array {
  if (sprite.length !== mask.length) {
    throw new Error('спрайт и маска разного размера');
  }
  const out = new Uint8Array(sprite.length);
  for (let i = 0; i < sprite.length; i += 4) {
    const maskAlpha = (mask[i + 3] ?? 0) / 255;
    const spriteAlpha = (sprite[i + 3] ?? 0) / 255;
    const outAlpha = maskAlpha + spriteAlpha * (1 - maskAlpha);
    const channels: [number, number][] = [
      [(mask[i] ?? 0) * (tint.r / 255), sprite[i] ?? 0],
      [(mask[i + 1] ?? 0) * (tint.g / 255), sprite[i + 1] ?? 0],
      [(mask[i + 2] ?? 0) * (tint.b / 255), sprite[i + 2] ?? 0],
    ];
    channels.forEach(([top, bottom], c) => {
      out[i + c] =
        outAlpha === 0
          ? 0
          : clampByte((top * maskAlpha + bottom * spriteAlpha * (1 - maskAlpha)) / outAlpha);
    });
    out[i + 3] = clampByte(outAlpha * 255);
  }
  return out;
}

export interface Image {
  width: number;
  height: number;
  data: Uint8Array;
}

/** Вырезает прямоугольник; выход за границы — ошибка. */
export function crop(image: Image, x: number, y: number, width: number, height: number): Image {
  if (x < 0 || y < 0 || x + width > image.width || y + height > image.height) {
    throw new Error(`прямоугольник ${x},${y} ${width}×${height} вне картинки ${image.width}×${image.height}`);
  }
  const data = new Uint8Array(width * height * 4);
  for (let row = 0; row < height; row++) {
    const from = ((y + row) * image.width + x) * 4;
    data.set(image.data.subarray(from, from + width * 4), row * width * 4);
  }
  return { width, height, data };
}

/** Кладёт картинку поверх холста в точку `x, y`, с учётом прозрачности. */
export function place(canvas: Image, image: Image, x: number, y: number): void {
  if (x < 0 || y < 0 || x + image.width > canvas.width || y + image.height > canvas.height) {
    throw new Error(`картинка ${image.width}×${image.height} в ${x},${y} не помещается на холст`);
  }
  for (let row = 0; row < image.height; row++) {
    for (let col = 0; col < image.width; col++) {
      const src = (row * image.width + col) * 4;
      const dst = ((y + row) * canvas.width + x + col) * 4;
      const topAlpha = (image.data[src + 3] ?? 0) / 255;
      const bottomAlpha = (canvas.data[dst + 3] ?? 0) / 255;
      const outAlpha = topAlpha + bottomAlpha * (1 - topAlpha);
      for (let c = 0; c < 3; c++) {
        const top = image.data[src + c] ?? 0;
        const bottom = canvas.data[dst + c] ?? 0;
        canvas.data[dst + c] =
          outAlpha === 0 ? 0 : clampByte((top * topAlpha + bottom * bottomAlpha * (1 - topAlpha)) / outAlpha);
      }
      canvas.data[dst + 3] = clampByte(outAlpha * 255);
    }
  }
}
