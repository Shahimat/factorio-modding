/**
 * Что перекрашивает `tools/recolor-sprites.ts`: ванильные спрайты турбо-лент
 * Space Age, из которых `shm-advanced-belts` собирает графику своих тиров.
 * Чистые данные и правила имён, без обращения к файлам.
 */

import type { Rgb } from './recolor.ts';

/** Мод, в который пишутся маски. */
export const ADVANCED_BELTS_MOD = 'shm-advanced-belts';

/**
 * Файлы турбо относительно `space-age/graphics/`. Замёрзшие патчи и остатки
 * не перекрашиваются: мод берёт их ванильными.
 */
export const TURBO_SOURCES: readonly string[] = [
  'entity/turbo-transport-belt/turbo-transport-belt.png',
  'entity/turbo-underground-belt/turbo-underground-belt-structure.png',
  'entity/turbo-underground-belt/turbo-underground-belt-structure-front-patch.png',
  'entity/turbo-underground-belt/turbo-underground-belt-structure-back-patch.png',
  'entity/turbo-splitter/turbo-splitter-north.png',
  'entity/turbo-splitter/turbo-splitter-east.png',
  'entity/turbo-splitter/turbo-splitter-south.png',
  'entity/turbo-splitter/turbo-splitter-west.png',
  'entity/turbo-splitter/turbo-splitter-east-top_patch.png',
  'entity/turbo-splitter/turbo-splitter-west-top_patch.png',
  'icons/turbo-transport-belt.png',
  'icons/turbo-underground-belt.png',
  'icons/turbo-splitter.png',
  'technology/turbo-transport-belt.png',
];

/**
 * Путь маски в моде относительно `graphics/`: `turbo-` из пути убирается, к
 * имени добавляется `-mask`. То же правило повторяет Lua-сторона мода
 * (`logic/graphics.lua`), когда добавляет слой маски к спрайтам прототипов.
 */
export function maskPath(source: string): string {
  if (!source.endsWith('.png')) {
    throw new Error(`не PNG: ${source}`);
  }
  return `${source.slice(0, -'.png'.length).replaceAll('turbo-', '')}-mask.png`;
}

/**
 * Цвета тиров для картинки мода, в порядке тиров. Источник правды — значения
 * по умолчанию в `mods/shm-advanced-belts/logic/defaults.lua`; при правке
 * менять в обоих местах.
 */
export const THUMBNAIL_TINTS: readonly Rgb[] = [
  { r: 210, g: 1, b: 247 },
  { r: 255, g: 110, b: 0 },
  { r: 160, g: 235, b: 255 },
  { r: 20, g: 40, b: 170 },
];

/** Иконка, из которой собирается картинка мода. */
export const THUMBNAIL_ICON = 'icons/turbo-transport-belt.png';

/** Размер картинки мода на портале. */
export const THUMBNAIL_SIZE = 144;
