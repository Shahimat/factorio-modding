#!/usr/bin/env node
/**
 * Порождает картинки `shm-orbital-logistics` из иконок установленной игры:
 * `thumbnail.png` — три платформы по кругу со стрелками по дуге, и
 * `graphics/tips-route.png` — челнок между складами-прокси на орбитах
 * Наувиса и Вулкана для «Советов и подсказок». Запуск: `npm run orbital-art`. Путь к бинарю игры
 * переопределяется переменной `FACTORIO_BIN`, как у `npm run test:ingame`.
 *
 * Результат — производные от ассетов Wube, оговорка в `LICENSE` мода,
 * convention `licensing`.
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

import { PNG } from 'pngjs';

import { gameDataDir } from './lib/game-install.ts';
import { route, thumbnail } from './lib/orbital-art.ts';
import { REPO_ROOT } from './lib/packages.ts';
import { crop, type Image } from './lib/recolor.ts';

const MOD_DIR = join(REPO_ROOT, 'mods', 'shm-orbital-logistics');

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
  const data = gameDataDir();
  // Иконки игры — 64 px с уменьшенными копиями справа: берём первые 64×64.
  const hub = crop(await readPng(join(data, 'space-age', 'graphics', 'icons', 'space-platform-hub.png')), 0, 0, 64, 64);
  const nauvis = await readPng(join(data, 'base', 'graphics', 'icons', 'starmap-planet-nauvis.png'));
  const vulcanus = await readPng(join(data, 'space-age', 'graphics', 'icons', 'starmap-planet-vulcanus.png'));
  // Склады-прокси на орбите — иконкой грузового отсека, чтобы не путать с челноком.
  const bay = crop(await readPng(join(data, 'space-age', 'graphics', 'icons', 'cargo-bay.png')), 0, 0, 64, 64);

  await writePng(join(MOD_DIR, 'thumbnail.png'), thumbnail(hub));
  await writePng(join(MOD_DIR, 'graphics', 'tips-route.png'), route(nauvis, vulcanus, hub, bay));
  console.log('orbital-art: thumbnail.png, graphics/tips-route.png');
}

await main();
