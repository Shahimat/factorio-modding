/**
 * Картинки `shm-orbital-logistics` из иконок игры: картинка мода — три
 * платформы по кругу со стрелками по дуге от одной к другой, и картинка
 * пути Наувис → Вулкан для «Советов и подсказок». Чистые функции над RGBA,
 * чтение и запись файлов — в `tools/orbital-art.ts`.
 */
import { type Image, place } from './recolor.ts';

export type Rgba = readonly [number, number, number, number];

export const THUMBNAIL_SIZE = 144;
/**
 * Окно «Советов и подсказок» растягивает картинку на всю ширину своей
 * области, сколько бы в ней ни было пикселей, а высоту берёт по пропорциям.
 * Поэтому холст широкий и низкий, а рисунок — в центре на прозрачном поле:
 * так он занимает около трети ширины и не превращается в пиксели.
 */
export const ROUTE_WIDTH = 1600;
export const ROUTE_HEIGHT = 320;
const ROUTE_CONTENT_WIDTH = 760;
const ROUTE_CONTENT_HEIGHT = 290;
const ORBIT_RING: Rgba = [170, 190, 220, 150];


const ARROW: Rgba = [255, 166, 77, 255];
const ROUTE_LINE: Rgba = [255, 214, 140, 255];
const BACKGROUND: Rgba = [24, 28, 40, 255];

export function blank(width: number, height: number, fill?: Rgba): Image {
  const data = new Uint8Array(width * height * 4);
  if (fill) {
    for (let i = 0; i < width * height; i++) {
      data.set(fill, i * 4);
    }
  }
  return { width, height, data };
}

/** Кладёт цвет с покрытием `coverage` (0…1) поверх пикселя. */
export function blendPixel(canvas: Image, x: number, y: number, color: Rgba, coverage: number): void {
  if (x < 0 || y < 0 || x >= canvas.width || y >= canvas.height || coverage <= 0) {
    return;
  }
  const i = (y * canvas.width + x) * 4;
  const top = (color[3] / 255) * Math.min(1, coverage);
  const bottom = (canvas.data[i + 3] ?? 0) / 255;
  const out = top + bottom * (1 - top);
  for (let c = 0; c < 3; c++) {
    const value = out === 0 ? 0 : ((color[c] ?? 0) * top + (canvas.data[i + c] ?? 0) * bottom * (1 - top)) / out;
    canvas.data[i + c] = Math.round(Math.max(0, Math.min(255, value)));
  }
  canvas.data[i + 3] = Math.round(out * 255);
}

/**
 * Масштабирование усреднением по площади с учётом прозрачности: при сильном
 * уменьшении (звёздная карта 512 → 128) не мельтешит, как ближайший сосед.
 */
export function scale(image: Image, width: number, height: number): Image {
  const out = blank(width, height);
  const sx = image.width / width;
  const sy = image.height / height;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const x0 = x * sx;
      const x1 = (x + 1) * sx;
      const y0 = y * sy;
      const y1 = (y + 1) * sy;
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      let area = 0;
      for (let py = Math.floor(y0); py < Math.ceil(y1); py++) {
        const wy = Math.min(y1, py + 1) - Math.max(y0, py);
        for (let px = Math.floor(x0); px < Math.ceil(x1); px++) {
          const wx = Math.min(x1, px + 1) - Math.max(x0, px);
          const w = wx * wy;
          const i = (Math.min(py, image.height - 1) * image.width + Math.min(px, image.width - 1)) * 4;
          const alpha = (image.data[i + 3] ?? 0) / 255;
          r += (image.data[i] ?? 0) * alpha * w;
          g += (image.data[i + 1] ?? 0) * alpha * w;
          b += (image.data[i + 2] ?? 0) * alpha * w;
          a += alpha * w;
          area += w;
        }
      }
      const o = (y * width + x) * 4;
      if (a > 0) {
        out.data[o] = Math.round(r / a);
        out.data[o + 1] = Math.round(g / a);
        out.data[o + 2] = Math.round(b / a);
      }
      out.data[o + 3] = Math.round((a / area) * 255);
    }
  }
  return out;
}

function normalize(angle: number): number {
  const full = Math.PI * 2;
  return ((angle % full) + full) % full;
}

/**
 * Угол `angle` внутри дуги от `start` по часовой стрелке (в экранных
 * координатах) до `end`. Дуга в полный оборот и больше — весь круг: иначе
 * её длина приводилась бы к нулю.
 */
export function withinArc(angle: number, start: number, end: number): boolean {
  if (end - start >= Math.PI * 2) {
    return true;
  }
  const span = normalize(end - start);
  return normalize(angle - start) <= span;
}

