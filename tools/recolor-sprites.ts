#!/usr/bin/env node
/**
 * Порождает графику тиров `shm-advanced-belts` из ванильных спрайтов
 * турбо-лент установленной игры: на каждый спрайт — маска цвета (см.
 * `tools/lib/recolor.ts`), которую мод кладёт слоем поверх ванильного
 * спрайта, плюс картинка мода из перекрашенных иконок.
 * Запуск: `npm run recolor-sprites`. Путь к бинарю игры переопределяется
 * переменной `FACTORIO_BIN`, как у `npm run test:ingame`.
 *
 * Результат — производные от ассетов Wube, оговорка в `LICENSE` мода,
 * convention `licensing`.
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import { PNG } from 'pngjs';

import { gameDataDir } from './lib/game-install.ts';
import { REPO_ROOT } from './lib/packages.ts';
import { composeTinted, crop, type Image, maskSprite, place, TURBO_SPLIT } from './lib/recolor.ts';
import {
  ADVANCED_BELTS_MOD,
  maskPath,
  THUMBNAIL_ICON,
  THUMBNAIL_SIZE,
  THUMBNAIL_TINTS,
  TURBO_SOURCES,
} from './lib/recolor-jobs.ts';

async function readPng(path: string): Promise<Image> {
  const png = PNG.sync.read(await readFile(path));
  return { width: png.width, height: png.height, data: new Uint8Array(png.data) };
}

async function writePng(path: string, image: Image): Promise<void> {
  const png = new PNG({ width: image.width, height: image.height, deflateLevel: 9 });
  png.data = Buffer.from(image.data);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, PNG.sync.write(png));
}

async function main(): Promise<void> {
  const sourceRoot = join(gameDataDir(), 'space-age', 'graphics');
  const modDir = join(REPO_ROOT, 'mods', ADVANCED_BELTS_MOD);
  const outRoot = join(modDir, 'graphics');

  for (const source of TURBO_SOURCES) {
    const image = await readPng(join(sourceRoot, source));
    await writePng(join(outRoot, maskPath(source)), { ...image, data: maskSprite(image.data, TURBO_SPLIT) });
    console.log(`${source} → ${maskPath(source)}`);
  }

  const icon = await readPng(join(sourceRoot, THUMBNAIL_ICON));
  const size = icon.height;
  const top = crop(icon, 0, 0, size, size);
  const mask = maskSprite(top.data, TURBO_SPLIT);
  const canvas: Image = {
    width: THUMBNAIL_SIZE,
    height: THUMBNAIL_SIZE,
    data: new Uint8Array(THUMBNAIL_SIZE * THUMBNAIL_SIZE * 4),
  };
  const margin = Math.floor((THUMBNAIL_SIZE - 2 * size) / 4);
  THUMBNAIL_TINTS.forEach((tint, index) => {
    const tinted: Image = { width: size, height: size, data: composeTinted(top.data, mask, tint) };
    const x = margin + (index % 2) * (size + 2 * margin);
    const y = margin + Math.floor(index / 2) * (size + 2 * margin);
    place(canvas, tinted, x, y);
  });
  await writePng(join(modDir, 'thumbnail.png'), canvas);
  console.log(`картинка мода → thumbnail.png, ${THUMBNAIL_SIZE}×${THUMBNAIL_SIZE}`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