/**
 * Дуга окружности со сглаживанием. Углы — в экранных координатах (y вниз),
 * от `start` до `end` по возрастанию угла. `dash` — длина штриха и
 * промежутка в пикселях дуги; без него — сплошная.
 */
export function drawArc(
  canvas: Image,
  cx: number,
  cy: number,
  radius: number,
  start: number,
  end: number,
  thickness: number,
  color: Rgba,
  dash?: number,
): void {
  const reach = radius + thickness;
  for (let y = Math.floor(cy - reach); y <= Math.ceil(cy + reach); y++) {
    for (let x = Math.floor(cx - reach); x <= Math.ceil(cx + reach); x++) {
      const dx = x + 0.5 - cx;
      const dy = y + 0.5 - cy;
      const angle = Math.atan2(dy, dx);
      if (!withinArc(angle, start, end)) {
        continue;
      }
      if (dash !== undefined) {
        const along = normalize(angle - start) * radius;
        if (Math.floor(along / dash) % 2 === 1) {
          continue;
        }
      }
      const distance = Math.abs(Math.hypot(dx, dy) - radius);
      blendPixel(canvas, x, y, color, thickness / 2 - distance + 0.5);
    }
  }
}

/** Закрашенный треугольник наконечника: остриё в `x, y`, смотрит под углом `angle`. */
export function drawArrowHead(canvas: Image, x: number, y: number, angle: number, size: number, color: Rgba): void {
  const back = angle + Math.PI;
  const spread = 0.5;
  const points = [
    [x, y],
    [x + Math.cos(back - spread) * size, y + Math.sin(back - spread) * size],
    [x + Math.cos(back + spread) * size, y + Math.sin(back + spread) * size],
  ] as const;
  const samples = 4;
  const minX = Math.floor(Math.min(...points.map((p) => p[0])));
  const maxX = Math.ceil(Math.max(...points.map((p) => p[0])));
  const minY = Math.floor(Math.min(...points.map((p) => p[1])));
  const maxY = Math.ceil(Math.max(...points.map((p) => p[1])));
  const inside = (px: number, py: number): boolean => {
    let sign = 0;
    for (let i = 0; i < 3; i++) {
      const [ax, ay] = points[i] ?? [0, 0];
      const [bx, by] = points[(i + 1) % 3] ?? [0, 0];
      const cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
      if (cross !== 0) {
        const s = Math.sign(cross);
        if (sign !== 0 && s !== sign) {
          return false;
        }
        sign = s;
      }
    }
    return true;
  };
  for (let py = minY; py <= maxY; py++) {
    for (let px = minX; px <= maxX; px++) {
      let hits = 0;
      for (let sy = 0; sy < samples; sy++) {
        for (let sx = 0; sx < samples; sx++) {
          if (inside(px + (sx + 0.5) / samples, py + (sy + 0.5) / samples)) {
            hits++;
          }
        }
      }
      blendPixel(canvas, px, py, color, hits / (samples * samples));
    }
  }
}

/** Дуга со стрелкой на конце, по направлению обхода. */
function arrowArc(
  canvas: Image,
  cx: number,
  cy: number,
  radius: number,
  start: number,
  end: number,
  thickness: number,
  color: Rgba,
  options: { dash?: number; head?: number; both?: boolean } = {},
): void {
  drawArc(canvas, cx, cy, radius, start, end, thickness, color, options.dash);
  const head = options.head ?? thickness * 3.2;
  drawArrowHead(canvas, cx + Math.cos(end) * radius, cy + Math.sin(end) * radius, end + Math.PI / 2, head, color);
  if (options.both) {
    drawArrowHead(canvas, cx + Math.cos(start) * radius, cy + Math.sin(start) * radius, start - Math.PI / 2, head, color);
  }
}

/** Звёзды на фоне — детерминированные, чтобы картинка порождалась одинаково. */
function stars(canvas: Image, count: number, seed: number): void {
  let state = seed;
  const next = (): number => {
    state = (state * 1103515245 + 12345) % 2147483648;
    return state / 2147483648;
  };
  for (let i = 0; i < count; i++) {
    const x = Math.floor(next() * canvas.width);
    const y = Math.floor(next() * canvas.height);
    const brightness = 140 + Math.floor(next() * 115);
    blendPixel(canvas, x, y, [brightness, brightness, brightness, 255], 0.9);
  }
}

/**
 * Картинка мода: тёмный космос, три платформы по кругу и стрелки по дуге
 * от каждой к следующей, по часовой стрелке. `platform` — иконка 64×64.
 */
export function thumbnail(platform: Image): Image {
  const size = THUMBNAIL_SIZE;
  const canvas = blank(size, size, BACKGROUND);
  stars(canvas, 40, 7);
  const cx = size / 2;
  const cy = size / 2 + 2;
  const radius = 44;
  const icon = scale(platform, 50, 50);
  const angles = [-Math.PI / 2, Math.PI / 6, (5 * Math.PI) / 6];
  const gap = 0.62;
  for (let i = 0; i < angles.length; i++) {
    const from = angles[i] ?? 0;
    const to = angles[(i + 1) % angles.length] ?? 0;
    arrowArc(canvas, cx, cy, radius, from + gap, (to < from ? to + Math.PI * 2 : to) - gap, 4, ARROW);
  }
  for (const angle of angles) {
    const x = Math.round(cx + Math.cos(angle) * radius - icon.width / 2);
    const y = Math.round(cy + Math.sin(angle) * radius - icon.height / 2);
    place(canvas, icon, Math.max(0, Math.min(size - icon.width, x)), Math.max(0, Math.min(size - icon.height, y)));
  }
  return canvas;
}

/**
 * Задумка мода одной картинкой: у Наувиса и Вулкана на кольце орбиты стоят
 * склады-прокси (иконка `depotIcon`, по умолчанию та же, что у челнока),
 * челнок летит по дуге от одного склада к другому, стрелки
 * на обоих концах — обмен грузом в обе стороны. Фон прозрачный — окно
 * подсказок само тёмное.
 */
export function route(from: Image, to: Image, platform: Image, depotIcon: Image = platform): Image {
  const canvas = blank(ROUTE_WIDTH, ROUTE_HEIGHT);
  const ox = Math.round((ROUTE_WIDTH - ROUTE_CONTENT_WIDTH) / 2);
  const oy = Math.round((ROUTE_HEIGHT - ROUTE_CONTENT_HEIGHT) / 2);
  const planet = 150;
  const ring = planet * 0.56;
  const centers = [
    { x: ox + ring + 8, y: oy + ROUTE_CONTENT_HEIGHT - ring - 6 },
    { x: ox + ROUTE_CONTENT_WIDTH - ring - 8, y: oy + ROUTE_CONTENT_HEIGHT - ring - 6 },
  ];
  const images = [scale(from, planet, planet), scale(to, planet, planet)];
  for (let i = 0; i < 2; i++) {
    const c = centers[i] ?? { x: 0, y: 0 };
    const image = images[i];
    if (image) {
      place(canvas, image, Math.round(c.x - planet / 2), Math.round(c.y - planet / 2));
    }
    drawArc(canvas, c.x, c.y, ring, -Math.PI, Math.PI, 2, ORBIT_RING);
  }
  // Склады-прокси на кольце, сверху-изнутри.
  const lean = (55 * Math.PI) / 180;
  const depotSize = 52;
  const depots = [
    { x: (centers[0]?.x ?? 0) + Math.cos(-lean) * ring, y: (centers[0]?.y ?? 0) + Math.sin(-lean) * ring },
    { x: (centers[1]?.x ?? 0) - Math.cos(-lean) * ring, y: (centers[1]?.y ?? 0) + Math.sin(-lean) * ring },
  ];
  const depot = scale(depotIcon, depotSize, depotSize);
  // Дуга челнока — от склада до склада, концы у краёв иконок.
  const startX = (depots[0]?.x ?? 0) + depotSize * 0.45;
  const endX = (depots[1]?.x ?? 0) - depotSize * 0.45;
  const baseY = (depots[0]?.y ?? 0) - depotSize * 0.2;
  const apexY = oy + 44;
  const half = (endX - startX) / 2;
  const sagitta = baseY - apexY;
  const radius = (half * half + sagitta * sagitta) / (2 * sagitta);
  const cx = (startX + endX) / 2;
  const cy = apexY + radius;
  const start = Math.atan2(baseY - cy, startX - cx);
  const end = Math.atan2(baseY - cy, endX - cx);
  arrowArc(canvas, cx, cy, radius, start, end, 4, ROUTE_LINE, { dash: 13, head: 20, both: true });
  for (const d of depots) {
    place(canvas, depot, Math.round(d.x - depotSize / 2), Math.round(d.y - depotSize / 2));
  }
  const shuttle = scale(platform, 68, 68);
  place(canvas, shuttle, Math.round(cx - shuttle.width / 2), Math.max(0, Math.round(apexY - shuttle.height / 2)));
  return canvas;
}
